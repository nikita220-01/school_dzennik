import { useCallback, useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { useAuth } from '../context/AuthContext'
import {
  WEEKDAY_NAMES,
  clearScheduleSlot,
  loadClasses,
  loadSchedule,
  loadSubjects,
  saveScheduleSlot
} from '../lib/schoolData'

/** Минимум видимых мест в дне; кнопка «＋» добавляет до MAX_SLOTS */
const MIN_SLOTS = 7
const MAX_SLOTS = 12

/**
 * Вкладка «Расписание»: сетка «день недели × уроки» для выбранного класса.
 * Учитель кликает клетку и выбирает предмет из окна (как в отметках),
 * ученики и родители видят расписание своего класса.
 */
export default function ScheduleScreen() {
  const { role, classId: myClassId } = useAuth()
  const isTeacher = role === 'teacher' || role === 'admin'

  const [classes, setClasses] = useState([])
  const [subjects, setSubjects] = useState([])
  const [classId, setClassId] = useState(myClassId || '')
  const [slots, setSlots] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  /** Открытая клетка: { weekday, lessonNumber, scheduleId, subjectId } */
  const [cell, setCell] = useState(null)
  /** Сколько мест показать по дням (добавляется кнопкой «＋», только локально) */
  const [slotCounts, setSlotCounts] = useState({})

  // 1. Справочники: классы и предметы
  useEffect(() => {
    let alive = true

    const run = async () => {
      try {
        const [classRows, subjectRows] = await Promise.all([loadClasses(), loadSubjects()])
        if (!alive) return
        setClasses(classRows)
        setSubjects(subjectRows)
        setClassId((current) => current || classRows[0]?.id || '')
      } catch (loadError) {
        if (alive) setError(loadError.message)
      } finally {
        if (alive) setLoading(false)
      }
    }

    run()
    return () => {
      alive = false
    }
  }, [])

  // Ученик всегда смотрит расписание своего класса
  useEffect(() => {
    if (!isTeacher && myClassId) setClassId(myClassId)
  }, [isTeacher, myClassId])

  // 2. Загрузка расписания выбранного класса
  const reload = useCallback(async (id) => {
    if (!id) {
      setSlots([])
      return
    }

    setError(null)
    try {
      const rows = await loadSchedule(id)
      setSlots(rows)
    } catch (loadError) {
      setError(loadError.message)
      setSlots([])
    }
  }, [])

  useEffect(() => {
    setSlotCounts({})
    reload(classId)
  }, [classId, reload])

  const subjectById = useMemo(() => {
    const map = {}
    for (const item of subjects) map[item.id] = item
    return map
  }, [subjects])

  const selectedClass = classes.find((item) => item.id === classId) || null

  /** Клетки по дням: { 1: [slot…], 2: [slot…] } */
  const byDay = useMemo(() => {
    const map = {}
    WEEKDAY_NAMES.forEach((_, index) => {
      map[index + 1] = []
    })
    for (const slot of slots) {
      if (map[slot.weekday]) map[slot.weekday].push(slot)
    }
    return map
  }, [slots])

  /** Сколько мест показывать в дне: минимум 7 и не меньше уже заполненных */
  const slotsToShow = (day) => {
    const filled = byDay[day].reduce((max, slot) => Math.max(max, slot.lesson_number), 0)
    return Math.min(MAX_SLOTS, Math.max(MIN_SLOTS, filled, slotCounts[day] || 0))
  }

  // 3. Действия учителя
  const handlePickSubject = async (subjectId) => {
    if (!cell || busy) return

    setBusy(true)
    setError(null)
    try {
      await saveScheduleSlot({
        classId,
        weekday: cell.weekday,
        lessonNumber: cell.lessonNumber,
        subjectId
      })
      setCell(null)
      await reload(classId)
    } catch (pickError) {
      setError(pickError.message)
    } finally {
      setBusy(false)
    }
  }

  const handleClear = async () => {
    if (!cell?.scheduleId || busy) return

    setBusy(true)
    setError(null)
    try {
      await clearScheduleSlot(cell.scheduleId)
      setCell(null)
      await reload(classId)
    } catch (clearError) {
      setError(clearError.message)
    } finally {
      setBusy(false)
    }
  }

  const addSlot = (day) => {
    setSlotCounts((current) => ({
      ...current,
      [day]: Math.min(MAX_SLOTS, slotsToShow(day) + 1)
    }))
  }

  return (
    <div className="grades schedule">
      <section className="sheet">
        <div className="sheet__row grades__controls">
          <label className="field field--compact">
            <span className="field__label">Класс</span>
            <select
              className="field__input"
              value={classId}
              onChange={(event) => setClassId(event.target.value)}
              disabled={!isTeacher || !classes.length}
            >
              {classes.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} класс
                </option>
              ))}
            </select>
          </label>

          <span className="sheet__note">
            {isTeacher
              ? 'Нажмите на клетку и выберите предмет — он появится в расписании.'
              : selectedClass
                ? `Расписание ${selectedClass.name} класса.`
                : ''}
          </span>
        </div>

        {error ? (
          <div className="alert alert--error" role="alert">
            {error}
          </div>
        ) : null}

        {loading && !slots.length ? (
          <p className="sheet__note">Загружаем расписание…</p>
        ) : (
          <div className="grades__table-wrap">
            <table className="grades__table schedule__table">
              <tbody>
                {WEEKDAY_NAMES.map((dayName, index) => {
                  const day = index + 1
                  const count = slotsToShow(day)

                  return (
                    <tr key={day}>
                      <th className="schedule__day" scope="row">
                        {dayName}
                      </th>
                      {Array.from({ length: count }, (_, offset) => {
                        const lessonNumber = offset + 1
                        const slot =
                          byDay[day].find((item) => item.lesson_number === lessonNumber) || null
                        const subject = slot ? subjectById[slot.subject_id] : null
                        const label = subject ? subject.short_name || subject.name : ''

                        return (
                          <td key={lessonNumber}>
                            {isTeacher ? (
                              <button
                                type="button"
                                className={`mark-cell${subject ? '' : ' mark-cell--empty'}`}
                                onClick={() =>
                                  setCell({
                                    weekday: day,
                                    lessonNumber,
                                    scheduleId: slot?.id || null,
                                    subjectId: slot?.subject_id || null
                                  })
                                }
                              >
                                {label}
                              </button>
                            ) : (
                              <span className={`mark-cell${subject ? '' : ' mark-cell--empty'}`}>
                                {label}
                              </span>
                            )}
                          </td>
                        )
                      })}
                      {isTeacher ? (
                        <td className="schedule__add">
                          <button
                            type="button"
                            className="button button--ghost button--small"
                            onClick={() => addSlot(day)}
                            disabled={count >= MAX_SLOTS}
                            aria-label="Добавить место"
                          >
                            ＋
                          </button>
                        </td>
                      ) : null}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Накладное окно выбора предмета — поверх всей страницы */}
      {cell
        ? createPortal(
            <div
              className="mark-dialog"
              role="dialog"
              aria-modal="true"
              onClick={() => (busy ? null : setCell(null))}
            >
              <div className="mark-dialog__card" onClick={(event) => event.stopPropagation()}>
                <h3 className="mark-dialog__title">
                  {WEEKDAY_NAMES[cell.weekday - 1]} · урок {cell.lessonNumber}
                </h3>
                <p className="mark-dialog__subject">
                  {selectedClass ? `${selectedClass.name} класс` : ''}
                </p>

                <p className="mark-dialog__pick">Выберите предмет:</p>
                <div className="mark-dialog__subjects">
                  {subjects.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      className={`mark-dialog__mark${cell.subjectId === item.id ? ' is-active' : ''}`}
                      onClick={() => handlePickSubject(item.id)}
                      disabled={busy}
                    >
                      {item.name}
                    </button>
                  ))}
                </div>

                <div className="mark-dialog__actions">
                  {cell.scheduleId ? (
                    <button
                      type="button"
                      className="button button--ghost button--small"
                      onClick={handleClear}
                      disabled={busy}
                    >
                      Убрать предмет
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className="button button--small"
                    onClick={() => setCell(null)}
                    disabled={busy}
                  >
                    Отмена
                  </button>
                </div>

                {busy ? <p className="sheet__note">Сохраняем…</p> : null}
              </div>
            </div>,
            document.body
          )
        : null}
    </div>
  )
}

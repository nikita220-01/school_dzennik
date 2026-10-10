import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import {
  linkChildByCard,
  loadAttendanceReasons,
  loadClasses,
  loadMyChildren,
  loadRoster,
  saveAbsenceReason,
  weekDates,
  weekTitle
} from '../lib/schoolData'

/**
 * Вкладка «Посещаемость»: список учеников → клик по ученику открывает таблицу
 * дат недели с причинами отсутствия. Причины заполняют только родители, учитель
 * и админ могут только просматривать их. Родитель видит своих детей
 * (parent_students) и может привязать ребёнка по номеру карты.
 */
export default function AttendanceScreen() {
  const { user, role, classId: myClassId } = useAuth()
  const isParent = role === 'parent'
  const isTeacher = role === 'teacher' || role === 'admin'
  // Причины отсутствия заполняют только родители; учитель/админ — только просмотр
  const canEdit = isParent

  const [classes, setClasses] = useState([])
  const [students, setStudents] = useState([])
  const [selectedClassId, setSelectedClassId] = useState(myClassId || '')
  const [selectedId, setSelectedId] = useState(null)
  const [weekOffset, setWeekOffset] = useState(0)
  const [reasons, setReasons] = useState([])
  const [drafts, setDrafts] = useState({})
  const [savingKey, setSavingKey] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  // Привязка ребёнка родителем по номеру карты
  const [cardNumber, setCardNumber] = useState('')
  const [linking, setLinking] = useState(false)

  const dates = useMemo(() => weekDates(weekOffset), [weekOffset])
  const weekFrom = dates[0].value
  const weekTo = dates[dates.length - 1].value


  // 1. Список учеников: родителю — его дети, остальным — класс
  useEffect(() => {
    let alive = true
    setLoading(true)

    const run = async () => {
      try {
        if (isParent) {
          const rows = await loadMyChildren(user?.id)
          if (!alive) return
          setStudents(rows)
        } else {
          const rows = await loadClasses()
          if (!alive) return
          setClasses(rows)
          setSelectedClassId((current) => current || myClassId || rows[0]?.id || '')
        }
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
  }, [isParent, user?.id, myClassId])

  // Для учителя/админа/ученика — грузим состав выбранного класса
  useEffect(() => {
    if (isParent) return
    if (!selectedClassId) return
    let alive = true

    loadRoster(selectedClassId)
      .then((rows) => {
        if (alive) setStudents(rows)
      })
      .catch((loadError) => {
        if (alive) setError(loadError.message)
      })

    return () => {
      alive = false
    }
  }, [isParent, selectedClassId])

  // 2. Причины отсутствия выбранного ученика за неделю
  const reload = useCallback(async () => {
    if (!selectedId) {
      setReasons([])
      return
    }
    setError(null)
    try {
      const rows = await loadAttendanceReasons({
        studentId: selectedId,
        from: weekFrom,
        to: weekTo
      })
      setReasons(rows)
      setDrafts({})
    } catch (loadError) {
      setError(loadError.message)
      setReasons([])
    }
  }, [selectedId, weekFrom, weekTo])

  useEffect(() => {
    reload()
  }, [reload])

  const selectedStudent = students.find((item) => item.id === selectedId) || null

  /** Причина в клетке: черновик правки важнее базы */
  const reasonOf = (date) => {
    const draft = drafts[date]
    if (draft !== undefined) return draft
    const row = reasons.find((item) => item.attend_date === date)
    return row ? row.reason || '' : ''
  }

  // 3. Сохранение причины — когда курсор убран из клетки
  const handleSave = async (date) => {
    const value = drafts[date]
    if (value === undefined || !selectedStudent) return

    setSavingKey(date)
    setError(null)
    try {
      await saveAbsenceReason({
        studentId: selectedStudent.id,
        classId: selectedStudent.classId || selectedClassId,
        date,
        reason: value,
        markedBy: user?.id
      })
      await reload()
    } catch (saveError) {
      setError(saveError.message)
    } finally {
      setSavingKey(null)
    }
  }

  const handleLinkChild = async (event) => {
    event.preventDefault()
    if (linking) return
    setLinking(true)
    setError(null)
    try {
      await linkChildByCard(cardNumber)
      setCardNumber('')
      const rows = await loadMyChildren(user?.id)
      setStudents(rows)
    } catch (linkError) {
      setError(linkError.message)
    } finally {
      setLinking(false)
    }
  }

  return (
    <div className="homework">
      <section className="sheet">
        <h2 className="grades__heading">Посещаемость</h2>

        {error ? (
          <div className="alert alert--error" role="alert">
            {error}
          </div>
        ) : null}

        {isParent ? (
          <form className="form homework__link" onSubmit={handleLinkChild}>
            <label className="field field--compact">
              <span className="field__label">Привязать ребёнка по номеру карты или ID</span>
              <input
                className="field__input"
                type="text"
                placeholder="100000"
                value={cardNumber}
                onChange={(event) => setCardNumber(event.target.value)}
                disabled={linking}
              />
            </label>
            <button className="button button--primary" type="submit" disabled={linking}>
              {linking ? 'Проверяем…' : 'Привязать'}
            </button>
          </form>
        ) : (
          <div className="grades__controls">
            <label className="field field--compact">
              <span className="field__label">Класс</span>
              <select
                className="field__input"
                value={selectedClassId}
                onChange={(event) => {
                  setSelectedClassId(event.target.value)
                  setSelectedId(null)
                }}
                disabled={!isTeacher}
              >
                {classes.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
          </div>
        )}

        <div className="homework__students">
          {loading ? <p className="sheet__note">Загружаем список…</p> : null}
          {!loading && students.length === 0 ? (
            <p className="sheet__note">
              {isParent
                ? 'Нет привязанных детей. Привяжите ребёнка по номеру карты выше.'
                : 'В этом классе пока нет учеников.'}
            </p>
          ) : null}
          {students.map((student) => (
            <button
              key={student.id}
              type="button"
              className={`button button--ghost button--small${
                student.id === selectedId ? ' is-active' : ''
              }`}
              onClick={() => setSelectedId(student.id)}
            >
              {student.fullName}
            </button>
          ))}
        </div>

        {selectedStudent ? (
          <>
            <div className="grades__week">
              <span className="field__label">Неделя</span>
              <div className="grades__week-nav">
                <button
                  type="button"
                  className="button button--ghost button--small"
                  onClick={() => setWeekOffset((current) => current - 1)}
                >
                  ←
                </button>
                <span className="grades__week-title">{weekTitle(weekOffset)}</span>
                <button
                  type="button"
                  className="button button--ghost button--small"
                  onClick={() => setWeekOffset((current) => current + 1)}
                >
                  →
                </button>
              </div>
            </div>

            <div className="grades__table-wrap">
              <table className="grades__table homework__table">
                <thead>
                  <tr>
                    {dates.map((date) => (
                      <th key={date.value} className={date.isToday ? 'is-today' : ''}>
                        <span className="grades__date">{date.label}</span>
                        <span className="grades__weekday">{date.weekday}</span>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    {dates.map((date) => (
                      <td key={date.value} className={date.isToday ? 'is-today' : ''}>
                        {canEdit ? (
                          <>
                            <input
                              className="homework__input"
                              type="text"
                              value={reasonOf(date.value)}
                              placeholder="Болел / причина"
                              onChange={(event) =>
                                setDrafts((current) => ({
                                  ...current,
                                  [date.value]: event.target.value
                                }))
                              }
                              onBlur={() => handleSave(date.value)}
                              disabled={savingKey === date.value}
                            />
                            {savingKey === date.value ? (
                              <span className="sheet__note">Сохраняем…</span>
                            ) : null}
                          </>
                        ) : (
                          <span className="homework__text">{reasonOf(date.value) || '—'}</span>
                        )}
                      </td>
                    ))}
                  </tr>
                </tbody>
              </table>
            </div>

            <p className="sheet__note homework__note">
              {canEdit
                ? `${selectedStudent.fullName}: укажите причину отсутствия в клетке дня — сохранится, когда уберёте курсор. Очистите клетку — причины не будет.`
                : `${selectedStudent.fullName}: причины отсутствий на выбранную неделю.`}
            </p>
          </>
        ) : null}
      </section>
    </div>
  )
}



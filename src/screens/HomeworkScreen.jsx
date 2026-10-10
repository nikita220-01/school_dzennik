import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import {
  clearHomework,
  loadClasses,
  loadHomework,
  loadSubjects,
  saveHomework,
  weekDates,
  weekTitle
} from '../lib/schoolData'

/**
 * Вкладка «Домашнее задание»: строка клеток на 5 дней недели.
 * Сверху — класс, предмет и перелистывание недель (← →).
 * Учитель пишет в клетке текст/цифры (сохранение — когда убрали курсор),
 * ученики и родители читают задания выбранного предмета.
 */
export default function HomeworkScreen() {
  const { role, classId: myClassId } = useAuth()
  const isTeacher = role === 'teacher' || role === 'admin'

  const [classes, setClasses] = useState([])
  const [subjects, setSubjects] = useState([])
  const [classId, setClassId] = useState(myClassId || '')
  const [subjectId, setSubjectId] = useState('')
  const [weekOffset, setWeekOffset] = useState(0)
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  /** Черновик клетки: { '2026-10-06': 'с. 12, № 5' } — правки ещё не сохранённые */
  const [drafts, setDrafts] = useState({})
  /** Дата клетки, которая сохраняется прямо сейчас */
  const [savingKey, setSavingKey] = useState(null)

  const dates = useMemo(() => weekDates(weekOffset), [weekOffset])
  const weekFrom = dates[0].value
  const weekTo = dates[dates.length - 1].value

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

  // Ученик всегда смотрит свой класс
  useEffect(() => {
    if (!isTeacher && myClassId) setClassId(myClassId)
  }, [isTeacher, myClassId])

  // По умолчанию — первый предмет списка
  useEffect(() => {
    setSubjectId((current) => current || subjects[0]?.id || '')
  }, [subjects])

  // 2. Загрузка заданий выбранного предмета за неделю
  const reload = useCallback(async () => {
    if (!classId || !subjectId) {
      setItems([])
      return
    }

    setError(null)
    try {
      const rows = await loadHomework({ classId, subjectId, from: weekFrom, to: weekTo })
      setItems(rows)
      setDrafts({})
    } catch (loadError) {
      setError(loadError.message)
      setItems([])
    }
  }, [classId, subjectId, weekFrom, weekTo])

  useEffect(() => {
    reload()
  }, [reload])

  /** Текст клетки: черновик правки важнее того, что в базе */
  const textOf = (date) => {
    const draft = drafts[date]
    if (draft !== undefined) return draft
    const row = items.find((item) => item.homework_date === date)
    return row ? row.text : ''
  }

  // 3. Сохранение: вызывается, когда учитель убрал курсор из клетки
  const handleSave = async (date) => {
    const text = drafts[date]
    if (text === undefined || !classId || !subjectId) return

    setSavingKey(date)
    setError(null)
    try {
      if (!text.trim()) {
        await clearHomework({ classId, subjectId, date })
      } else {
        await saveHomework({ classId, subjectId, date, text })
      }
      await reload()
    } catch (saveError) {
      setError(saveError.message)
    } finally {
      setSavingKey(null)
    }
  }

  const selectedClass = classes.find((item) => item.id === classId) || null
  const selectedSubject = subjects.find((item) => item.id === subjectId) || null

  return (
    <div className="grades homework">
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

          <label className="field field--compact">
            <span className="field__label">Предмет</span>
            <select
              className="field__input"
              value={subjectId}
              onChange={(event) => setSubjectId(event.target.value)}
              disabled={!subjects.length}
            >
              {subjects.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </label>

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
        </div>

        {error ? (
          <div className="alert alert--error" role="alert">
            {error}
          </div>
        ) : null}

        {loading && !items.length && !drafts.length ? (
          <p className="sheet__note">Загружаем задания…</p>
        ) : (
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
                      {isTeacher ? (
                        <>
                          <input
                            className="homework__input"
                            type="text"
                            value={textOf(date.value)}
                            placeholder="с. 12, № 5"
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
                        <span className="homework__text">{textOf(date.value) || '—'}</span>
                      )}
                    </td>
                  ))}
                </tr>
              </tbody>
            </table>
          </div>
        )}

        <p className="sheet__note homework__note">
          {isTeacher
            ? 'Напишите задание в клетке дня — оно сохранится, как только уберёте курсор. Очистите клетку — задания не будет.'
            : selectedSubject && selectedClass
              ? `${selectedSubject.name} · ${selectedClass.name} класс: задания на выбранную неделю. Недели листаются стрелками.`
              : ''}
        </p>
      </section>
    </div>
  )
}

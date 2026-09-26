import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import {
  ABSENT,
  MARKS,
  average,
  clearCell,
  formatAverage,
  loadClasses,
  loadRoster,
  loadSubjectAverages,
  loadSubjects,
  loadWeekMarks,
  markKey,
  saveAbsent,
  saveMark,
  weekDates,
  weekTitle
} from '../lib/schoolData'

/**
 * Экран «Отметки» на данных Supabase:
 *  • учитель (role teacher/admin) ставит отметки 1…10 и «Н» любому классу, куда назначен;
 *  • ученик видит свой класс, свои отметки и средние баллы по предметам;
 *  • данные лежат в таблицах grades / attendance, поэтому видны с любого устройства.
 */
export default function GradesScreen() {
  const { role, profile, displayName, enrollment, classId: myClassId } = useAuth()
  const isTeacher = role === 'teacher' || role === 'admin'
  const teacherId = profile?.id || null
  const myStudentId = enrollment?.studentId || null

  const [classes, setClasses] = useState([])
  const [subjects, setSubjects] = useState([])
  const [classId, setClassId] = useState(myClassId || '')
  const [subjectId, setSubjectId] = useState('')
  const [weekOffset, setWeekOffset] = useState(0)
  const [roster, setRoster] = useState([])
  const [marks, setMarks] = useState({})
  const [absences, setAbsences] = useState({})
  const [subjectAverages, setSubjectAverages] = useState([])
  const [loading, setLoading] = useState(true)
  const [savingCell, setSavingCell] = useState(null)
  const [error, setError] = useState(null)

  const dates = useMemo(() => weekDates(weekOffset), [weekOffset])
  const weekFrom = dates[0].value
  const weekTo = dates[dates.length - 1].value

  // 1. Справочники: классы (3А…11Г) и предметы
  useEffect(() => {
    let alive = true

    const run = async () => {
      try {
        const [classRows, subjectRows] = await Promise.all([loadClasses(), loadSubjects()])
        if (!alive) return
        setClasses(classRows)
        setSubjects(subjectRows)
        setClassId((current) => current || classRows[0]?.id || '')
        setSubjectId((current) => current || subjectRows[0]?.id || '')
      } catch (loadError) {
        if (alive) {
          setError(loadError.message)
          setLoading(false)
        }
      }
    }

    run()
    return () => {
      alive = false
    }
  }, [])

  // Ученик всегда смотрит свой класс — выбор класса ему недоступен
  useEffect(() => {
    if (!isTeacher && myClassId) setClassId(myClassId)
  }, [isTeacher, myClassId])

  // 2. Список класса и отметки недели
  const loadWeek = useCallback(async () => {
    if (!classId || !subjectId) {
      setRoster([])
      setMarks({})
      setAbsences({})
      setLoading(false)
      return
    }

    setLoading(true)
    setError(null)

    try {
      const rosterRows = await loadRoster(classId)
      setRoster(rosterRows)

      const studentIds = isTeacher
        ? rosterRows.map((student) => student.id)
        : rosterRows.filter((student) => student.id === myStudentId).map((student) => student.id)

      const week = await loadWeekMarks({
        studentIds,
        subjectId,
        classId,
        from: weekFrom,
        to: weekTo
      })

      setMarks(week.marks)
      setAbsences(week.absences)
    } catch (loadError) {
      setError(loadError.message)
      setRoster([])
      setMarks({})
      setAbsences({})
    } finally {
      setLoading(false)
    }
  }, [classId, subjectId, weekFrom, weekTo, isTeacher, myStudentId])

  useEffect(() => {
    loadWeek()
  }, [loadWeek])

  // 3. Средние баллы ученика по предметам (представление v_student_subject_averages)
  useEffect(() => {
    let alive = true

    if (isTeacher || !myStudentId) {
      setSubjectAverages([])
      return () => {
        alive = false
      }
    }

    const run = async () => {
      try {
        const rows = await loadSubjectAverages(myStudentId)
        if (alive) setSubjectAverages(rows)
      } catch (loadError) {
        if (alive) setError(loadError.message)
      }
    }

    run()
    return () => {
      alive = false
    }
  }, [isTeacher, myStudentId])

  // 4. Значения клеток: отметка «перебивает» пропуск дня
  const markOf = (studentId, date) => marks[markKey(studentId, date)] || ''
  const cellValueOf = (studentId, date) =>
    markOf(studentId, date) || (absences[markKey(studentId, date)] ? ABSENT : '')

  const rows = useMemo(() => {
    if (isTeacher) return roster
    if (!myStudentId) return []
    return roster.filter((student) => student.id === myStudentId)
  }, [isTeacher, roster, myStudentId])

  const classAverage = average(
    rows.flatMap((student) => dates.map((date) => markOf(student.id, date)))
  )

  const selectedClass = classes.find((item) => item.id === classId) || null

  const onMarkChange = async (studentId, date, value) => {
    if (!subjectId) return

    const key = markKey(studentId, date)
    setSavingCell(key)
    setError(null)

    try {
      if (!value) {
        await clearCell({ studentId, subjectId, date })
        setMarks((current) => {
          const next = { ...current }
          delete next[key]
          return next
        })
        setAbsences((current) => {
          const next = { ...current }
          delete next[key]
          return next
        })
      } else if (value === ABSENT) {
        await saveAbsent({ studentId, subjectId, classId, date, teacherId })
        setMarks((current) => {
          const next = { ...current }
          delete next[key]
          return next
        })
        setAbsences((current) => ({ ...current, [key]: true }))
      } else {
        await saveMark({ studentId, subjectId, date, value, teacherId })
        setMarks((current) => ({ ...current, [key]: value }))
      }
    } catch (saveError) {
      setError(saveError.message)
      // Показываем то, что реально лежит в базе
      loadWeek()
    } finally {
      setSavingCell(null)
    }
  }


  const emptyText = (() => {
    if (!classes.length) {
      return (
        'Классы не найдены. Примените supabase/apply_all.sql — он создаёт 36 классов 3А…11Г, ' +
        'и проверьте доступ: учителя назначает supabase/promote_teacher.sql.'
      )
    }

    if (isTeacher) {
      return selectedClass?.invite_code
        ? `В классе ${selectedClass.name} пока нет учеников. Передайте ученикам код ${selectedClass.invite_code} — после регистрации и ввода кода они появятся здесь.`
        : 'В этом классе пока нет учеников'
    }

    return myStudentId
      ? 'За эту неделю отметок нет — их поставит учитель'
      : 'Вы ещё не в классе: введите код класса на главной странице в блоке «Присоединиться к классу»'
  })()

  return (
    <div className="grades">
      <div className="grades__controls">
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

      <div className="grades__summary">
        <span className="badge badge--role">
          {isTeacher
            ? `Класс ${selectedClass?.name || '—'}`
            : `Мои отметки · ${selectedClass?.name || 'класс не выбран'}`}
        </span>
        {isTeacher && selectedClass?.invite_code ? (
          <span className="badge">Код класса для учеников: {selectedClass.invite_code}</span>
        ) : null}
        <span className="grades__average">
          Средняя по {isTeacher ? 'классу' : 'неделе'}: <strong>{formatAverage(classAverage)}</strong>
        </span>
        <span className="grades__legend">
          Шкала 1–10 · <strong>{ABSENT}</strong> — не был на уроке (в средний балл не входит)
        </span>
      </div>


      <div className="grades__table-wrap">
        <table className="grades__table">
          <thead>
            <tr>
              <th className="grades__student-col">Ученик</th>
              {dates.map((date) => (
                <th key={date.value} className={date.isToday ? 'is-today' : ''}>
                  <span className="grades__date">{date.label}</span>
                  <span className="grades__weekday">{date.weekday}</span>
                </th>
              ))}
              <th>Средний</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((student) => (
              <tr key={student.id}>
                <th className="grades__student-col" scope="row">
                  {student.fullName}
                </th>
                {dates.map((date) => {
                  const cellKey = markKey(student.id, date.value)
                  const value = cellValueOf(student.id, date.value)

                  return (
                    <td key={date.value} className={date.isToday ? 'is-today' : ''}>
                      {isTeacher ? (
                        <select
                          className={`mark-cell mark-cell--${value || 'empty'}`}
                          value={value}
                          onChange={(event) => onMarkChange(student.id, date.value, event.target.value)}
                          disabled={savingCell === cellKey}
                          aria-label={`${student.fullName}, ${date.label}`}
                        >
                          <option value="">—</option>
                          {MARKS.map((mark) => (
                            <option key={mark} value={mark}>
                              {mark}
                            </option>
                          ))}
                          <option value={ABSENT}>{ABSENT}</option>
                        </select>
                      ) : (
                        <span className={`mark-cell mark-cell--${value || 'empty'}`}>{value || '—'}</span>
                      )}
                    </td>
                  )
                })}
                <td className="grades__average-cell">
                  {formatAverage(average(dates.map((date) => markOf(student.id, date.value))))}
                </td>
              </tr>
            ))}
            {!rows.length ? (
              <tr>
                <td className="grades__empty" colSpan={dates.length + 2}>
                  {loading ? 'Загружаем данные из базы…' : emptyText}
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>

      {!isTeacher && subjectAverages.length ? (
        <div className="panel">
          <h2 className="panel__title">Средний балл по предметам</h2>
          <p className="grades__legend">
            {subjectAverages.map((row) => (
              <span className="badge" key={row.subject_id}>
                {row.subject_name}: {formatAverage(row.average)} ({row.grades_count})
              </span>
            ))}
          </p>
        </div>
      ) : null}

      {isTeacher ? (
        <p className="grades__hint">
          Выберите отметку прямо в клетке: от 10 до 1 или «{ABSENT}». Отметки сохраняются в базе
          Supabase, поэтому ученик увидит их на своём устройстве. Средний балл считается
          автоматически по числовым отметкам недели.
        </p>
      ) : (
        <p className="grades__hint">
          Отметки ставит учитель — здесь таблица только для просмотра. Данные читаются из базы,
          поэтому обновление видно сразу после отметки учителя.
        </p>
      )}
    </div>
  )
}


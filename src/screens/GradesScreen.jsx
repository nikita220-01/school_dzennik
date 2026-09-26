import { useMemo, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import {
  ABSENT,
  CLASSES,
  MARKS,
  SUBJECTS,
  average,
  formatAverage,
  getAllMarks,
  getRoster,
  markKey,
  setMark,
  weekDates,
  weekTitle
} from '../lib/schoolData'

/** Экран «Отметки»: учитель выставляет отметки в таблицу, ученик видит свои */
export default function GradesScreen() {
  const { role, className, displayName } = useAuth()
  const isTeacher = role === 'teacher' || role === 'admin'

  const [classId, setClassId] = useState(className || CLASSES[4])
  const [subject, setSubject] = useState(SUBJECTS[0])
  const [weekOffset, setWeekOffset] = useState(0)
  const [version, setVersion] = useState(0)

  const dates = useMemo(() => weekDates(weekOffset), [weekOffset])
  const roster = useMemo(() => getRoster(classId), [classId])
  const marks = useMemo(() => getAllMarks(), [version, classId, subject, weekOffset])

  const myName = (displayName || '').trim()
  const mine = roster.filter((student) => student.fullName === myName)
  // Если ученика ещё нет в списке класса — показываем его личную строку
  const rows = isTeacher
    ? roster
    : mine.length
      ? mine
      : [{ id: 'me', fullName: myName || 'Мои отметки' }]

  const markOf = (studentId, date) => marks[markKey(classId, subject, date, studentId)] || ''

  const onMarkChange = (studentId, date, value) => {
    setMark(classId, subject, date, studentId, value)
    setVersion((current) => current + 1)
  }

  const allMarksOf = (studentId) => dates.map((date) => markOf(studentId, date.value))

  const classAverage = average(rows.flatMap((student) => allMarksOf(student.id)))

  return (
    <div className="grades">
      <div className="grades__controls">
        <label className="field field--compact">
          <span className="field__label">Класс</span>
          <select
            className="field__input"
            value={classId}
            onChange={(event) => setClassId(event.target.value)}
            disabled={!isTeacher}
          >
            {[classId, ...CLASSES.filter((item) => item !== classId)].map((item) => (
              <option key={item} value={item}>
                {item} класс
              </option>
            ))}
          </select>
        </label>

        <label className="field field--compact">
          <span className="field__label">Предмет</span>
          <select
            className="field__input"
            value={subject}
            onChange={(event) => setSubject(event.target.value)}
          >
            {SUBJECTS.map((item) => (
              <option key={item} value={item}>
                {item}
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

      <div className="grades__summary">
        <span className="badge badge--role">
          {isTeacher ? `Класс ${classId}` : `Мои отметки · ${classId}`}
        </span>
        <span className="grades__average">
          Средняя по {isTeacher ? 'классу' : 'неделе'}:{' '}
          <strong>{formatAverage(classAverage)}</strong>
        </span>
        <span className="grades__legend">
          <strong>{ABSENT}</strong> — не был на уроке (в средний балл не входит)
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
                {dates.map((date) => (
                  <td key={date.value} className={date.isToday ? 'is-today' : ''}>
                    {isTeacher ? (
                      <select
                        className={`mark-cell mark-cell--${markOf(student.id, date.value) || 'empty'}`}
                        value={markOf(student.id, date.value)}
                        onChange={(event) => onMarkChange(student.id, date.value, event.target.value)}
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
                      <span
                        className={`mark-cell mark-cell--${markOf(student.id, date.value) || 'empty'}`}
                      >
                        {markOf(student.id, date.value) || '—'}
                      </span>
                    )}
                  </td>
                ))}
                <td className="grades__average-cell">
                  {formatAverage(average(allMarksOf(student.id)))}
                </td>
              </tr>
            ))}
            {!rows.length ? (
              <tr>
                <td className="grades__empty" colSpan={dates.length + 2}>
                  {isTeacher
                    ? 'В этом классе пока нет учеников'
                    : 'Отметок пока нет — их поставит учитель'}
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>

      {isTeacher ? (
        <p className="grades__hint">
          Выберите отметку прямо в клетке: 5, 4, 3, 2 или «{ABSENT}». Средний балл считается
          автоматически по числовым отметкам недели.
        </p>
      ) : (
        <p className="grades__hint">Отметки ставит учитель — здесь таблица только для просмотра.</p>
      )}
    </div>
  )
}

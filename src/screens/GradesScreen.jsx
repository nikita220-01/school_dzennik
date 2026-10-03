import { useCallback, useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { useAuth } from '../context/AuthContext'
import {
  ABSENT,
  MARKS,
  clearCell,
  formatAverage,
  loadClasses,
  loadRoster,
  loadSubjectAverages,
  loadSubjects,
  loadWeekMarks,
  markKey,
  moveStudentToClass,
  saveAbsent,
  saveMark,
  weekDates,
  weekTitle
} from '../lib/schoolData'

/** Значение выпадающего списка «Все предметы» (просмотр всех предметов сразу) */
const ALL_SUBJECTS = 'ALL'

/**
 * Экран «Отметки»: отдельные «листы», как в Excel.
 *  1) обрамление: выбор класса и предмета, стрелки «← →» перелистывают неделю
 *     (пять рабочих дней на страницу);
 *  2) пробел и второе обрамление: журнал — ученики в столбик, даты сверху;
 *  3) клетки пустые: учитель нажимает клетку и в отдельном окне выбирает отметку.
 */
export default function GradesScreen() {
  const { role, profile, enrollment, classId: myClassId } = useAuth()
  const isTeacher = role === 'teacher' || role === 'admin'
  const teacherId = profile?.id || null
  const myStudentId = enrollment?.studentId || null

  const [classes, setClasses] = useState([])
  const [subjects, setSubjects] = useState([])
  const [classId, setClassId] = useState(myClassId || '')
  const [subjectId, setSubjectId] = useState(ALL_SUBJECTS)
  const [weekOffset, setWeekOffset] = useState(0)
  const [roster, setRoster] = useState([])
  const [marks, setMarks] = useState({})
  const [absences, setAbsences] = useState({})
  const [subjectAverages, setSubjectAverages] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [saving, setSaving] = useState(false)
  /** Открытая клетка: { studentId, date, name } — накладное окно выбора отметки */
  const [cell, setCell] = useState(null)
  const [moveStudentId, setMoveStudentId] = useState('')
  const [moveClassId, setMoveClassId] = useState('')
  const [moving, setMoving] = useState(false)
  const [notice, setNotice] = useState(null)

  const dates = useMemo(() => weekDates(weekOffset), [weekOffset])
  const weekFrom = dates[0].value
  const weekTo = dates[dates.length - 1].value
  const singleSubject = subjectId !== ALL_SUBJECTS

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

  // Ученик всегда смотрит свой класс
  useEffect(() => {
    if (!isTeacher && myClassId) setClassId(myClassId)
  }, [isTeacher, myClassId])

  // 2. Список класса и отметки недели
  const loadWeek = useCallback(async () => {
    if (!classId) {
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
// 3. Средние баллы ученика по предметам
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

  // 4. Значение клетки: отметка важнее пропуска дня
  const markOf = (studentId, date) => marks[markKey(studentId, date)] || ''
  const cellValueOf = (studentId, date) =>
    markOf(studentId, date) || (absences[markKey(studentId, date)] ? ABSENT : '')

  const rows = useMemo(() => {
    if (isTeacher) return roster
    if (!myStudentId) return []
    return roster.filter((student) => student.id === myStudentId)
  }, [isTeacher, roster, myStudentId])

  const selectedClass = classes.find((item) => item.id === classId) || null
  const selectedSubject = subjects.find((item) => item.id === subjectId) || null

  // 5. Сохранение отметки, выбранной в накладном окне
  const applyMark = async (value) => {
    if (!cell || !singleSubject || saving) return

    const { studentId, date } = cell
    const key = markKey(studentId, date)
    setSaving(true)
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

      setCell(null)
    } catch (saveError) {
      setError(saveError.message)
      loadWeek()
    } finally {
      setSaving(false)
    }
  }

  const handleMoveStudent = async () => {
    if (!moveStudentId || !moveClassId) return

    setMoving(true)
    setNotice(null)
    setError(null)

    try {
      await moveStudentToClass({ studentId: moveStudentId, classId: moveClassId })
      const target = classes.find((item) => item.id === moveClassId)
      setNotice(`Ученик переведён в ${target?.name || 'другой'} класс.`)
      setMoveStudentId('')
      await loadWeek()
    } catch (moveError) {
      setError(moveError.message)
    } finally {
      setMoving(false)
    }
  }

  const emptyText = !classes.length
    ? 'Классы не найдены: примените supabase/apply_all.sql и supabase/promote_teacher.sql'
    : isTeacher
      ? `В классе ${selectedClass?.name || ''} нет учеников${
          selectedClass?.invite_code ? `. Код класса для учеников: ${selectedClass.invite_code}` : ''
        }`
      : myStudentId
        ? 'За эту неделю отметок нет'
        : 'Вы ещё не в классе: введите код класса на главной странице'
return (
    <div className="grades">
      {/* ЛИСТ 1 — обрамление с выбором класса и предмета */}
      <section className="sheet">
        <h2 className="sheet__title">Журнал отметок</h2>

        <div className="sheet__row">
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
            >
              <option value={ALL_SUBJECTS}>Все предметы</option>
              {subjects.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </label>

          <div className="grades__week">
            <span className="field__label">Страница (5 рабочих дней)</span>
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

        {isTeacher && selectedClass?.invite_code ? (
          <p className="sheet__note">Код класса для учеников: {selectedClass.invite_code}</p>
        ) : null}

        {!singleSubject ? (
          <p className="sheet__note">
            Просмотр всех предметов: в клетке видно «8, 9» — это разные предметы за день. Чтобы
            поставить отметку, выберите конкретный предмет.
          </p>
        ) : null}
      </section>

      {error ? (
        <div className="alert alert--error" role="alert">
          {error}
        </div>
      ) : null}

      {/* ЛИСТ 2 — сам журнал: ученики в столбик, даты сверху */}
      <section className="sheet">
        <div className="grades__table-wrap">
          <table className="grades__table">
            <thead>
              <tr>
                <th className="grades__title" colSpan={dates.length + 1}>
                  {selectedClass ? `${selectedClass.name} класс` : 'Класс не выбран'}
                  {selectedSubject ? ` · ${selectedSubject.name}` : ' · все предметы'}
                  {' · '}
                  {weekTitle(weekOffset)}
                </th>
              </tr>
              <tr>
                <th className="grades__student-col">Ученик</th>
                {dates.map((date) => (
                  <th key={date.value} className={date.isToday ? 'is-today' : ''}>
                    <span className="grades__date">{date.label}</span>
                    <span className="grades__weekday">{date.weekday}</span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((student) => (
                <tr key={student.id}>
                  <th className="grades__student-col" scope="row">
                    {student.fullName}
                  </th>
                  {dates.map((date) => {
                    const value = cellValueOf(student.id, date.value)
                    const clickable = isTeacher && singleSubject

                    return (
                      <td key={date.value} className={date.isToday ? 'is-today' : ''}>
                        {clickable ? (
                          <button
                            type="button"
                            className={`mark-cell mark-cell--${value || 'empty'}`}
                            onClick={() =>
                              setCell({
                                studentId: student.id,
                                date: date.value,
                                name: `${student.fullName} · ${date.label}`
                              })
                            }
                            aria-label={`Отметка: ${student.fullName}, ${date.label}`}
                          >
                            {value || ''}
                          </button>
                        ) : (
                          <span className={`mark-cell mark-cell--${value || 'empty'}`}>
                            {value || ''}
                          </span>
                        )}
                      </td>
                    )
                  })}
                </tr>
              ))}
              {!rows.length ? (
                <tr>
                  <td className="grades__empty" colSpan={dates.length + 1}>
                    {loading ? 'Загружаем данные из базы…' : emptyText}
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>

        <p className="sheet__note">
          Шкала 1–10 · «{ABSENT}» — не был на уроке (в средний балл не входит).{' '}
          {isTeacher && singleSubject ? 'Нажмите на пустую клетку — откроется окно выбора.' : ''}
        </p>
      </section>

      {/* ЛИСТ 3 — средние баллы ученика по предметам */}
      {!isTeacher && subjectAverages.length ? (
        <section className="sheet">
          <h2 className="sheet__title">Средний балл по предметам</h2>
          <p className="grades__legend">
            {subjectAverages.map((row) => (
              <span className="badge" key={row.subject_id}>
                {row.subject_name}: {formatAverage(row.average)} ({row.grades_count})
              </span>
            ))}
          </p>
        </section>
      ) : null}

      {/* ЛИСТ 4 — перевод ученика в другой класс */}
      {isTeacher ? (
        <section className="sheet">
          <h2 className="sheet__title">Перевод ученика в другой класс</h2>
          <p className="sheet__note">
            Меняется только класс ученика: вход, отметки и карточка остаются те же.
          </p>

          <div className="sheet__row">
            <label className="field field--compact">
              <span className="field__label">Ученик из класса {selectedClass?.name || '—'}</span>
              <select
                className="field__input"
                value={moveStudentId}
                onChange={(event) => setMoveStudentId(event.target.value)}
                disabled={moving || !roster.length}
              >
                <option value="">— выберите ученика —</option>
                {roster.map((student) => (
                  <option key={student.id} value={student.id}>
                    {student.fullName}
                  </option>
                ))}
              </select>
            </label>

            <label className="field field--compact">
              <span className="field__label">Новый класс</span>
              <select
                className="field__input"
                value={moveClassId}
                onChange={(event) => setMoveClassId(event.target.value)}
                disabled={moving || !classes.length}
              >
                <option value="">— выберите класс —</option>
                {classes
                  .filter((item) => item.id !== classId)
                  .map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name} класс
                    </option>
                  ))}
              </select>
            </label>

            <button
              className="button button--primary"
              type="button"
              onClick={handleMoveStudent}
              disabled={moving || !moveStudentId || !moveClassId}
            >
              {moving ? 'Переводим…' : 'Перевести'}
            </button>
          </div>

          {notice ? (
            <div className="alert alert--success" role="status">
              {notice}
            </div>
          ) : null}
        </section>
      ) : null}

      {/* Накладное окно выбора отметки — portal в body, чтобы быть поверх всего */}
      {cell
        ? createPortal(
            <div
              className="mark-dialog"
              role="dialog"
              aria-modal="true"
              onClick={() => (saving ? null : setCell(null))}
            >
              <div
                className="mark-dialog__card"
                onClick={(event) => event.stopPropagation()}
              >
                <h3 className="mark-dialog__title">{cell.name}</h3>
                <p className="mark-dialog__subject">
                  {selectedSubject?.name || 'Все предметы'}
                </p>

                <div className="mark-dialog__grid">
                  {MARKS.map((mark) => (
                    <button
                      key={mark}
                      type="button"
                      className="mark-dialog__mark"
                      onClick={() => applyMark(mark)}
                      disabled={saving}
                    >
                      {mark}
                    </button>
                  ))}
                </div>

                <div className="mark-dialog__actions">
                  <button
                    type="button"
                    className="button button--ghost button--small"
                    onClick={() => applyMark(ABSENT)}
                    disabled={saving}
                  >
                    {ABSENT} — не был
                  </button>
                  <button
                    type="button"
                    className="button button--ghost button--small"
                    onClick={() => applyMark('')}
                    disabled={saving}
                  >
                    Убрать отметку
                  </button>
                  <button
                    type="button"
                    className="button button--small"
                    onClick={() => setCell(null)}
                    disabled={saving}
                  >
                    Отмена
                  </button>
                </div>

                {saving ? <p className="sheet__note">Сохраняем…</p> : null}
              </div>
            </div>,
            document.body
          )
        : null}
    </div>
  )
}
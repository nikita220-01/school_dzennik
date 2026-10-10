/**
 * Школьные данные — теперь из Supabase (таблицы grades/attendance/students,
 * представления v_class_roster и v_student_subject_averages).
 *
 * Все функции чтения/записи асинхронные: экраны держат данные в состоянии React,
 * а localStorage больше не используется — отметки видны с любого устройства.
 *
 * Чистые функции (average, formatAverage, weekDates, weekTitle) оставлены здесь же,
 * чтобы экраны по-прежнему импортировали всё из одного модуля.
 */
import { supabase } from './supabase'

/** Отметки 10-балльной шкалы (по убыванию — так удобнее выбирать в списке) */
export const MARKS = ['10', '9', '8', '7', '6', '5', '4', '3', '2', '1']

/** «Н» — не был на уроке. Не оценка, в средний балл не входит */
export const ABSENT = 'Н'

/** Вид отметки в таблице grades: обычная текущая отметка дневника */
export const GRADE_KIND = 'current'

/**
 * В базе посещаемость поурочная (student_id + attend_date + lesson_number),
 * а клетка дневника — это «день по предмету». Поэтому «Н» из дневника хранится
 * как один урок дня (номер 1).
 */
export const ABSENCE_LESSON_NUMBER = 1

/** Статусы посещаемости, которые в дневнике показываются как «Н» */
const ABSENCE_STATUSES = ['absent', 'excused']

/** Подсказки к частым ошибкам базы (RLS, дубли, неприменённая схема) */
const DB_ERROR_HINTS = [
  {
    test: /row-level security|permission denied/i,
    text:
      'Недостаточно прав в базе. Проверьте, что у аккаунта роль teacher/admin и что учитель назначен ' +
      'на класс (таблица class_subjects) — это делает supabase/promote_teacher.sql'
  },
  { test: /duplicate key/i, text: 'Такая запись уже есть в базе' },
  { test: /invalid api key|invalid jwt/i, text: 'Не принят ключ проекта Supabase' },
  {
    test: /does not exist|schema cache/i,
    text: 'В базе нет нужной таблицы или представления — примените supabase/apply_all.sql в SQL Editor'
  }
]

/** Ошибки базы приводим к понятному русскому тексту (оригинал оставляем в скобках) */
export function translateDbError(error) {
  const raw = error?.message || error?.hint || String(error || 'неизвестная ошибка')
  const hint = DB_ERROR_HINTS.find((item) => item.test.test(raw))
  return hint ? `${hint.text} (${raw})` : raw
}

async function load(query, message) {
  const { data, error } = await query
  if (error) throw new Error(`${message}: ${translateDbError(error)}`)
  return data ?? []
}

/* ------------------------------------------------------------------ */
/*  Справочники                                                        */
/* ------------------------------------------------------------------ */

/** Предметы школы: id нужен для таблицы grades, name — для интерфейса */
export async function loadSubjects() {
  return load(
    supabase.from('subjects').select('id, name, short_name, color').order('name'),
    'Не удалось загрузить список предметов'
  )
}

/** Классы школы: 3А…11Г. Поле invite_code — код для учеников */
export async function loadClasses() {
  return load(
    supabase
      .from('classes')
      .select('id, name, grade_level, academic_year, invite_code')
      .order('grade_level', { ascending: true })
      .order('name', { ascending: true }),
    'Не удалось загрузить список классов'
  )
}

/* ------------------------------------------------------------------ */
/*  Ученики класса                                                     */
/* ------------------------------------------------------------------ */

/** Список учеников класса (виден по правилам RLS: админ, учитель класса, ученик, родитель) */
export async function loadRoster(classId) {
  const rows = await load(
    supabase
      .from('v_class_roster')
      .select('student_id, student_name, card_number, is_active')
      .eq('class_id', classId)
      .order('student_name'),
    'Не удалось загрузить список класса'
  )

  return rows.map((row) => ({
    id: row.student_id,
    fullName: row.student_name || 'Без имени',
    cardNumber: row.card_number,
    isActive: row.is_active
  }))
}

/** Карточка ученика текущего пользователя: класс и номер карты (или null) */
export async function loadMyStudent(profileId) {
  if (!profileId) return null

  const { data, error } = await supabase
    .from('students')
    .select('id, class_id, card_number, classes ( name )')
    .eq('profile_id', profileId)
    .maybeSingle()

  if (error) throw new Error(`Не удалось прочитать карточку ученика: ${translateDbError(error)}`)
  if (!data) return null

  const related = Array.isArray(data.classes) ? data.classes[0] : data.classes

  return {
    studentId: data.id,
    classId: data.class_id,
    className: related?.name || null,
    cardNumber: data.card_number
  }
}

/* ------------------------------------------------------------------ */
/*  Отметки и пропуски                                                 */
/* ------------------------------------------------------------------ */

/** Ключ клетки дневника: ученик + дата */
export function markKey(studentId, date) {
  return `${studentId}|${date}`
}

/**
 * Отметки и пропуски класса за учебную неделю.
 * subjectId = 'ALL' (или пусто) — показать отметки по всем предметам сразу:
 * тогда в клетке будет «8, 9» (несколько предметов за день).
 */
export async function loadWeekMarks({ studentIds, subjectId, classId, from, to }) {
  const empty = { marks: {}, absences: {} }
  if (!studentIds?.length || !classId) return empty

  const allSubjects = subjectId === 'ALL' || !subjectId

  let gradesQuery = supabase
    .from('grades')
    .select('student_id, grade_date, value')
    .eq('kind', GRADE_KIND)
    .in('student_id', studentIds)
    .gte('grade_date', from)
    .lte('grade_date', to)

  if (!allSubjects) gradesQuery = gradesQuery.eq('subject_id', subjectId)

  const [grades, attendance] = await Promise.all([
    gradesQuery,
    supabase
      .from('attendance')
      .select('student_id, attend_date, status')
      .eq('class_id', classId)
      .in('student_id', studentIds)
      .in('status', ABSENCE_STATUSES)
      .gte('attend_date', from)
      .lte('attend_date', to)
  ])

  if (grades.error) throw new Error(`Не удалось загрузить отметки: ${translateDbError(grades.error)}`)
  if (attendance.error) {
    throw new Error(`Не удалось загрузить посещаемость: ${translateDbError(attendance.error)}`)
  }

  const marks = {}
  for (const row of grades.data ?? []) {
    const key = markKey(row.student_id, row.grade_date)
    const value = String(row.value)
    marks[key] = marks[key] ? `${marks[key]}, ${value}` : value
  }

  const absences = {}
  for (const row of attendance.data ?? []) absences[markKey(row.student_id, row.attend_date)] = true

  return { marks, absences }
}

/** Средние баллы ученика по предметам (представление v_student_subject_averages) */
export async function loadSubjectAverages(studentId) {
  if (!studentId) return []
  return load(
    supabase
      .from('v_student_subject_averages')
      .select('subject_id, subject_name, average, weighted_average, grades_count')
      .eq('student_id', studentId)
      .order('subject_name'),
    'Не удалось загрузить средние баллы'
  )
}


/**
 * Учитель ставит числовую отметку 1…10.
 * upsert по ключу (ученик + предмет + дата + вид): повторное сохранение клетки
 * обновляет ту же отметку, а не создаёт дубль.
 */
export async function saveMark({ studentId, subjectId, date, value, teacherId }) {
  const { error } = await supabase.from('grades').upsert(
    {
      student_id: studentId,
      subject_id: subjectId,
      grade_date: date,
      kind: GRADE_KIND,
      value: Number(value),
      teacher_id: teacherId || null
    },
    { onConflict: 'student_id,subject_id,grade_date,kind' }
  )

  if (error) throw new Error(`Не удалось сохранить отметку: ${translateDbError(error)}`)
}

/** Учитель ставит «Н»: запись в attendance + убираем отметку этого предмета за день */
export async function saveAbsent({ studentId, subjectId, classId, date, teacherId }) {
  const { error } = await supabase.from('attendance').upsert(
    {
      student_id: studentId,
      class_id: classId,
      attend_date: date,
      lesson_number: ABSENCE_LESSON_NUMBER,
      status: 'absent',
      marked_by: teacherId || null
    },
    { onConflict: 'student_id,attend_date,lesson_number' }
  )

  if (error) throw new Error(`Не удалось сохранить пропуск: ${translateDbError(error)}`)
  await deleteMark({ studentId, subjectId, date })
}

async function deleteMark({ studentId, subjectId, date }) {
  const { error } = await supabase
    .from('grades')
    .delete()
    .eq('student_id', studentId)
    .eq('subject_id', subjectId)
    .eq('grade_date', date)
    .eq('kind', GRADE_KIND)

  if (error) throw new Error(`Не удалось убрать отметку: ${translateDbError(error)}`)
}

/**
 * Очистить клетку («—»): убираем отметку предмета за этот день и отметку «Н» дня.
 * «Н» в дневнике — день целиком, поэтому очистка снимает её у ученика на весь день.
 */
export async function clearCell({ studentId, subjectId, date }) {
  await deleteMark({ studentId, subjectId, date })

  const { error } = await supabase
    .from('attendance')
    .delete()
    .eq('student_id', studentId)
    .eq('attend_date', date)
    .eq('lesson_number', ABSENCE_LESSON_NUMBER)

  if (error) throw new Error(`Не удалось очистить клетку: ${translateDbError(error)}`)
}

/* ------------------------------------------------------------------ */
/*  Замечания по датам (дата — замечание — просьба)                    */
/* ------------------------------------------------------------------ */

/** Замечания по датам класса за период (для текущей недели журнала) */
export async function loadDateRemarks({ classId, from, to }) {
  return load(
    supabase
      .from('date_remarks')
      .select('id, remark_date, remark, request, created_by, created_at')
      .eq('class_id', classId)
      .gte('remark_date', from)
      .lte('remark_date', to)
      .order('remark_date', { ascending: true })
      .order('created_at', { ascending: true }),
    'Не удалось загрузить замечания по датам'
  )
}

/** Учитель добавляет замечание: дата, текст замечания, просьба */
export async function addDateRemark({ classId, remarkDate, remark, request, createdBy }) {
  const { data, error } = await supabase
    .from('date_remarks')
    .insert({
      class_id: classId,
      remark_date: remarkDate,
      remark: remark.trim(),
      request: (request || '').trim(),
      created_by: createdBy || null
    })
    .select('id, remark_date, remark, request, created_by, created_at')
    .single()

  if (error) throw new Error(`Не удалось добавить замечание: ${translateDbError(error)}`)
  return data
}

/** Учитель удаляет замечание */
export async function deleteDateRemark(remarkId) {
  const { error } = await supabase.from('date_remarks').delete().eq('id', remarkId)

  if (error) throw new Error(`Не удалось удалить замечание: ${translateDbError(error)}`)
}

/** Учитель (или админ) переводит ученика в другой класс: меняется только students.class_id */
export async function moveStudentToClass({ studentId, classId }) {
  if (!studentId || !classId) throw new Error('Выберите ученика и новый класс')

  const { error } = await supabase
    .from('students')
    .update({ class_id: classId })
    .eq('id', studentId)

  if (error) {
    throw new Error(`Не удалось перевести ученика: ${translateDbError(error)}`)
  }
}

/** Ученик присоединяется к классу по коду приглашения (RPC join_class) */
export async function joinClass(code) {
  const trimmed = (code || '').trim()
  if (!trimmed) throw new Error('Укажите код класса, например 7A2025')

  const { data, error } = await supabase.rpc('join_class', { p_invite_code: trimmed })
  if (error) throw new Error(translateDbError(error))
  return data
}

/* ------------------------------------------------------------------ */
/*  Расписание классов (день недели — урок — предмет)                 */
/* ------------------------------------------------------------------ */

/** Дни учебной недели: индекс массива + 1 = weekday в базе (1 = Понедельник) */
export const WEEKDAY_NAMES = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница']

/** Расписание класса: строки { id, weekday, lesson_number, subject_id } */
export async function loadSchedule(classId) {
  return load(
    supabase
      .from('class_schedules')
      .select('id, weekday, lesson_number, subject_id')
      .eq('class_id', classId)
      .order('weekday', { ascending: true })
      .order('lesson_number', { ascending: true }),
    'Не удалось загрузить расписание'
  )
}

/** Учитель ставит или меняет предмет в клетке (день + номер урока) */
export async function saveScheduleSlot({ classId, weekday, lessonNumber, subjectId }) {
  const { error } = await supabase.from('class_schedules').upsert(
    {
      class_id: classId,
      weekday,
      lesson_number: lessonNumber,
      subject_id: subjectId,
      updated_at: new Date().toISOString()
    },
    { onConflict: 'class_id,weekday,lesson_number' }
  )

  if (error) throw new Error(`Не удалось сохранить расписание: ${translateDbError(error)}`)
}

/** Учитель убирает предмет из клетки расписания */
export async function clearScheduleSlot(scheduleId) {
  const { error } = await supabase.from('class_schedules').delete().eq('id', scheduleId)

  if (error) throw new Error(`Не удалось убрать предмет из расписания: ${translateDbError(error)}`)
}

/* ------------------------------------------------------------------ */
/*  Домашнее задание (класс — предмет — дата — текст)                 */
/* ------------------------------------------------------------------ */

/** Задания класса по предмету за период недели */
export async function loadHomework({ classId, subjectId, from, to }) {
  return load(
    supabase
      .from('day_homework')
      .select('id, homework_date, text')
      .eq('class_id', classId)
      .eq('subject_id', subjectId)
      .gte('homework_date', from)
      .lte('homework_date', to)
      .order('homework_date', { ascending: true }),
    'Не удалось загрузить домашнее задание'
  )
}

/** Учитель пишет задание в клетку дня (upsert: одна строка на класс+предмет+дату) */
export async function saveHomework({ classId, subjectId, date, text }) {
  const { error } = await supabase.from('day_homework').upsert(
    {
      class_id: classId,
      subject_id: subjectId,
      homework_date: date,
      text: text.trim(),
      updated_at: new Date().toISOString()
    },
    { onConflict: 'class_id,subject_id,homework_date' }
  )

  if (error) throw new Error(`Не удалось сохранить задание: ${translateDbError(error)}`)
}

/** Учитель очищает клетку дня (удаляет задание предмета на эту дату) */
export async function clearHomework({ classId, subjectId, date }) {
  const { error } = await supabase
    .from('day_homework')
    .delete()
    .eq('class_id', classId)
    .eq('subject_id', subjectId)
    .eq('homework_date', date)

  if (error) throw new Error(`Не удалось очистить задание: ${translateDbError(error)}`)
}

/* ------------------------------------------------------------------ */
/*  Посещаемость: причины отсутствия (заполняют родители)              */
/* ------------------------------------------------------------------ */

/** Дети текущего родителя: [{ id, classId, fullName, cardNumber }] */
export async function loadMyChildren(parentId) {
  // Три простых запроса вместо вложенного embed students→profiles:
  // в схеме students связан с profiles несколькими путями (profile_id,
  // а также обратные связи через parent_students/class_subjects/schedule…),
  // и PostgREST из-за этого падает с ошибкой «more than one relationship».
  const links = await load(
    supabase.from('parent_students').select('student_id').eq('parent_id', parentId),
    'Не удалось загрузить детей'
  )

  const studentIds = links.map((row) => row.student_id).filter(Boolean)
  if (!studentIds.length) return []

  const students = await load(
    supabase
      .from('students')
      .select('id, class_id, card_number, profile_id')
      .in('id', studentIds),
    'Не удалось загрузить учеников'
  )
  if (!students.length) return []

  const profileIds = [...new Set(students.map((student) => student.profile_id).filter(Boolean))]
  let nameById = new Map()
  if (profileIds.length) {
    const profiles = await load(
      supabase.from('profiles').select('id, full_name').in('id', profileIds),
      'Не удалось загрузить имена учеников'
    )
    nameById = new Map(profiles.map((profile) => [profile.id, profile.full_name]))
  }

  return students.map((student) => ({
    id: student.id,
    classId: student.class_id,
    fullName: nameById.get(student.profile_id) || 'Ученик',
    cardNumber: student.card_number
  }))
}

/** Родитель привязывает ребёнка по номеру карты (RPC link_child) */
export async function linkChildByCard(cardNumber) {
  const trimmed = (cardNumber || '').trim()
  if (!trimmed) throw new Error('Укажите номер карты ребёнка')

  const { data, error } = await supabase.rpc('link_child', { p_card_number: trimmed })
  if (error) throw new Error(translateDbError(error))
  return data
}

/**
 * Родитель привязывает нескольких детей по номерам карт сразу.
 * Каждый номер обрабатывается отдельно: один «плохой» не срывает остальные.
 * Возвращает [{ card, ok, error }] — error заполнен только при неудаче.
 */
export async function linkChildrenByCards(cardNumbers) {
  const cards = (cardNumbers || [])
    .map((value) => String(value || '').trim())
    .filter(Boolean)

  const results = []
  for (const card of cards) {
    try {
      await linkChildByCard(card)
      results.push({ card, ok: true, error: null })
    } catch (error) {
      results.push({ card, ok: false, error: error.message })
    }
  }
  return results
}

/** Причины отсутствия ученика за период (посещаемость дня — урок №1) */
export async function loadAttendanceReasons({ studentId, from, to }) {
  return load(
    supabase
      .from('attendance')
      .select('id, attend_date, status, reason')
      .eq('student_id', studentId)
      .eq('lesson_number', ABSENCE_LESSON_NUMBER)
      .gte('attend_date', from)
      .lte('attend_date', to)
      .order('attend_date', { ascending: true }),
    'Не удалось загрузить посещаемость'
  )
}

/**
 * Родитель (или учитель) пишет причину отсутствия на дату.
 * Пустая причина — убираем текст, статус дня не трогаем («Н» учителя остаётся).
 */
export async function saveAbsenceReason({ studentId, classId, date, reason, markedBy }) {
  const text = (reason || '').trim()

  if (!text) {
    const { error } = await supabase
      .from('attendance')
      .update({ reason: null })
      .eq('student_id', studentId)
      .eq('attend_date', date)
      .eq('lesson_number', ABSENCE_LESSON_NUMBER)

    if (error) throw new Error(`Не удалось очистить причину: ${translateDbError(error)}`)
    return
  }

  const { error } = await supabase.from('attendance').upsert(
    {
      student_id: studentId,
      class_id: classId,
      attend_date: date,
      lesson_number: ABSENCE_LESSON_NUMBER,
      status: 'excused',
      reason: text,
      marked_by: markedBy || null
    },
    { onConflict: 'student_id,attend_date,lesson_number' }
  )

  if (error) throw new Error(`Не удалось сохранить причину: ${translateDbError(error)}`)
}

/* ------------------------------------------------------------------ */
/*  Вычисления и даты (без обращения к базе)                           */
/* ------------------------------------------------------------------ */

/** Средняя арифметическая по числовым отметкам; «Н» и пустые клетки игнорируются */
export function average(marks) {
  const numbers = marks.filter((mark) => MARKS.includes(mark)).map(Number)
  if (!numbers.length) return null
  const sum = numbers.reduce((acc, value) => acc + value, 0)
  return Math.round((sum / numbers.length) * 100) / 100
}

export function formatAverage(value) {
  return value === null || value === undefined ? '—' : Number(value).toFixed(2)
}

function iso(date) {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

const WEEKDAYS = ['Пон', 'Вто', 'Сре', 'Чет', 'Пят']

/** Учебная неделя: 5 дней. offset — смещение в неделях (0 — текущая) */
export function weekDates(offset = 0) {
  const today = new Date()
  today.setHours(12, 0, 0, 0)
  const monday = new Date(today)
  const day = (today.getDay() + 6) % 7
  monday.setDate(today.getDate() - day + offset * 7)

  return WEEKDAYS.map((weekday, index) => {
    const date = new Date(monday)
    date.setDate(monday.getDate() + index)
    const dayNumber = String(date.getDate()).padStart(2, '0')
    const monthNumber = String(date.getMonth() + 1).padStart(2, '0')
    return {
      value: iso(date),
      weekday,
      label: `${dayNumber}.${monthNumber}.${date.getFullYear()}`,
      isToday: iso(date) === iso(today)
    }
  })
}

export function weekTitle(offset) {
  const dates = weekDates(offset)
  const from = dates[0]
  const to = dates[dates.length - 1]
  const range = `${from.label} — ${to.label}`
  return offset === 0 ? `Текущая неделя · ${range}` : range
}


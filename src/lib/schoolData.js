/**
 * Школьные данные (демо-слой на localStorage).
 * API специально простой: позже его можно заменить на запросы к Supabase,
 * не меняя экраны.
 */

export const SUBJECTS = [
  'Математика',
  'Русский язык',
  'Литература',
  'История',
  'Физика',
  'Химия',
  'Биология',
  'География',
  'Английский язык',
  'Информатика',
  'Физкультура'
]

export const CLASSES = ['5А', '5Б', '6А', '6Б', '7А', '7Б', '8А', '8Б', '9А', '10А', '11А']

/** Отметки, из которых считается средняя арифметическая («Н» — не оценка) */
export const MARKS = ['5', '4', '3', '2']
export const ABSENT = 'Н'

const GRADES_KEY = 'sd_grades_v1'
const STUDENTS_KEY = 'sd_students_v1'

const SURNAMES = [
  'Иванов', 'Петров', 'Смирнов', 'Кузнецов', 'Соколов', 'Попов', 'Лебедев', 'Новиков',
  'Морозов', 'Волков', 'Зайцев', 'Егоров', 'Павлов', 'Семёнов', 'Голубев', 'Виноградов',
  'Богданов', 'Воробьёв', 'Фёдоров', 'Михайлов'
]
const NAMES = ['Артём', 'София', 'Иван', 'Мария', 'Даниил', 'Анна', 'Пётр', 'Полина', 'Егор', 'Вера']
const FEMALE_END = { Иванова: true }

function hash(text) {
  let value = 7
  for (let i = 0; i < text.length; i += 1) value = (value * 31 + text.charCodeAt(i)) % 1000003
  return value
}

function reading(key, fallback) {
  try {
    const raw = window.localStorage.getItem(key)
    return raw ? JSON.parse(raw) : fallback
  } catch {
    return fallback
  }
}

function writing(key, value) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value))
  } catch {
    /* приватный режим — просто не сохраняем */
  }
}

function femaleSurname(surname) {
  return FEMALE_END[surname] ? surname : `${surname}а`
}

/** Ученики класса: демо-состав (детерминированный по названию класса) + зарегистрированные */
export function getRoster(classId) {
  const registered = reading(STUDENTS_KEY, {})[classId] || []
  const seed = hash(classId)
  const list = []

  for (let i = 0; i < 12; i += 1) {
    const surname = SURNAMES[(seed + i * 3) % SURNAMES.length]
    const name = NAMES[(seed + i * 5) % NAMES.length]
    const isGirl = (seed + i) % 2 === 1
    list.push({ id: `${classId}-demo-${i}`, fullName: `${isGirl ? femaleSurname(surname) : surname} ${name}` })
  }

  registered.forEach((student) => {
    if (!list.some((item) => item.fullName === student.fullName)) {
      list.push({ id: `${classId}-user-${hash(student.fullName)}`, fullName: student.fullName })
    }
  })

  return list
}

export function addStudent(classId, fullName) {
  const all = reading(STUDENTS_KEY, {})
  const list = all[classId] || []
  if (!list.some((item) => item.fullName === fullName)) list.push({ fullName })
  all[classId] = list
  writing(STUDENTS_KEY, all)
}

function cellKey(classId, subject, date, studentId) {
  return `${classId}|${subject}|${date}|${studentId}`
}

export { cellKey as markKey }

/** Все отметки одним объектом (чтобы не читать хранилище на каждую клетку) */
export function getAllMarks() {
  return reading(GRADES_KEY, {})
}

export function getMark(classId, subject, date, studentId) {
  return reading(GRADES_KEY, {})[cellKey(classId, subject, date, studentId)] || ''
}

export function setMark(classId, subject, date, studentId, value) {
  const all = reading(GRADES_KEY, {})
  const key = cellKey(classId, subject, date, studentId)
  if (value) all[key] = value
  else delete all[key]
  writing(GRADES_KEY, all)
  return all
}

/** Средняя арифметическая по числовым отметкам; «Н» и пустые клетки игнорируются */
export function average(marks) {
  const numbers = marks.filter((mark) => MARKS.includes(mark)).map(Number)
  if (!numbers.length) return null
  const sum = numbers.reduce((acc, value) => acc + value, 0)
  return Math.round((sum / numbers.length) * 100) / 100
}

export function formatAverage(value) {
  return value === null ? '—' : value.toFixed(2)
}

function iso(date) {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

const WEEKDAYS = ['пн', 'вт', 'ср', 'чт', 'пт']

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
      label: `${dayNumber}.${monthNumber}`,
      isToday: iso(date) === iso(today)
    }
  })
}

export function weekTitle(offset) {
  const dates = weekDates(offset)
  const from = dates[0]
  const to = dates[dates.length - 1]
  return offset === 0 ? 'Текущая неделя' : `${from.label} — ${to.label}`
}

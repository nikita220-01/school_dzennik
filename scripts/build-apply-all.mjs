/**
 * Сборка supabase/apply_all.sql из отдельных файлов.
 * Запуск:  npm run build:sql
 *
 * Зачем: один файл удобно вставлять в SQL Editor Supabase целиком.
 * Порядок частей важен: миграции → seed (данные) → promote (роли).
 * Между частями добавляются маркеры «НАЧАЛО/КОНЕЦ», чтобы в редакторе было
 * видно, из какого файла пришёл тот или иной блок.
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const supabaseDir = join(root, 'supabase')

/** Части в порядке применения. note — краткое описание для шапки файла */
const PARTS = [
  {
    file: 'migrations/20260101000000_00_extensions_and_types.sql',
    note: 'расширения и ENUM'
  },
  {
    file: 'migrations/20260101000001_01_core_tables.sql',
    note: '15 таблиц и индексы'
  },
  {
    file: 'migrations/20260101000002_02_functions_and_triggers.sql',
    note: 'функции и триггеры'
  },
  {
    file: 'migrations/20260101000003_03_rls_policies.sql',
    note: 'права доступа (RLS)'
  },
  {
    file: 'migrations/20260101000004_04_views.sql',
    note: '5 представлений (VIEW)'
  },
  {
    file: 'migrations/20260101000005_05_classes_and_grades_scale.sql',
    note: 'классы 3А…11Г (36 классов) и 10-балльная шкала оценок'
  },
  {
    file: 'migrations/20260101000006_06_teacher_can_move_students.sql',
    note: 'учитель может переводить ученика в другой класс'
  },
  {
    file: 'seed.sql',
    note: 'демо-данные: школа, 4 четверти, 15 предметов, все классы 3А…11Г'
  },
  {
    file: 'promote_teacher.sql',
    note:
      'роль «учитель» тем, кто регистрировался учителем (или самому новому аккаунту)\n' +
      '--                                                                  и назначение ему классов; пока пользователей нет — пишет NOTICE'
  }
]

const HEADER = `-- =============================================================================
--  ШКОЛЬНЫЙ ДНЕВНИК — ЗАПУСТИТЬ ВСЁ ОДНИМ ФАЙЛОМ
--
--  Этот файл склеен из ${PARTS.length} частей (создан автоматически, порядок важен):
${PARTS.map((part, index) => `--    ${index + 1}) ${part.file} — ${part.note}`).join('\n')}
--
--  КАК ЗАПУСКАТЬ
--    1. Supabase → ваш проект → SQL Editor → New query.
--    2. Откройте этот файл, выделите всё (Ctrl+A), скопируйте (Ctrl+C) и вставьте в редактор.
--    3. Нажмите Run (Ctrl+Enter). Ожидаемый результат: «Success. No rows returned».
--    4. Проверка в новом запросе:
--         select count(*) from public.subjects;   -- 15 предметов
--         select count(*) from public.classes;    -- 36 классов (3А…11Г)
--         select name, invite_code from public.classes order by grade_level, name;
--
--  ФАЙЛ ИДЕМПОТЕНТНЫЙ: повторный запуск безопасен (if not exists / create or replace /
--  drop ... if exists), поэтому его можно прогнать ещё раз, если проект «поехал».
--  Хотите по шагам и с остановками — запускайте исходные файлы по одному из папки supabase/migrations.
-- =============================================================================
`

/** Читаем файл и приводим переводы строк к \r\n (как в остальном проекте) */
function readPart(relativePath) {
  const raw = readFileSync(join(supabaseDir, relativePath), 'utf8').replace(/^\uFEFF/, '')
  const lines = raw.split(/\r?\n/)
  while (lines.length && lines[lines.length - 1] === '') lines.pop()
  return lines.join('\r\n')
}

const startMarker = (relativePath) =>
  `-- >>>>>>>>>>>>>>>>>>>>>> НАЧАЛО: supabase\\${relativePath.replace(/\//g, '\\')} >>>>>>>>>>>>>>>>>>>>>>`

const endMarker = (relativePath) =>
  `-- <<<<<<<<<<<<<<<<<<<<<< КОНЕЦ: supabase\\${relativePath.replace(/\//g, '\\')} <<<<<<<<<<<<<<<<<<<<<<`

const chunks = [HEADER]
const missing = []

PARTS.forEach((part, index) => {
  let body
  try {
    body = readPart(part.file)
  } catch (error) {
    missing.push(`${part.file} (${error.code || error.message})`)
    return
  }

  const isLast = index === PARTS.length - 1
  chunks.push(`${startMarker(part.file)}\r\n`)
  if (!isLast) chunks.push('\r\n')
  chunks.push(`${body}\r\n\r\n${endMarker(part.file)}\r\n`)
  if (!isLast) chunks.push('\r\n')
})

// Шапка в шаблоне набрана с обычными переводами строк — приводим их к \r\n,
// чтобы файл был единообразным (как и остальные файлы проекта на Windows).
const output = chunks.join('').replace(/(?<!\r)\n/g, '\r\n')
writeFileSync(join(supabaseDir, 'apply_all.sql'), output, 'utf8')

if (missing.length) {
  console.error('Не найдены файлы (пропущены в сборке):')
  for (const item of missing) console.error(`  - ${item}`)
  process.exitCode = 1
}

console.log(`supabase/apply_all.sql собран из ${PARTS.length - missing.length} частей.`)
console.log(`Размер: ${Buffer.byteLength(output, 'utf8')} байт, строк: ${output.split('\r\n').length - 1}.`)

/**
 * Проверка SQL: синтаксис и сборка apply_all.sql.
 * Запуск:  npm run check:sql
 *
 * Что делает:
 *  1) парсит настоящим парсером PostgreSQL (pgsql-parser / libpg_query) все файлы
 *     supabase/migrations/*.sql, seed.sql, promote_teacher.sql и apply_all.sql;
 *  2) проверяет, что в apply_all.sql есть блок «НАЧАЛО/КОНЕЦ» для каждого файла
 *     (иначе сборщик забыли запустить — npm run build:sql);
 *  3) проверяет, что нет BOM и файлы в UTF-8.
 */
import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { parse } from 'pgsql-parser'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const supabaseDir = join(root, 'supabase')

const migrations = readdirSync(join(supabaseDir, 'migrations'))
  .filter((name) => name.endsWith('.sql'))
  .sort()

const parts = [...migrations.map((name) => `migrations/${name}`), 'seed.sql', 'promote_teacher.sql']

const files = [...parts, 'apply_all.sql']
let failed = 0

for (const relativePath of files) {
  const fullPath = join(supabaseDir, relativePath)
  const raw = readFileSync(fullPath, 'utf8')

  if (raw.charCodeAt(0) === 0xfeff) {
    console.log(` FAIL  ${relativePath} — файл начинается с BOM`)
    failed += 1
    continue
  }

  try {
    const result = await parse(raw)
    const count = result?.stmts?.length ?? result?.parse_tree?.stmts?.length ?? 0
    console.log(`  OK   ${relativePath} — ${count} инструкций`)
  } catch (error) {
    console.log(` FAIL  ${relativePath} — ${error.message.split('\n')[0]}`)
    failed += 1
  }
}

// Сборка: каждый файл должен быть вставлен в apply_all.sql
const applyAll = readFileSync(join(supabaseDir, 'apply_all.sql'), 'utf8')
for (const relativePath of parts) {
  const windowsPath = relativePath.replace(/\//g, '\\')
  const hasBoth =
    applyAll.includes(`НАЧАЛО: supabase\\${windowsPath}`) &&
    applyAll.includes(`КОНЕЦ: supabase\\${windowsPath}`)
  if (!hasBoth) {
    console.log(` FAIL  apply_all.sql — нет блока для ${relativePath} (запустите npm run build:sql)`)
    failed += 1
  }
}

console.log(
  failed === 0
    ? `\nВсё в порядке: ${files.length} SQL-файлов разобраны, apply_all.sql содержит все ${parts.length} частей.`
    : `\nПроблем: ${failed}`
)
process.exit(failed === 0 ? 0 : 1)

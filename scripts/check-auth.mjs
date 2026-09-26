/**
 * Самопроверка связки с Supabase (безопасная: ничего не создаёт и не удаляет).
 * Запуск:  npm run check:auth
 *
 * Проверяет:
 *  1) читается ли .env и валиден ли публичный ключ (publishable / anon);
 *  2) отвечает ли Supabase Auth;
 *  3) приходят ли ожидаемые ошибки входа/регистрации и как они переводятся на русский.
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { translateAuthError } from '../src/lib/authErrors.js'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

function loadEnv() {
  try {
    const raw = readFileSync(join(root, '.env'), 'utf8')
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const eq = trimmed.indexOf('=')
      if (eq === -1) continue
      const key = trimmed.slice(0, eq).trim()
      const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, '')
      if (!(key in process.env)) process.env[key] = value
    }
  } catch {
    // .env нет — работаем с переменными окружения
  }
}

function mask(value) {
  if (!value) return '—'
  return `${value.slice(0, 12)}…${value.slice(-4)} (${value.length} символов)`
}

loadEnv()

const url = process.env.VITE_SUPABASE_URL
const key = process.env.VITE_SUPABASE_ANON_KEY

const results = []
const record = (name, ok, info) => {
  results.push({ name, ok, info })
  console.log(`${ok ? '  OK  ' : ' FAIL '} ${name}${info ? ` — ${info}` : ''}`)
}

console.log('Проверка подключения к Supabase\n')

if (!url || !key) {
  record('Переменные окружения', false, 'нет VITE_SUPABASE_URL или VITE_SUPABASE_ANON_KEY')
  console.log('\nСкопируйте .env.example в .env и вставьте значения из Supabase.')
  process.exit(1)
}

record('VITE_SUPABASE_URL', /^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url), url)
record(
  'Публичный ключ',
  true,
  key.startsWith('sb_publishable_') ? `publishable ${mask(key)}` : `anon JWT ${mask(key)}`
)

if (key.startsWith('sb_secret_') || key.includes('service_role')) {
  record('Безопасность ключа', false, 'в браузерный ключ попал secret/service_role — так нельзя')
  process.exit(1)
}

const supabase = createClient(url, key)

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function main() {
  try {
    const { data, error } = await supabase.auth.getSession()
    record('Ответ Auth API', !error, error ? translateAuthError(error) : 'сессия проверена, ошибок нет')
    if (error) throw error

    if (data?.session) {
      console.log(`       (найдена сохранённая сессия пользователя ${data.session.user.email})`)
    }
  } catch (error) {
    record('Ответ Auth API', false, translateAuthError(error))
    console.log('\nSupabase недоступен. Проверьте интернет, URL проекта и что проект не на паузе.')
    process.exit(1)
  }

  // 1. Вход с несуществующими данными — ждём "Invalid login credentials"
  const fake = await supabase.auth.signInWithPassword({
    email: `nonexistent-${Date.now()}@example.com`,
    password: 'not-a-real-password'
  })
  record(
    'Вход: неверные данные',
    /invalid login credentials/i.test(fake.error?.message || ''),
    fake.error ? translateAuthError(fake.error) : 'неожиданно вернулась сессия!'
  )

  await sleep(600)

  // 2. Регистрация с коротким паролем — ждём ошибку валидации пароля (пользователь не создаётся)
  const weak = await supabase.auth.signUp({
    email: `weak-${Date.now()}@example.com`,
    password: '123'
  })
  record(
    'Регистрация: короткий пароль',
    Boolean(weak.error),
    weak.error ? translateAuthError(weak.error) : 'неожиданно вернулись данные пользователя'
  )

  const failed = results.filter((item) => !item.ok)
  console.log(
    failed.length === 0
      ? '\nВсё в порядке: ключ рабочий, Auth отвечает, ошибки переводятся на русский.'
      : `\nПроблемы: ${failed.map((item) => item.name).join(', ')}`
  )
  process.exit(failed.length === 0 ? 0 : 1)
}

main()

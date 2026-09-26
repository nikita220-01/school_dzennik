import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'Не заданы VITE_SUPABASE_URL или VITE_SUPABASE_ANON_KEY. ' +
      'Скопируйте .env.example в .env и вставьте значения из Supabase (Project Settings → API Keys).'
  )
}

/**
 * Единственный клиент Supabase для всего приложения.
 * Используется только ПУБЛИЧНЫЙ ключ (publishable / anon):
 * доступ к данным ограничивается правилами RLS на стороне базы.
 */
export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
})

export const SUPABASE_URL = url

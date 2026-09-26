import { createClient } from '@supabase/supabase-js'

/**
 * Запасные значения (fallback).
 * Публичный publishable-ключ не секретный: он попадает в JS и действует только в рамках RLS.
 * Переменные окружения VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY имеют приоритет.
 */
const FALLBACK_URL = 'https://ftvhzgdggzcthyfvzcbh.supabase.co'
const FALLBACK_ANON_KEY = 'sb_publishable_C3RVV2BMDfwdK5wv5nGt8w_Pm17Z_QH'

const url = import.meta.env.VITE_SUPABASE_URL || FALLBACK_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || FALLBACK_ANON_KEY

/** Понятное сообщение вместо пустого экрана, если переменные окружения не заданы и fallback пуст */
export const configError =
  !url || !anonKey
    ? 'Не заданы VITE_SUPABASE_URL и/или VITE_SUPABASE_ANON_KEY. ' +
      'Проверьте значения в src/lib/supabase.js (константы FALLBACK_*) или в .env.'
    : null

export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
})

export const SUPABASE_URL = url


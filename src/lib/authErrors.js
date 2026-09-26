/**
 * Понятные русские тексты вместо англоязычных ошибок Supabase Auth.
 */
const MESSAGES = [
  [/invalid login credentials/i, 'Неверный email или пароль'],
  [/email not confirmed/i, 'Email не подтверждён — проверьте почту и перейдите по ссылке из письма'],
  [/user already registered/i, 'Пользователь с таким email уже зарегистрирован'],
  [/password should be at least (\d+) characters/i, 'Пароль должен быть не короче 6 символов'],
  [/password.*too short|password.*weak/i, 'Слишком простой пароль — минимум 6 символов'],
  [/unable to validate email address|invalid format/i, 'Некорректный email'],
  [/email rate limit exceeded|over_email_send_rate_limit/i, 'Слишком много писем. Подождите минуту и попробуйте снова'],
  [/for security purposes.*(\d+) seconds/i, 'Слишком часто. Подождите немного и попробуйте снова'],
  [/signups? not allowed|signup is disabled/i, 'Регистрация отключена в настройках Supabase (Authentication → Providers → Email)'],
  [/anonymous sign-?ins? (are|is) disabled/i, 'Анонимный вход отключён в настройках Supabase'],
  [/user not found/i, 'Пользователь не найден'],
  [/network|failed to fetch|load failed/i, 'Нет связи с Supabase — проверьте интернет и VITE_SUPABASE_URL']
]

export function translateAuthError(error) {
  if (!error) return 'Неизвестная ошибка'
  const raw = error.message || String(error)

  for (const [pattern, text] of MESSAGES) {
    if (pattern.test(raw)) return text
  }

  return raw
}

/** Простая проверка email — без сложных регулярных выражений */
export function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(String(value || '').trim())
}

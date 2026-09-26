import { useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { isValidEmail } from '../lib/authErrors'

const ROLES = [
  { value: 'student', label: 'Ученик', emoji: '🎒' },
  { value: 'parent', label: 'Родитель', emoji: '👪' },
  { value: 'teacher', label: 'Учитель', emoji: '👩‍🏫' }
]

export default function AuthScreen() {
  const { signIn, signUp } = useAuth()

  const [mode, setMode] = useState('login') // 'login' | 'register'
  const [form, setForm] = useState({
    fullName: '',
    email: '',
    password: '',
    passwordRepeat: '',
    role: 'student'
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [notice, setNotice] = useState(null)

  const update = (field) => (event) => {
    setForm((prev) => ({ ...prev, [field]: event.target.value }))
  }

  const switchMode = (nextMode) => {
    if (busy) return
    setMode(nextMode)
    setError(null)
    setNotice(null)
  }

  const handleLogin = async () => {
    if (!form.email.trim() || !form.password) {
      throw new Error('Введите email и пароль')
    }
    if (!isValidEmail(form.email)) {
      throw new Error('Проверьте формат email, например ivan@example.com')
    }
    await signIn(form.email, form.password)
  }

  const handleRegister = async () => {
    if (!form.fullName.trim()) {
      throw new Error('Укажите фамилию и имя')
    }
    if (!isValidEmail(form.email)) {
      throw new Error('Проверьте формат email, например ivan@example.com')
    }
    if (form.password.length < 6) {
      throw new Error('Пароль должен быть не короче 6 символов')
    }
    if (form.password !== form.passwordRepeat) {
      throw new Error('Пароли не совпадают')
    }

    const { needsEmailConfirm } = await signUp({
      email: form.email,
      password: form.password,
      fullName: form.fullName,
      role: form.role
    })

    if (needsEmailConfirm) {
      setNotice(
        `Аккаунт создан. Мы отправили письмо на ${form.email.trim()} — перейдите по ссылке в письме, затем войдите.`
      )
      setMode('login')
      setForm((prev) => ({ ...prev, password: '', passwordRepeat: '' }))
    }
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    if (busy) return

    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      if (mode === 'login') {
        await handleLogin()
      } else {
        await handleRegister()
      }
    } catch (submitError) {
      setError(submitError.message || 'Неизвестная ошибка')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth">
      <div className="auth__card">
        <header className="auth__header">
          <span className="auth__logo" role="img" aria-label="Книга">
            📘
          </span>
          <div>
            <h1 className="auth__title">Школьный дневник</h1>
            <p className="auth__subtitle">
              {mode === 'login'
                ? 'Войдите, чтобы увидеть дневник'
                : 'Создайте аккаунт ученика, родителя или учителя'}
            </p>
          </div>
        </header>

        <div className="tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'login'}
            className={`tabs__item ${mode === 'login' ? 'is-active' : ''}`}
            onClick={() => switchMode('login')}
          >
            Вход
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'register'}
            className={`tabs__item ${mode === 'register' ? 'is-active' : ''}`}
            onClick={() => switchMode('register')}
          >
            Регистрация
          </button>
        </div>

        <form className="form" onSubmit={onSubmit} noValidate>
          {mode === 'register' && (
            <label className="field">
              <span className="field__label">Фамилия и имя</span>
              <input
                className="field__input"
                type="text"
                autoComplete="name"
                placeholder="Иванов Иван"
                value={form.fullName}
                onChange={update('fullName')}
                disabled={busy}
              />
            </label>
          )}

          <label className="field">
            <span className="field__label">Email</span>
            <input
              className="field__input"
              type="email"
              autoComplete="email"
              placeholder="ivan@example.com"
              value={form.email}
              onChange={update('email')}
              disabled={busy}
            />
          </label>

          <label className="field">
            <span className="field__label">Пароль</span>
            <input
              className="field__input"
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              placeholder="Минимум 6 символов"
              value={form.password}
              onChange={update('password')}
              disabled={busy}
            />
          </label>

          {mode === 'register' && (
            <>
              <label className="field">
                <span className="field__label">Повторите пароль</span>
                <input
                  className="field__input"
                  type="password"
                  autoComplete="new-password"
                  placeholder="Ещё раз"
                  value={form.passwordRepeat}
                  onChange={update('passwordRepeat')}
                  disabled={busy}
                />
              </label>

              <fieldset className="field field--roles">
                <legend className="field__label">Кто вы?</legend>
                <div className="roles">
                  {ROLES.map((role) => (
                    <label
                      key={role.value}
                      className={`role ${form.role === role.value ? 'is-active' : ''}`}
                    >
                      <input
                        type="radio"
                        name="role"
                        value={role.value}
                        checked={form.role === role.value}
                        onChange={update('role')}
                        disabled={busy}
                      />
                      <span className="role__emoji" aria-hidden="true">
                        {role.emoji}
                      </span>
                      <span>{role.label}</span>
                    </label>
                  ))}
                </div>
              </fieldset>
            </>
          )}

          {error ? (
            <div className="alert alert--error" role="alert">
              {error}
            </div>
          ) : null}

          {notice ? (
            <div className="alert alert--success" role="status">
              {notice}
            </div>
          ) : null}

          <button className="button button--primary" type="submit" disabled={busy}>
            {busy ? (
              <>
                <span className="button__spinner" aria-hidden="true" />
                Подождите…
              </>
            ) : mode === 'login' ? (
              'Войти'
            ) : (
              'Создать аккаунт'
            )}
          </button>
        </form>

        <p className="auth__hint">
          {mode === 'login' ? (
            <>
              Ещё нет аккаунта?{' '}
              <button type="button" className="link" onClick={() => switchMode('register')}>
                Зарегистрируйтесь
              </button>
            </>
          ) : (
            <>
              Уже есть аккаунт?{' '}
              <button type="button" className="link" onClick={() => switchMode('login')}>
                Войдите
              </button>
            </>
          )}
        </p>
      </div>
    </div>
  )
}

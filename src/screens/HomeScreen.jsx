import { useState } from 'react'
import { useAuth } from '../context/AuthContext'
import GradesScreen from './GradesScreen'

const ROLE_LABELS = {
  admin: 'Администратор',
  teacher: 'Учитель',
  parent: 'Родитель',
  student: 'Ученик'
}

const SECTIONS = [
  { title: 'Дневник', emoji: '📔', hint: 'Оценки за неделю' },
  { title: 'Расписание', emoji: '🗓️', hint: 'Уроки по дням' },
  { title: 'Домашние задания', emoji: '✏️', hint: 'Что задали' },
  { title: 'Посещаемость', emoji: '✅', hint: 'Пропуски и причины' }
]

/**
 * Блок «Присоединиться к классу».
 * Класс хранится в базе (таблица students), а привязка идёт по коду приглашения
 * из таблицы classes — тот же код выдаёт учитель в разделе «Отметки».
 */
function JoinClassPanel({ currentClassName }) {
  const { joinClass } = useAuth()
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [done, setDone] = useState(null)

  const onSubmit = async (event) => {
    event.preventDefault()
    if (busy) return

    setBusy(true)
    setError(null)
    setDone(null)

    try {
      await joinClass(code)
      setCode('')
      setDone('Готово: класс сохранён в базе. Отметки смотрите во вкладке «Отметки».')
    } catch (joinError) {
      setError(joinError.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="panel">
      <h2 className="panel__title">Присоединиться к классу</h2>
      <p className="home__meta">
        {currentClassName
          ? `Ваш класс по базе: ${currentClassName}. Можно перейти в другой класс, введя новый код.`
          : 'Введите код класса (например 7A2025) — после этого вы появитесь в списке класса у учителя.'}
      </p>

      <form className="form" onSubmit={onSubmit}>
        <label className="field field--compact">
          <span className="field__label">Код класса</span>
          <input
            className="field__input"
            type="text"
            placeholder="7A2025"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            disabled={busy}
          />
        </label>

        <button className="button button--primary" type="submit" disabled={busy}>
          {busy ? (
            <>
              <span className="button__spinner" aria-hidden="true" />
              Проверяем…
            </>
          ) : (
            'Присоединиться'
          )}
        </button>
      </form>

      {error ? (
        <div className="alert alert--error" role="alert">
          {error}
        </div>
      ) : null}

      {done ? (
        <div className="alert alert--success" role="status">
          {done}
        </div>
      ) : null}
    </section>
  )
}

export default function HomeScreen() {
  const {
    displayName,
    user,
    profile,
    role,
    profileRole,
    metaRole,
    className,
    enrollment,
    profileError,
    signOut
  } = useAuth()
  const [tab, setTab] = useState('diary') // 'diary' | 'grades'
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  const onSignOut = async () => {
    setBusy(true)
    setError(null)
    try {
      await signOut()
    } catch (signOutError) {
      setError(signOutError.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="home">
      <header className="home__top">
        <div>
          <p className="home__greeting">Здравствуйте,</p>
          <h1 className="home__name">{displayName || 'пользователь'}</h1>
          <p className="home__meta">
            <span className="badge badge--role">{ROLE_LABELS[role] || 'Роль не задана'}</span>
            {className ? <span className="badge">{className} класс</span> : null}
            <span className="home__email">{user?.email}</span>
          </p>
        </div>

        <button className="button button--ghost" type="button" onClick={onSignOut} disabled={busy}>
          {busy ? 'Выходим…' : 'Выйти'}
        </button>
      </header>

      {error ? (
        <div className="alert alert--error" role="alert">
          {error}
        </div>
      ) : null}

      {profileError ? (
        <div className="alert alert--info">
          Аккаунт работает, но профиль из таблицы <code>profiles</code> не прочитан: данные берутся
          из метаданных авторизации. Подробности: {profileError}
        </div>
      ) : null}

      {metaRole === 'teacher' && profileRole !== 'teacher' && profileRole !== 'admin' ? (
        <div className="alert alert--info">
          Вы регистрировались как учитель, но в базе у профиля роль «{profileRole || 'не задана'}».
          Пока роль не выдана, база не разрешит ставить отметки. Администратору школы нужно
          выполнить файл <code>supabase/promote_teacher.sql</code> в SQL Editor Supabase.
        </div>
      ) : null}

      {role === 'student' && !enrollment ? <JoinClassPanel currentClassName={className} /> : null}

      <nav className="tabs tabs--screens" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'diary'}
          className={`tabs__item ${tab === 'diary' ? 'is-active' : ''}`}
          onClick={() => setTab('diary')}
        >
          📔 Дневник
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'grades'}
          className={`tabs__item ${tab === 'grades' ? 'is-active' : ''}`}
          onClick={() => setTab('grades')}
        >
          📝 Отметки
        </button>
      </nav>

      {tab === 'grades' ? (
        <GradesScreen />
      ) : (
        <>
          <section className="cards">
        {SECTIONS.map((section) => (
          <article className="card" key={section.title}>
            <span className="card__emoji" aria-hidden="true">
              {section.emoji}
            </span>
            <h2 className="card__title">{section.title}</h2>
            <p className="card__hint">{section.hint}</p>
            <span className="badge badge--soon">скоро</span>
          </article>
        ))}
      </section>

      <section className="panel">
        <h2 className="panel__title">Профиль</h2>
        <dl className="kv">
          <div>
            <dt>ID пользователя</dt>
            <dd className="kv__mono">{user?.id}</dd>
          </div>
          <div>
            <dt>Email</dt>
            <dd>{user?.email}</dd>
          </div>
          <div>
            <dt>Роль</dt>
            <dd>{profile?.role || role || '—'}</dd>
          </div>
          <div>
            <dt>Класс</dt>
            <dd>{className || '—'}</dd>
          </div>
          {enrollment?.cardNumber ? (
            <div>
              <dt>Номер карты ученика</dt>
              <dd className="kv__mono">{enrollment.cardNumber}</dd>
            </div>
          ) : null}
          <div>
            <dt>Школа</dt>
            <dd>{profile?.school_id || '—'}</dd>
          </div>
          <div>
            <dt>Сессия создана</dt>
            <dd>{user?.created_at ? new Date(user.created_at).toLocaleString('ru-RU') : '—'}</dd>
          </div>
        </dl>
      </section>
        </>
      )}
    </div>
  )
}

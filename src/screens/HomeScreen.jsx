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

export default function HomeScreen() {
  const { displayName, user, profile, role, className, profileError, signOut } = useAuth()
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

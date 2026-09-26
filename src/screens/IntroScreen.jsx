const FEATURES = [
  { emoji: '🗓️', label: 'Расписание' },
  { emoji: '📝', label: 'Оценки' },
  { emoji: '🎒', label: 'Домашние задания' }
]

/**
 * Стартовое интро: показывается один раз при заходе на сайт,
 * пока пользователь не нажал «Войдите».
 */
export default function IntroScreen({ onEnter }) {
  return (
    <div className="intro">
      <div className="intro__glow" aria-hidden="true" />

      <div className="intro__content">
        <span className="intro__logo" role="img" aria-label="Книга">
          📘
        </span>

        <p className="intro__badge">2026 · учебный год</p>
        <h1 className="intro__title">Школьный дневник</h1>
        <p className="intro__subtitle">
          Оценки, расписание и домашние задания — в одном месте. Для учеников, родителей и учителей.
        </p>

        <ul className="intro__features">
          {FEATURES.map((feature) => (
            <li className="intro__feature" key={feature.label}>
              <span aria-hidden="true">{feature.emoji}</span> {feature.label}
            </li>
          ))}
        </ul>

        <button type="button" className="button button--primary intro__cta" onClick={onEnter}>
          Войдите
        </button>

        <p className="intro__hint">Нет аккаунта? Зарегистрироваться можно на следующем шаге.</p>
      </div>
    </div>
  )
}

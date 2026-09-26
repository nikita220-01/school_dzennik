import { useEffect, useState } from 'react'

const STEPS = [
  'Подключаемся к серверу…',
  'Проверяем сессию…',
  'Готовим дневник…'
]

/**
 * Загрузочное (boot) меню: показывается, пока приложение проверяет сессию
 * и подтягивает профиль пользователя.
 */
export default function BootScreen({ error }) {
  const [step, setStep] = useState(0)

  useEffect(() => {
    const timer = setInterval(() => {
      setStep((current) => (current < STEPS.length - 1 ? current + 1 : current))
    }, 420)
    return () => clearInterval(timer)
  }, [])

  return (
    <div className="boot">
      <div className="boot__logo">
        <span role="img" aria-label="Книга">
          📘
        </span>
      </div>

      <h1 className="boot__title">Школьный дневник</h1>
      <p className="boot__subtitle">Электронный дневник и журнал</p>

      <div className="boot__spinner" aria-hidden="true" />

      <p className="boot__step" role="status">
        {error ? 'Не удалось завершить загрузку' : STEPS[step]}
      </p>

      <div className="boot__bar" aria-hidden="true">
        <div className="boot__bar-fill" />
      </div>

      {error ? (
        <div className="alert alert--error boot__alert">
          <strong>Ошибка загрузки.</strong> {error}
        </div>
      ) : null}
    </div>
  )
}

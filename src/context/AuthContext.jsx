import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { translateAuthError } from '../lib/authErrors'
import { joinClass as joinClassByCode, loadMyStudent } from '../lib/schoolData'

/** Минимальное время показа загрузочного экрана, чтобы он не «мигал» */
const MIN_BOOT_MS = 1400

const AuthContext = createContext(null)

/**
 * Приводим роль к нижнему регистру и понимаем русские/заглавные варианты:
 * «Учитель», «Teacher», «TEACHER» → 'teacher'. В базе и в коде роль — строчными.
 */
const ROLE_ALIASES = {
  teacher: 'teacher',
  учитель: 'teacher',
  admin: 'admin',
  administrator: 'admin',
  админ: 'admin',
  администратор: 'admin',
  student: 'student',
  ученик: 'student',
  ученица: 'student',
  parent: 'parent',
  родитель: 'parent'
}

export function normalizeRole(raw) {
  if (raw === null || raw === undefined) return null
  const key = String(raw).trim().toLowerCase()
  if (!key) return null
  return ROLE_ALIASES[key] || key
}

/** Данные пользователя из метаданных auth — запасной вариант, если таблицы profiles ещё нет */
function profileFromMetadata(user) {
  if (!user) return null
  const meta = user.user_metadata || {}
  return {
    id: user.id,
    email: user.email,
    full_name: meta.full_name || null,
    role: normalizeRole(meta.role) || 'student',
    class_name: meta.class_name || null,
    school_id: null,
    is_active: true,
    __source: 'auth'
  }
}

export function AuthProvider({ children }) {
  const [booting, setBooting] = useState(true)
  const [bootError, setBootError] = useState(null)
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [profileError, setProfileError] = useState(null)
  /** Карточка ученика из базы: { studentId, classId, className, cardNumber } */
  const [enrollment, setEnrollment] = useState(null)
  const [enrollmentError, setEnrollmentError] = useState(null)

  const loadProfile = useCallback(async (user) => {
    if (!user) {
      setProfile(null)
      setProfileError(null)
      return
    }

    const fallback = profileFromMetadata(user)
    const { data, error } = await supabase
      .from('profiles')
      .select('id, email, full_name, role, school_id, is_active')
      .eq('id', user.id)
      .maybeSingle()

    if (error) {
      // Таблица profiles ещё не создана (SQL не применён) — не критично для входа.
      setProfile(fallback)
      setProfileError(error.message)
      return
    }

    setProfile(data || fallback)
    setProfileError(null)
  }, [])

  /**
   * Класс ученика берём из таблицы students (через RPC join_class его заполняет
   * ученик по коду). У учителя и админа карточки ученика нет — enrollment = null.
   */
  const loadEnrollment = useCallback(async (userId) => {
    if (!userId) {
      setEnrollment(null)
      setEnrollmentError(null)
      return
    }

    try {
      const row = await loadMyStudent(userId)
      setEnrollment(row)
      setEnrollmentError(null)
    } catch (error) {
      setEnrollment(null)
      setEnrollmentError(error.message)
    }
  }, [])

  useEffect(() => {
    let alive = true
    const startedAt = Date.now()

    const bootstrap = async () => {
      try {
        const { data, error } = await supabase.auth.getSession()
        if (error) throw error

        const current = data.session
        if (!alive) return

        setSession(current)
        if (current?.user) {
          await loadProfile(current.user)
          await loadEnrollment(current.user.id)
        }
      } catch (error) {
        if (alive) setBootError(translateAuthError(error))
      } finally {
        const elapsed = Date.now() - startedAt
        const wait = Math.max(0, MIN_BOOT_MS - elapsed)
        setTimeout(() => {
          if (alive) setBooting(false)
        }, wait)
      }
    }

    bootstrap()

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      if (nextSession?.user) {
        loadProfile(nextSession.user)
        loadEnrollment(nextSession.user.id)
      } else {
        setProfile(null)
        setProfileError(null)
        setEnrollment(null)
        setEnrollmentError(null)
      }
    })

    return () => {
      alive = false
      listener.subscription.unsubscribe()
    }
  }, [loadProfile, loadEnrollment])

  const signIn = useCallback(async (email, password) => {
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    })
    if (error) throw new Error(translateAuthError(error))
  }, [])

  const signUp = useCallback(
    async ({ email, password, fullName, role, classCode }) => {
      const trimmedCode = (classCode || '').trim()

      const { data, error } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          data: {
            full_name: fullName.trim(),
            role,
            // Код класса нужен, чтобы ученик сразу попал в список класса
            invite_code: trimmedCode || null
          }
        }
      })
      if (error) throw new Error(translateAuthError(error))

      // Если в Supabase включено подтверждение email, сессии сразу не будет.
      const needsEmailConfirm = !data.session

      // Ученика сразу записываем в класс (RPC join_class), чтобы он появился
      // в списке учителя на любом устройстве. Ошибку не «валим» на регистрацию:
      // код можно ввести позже в дневнике.
      if (data.session?.user && role === 'student' && trimmedCode) {
        try {
          await joinClassByCode(trimmedCode)
          await loadEnrollment(data.session.user.id)
        } catch (joinError) {
          return { needsEmailConfirm, joinError: joinError.message }
        }
      }

      return { needsEmailConfirm }
    },
    [loadEnrollment]
  )

  /** Ученик присоединяется к классу по коду (например 7A2025) или меняет класс */
  const joinClass = useCallback(
    async (code) => {
      const classId = await joinClassByCode(code)
      const { data } = await supabase.auth.getUser()
      await loadEnrollment(data?.user?.id)
      return classId
    },
    [loadEnrollment]
  )

  /** Перечитать карточку ученика (класс и номер карты) из базы */
  const refreshEnrollment = useCallback(async () => {
    const { data } = await supabase.auth.getUser()
    await loadEnrollment(data?.user?.id)
  }, [loadEnrollment])

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut()
    if (error) throw new Error(translateAuthError(error))
  }, [])

  const value = useMemo(() => {
    const user = session?.user || null
    const displayName =
      profile?.full_name ||
      user?.user_metadata?.full_name ||
      (user?.email ? user.email.split('@')[0] : null)

    const profileRole = normalizeRole(profile?.role)
    const metaRole = normalizeRole(user?.user_metadata?.role)
    // Старшинство ролей: admin > teacher > то, что вернула база.
    // Триггер БД создаёт профиль со 'student', поэтому заявку «teacher» не теряем.
    const role =
      profileRole === 'admin' || metaRole === 'admin'
        ? 'admin'
        : profileRole === 'teacher' || metaRole === 'teacher'
          ? 'teacher'
          : profileRole || metaRole || null

    return {
      booting,
      bootError,
      session,
      user,
      profile,
      profileError,
      profileRole,
      metaRole,
      role,
      /** Класс ученика из базы: { studentId, classId, className, cardNumber } */
      enrollment,
      enrollmentError,
      studentId: enrollment?.studentId || null,
      classId: enrollment?.classId || null,
      className: enrollment?.className || null,
      displayName,
      signIn,
      signUp,
      signOut,
      joinClass,
      refreshEnrollment
    }
  }, [
    booting,
    bootError,
    session,
    profile,
    profileError,
    enrollment,
    enrollmentError,
    signIn,
    signUp,
    signOut,
    joinClass,
    refreshEnrollment
  ])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth() можно использовать только внутри <AuthProvider>')
  }
  return context
}

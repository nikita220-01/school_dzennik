import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { translateAuthError } from '../lib/authErrors'

/** Минимальное время показа загрузочного экрана, чтобы он не «мигал» */
const MIN_BOOT_MS = 1400

const AuthContext = createContext(null)

/** Данные пользователя из метаданных auth — запасной вариант, если таблицы profiles ещё нет */
function profileFromMetadata(user) {
  if (!user) return null
  const meta = user.user_metadata || {}
  return {
    id: user.id,
    email: user.email,
    full_name: meta.full_name || null,
    role: meta.role || 'student',
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
        if (current?.user) await loadProfile(current.user)
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
      } else {
        setProfile(null)
        setProfileError(null)
      }
    })

    return () => {
      alive = false
      listener.subscription.unsubscribe()
    }
  }, [loadProfile])

  const signIn = useCallback(async (email, password) => {
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    })
    if (error) throw new Error(translateAuthError(error))
  }, [])

  const signUp = useCallback(async ({ email, password, fullName, role }) => {
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        data: {
          full_name: fullName.trim(),
          role
        }
      }
    })
    if (error) throw new Error(translateAuthError(error))

    // Если в Supabase включено подтверждение email, сессии сразу не будет.
    return { needsEmailConfirm: !data.session }
  }, [])

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

    return {
      booting,
      bootError,
      session,
      user,
      profile,
      profileError,
      role: profile?.role || user?.user_metadata?.role || null,
      displayName,
      signIn,
      signUp,
      signOut
    }
  }, [booting, bootError, session, profile, profileError, signIn, signUp, signOut])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth() можно использовать только внутри <AuthProvider>')
  }
  return context
}

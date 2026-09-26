import { useState } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext'
import { configError } from './lib/supabase'
import BootScreen from './screens/BootScreen'
import IntroScreen from './screens/IntroScreen'
import AuthScreen from './screens/AuthScreen'
import HomeScreen from './screens/HomeScreen'

function Router() {
  const { booting, bootError, user } = useAuth()
  /** Интро показываем один раз за визит; после выхода из аккаунта оно снова появится */
  const [introSeen, setIntroSeen] = useState(false)

  if (configError) return <BootScreen error={configError} />
  if (booting) return <BootScreen />
  if (bootError) return <BootScreen error={bootError} />
  if (!user && !introSeen) return <IntroScreen onEnter={() => setIntroSeen(true)} />
  if (!user) return <AuthScreen />
  return <HomeScreen />
}

export default function App() {
  return (
    <AuthProvider>
      <Router />
    </AuthProvider>
  )
}

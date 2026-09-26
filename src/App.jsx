import { AuthProvider, useAuth } from './context/AuthContext'
import BootScreen from './screens/BootScreen'
import AuthScreen from './screens/AuthScreen'
import HomeScreen from './screens/HomeScreen'

function Router() {
  const { booting, bootError, user } = useAuth()

  if (booting) return <BootScreen />
  if (bootError) return <BootScreen error={bootError} />
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

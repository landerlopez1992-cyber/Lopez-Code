import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut,
  type User,
} from 'firebase/auth'
import { firebaseConfigured, getFirebase } from '../lib/firebase'
import { getDataMode, isAdminUid } from '../lib/adminApi'

interface AuthState {
  user: User | null
  email: string | null
  loading: boolean
  isAdmin: boolean
  demoMode: boolean
  login: (email: string, password: string) => Promise<void>
  loginDemo: () => void
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [email, setEmail] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [isAdmin, setIsAdmin] = useState(false)
  const [demoSession, setDemoSession] = useState(false)

  useEffect(() => {
    if (!firebaseConfigured) {
      setLoading(false)
      return
    }
    const { auth } = getFirebase()
    if (!auth) {
      setLoading(false)
      return
    }
    return onAuthStateChanged(auth, async (u) => {
      setUser(u)
      setEmail(u?.email ?? null)
      if (u) {
        setIsAdmin(await isAdminUid(u.uid))
      } else {
        setIsAdmin(false)
      }
      setLoading(false)
    })
  }, [])

  const value = useMemo<AuthState>(
    () => ({
      user,
      email: demoSession ? 'demo.admin@voryxel.com' : email,
      loading,
      isAdmin: demoSession || isAdmin,
      demoMode: getDataMode() === 'demo' || demoSession,
      login: async (em, password) => {
        const { auth } = getFirebase()
        if (!auth) throw new Error('Firebase no configurado. Usa modo demo.')
        const cred = await signInWithEmailAndPassword(auth, em.trim(), password)
        const ok = await isAdminUid(cred.user.uid)
        if (!ok) {
          await signOut(auth)
          throw new Error(
            'Tu cuenta no está en /admins. Agrégala en Firebase Console.',
          )
        }
        setDemoSession(false)
      },
      loginDemo: () => {
        setDemoSession(true)
        setIsAdmin(true)
        setEmail('demo.admin@voryxel.com')
        setLoading(false)
      },
      logout: async () => {
        setDemoSession(false)
        const { auth } = getFirebase()
        if (auth) await signOut(auth)
        setUser(null)
        setEmail(null)
        setIsAdmin(false)
      },
    }),
    [user, email, loading, isAdmin, demoSession],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth outside AuthProvider')
  return ctx
}

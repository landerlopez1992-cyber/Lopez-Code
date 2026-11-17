import { useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { Button, Card, Input } from '../components/ui'
import { firebaseConfigured } from '../lib/firebase'

export function LoginPage() {
  const { login, loginDemo, isAdmin, loading } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (!loading && isAdmin) return <Navigate to="/" replace />

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await login(email, password)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error de login')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <Card className="w-full max-w-md p-6">
        <div className="mb-6">
          <div className="text-xs font-semibold uppercase tracking-[0.18em] text-blue-400">
            Voryxel Code
          </div>
          <h1 className="mt-2 text-2xl font-semibold">Panel administrador</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Control de usuarios, uso, billing y operación del producto.
          </p>
        </div>

        <form className="space-y-3" onSubmit={onSubmit}>
          <div>
            <label className="mb-1 block text-xs text-zinc-500">Email</label>
            <Input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@voryxel.com"
              required={firebaseConfigured}
              disabled={!firebaseConfigured}
            />
          </div>
          <div>
            <label className="mb-1 block text-xs text-zinc-500">Password</label>
            <Input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required={firebaseConfigured}
              disabled={!firebaseConfigured}
            />
          </div>
          {error ? (
            <div className="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-300">
              {error}
            </div>
          ) : null}
          <Button
            type="submit"
            className="w-full"
            disabled={busy || !firebaseConfigured}
          >
            {busy ? 'Entrando…' : 'Entrar con Firebase'}
          </Button>
        </form>

        <div className="my-4 flex items-center gap-3 text-xs text-zinc-600">
          <div className="h-px flex-1 bg-zinc-800" />
          o
          <div className="h-px flex-1 bg-zinc-800" />
        </div>

        <Button variant="outline" className="w-full" onClick={loginDemo}>
          Entrar en modo demo
        </Button>

        {!firebaseConfigured ? (
          <p className="mt-4 text-xs leading-relaxed text-zinc-500">
            Firebase Web aún no tiene <code>VITE_FIREBASE_*</code>. Copia{' '}
            <code>.env.example</code> → <code>.env</code> y crea un doc en{' '}
            <code>admins/&#123;uid&#125;</code> para tu cuenta.
          </p>
        ) : null}
      </Card>
    </div>
  )
}

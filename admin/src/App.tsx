import { Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './auth/AuthContext'
import { AdminShell } from './components/AdminShell'
import { LoginPage } from './pages/LoginPage'
import { OverviewPage } from './pages/OverviewPage'
import { UsersPage } from './pages/UsersPage'
import { ActivePage } from './pages/ActivePage'
import { UsagePage } from './pages/UsagePage'
import { BillingPage } from './pages/BillingPage'
import { ModelsPage } from './pages/ModelsPage'
import { FlagsPage } from './pages/FlagsPage'
import { AuditPage } from './pages/AuditPage'
import { SystemPage } from './pages/SystemPage'
import type { ReactNode } from 'react'

function RequireAdmin({ children }: { children: ReactNode }) {
  const { loading, isAdmin } = useAuth()
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-sm text-zinc-500">
        Cargando…
      </div>
    )
  }
  if (!isAdmin) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/"
          element={
            <RequireAdmin>
              <AdminShell />
            </RequireAdmin>
          }
        >
          <Route index element={<OverviewPage />} />
          <Route path="users" element={<UsersPage />} />
          <Route path="active" element={<ActivePage />} />
          <Route path="usage" element={<UsagePage />} />
          <Route path="billing" element={<BillingPage />} />
          <Route path="models" element={<ModelsPage />} />
          <Route path="flags" element={<FlagsPage />} />
          <Route path="audit" element={<AuditPage />} />
          <Route path="system" element={<SystemPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AuthProvider>
  )
}

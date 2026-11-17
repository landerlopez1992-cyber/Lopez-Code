import { NavLink, Outlet } from 'react-router-dom'
import {
  Activity,
  CreditCard,
  Flag,
  LayoutDashboard,
  LogOut,
  ScrollText,
  Settings2,
  Users,
  Cpu,
  Radio,
} from 'lucide-react'
import clsx from 'clsx'
import { useAuth } from '../auth/AuthContext'
import { Button } from './ui'

const nav = [
  { to: '/', label: 'Overview', icon: LayoutDashboard },
  { to: '/users', label: 'Usuarios', icon: Users },
  { to: '/active', label: 'Activos ahora', icon: Radio },
  { to: '/usage', label: 'Uso & tokens', icon: Activity },
  { to: '/billing', label: 'Billing', icon: CreditCard },
  { to: '/models', label: 'Modelos', icon: Cpu },
  { to: '/flags', label: 'Feature flags', icon: Flag },
  { to: '/audit', label: 'Audit log', icon: ScrollText },
  { to: '/system', label: 'Sistema', icon: Settings2 },
]

export function AdminShell() {
  const { email, demoMode, logout } = useAuth()

  return (
    <div className="flex min-h-screen">
      <aside className="sticky top-0 flex h-screen w-60 shrink-0 flex-col border-r border-zinc-800 bg-zinc-950/80 px-3 py-4 backdrop-blur">
        <div className="mb-6 px-2">
          <div className="text-xs font-semibold uppercase tracking-[0.18em] text-blue-400">
            Voryxel
          </div>
          <div className="mt-1 text-lg font-semibold text-zinc-50">Admin</div>
          {demoMode ? (
            <div className="mt-2 rounded-md bg-amber-500/10 px-2 py-1 text-[11px] text-amber-300">
              Modo demo · datos de ejemplo
            </div>
          ) : (
            <div className="mt-2 rounded-md bg-emerald-500/10 px-2 py-1 text-[11px] text-emerald-300">
              Firebase live
            </div>
          )}
        </div>
        <nav className="flex flex-1 flex-col gap-0.5">
          {nav.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              className={({ isActive }) =>
                clsx(
                  'flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm transition',
                  isActive
                    ? 'bg-zinc-800 text-white'
                    : 'text-zinc-400 hover:bg-zinc-900 hover:text-zinc-100',
                )
              }
            >
              <item.icon size={16} />
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-3 border-t border-zinc-800 pt-3">
          <div className="truncate px-2 text-xs text-zinc-500">{email}</div>
          <Button
            variant="ghost"
            className="mt-1 w-full justify-start"
            onClick={() => void logout()}
          >
            <LogOut size={14} />
            Salir
          </Button>
        </div>
      </aside>
      <main className="min-w-0 flex-1 px-6 py-6 lg:px-8">
        <Outlet />
      </main>
    </div>
  )
}

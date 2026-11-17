import { useEffect, useMemo, useState } from 'react'
import { formatDistanceToNow } from 'date-fns'
import { es } from 'date-fns/locale'
import { adjustUserBalance, fetchUsers, updateUserStatus } from '../lib/adminApi'
import type { AdminUser } from '../types'
import { useAuth } from '../auth/AuthContext'
import {
  Badge,
  Button,
  Input,
  PageHeader,
  TableShell,
  Td,
  Th,
} from '../components/ui'

export function UsersPage() {
  const { email, demoMode } = useAuth()
  const [users, setUsers] = useState<AdminUser[]>([])
  const [q, setQ] = useState('')
  const [status, setStatus] = useState<'all' | AdminUser['status']>('all')

  async function reload() {
    setUsers(await fetchUsers())
  }

  useEffect(() => {
    void reload()
  }, [])

  const filtered = useMemo(() => {
    return users.filter((u) => {
      if (status !== 'all' && u.status !== status) return false
      if (!q.trim()) return true
      const hay = `${u.email} ${u.displayName ?? ''} ${u.uid}`.toLowerCase()
      return hay.includes(q.trim().toLowerCase())
    })
  }, [users, q, status])

  return (
    <div>
      <PageHeader
        title="Usuarios"
        subtitle="Cuentas, saldo, rol, estado y última actividad."
        actions={
          <div className="flex flex-wrap gap-2">
            <Input
              className="w-56"
              placeholder="Buscar email / uid…"
              value={q}
              onChange={(e) => setQ(e.target.value)}
            />
            <select
              className="rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm"
              value={status}
              onChange={(e) => setStatus(e.target.value as typeof status)}
            >
              <option value="all">Todos</option>
              <option value="active">Activos</option>
              <option value="suspended">Suspendidos</option>
              <option value="deleted">Eliminados</option>
            </select>
          </div>
        }
      />

      <TableShell>
        <table className="min-w-full">
          <thead className="border-b border-zinc-800 bg-zinc-950/60">
            <tr>
              <Th>Usuario</Th>
              <Th>Estado</Th>
              <Th>Rol</Th>
              <Th className="text-right">Saldo</Th>
              <Th className="text-right">Tokens</Th>
              <Th>Última actividad</Th>
              <Th>Acciones</Th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((u) => (
              <tr key={u.uid} className="border-b border-zinc-800/80 hover:bg-zinc-900/40">
                <Td>
                  <div className="font-medium">{u.displayName ?? u.email}</div>
                  <div className="text-xs text-zinc-500">{u.email}</div>
                  <div className="text-[11px] text-zinc-600">{u.platform} · {u.appVersion}</div>
                </Td>
                <Td>
                  <Badge
                    tone={
                      u.status === 'active'
                        ? 'green'
                        : u.status === 'suspended'
                          ? 'red'
                          : 'zinc'
                    }
                  >
                    {u.status}
                  </Badge>
                </Td>
                <Td>
                  <Badge tone={u.role === 'admin' ? 'blue' : u.role === 'support' ? 'amber' : 'zinc'}>
                    {u.role}
                  </Badge>
                </Td>
                <Td className="text-right tabular-nums">${u.balance.toFixed(2)}</Td>
                <Td className="text-right tabular-nums">
                  {u.totalTokens >= 1000
                    ? `${(u.totalTokens / 1000).toFixed(0)}K`
                    : u.totalTokens}
                </Td>
                <Td className="text-zinc-400">
                  {formatDistanceToNow(new Date(u.lastActiveAt), {
                    addSuffix: true,
                    locale: es,
                  })}
                </Td>
                <Td>
                  <div className="flex flex-wrap gap-1">
                    <Button
                      variant="outline"
                      className="!px-2 !py-1 text-xs"
                      disabled={demoMode}
                      onClick={() =>
                        void updateUserStatus(
                          u.uid,
                          u.status === 'suspended' ? 'active' : 'suspended',
                          email ?? 'admin',
                        ).then(reload)
                      }
                    >
                      {u.status === 'suspended' ? 'Reactivar' : 'Suspender'}
                    </Button>
                    <Button
                      variant="ghost"
                      className="!px-2 !py-1 text-xs"
                      disabled={demoMode}
                      onClick={() => {
                        const raw = window.prompt('Ajuste de saldo (+/- USD)', '5')
                        if (!raw) return
                        const delta = Number(raw)
                        if (!Number.isFinite(delta)) return
                        const note = window.prompt('Nota', 'Ajuste admin') ?? 'Ajuste admin'
                        void adjustUserBalance(u.uid, delta, note, email ?? 'admin').then(
                          reload,
                        )
                      }}
                    >
                      Ajustar $
                    </Button>
                  </div>
                </Td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableShell>
      {demoMode ? (
        <p className="mt-3 text-xs text-zinc-500">
          En modo demo las acciones de escritura están deshabilitadas. Conecta Firebase Web + doc{' '}
          <code>admins/&#123;uid&#125;</code> para operar en vivo.
        </p>
      ) : null}
    </div>
  )
}

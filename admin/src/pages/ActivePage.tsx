import { useEffect, useState } from 'react'
import { formatDistanceToNow } from 'date-fns'
import { es } from 'date-fns/locale'
import { fetchActiveSessions } from '../lib/adminApi'
import type { ActiveSession } from '../types'
import { Badge, PageHeader, TableShell, Td, Th } from '../components/ui'

export function ActivePage() {
  const [sessions, setSessions] = useState<ActiveSession[]>([])

  useEffect(() => {
    void fetchActiveSessions().then(setSessions)
    const id = window.setInterval(() => {
      void fetchActiveSessions().then(setSessions)
    }, 15_000)
    return () => window.clearInterval(id)
  }, [])

  return (
    <div>
      <PageHeader
        title="Activos ahora"
        subtitle="Sesiones con heartbeat en los últimos 15 minutos (IDE / admin)."
      />
      <TableShell>
        <table className="min-w-full">
          <thead className="border-b border-zinc-800 bg-zinc-950/60">
            <tr>
              <Th>Usuario</Th>
              <Th>Plataforma</Th>
              <Th>Versión</Th>
              <Th>Visto</Th>
              <Th>IP</Th>
            </tr>
          </thead>
          <tbody>
            {sessions.map((s) => (
              <tr key={s.uid} className="border-b border-zinc-800/80">
                <Td>
                  <div className="flex items-center gap-2">
                    <span className="h-2 w-2 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.8)]" />
                    {s.email}
                  </div>
                </Td>
                <Td>
                  <Badge tone="blue">{s.platform}</Badge>
                </Td>
                <Td className="text-zinc-400">{s.appVersion || '—'}</Td>
                <Td>
                  {formatDistanceToNow(new Date(s.lastSeenAt), {
                    addSuffix: true,
                    locale: es,
                  })}
                </Td>
                <Td className="text-zinc-500">{s.ipHint ?? '—'}</Td>
              </tr>
            ))}
            {sessions.length === 0 ? (
              <tr>
                <td
                  colSpan={5}
                  className="px-3 py-8 text-center text-sm text-zinc-500"
                >
                  Nadie activo en la ventana de 15 min.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </TableShell>
    </div>
  )
}

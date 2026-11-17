import { useEffect, useState } from 'react'
import { format } from 'date-fns'
import { fetchUsageEvents } from '../lib/adminApi'
import type { UsageEvent } from '../types'
import { Badge, PageHeader, TableShell, Td, Th } from '../components/ui'

function fmtTokens(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return String(n)
}

export function UsagePage() {
  const [events, setEvents] = useState<UsageEvent[]>([])

  useEffect(() => {
    void fetchUsageEvents().then(setEvents)
  }, [])

  return (
    <div>
      <PageHeader
        title="Uso & tokens"
        subtitle="Llamadas al agente, modelos y costo por evento (estilo Cursor Usage)."
      />
      <TableShell>
        <table className="min-w-full">
          <thead className="border-b border-zinc-800 bg-zinc-950/60">
            <tr>
              <Th>Fecha</Th>
              <Th>Tipo</Th>
              <Th>Usuario</Th>
              <Th>Modelo</Th>
              <Th className="text-right">Tokens</Th>
              <Th className="text-right">Costo</Th>
              <Th>Nota</Th>
            </tr>
          </thead>
          <tbody>
            {events.map((e) => (
              <tr key={e.id} className="border-b border-zinc-800/80">
                <Td className="tabular-nums text-zinc-400">
                  {format(new Date(e.date), 'MMM d, HH:mm')}
                </Td>
                <Td>
                  <Badge
                    tone={
                      e.type === 'usage'
                        ? 'blue'
                        : e.type === 'topup'
                          ? 'green'
                          : 'amber'
                    }
                  >
                    {e.type}
                  </Badge>
                </Td>
                <Td>{e.email}</Td>
                <Td className="text-zinc-400">{e.model}</Td>
                <Td className="text-right tabular-nums">
                  {e.tokens ? fmtTokens(e.tokens) : '—'}
                </Td>
                <Td className="text-right tabular-nums">
                  {e.type === 'topup' ? '+' : e.type === 'adjust' && e.cost > 0 ? '+' : ''}
                  ${Math.abs(e.cost).toFixed(e.type === 'usage' ? 4 : 2)}
                </Td>
                <Td className="text-zinc-500">{e.note ?? '—'}</Td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableShell>
    </div>
  )
}

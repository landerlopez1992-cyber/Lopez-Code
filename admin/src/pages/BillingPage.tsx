import { useEffect, useMemo, useState } from 'react'
import { fetchUsageEvents, fetchUsers } from '../lib/adminApi'
import type { AdminUser, UsageEvent } from '../types'
import { Card, PageHeader, StatCard, TableShell, Td, Th, Badge } from '../components/ui'

export function BillingPage() {
  const [users, setUsers] = useState<AdminUser[]>([])
  const [events, setEvents] = useState<UsageEvent[]>([])

  useEffect(() => {
    void Promise.all([fetchUsers(), fetchUsageEvents()]).then(([u, e]) => {
      setUsers(u)
      setEvents(e)
    })
  }, [])

  const topups = useMemo(
    () => events.filter((e) => e.type === 'topup' || e.type === 'adjust'),
    [events],
  )
  const liability = users.reduce((s, u) => s + Math.max(0, u.balance), 0)
  const lowBalance = users.filter((u) => u.balance > 0 && u.balance < 2).length

  return (
    <div>
      <PageHeader
        title="Billing"
        subtitle="Pasivo de créditos, recargas, ajustes y cuentas en riesgo."
      />
      <div className="grid gap-3 sm:grid-cols-3">
        <StatCard label="Pasivo de saldo" value={`$${liability.toFixed(2)}`} hint="Suma de balances > 0" />
        <StatCard label="Movimientos $ " value={String(topups.length)} hint="Recargas + ajustes" />
        <StatCard label="Saldo bajo" value={String(lowBalance)} hint="< $2 USD" />
      </div>

      <div className="mt-6 grid gap-4 xl:grid-cols-2">
        <div>
          <h2 className="mb-2 text-sm font-medium text-zinc-300">Movimientos recientes</h2>
          <TableShell>
            <table className="min-w-full">
              <thead className="border-b border-zinc-800 bg-zinc-950/60">
                <tr>
                  <Th>Usuario</Th>
                  <Th>Tipo</Th>
                  <Th className="text-right">Monto</Th>
                </tr>
              </thead>
              <tbody>
                {topups.map((e) => (
                  <tr key={e.id} className="border-b border-zinc-800/80">
                    <Td>{e.email}</Td>
                    <Td>
                      <Badge tone={e.type === 'topup' ? 'green' : 'amber'}>{e.type}</Badge>
                    </Td>
                    <Td className="text-right tabular-nums">
                      {e.cost >= 0 ? '+' : ''}
                      ${e.cost.toFixed(2)}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableShell>
        </div>
        <Card className="p-4">
          <h2 className="mb-2 text-sm font-medium text-zinc-300">Controles recomendados</h2>
          <ul className="space-y-2 text-sm text-zinc-400">
            <li>• Soft-cap diario de tokens por usuario / plan.</li>
            <li>• Alertas cuando el pasivo de créditos crece vs caja API.</li>
            <li>• Refunds y ajustes siempre con nota en audit log.</li>
            <li>• Freeze de cuenta ante anomalías (rate / costo).</li>
            <li>• Export CSV de ledger para contabilidad.</li>
          </ul>
        </Card>
      </div>
    </div>
  )
}

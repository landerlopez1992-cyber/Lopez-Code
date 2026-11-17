import { useEffect, useState } from 'react'
import { format } from 'date-fns'
import { fetchAudit } from '../lib/adminApi'
import type { AuditEntry } from '../types'
import { PageHeader, TableShell, Td, Th } from '../components/ui'

export function AuditPage() {
  const [rows, setRows] = useState<AuditEntry[]>([])

  useEffect(() => {
    void fetchAudit().then(setRows)
  }, [])

  return (
    <div>
      <PageHeader
        title="Audit log"
        subtitle="Quién cambió qué: suspensiones, créditos, flags."
      />
      <TableShell>
        <table className="min-w-full">
          <thead className="border-b border-zinc-800 bg-zinc-950/60">
            <tr>
              <Th>Cuando</Th>
              <Th>Actor</Th>
              <Th>Acción</Th>
              <Th>Target</Th>
              <Th>Detalle</Th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-zinc-800/80">
                <Td className="tabular-nums text-zinc-400">
                  {format(new Date(r.at), 'MMM d, HH:mm')}
                </Td>
                <Td>{r.actorEmail}</Td>
                <Td className="font-mono text-xs text-blue-300">{r.action}</Td>
                <Td>{r.target}</Td>
                <Td className="text-zinc-400">{r.detail}</Td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableShell>
    </div>
  )
}

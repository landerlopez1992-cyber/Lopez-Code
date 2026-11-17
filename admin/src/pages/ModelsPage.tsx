import { useEffect, useState } from 'react'
import { fetchModels } from '../lib/adminApi'
import type { ModelPricingRow } from '../types'
import { Badge, PageHeader, TableShell, Td, Th } from '../components/ui'

export function ModelsPage() {
  const [rows, setRows] = useState<ModelPricingRow[]>([])

  useEffect(() => {
    void fetchModels().then(setRows)
  }, [])

  return (
    <div>
      <PageHeader
        title="Modelos & pricing"
        subtitle="Tarifas API, margen del producto y disponibilidad por modelo."
      />
      <TableShell>
        <table className="min-w-full">
          <thead className="border-b border-zinc-800 bg-zinc-950/60">
            <tr>
              <Th>Modelo</Th>
              <Th className="text-right">Input / 1M</Th>
              <Th className="text-right">Output / 1M</Th>
              <Th className="text-right">Margen</Th>
              <Th>Estado</Th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-zinc-800/80">
                <Td className="font-medium">{r.model}</Td>
                <Td className="text-right tabular-nums">${r.inputPer1M.toFixed(2)}</Td>
                <Td className="text-right tabular-nums">${r.outputPer1M.toFixed(2)}</Td>
                <Td className="text-right tabular-nums">{r.marginPercent}%</Td>
                <Td>
                  <Badge tone={r.enabled ? 'green' : 'zinc'}>
                    {r.enabled ? 'enabled' : 'disabled'}
                  </Badge>
                </Td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableShell>
    </div>
  )
}

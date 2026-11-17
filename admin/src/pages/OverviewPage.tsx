import { useEffect, useState } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { fetchStats } from '../lib/adminApi'
import type { DashboardStats } from '../types'
import { Card, PageHeader, StatCard } from '../components/ui'

function fmtTokens(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return String(n)
}

export function OverviewPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null)

  useEffect(() => {
    void fetchStats().then(setStats)
  }, [])

  if (!stats) {
    return <div className="text-sm text-zinc-500">Cargando overview…</div>
  }

  return (
    <div>
      <PageHeader
        title="Overview"
        subtitle="Pulso del producto: usuarios, consumo de tokens y facturación."
      />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Usuarios" value={String(stats.totalUsers)} hint={`${stats.suspended} suspendidos`} />
        <StatCard label="Activos ahora" value={String(stats.activeNow)} hint={`${stats.activeToday} hoy`} />
        <StatCard label="Tokens 7d" value={fmtTokens(stats.tokens7d)} hint={`API ~$${stats.apiSpend7d.toFixed(2)}`} />
        <StatCard
          label="Recargas 7d"
          value={`$${stats.revenue7d.toFixed(2)}`}
          hint={`Saldo medio $${stats.avgBalance.toFixed(2)}`}
        />
      </div>

      <div className="mt-6 grid gap-4 xl:grid-cols-3">
        <Card className="p-4 xl:col-span-2">
          <div className="mb-3 text-sm font-medium text-zinc-200">Uso de tokens (14 días)</div>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={stats.usageSeries}>
                <defs>
                  <linearGradient id="tok" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#3b82f6" stopOpacity={0.45} />
                    <stop offset="100%" stopColor="#3b82f6" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid stroke="#27272a" strokeDasharray="3 3" />
                <XAxis dataKey="day" tick={{ fill: '#71717a', fontSize: 11 }} />
                <YAxis tick={{ fill: '#71717a', fontSize: 11 }} tickFormatter={fmtTokens} />
                <Tooltip
                  contentStyle={{
                    background: '#18181b',
                    border: '1px solid #3f3f46',
                    borderRadius: 8,
                  }}
                />
                <Area
                  type="monotone"
                  dataKey="tokens"
                  stroke="#3b82f6"
                  fill="url(#tok)"
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Card>

        <Card className="p-4">
          <div className="mb-3 text-sm font-medium text-zinc-200">Top modelos</div>
          <div className="space-y-3">
            {stats.topModels.map((m) => (
              <div key={m.model} className="rounded-lg border border-zinc-800 bg-zinc-950/50 p-3">
                <div className="flex items-center justify-between gap-2">
                  <div className="font-medium text-zinc-100">{m.model}</div>
                  <div className="text-xs text-zinc-500">${m.cost.toFixed(2)}</div>
                </div>
                <div className="mt-1 text-xs text-zinc-400">{fmtTokens(m.tokens)} tokens</div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  )
}

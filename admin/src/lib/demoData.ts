import { subDays, subHours, subMinutes, formatISO } from 'date-fns'
import type {
  AdminUser,
  ActiveSession,
  AuditEntry,
  DashboardStats,
  FeatureFlag,
  ModelPricingRow,
  UsageEvent,
  UsagePoint,
} from '../types'

const now = new Date()

function dayKey(d: Date) {
  return d.toISOString().slice(0, 10)
}

export const demoUsers: AdminUser[] = [
  {
    uid: 'u_01',
    email: 'ana.rios@studio.dev',
    displayName: 'Ana Ríos',
    status: 'active',
    role: 'user',
    balance: 42.5,
    totalSpent: 87.2,
    totalTokens: 1_240_000,
    createdAt: formatISO(subDays(now, 40)),
    lastActiveAt: formatISO(subMinutes(now, 3)),
    platform: 'macos',
    appVersion: '1.5.1',
    country: 'CO',
  },
  {
    uid: 'u_02',
    email: 'marco.vega@apps.io',
    displayName: 'Marco Vega',
    status: 'active',
    role: 'user',
    balance: 8.1,
    totalSpent: 210.4,
    totalTokens: 4_880_000,
    createdAt: formatISO(subDays(now, 90)),
    lastActiveAt: formatISO(subMinutes(now, 12)),
    platform: 'macos',
    appVersion: '1.5.1',
    country: 'MX',
  },
  {
    uid: 'u_03',
    email: 'sofia.admin@voryxel.com',
    displayName: 'Sofía Admin',
    status: 'active',
    role: 'admin',
    balance: 0,
    totalSpent: 0,
    totalTokens: 12_000,
    createdAt: formatISO(subDays(now, 120)),
    lastActiveAt: formatISO(subMinutes(now, 1)),
    platform: 'web',
    appVersion: 'admin',
    country: 'US',
  },
  {
    uid: 'u_04',
    email: 'luis.perez@mail.com',
    status: 'suspended',
    role: 'user',
    balance: 0.4,
    totalSpent: 55.0,
    totalTokens: 900_000,
    createdAt: formatISO(subDays(now, 20)),
    lastActiveAt: formatISO(subDays(now, 30)),
    platform: 'macos',
    appVersion: '1.4.0',
    country: 'ES',
  },
  {
    uid: 'u_05',
    email: 'nina.codes@dev.co',
    status: 'active',
    role: 'user',
    balance: 19.82,
    totalSpent: 33.1,
    totalTokens: 640_000,
    createdAt: formatISO(subDays(now, 7)),
    lastActiveAt: formatISO(subHours(now, 2)),
    platform: 'macos',
    appVersion: '1.5.1',
    country: 'AR',
  },
  {
    uid: 'u_06',
    email: 'ops.support@voryxel.com',
    status: 'active',
    role: 'support',
    balance: 5,
    totalSpent: 2.2,
    totalTokens: 40_000,
    createdAt: formatISO(subDays(now, 60)),
    lastActiveAt: formatISO(subMinutes(now, 8)),
    platform: 'web',
    appVersion: 'admin',
    country: 'US',
  },
]

export const demoSessions: ActiveSession[] = demoUsers
  .filter((u) => u.status === 'active')
  .slice(0, 4)
  .map((u, i) => ({
    uid: u.uid,
    email: u.email,
    platform: u.platform ?? 'macos',
    appVersion: u.appVersion ?? '1.5.1',
    lastSeenAt: formatISO(subMinutes(now, i * 4 + 1)),
    ipHint: `186.154.${10 + i}.x`,
  }))

export const demoUsageSeries: UsagePoint[] = Array.from({ length: 14 }).map((_, i) => {
  const d = subDays(now, 13 - i)
  const tokens = 180_000 + Math.round(Math.sin(i / 2) * 80_000) + i * 12_000
  return {
    day: dayKey(d),
    tokens,
    cost: Number((tokens * 0.0000045).toFixed(2)),
    requests: 40 + i * 3 + (i % 4) * 8,
  }
})

export const demoEvents: UsageEvent[] = [
  {
    id: 'e1',
    uid: 'u_02',
    email: 'marco.vega@apps.io',
    model: 'gpt-4.1',
    tokens: 888_400,
    cost: 4.12,
    type: 'usage',
    date: formatISO(subHours(now, 1)),
    note: 'Agent',
  },
  {
    id: 'e2',
    uid: 'u_01',
    email: 'ana.rios@studio.dev',
    model: 'gpt-4.1-mini',
    tokens: 122_000,
    cost: 0.28,
    type: 'usage',
    date: formatISO(subHours(now, 2)),
    note: 'Ask',
  },
  {
    id: 'e3',
    uid: 'u_05',
    email: 'nina.codes@dev.co',
    model: '—',
    tokens: 0,
    cost: 25,
    type: 'topup',
    date: formatISO(subHours(now, 5)),
    note: 'Recarga +$25',
  },
  {
    id: 'e4',
    uid: 'u_02',
    email: 'marco.vega@apps.io',
    model: 'claude-sonnet',
    tokens: 633_100,
    cost: 3.01,
    type: 'usage',
    date: formatISO(subHours(now, 6)),
  },
  {
    id: 'e5',
    uid: 'u_04',
    email: 'luis.perez@mail.com',
    model: '—',
    tokens: 0,
    cost: -10,
    type: 'adjust',
    date: formatISO(subDays(now, 1)),
    note: 'Ajuste admin: abuso de cuota',
  },
]

export const demoFlags: FeatureFlag[] = [
  {
    id: 'agent_auto_apply',
    name: 'Agent auto-apply edits',
    description: 'Aplica edits del agente sin confirmación en modo Agent.',
    enabled: true,
    rolloutPercent: 100,
    updatedAt: formatISO(subDays(now, 2)),
  },
  {
    id: 'inspector_v2',
    name: 'Inspector v2',
    description: 'Monitor lateral + selección DOM en Preview.',
    enabled: true,
    rolloutPercent: 80,
    updatedAt: formatISO(subDays(now, 1)),
  },
  {
    id: 'wallet_cloud_sync',
    name: 'Wallet cloud sync',
    description: 'Sincroniza saldo/transacciones con Firestore.',
    enabled: true,
    rolloutPercent: 100,
    updatedAt: formatISO(subDays(now, 5)),
  },
  {
    id: 'ui_builder',
    name: 'UI Builder',
    description: 'Panel visual para insertar widgets Flutter.',
    enabled: false,
    rolloutPercent: 15,
    updatedAt: formatISO(subHours(now, 10)),
  },
]

export const demoAudit: AuditEntry[] = [
  {
    id: 'a1',
    actorEmail: 'sofia.admin@voryxel.com',
    action: 'user.suspend',
    target: 'luis.perez@mail.com',
    detail: 'Uso anómalo de tokens',
    at: formatISO(subDays(now, 1)),
  },
  {
    id: 'a2',
    actorEmail: 'ops.support@voryxel.com',
    action: 'credits.adjust',
    target: 'nina.codes@dev.co',
    detail: '+$5 cortesía soporte',
    at: formatISO(subHours(now, 8)),
  },
  {
    id: 'a3',
    actorEmail: 'sofia.admin@voryxel.com',
    action: 'flag.update',
    target: 'ui_builder',
    detail: 'rollout 15%',
    at: formatISO(subHours(now, 10)),
  },
]

export const demoModels: ModelPricingRow[] = [
  {
    id: 'm1',
    model: 'gpt-4.1',
    inputPer1M: 2.0,
    outputPer1M: 8.0,
    marginPercent: 20,
    enabled: true,
  },
  {
    id: 'm2',
    model: 'gpt-4.1-mini',
    inputPer1M: 0.4,
    outputPer1M: 1.6,
    marginPercent: 20,
    enabled: true,
  },
  {
    id: 'm3',
    model: 'claude-sonnet',
    inputPer1M: 3.0,
    outputPer1M: 15.0,
    marginPercent: 25,
    enabled: true,
  },
]

export function buildDemoStats(): DashboardStats {
  const tokens7d = demoUsageSeries.slice(-7).reduce((s, p) => s + p.tokens, 0)
  const revenue7d = demoEvents
    .filter((e) => e.type === 'topup')
    .reduce((s, e) => s + e.cost, 0)
  return {
    totalUsers: demoUsers.length,
    activeNow: demoSessions.length,
    activeToday: demoUsers.filter(
      (u) => Date.now() - new Date(u.lastActiveAt).getTime() < 86_400_000,
    ).length,
    revenue7d,
    tokens7d,
    apiSpend7d: Number((tokens7d * 0.0000038).toFixed(2)),
    avgBalance:
      demoUsers.reduce((s, u) => s + u.balance, 0) / Math.max(1, demoUsers.length),
    suspended: demoUsers.filter((u) => u.status === 'suspended').length,
    usageSeries: demoUsageSeries,
    topModels: [
      { model: 'gpt-4.1', tokens: 2_100_000, cost: 9.8 },
      { model: 'gpt-4.1-mini', tokens: 1_400_000, cost: 2.1 },
      { model: 'claude-sonnet', tokens: 980_000, cost: 6.4 },
    ],
  }
}

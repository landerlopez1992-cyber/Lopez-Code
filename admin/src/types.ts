export type UserStatus = 'active' | 'suspended' | 'deleted'

export interface AdminUser {
  uid: string
  email: string
  displayName?: string
  status: UserStatus
  role: 'user' | 'admin' | 'support'
  balance: number
  totalSpent: number
  totalTokens: number
  createdAt: string
  lastActiveAt: string
  platform?: string
  appVersion?: string
  country?: string
}

export interface UsagePoint {
  day: string
  tokens: number
  cost: number
  requests: number
}

export interface UsageEvent {
  id: string
  uid: string
  email: string
  model: string
  tokens: number
  cost: number
  type: 'usage' | 'topup' | 'adjust'
  date: string
  note?: string
}

export interface ActiveSession {
  uid: string
  email: string
  platform: string
  appVersion: string
  lastSeenAt: string
  ipHint?: string
}

export interface FeatureFlag {
  id: string
  name: string
  description: string
  enabled: boolean
  rolloutPercent: number
  updatedAt: string
}

export interface AuditEntry {
  id: string
  actorEmail: string
  action: string
  target: string
  detail: string
  at: string
}

export interface DashboardStats {
  totalUsers: number
  activeNow: number
  activeToday: number
  revenue7d: number
  tokens7d: number
  apiSpend7d: number
  avgBalance: number
  suspended: number
  usageSeries: UsagePoint[]
  topModels: { model: string; tokens: number; cost: number }[]
}

export interface ModelPricingRow {
  id: string
  model: string
  inputPer1M: number
  outputPer1M: number
  marginPercent: number
  enabled: boolean
}

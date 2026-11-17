import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
  serverTimestamp,
} from 'firebase/firestore'
import type {
  AdminUser,
  ActiveSession,
  AuditEntry,
  DashboardStats,
  FeatureFlag,
  ModelPricingRow,
  UsageEvent,
} from '../types'
import { firebaseConfigured, getFirebase } from './firebase'
import {
  buildDemoStats,
  demoAudit,
  demoEvents,
  demoFlags,
  demoModels,
  demoSessions,
  demoUsers,
} from './demoData'

export type DataMode = 'demo' | 'firebase'

export function getDataMode(): DataMode {
  return firebaseConfigured ? 'firebase' : 'demo'
}

async function assertAdmin(uid: string): Promise<boolean> {
  const { db } = getFirebase()
  if (!db) return false
  const snap = await getDoc(doc(db, 'admins', uid))
  return snap.exists()
}

export async function isAdminUid(uid: string): Promise<boolean> {
  if (!firebaseConfigured) return true
  return assertAdmin(uid)
}

function mapUser(id: string, data: Record<string, unknown>): AdminUser {
  return {
    uid: id,
    email: String(data.email ?? ''),
    displayName: data.displayName ? String(data.displayName) : undefined,
    status: (data.status as AdminUser['status']) || 'active',
    role: (data.role as AdminUser['role']) || 'user',
    balance: Number(data.balance ?? 0),
    totalSpent: Number(data.totalSpent ?? 0),
    totalTokens: Number(data.totalTokens ?? 0),
    createdAt: String(
      data.createdAtIso ??
        (data.createdAt as { toDate?: () => Date })?.toDate?.()?.toISOString?.() ??
        new Date().toISOString(),
    ),
    lastActiveAt: String(
      data.lastActiveAtIso ??
        (data.lastActiveAt as { toDate?: () => Date })?.toDate?.()?.toISOString?.() ??
        new Date(0).toISOString(),
    ),
    platform: data.platform ? String(data.platform) : undefined,
    appVersion: data.appVersion ? String(data.appVersion) : undefined,
    country: data.country ? String(data.country) : undefined,
  }
}

export async function fetchUsers(): Promise<AdminUser[]> {
  if (!firebaseConfigured) return demoUsers
  const { db } = getFirebase()
  if (!db) return demoUsers
  const snap = await getDocs(query(collection(db, 'users'), limit(500)))
  return snap.docs.map((d) => mapUser(d.id, d.data()))
}

export async function fetchActiveSessions(): Promise<ActiveSession[]> {
  if (!firebaseConfigured) return demoSessions
  const { db } = getFirebase()
  if (!db) return demoSessions
  const cutoff = new Date(Date.now() - 15 * 60_000).toISOString()
  const snap = await getDocs(
    query(
      collection(db, 'users'),
      where('lastActiveAtIso', '>', cutoff),
      limit(200),
    ),
  )
  return snap.docs.map((d) => {
    const data = d.data()
    return {
      uid: d.id,
      email: String(data.email ?? ''),
      platform: String(data.platform ?? 'unknown'),
      appVersion: String(data.appVersion ?? ''),
      lastSeenAt: String(data.lastActiveAtIso ?? new Date().toISOString()),
    }
  })
}

export async function fetchUsageEvents(): Promise<UsageEvent[]> {
  if (!firebaseConfigured) return demoEvents
  // En producción: collectionGroup('transactions') + Cloud Function agregadora.
  // Por ahora devolvemos demo si no hay índice / datos.
  try {
    const { db } = getFirebase()
    if (!db) return demoEvents
    const users = await fetchUsers()
    const events: UsageEvent[] = []
    for (const u of users.slice(0, 30)) {
      const qs = await getDocs(
        query(
          collection(db, 'users', u.uid, 'transactions'),
          orderBy('date', 'desc'),
          limit(10),
        ),
      )
      for (const t of qs.docs) {
        const data = t.data()
        events.push({
          id: t.id,
          uid: u.uid,
          email: u.email,
          model: String(data.model ?? '—'),
          tokens: Number(data.tokens ?? 0),
          cost: Number(data.cost ?? 0),
          type: (data.type as UsageEvent['type']) || 'usage',
          date: String(data.date ?? new Date().toISOString()),
          note: data.note ? String(data.note) : undefined,
        })
      }
    }
    events.sort((a, b) => b.date.localeCompare(a.date))
    return events.slice(0, 100)
  } catch {
    return demoEvents
  }
}

export async function fetchStats(): Promise<DashboardStats> {
  if (!firebaseConfigured) return buildDemoStats()
  const users = await fetchUsers()
  const sessions = await fetchActiveSessions()
  const demo = buildDemoStats()
  return {
    ...demo,
    totalUsers: users.length,
    activeNow: sessions.length,
    activeToday: users.filter(
      (u) => Date.now() - new Date(u.lastActiveAt).getTime() < 86_400_000,
    ).length,
    avgBalance:
      users.reduce((s, u) => s + u.balance, 0) / Math.max(1, users.length),
    suspended: users.filter((u) => u.status === 'suspended').length,
  }
}

export async function fetchFlags(): Promise<FeatureFlag[]> {
  if (!firebaseConfigured) return demoFlags
  const { db } = getFirebase()
  if (!db) return demoFlags
  const snap = await getDocs(collection(db, 'featureFlags'))
  if (snap.empty) return demoFlags
  return snap.docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      name: String(data.name ?? d.id),
      description: String(data.description ?? ''),
      enabled: Boolean(data.enabled),
      rolloutPercent: Number(data.rolloutPercent ?? 0),
      updatedAt: String(data.updatedAtIso ?? new Date().toISOString()),
    }
  })
}

export async function setFlagEnabled(id: string, enabled: boolean) {
  if (!firebaseConfigured) return
  const { db } = getFirebase()
  if (!db) return
  await setDoc(
    doc(db, 'featureFlags', id),
    {
      enabled,
      updatedAt: serverTimestamp(),
      updatedAtIso: new Date().toISOString(),
    },
    { merge: true },
  )
}

export async function fetchAudit(): Promise<AuditEntry[]> {
  if (!firebaseConfigured) return demoAudit
  const { db } = getFirebase()
  if (!db) return demoAudit
  const snap = await getDocs(
    query(collection(db, 'adminAudit'), orderBy('at', 'desc'), limit(100)),
  )
  if (snap.empty) return demoAudit
  return snap.docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      actorEmail: String(data.actorEmail ?? ''),
      action: String(data.action ?? ''),
      target: String(data.target ?? ''),
      detail: String(data.detail ?? ''),
      at: String(data.at ?? new Date().toISOString()),
    }
  })
}

export async function fetchModels(): Promise<ModelPricingRow[]> {
  if (!firebaseConfigured) return demoModels
  const { db } = getFirebase()
  if (!db) return demoModels
  const snap = await getDocs(collection(db, 'modelPricing'))
  if (snap.empty) return demoModels
  return snap.docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      model: String(data.model ?? d.id),
      inputPer1M: Number(data.inputPer1M ?? 0),
      outputPer1M: Number(data.outputPer1M ?? 0),
      marginPercent: Number(data.marginPercent ?? 20),
      enabled: data.enabled !== false,
    }
  })
}

export async function updateUserStatus(
  uid: string,
  status: AdminUser['status'],
  actorEmail: string,
) {
  if (!firebaseConfigured) return
  const { db } = getFirebase()
  if (!db) return
  await updateDoc(doc(db, 'users', uid), {
    status,
    updatedAt: serverTimestamp(),
  })
  await setDoc(doc(collection(db, 'adminAudit')), {
    actorEmail,
    action: status === 'suspended' ? 'user.suspend' : 'user.status',
    target: uid,
    detail: `status → ${status}`,
    at: new Date().toISOString(),
  })
}

export async function adjustUserBalance(
  uid: string,
  delta: number,
  note: string,
  actorEmail: string,
) {
  if (!firebaseConfigured) return
  const { db } = getFirebase()
  if (!db) return
  const ref = doc(db, 'users', uid)
  const snap = await getDoc(ref)
  const current = Number(snap.data()?.balance ?? 0)
  const next = current + delta
  await updateDoc(ref, {
    balance: next,
    updatedAt: serverTimestamp(),
  })
  const txId = `adj_${Date.now()}`
  await setDoc(doc(db, 'users', uid, 'transactions', txId), {
    id: txId,
    date: new Date().toISOString(),
    type: 'adjust',
    model: '—',
    tokens: 0,
    cost: delta,
    balanceAfter: next,
    note,
  })
  await setDoc(doc(collection(db, 'adminAudit')), {
    actorEmail,
    action: 'credits.adjust',
    target: uid,
    detail: `${delta >= 0 ? '+' : ''}${delta.toFixed(2)} · ${note}`,
    at: new Date().toISOString(),
  })
}

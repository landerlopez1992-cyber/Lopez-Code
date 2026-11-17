import { Card, PageHeader, Badge } from '../components/ui'
import { firebaseConfigured } from '../lib/firebase'
import { getDataMode } from '../lib/adminApi'

const checklist = [
  {
    title: 'Auth admin',
    body: 'Colección admins/{uid} o custom claims. Solo staff entra al panel.',
  },
  {
    title: 'Heartbeat de clientes',
    body: 'El IDE escribe lastActiveAtIso / platform / appVersion en users/{uid}.',
  },
  {
    title: 'Ledger de créditos',
    body: 'users/{uid}/transactions — uso, recargas y ajustes admin.',
  },
  {
    title: 'Feature flags',
    body: 'featureFlags/* leídas por el IDE al arrancar / refresh.',
  },
  {
    title: 'Cloud Functions (siguiente)',
    body: 'Agregados diarios, rate limits server-side, webhooks Stripe, emails.',
  },
  {
    title: 'Observabilidad',
    body: 'Errores del agente, latencia OpenAI, 429s, crash reports del desktop.',
  },
]

export function SystemPage() {
  const mode = getDataMode()

  return (
    <div>
      <PageHeader
        title="Sistema"
        subtitle="Estado de la plataforma admin y roadmap de control."
      />
      <div className="mb-4 flex flex-wrap gap-2">
        <Badge tone={firebaseConfigured ? 'green' : 'amber'}>
          Firebase Web: {firebaseConfigured ? 'configurado' : 'pendiente (.env)'}
        </Badge>
        <Badge tone={mode === 'firebase' ? 'green' : 'amber'}>
          Data mode: {mode}
        </Badge>
        <Badge tone="blue">Project: voryxel-code</Badge>
      </div>

      <div className="grid gap-3 lg:grid-cols-2">
        {checklist.map((c) => (
          <Card key={c.title} className="p-4">
            <div className="font-medium text-zinc-100">{c.title}</div>
            <p className="mt-1 text-sm text-zinc-400">{c.body}</p>
          </Card>
        ))}
      </div>

      <Card className="mt-4 p-4">
        <div className="font-medium text-zinc-100">Herramientas de este calibre</div>
        <div className="mt-3 grid gap-2 text-sm text-zinc-400 md:grid-cols-2">
          <div>• Usuarios / roles / suspensión</div>
          <div>• Sesiones activas en tiempo real</div>
          <div>• Usage por modelo y costo</div>
          <div>• Billing: pasivo, recargas, ajustes</div>
          <div>• Pricing & márgenes</div>
          <div>• Feature flags / kill switches</div>
          <div>• Audit log inmutable</div>
          <div>• Soporte: notas + créditos cortesía</div>
          <div>• Anuncios / force-update versión</div>
          <div>• API keys rotación (próximo)</div>
          <div>• Abuse detection (próximo)</div>
          <div>• Export contable CSV (próximo)</div>
        </div>
      </Card>
    </div>
  )
}

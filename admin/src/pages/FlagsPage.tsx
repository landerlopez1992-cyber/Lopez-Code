import { useEffect, useState } from 'react'
import { fetchFlags, setFlagEnabled } from '../lib/adminApi'
import type { FeatureFlag } from '../types'
import { useAuth } from '../auth/AuthContext'
import { Badge, Button, Card, PageHeader } from '../components/ui'

export function FlagsPage() {
  const { demoMode } = useAuth()
  const [flags, setFlags] = useState<FeatureFlag[]>([])

  async function reload() {
    setFlags(await fetchFlags())
  }

  useEffect(() => {
    void reload()
  }, [])

  return (
    <div>
      <PageHeader
        title="Feature flags"
        subtitle="Rollouts graduales sin redeploy del IDE."
      />
      <div className="grid gap-3 lg:grid-cols-2">
        {flags.map((f) => (
          <Card key={f.id} className="p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <div className="font-medium text-zinc-100">{f.name}</div>
                  <Badge tone={f.enabled ? 'green' : 'zinc'}>
                    {f.enabled ? 'ON' : 'OFF'}
                  </Badge>
                </div>
                <p className="mt-1 text-sm text-zinc-400">{f.description}</p>
                <p className="mt-2 text-xs text-zinc-600">
                  Rollout {f.rolloutPercent}% · {f.id}
                </p>
              </div>
              <Button
                variant={f.enabled ? 'outline' : 'primary'}
                disabled={demoMode}
                onClick={() =>
                  void setFlagEnabled(f.id, !f.enabled).then(reload)
                }
              >
                {f.enabled ? 'Desactivar' : 'Activar'}
              </Button>
            </div>
          </Card>
        ))}
      </div>
    </div>
  )
}

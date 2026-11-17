# Voryxel Admin

Panel web administrativo de **Voryxel Code** (React 19 + Vite + TypeScript + Tailwind v4 + Firebase).

## Qué incluye

| Módulo | Control |
| --- | --- |
| Overview | KPIs: users, activos, tokens 7d, recargas, top modelos |
| Usuarios | Listado, búsqueda, suspender/reactivar, ajustar saldo |
| Activos ahora | Heartbeats recientes (IDE online) |
| Uso & tokens | Ledger de llamadas (modelo, tokens, costo) |
| Billing | Pasivo de créditos, movimientos, cuentas en riesgo |
| Modelos | Pricing + margen por modelo |
| Feature flags | Kill switches / rollouts |
| Audit log | Quién cambió qué |
| Sistema | Checklist de plataforma |

## Arranque

```bash
cd admin
npm install
npm run dev
```

Abre http://localhost:5173 → **Entrar en modo demo** (datos de ejemplo).

## Firebase live

1. Crea una app **Web** en el proyecto `voryxel-code`.
2. Copia `admin/.env.example` → `admin/.env` y rellena las keys.
3. En Firestore crea `admins/{tuUid}` (documento vacío basta).
4. Despliega reglas: `firebase deploy --only firestore:rules`
5. Hosting opcional: `npm run build` y apunta Firebase Hosting a `admin/dist`.

## Relación con el IDE Flutter

El desktop escribe en `users/{uid}`:

- `email`, `balance`, `lastActiveAtIso`, `platform`, `appVersion`, `status`
- `users/{uid}/transactions/{txId}`

El admin lee esas colecciones (requiere ser doc en `admins/`).

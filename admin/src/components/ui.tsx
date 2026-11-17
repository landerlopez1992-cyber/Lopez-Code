import clsx from 'clsx'
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from 'react'

export function Card({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={clsx(
        'rounded-xl border border-zinc-800 bg-zinc-900/70 shadow-[0_0_0_1px_rgba(255,255,255,0.02)]',
        className,
      )}
    >
      {children}
    </div>
  )
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string
  subtitle?: string
  actions?: ReactNode
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-zinc-50">
          {title}
        </h1>
        {subtitle ? (
          <p className="mt-1 text-sm text-zinc-400">{subtitle}</p>
        ) : null}
      </div>
      {actions}
    </div>
  )
}

export function StatCard({
  label,
  value,
  hint,
}: {
  label: string
  value: string
  hint?: string
}) {
  return (
    <Card className="p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">
        {label}
      </div>
      <div className="mt-2 text-2xl font-semibold tabular-nums text-zinc-50">
        {value}
      </div>
      {hint ? <div className="mt-1 text-xs text-zinc-500">{hint}</div> : null}
    </Card>
  )
}

export function Button({
  variant = 'primary',
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'ghost' | 'danger' | 'outline'
}) {
  return (
    <button
      className={clsx(
        'inline-flex items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition disabled:opacity-50',
        variant === 'primary' &&
          'bg-blue-600 text-white hover:bg-blue-500',
        variant === 'ghost' &&
          'bg-transparent text-zinc-300 hover:bg-zinc-800',
        variant === 'outline' &&
          'border border-zinc-700 bg-zinc-900 text-zinc-200 hover:bg-zinc-800',
        variant === 'danger' &&
          'bg-red-600/90 text-white hover:bg-red-500',
        className,
      )}
      {...props}
    />
  )
}

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={clsx(
        'w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none ring-blue-500/40 placeholder:text-zinc-600 focus:ring-2',
        props.className,
      )}
    />
  )
}

export function Badge({
  children,
  tone = 'zinc',
}: {
  children: ReactNode
  tone?: 'zinc' | 'green' | 'red' | 'blue' | 'amber'
}) {
  const tones = {
    zinc: 'bg-zinc-800 text-zinc-300',
    green: 'bg-emerald-500/15 text-emerald-400',
    red: 'bg-red-500/15 text-red-400',
    blue: 'bg-blue-500/15 text-blue-400',
    amber: 'bg-amber-500/15 text-amber-400',
  }
  return (
    <span
      className={clsx(
        'inline-flex rounded-md px-2 py-0.5 text-[11px] font-semibold',
        tones[tone],
      )}
    >
      {children}
    </span>
  )
}

export function TableShell({ children }: { children: ReactNode }) {
  return (
    <Card className="overflow-hidden">
      <div className="overflow-x-auto">{children}</div>
    </Card>
  )
}

export function Th({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <th
      className={clsx(
        'px-3 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-zinc-500',
        className,
      )}
    >
      {children}
    </th>
  )
}

export function Td({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <td className={clsx('px-3 py-2.5 text-sm text-zinc-200', className)}>
      {children}
    </td>
  )
}

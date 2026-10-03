import type { OrderStatus } from '../api'

// Primitives shared by the Seller Hub panes, switcher, overview, and modals.

export const money = (n: number) => `$${n.toFixed(2)}`

export const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('')

export type Tone = 'accent' | 'warn' | 'ok' | 'muted'

export const ORDER_PILLS: Record<OrderStatus, { tone: Tone; label: string }> = {
  PLACED: { tone: 'accent', label: 'To fulfill' },
  PACKED: { tone: 'accent', label: 'Packed' },
  SHIPPED: { tone: 'warn', label: 'Shipped' },
  DELIVERED: { tone: 'ok', label: 'Delivered' },
  READY_FOR_PICKUP: { tone: 'warn', label: 'Ready for pickup' },
  PICKED_UP: { tone: 'ok', label: 'Picked up' },
  CANCELED: { tone: 'muted', label: 'Canceled' },
}

export function StatusPill({ tone, children }: { tone: Tone; children: string }) {
  const classes = {
    accent: 'bg-crema-400/20 text-crema-500',
    warn: 'bg-warn-100 text-warn-700',
    ok: 'bg-ok-100 text-ok-700',
    muted: 'bg-cream-100 text-espresso-500',
  }[tone]
  return (
    <span className={`inline-block rounded-full px-2.5 py-1 text-xs font-semibold whitespace-nowrap ${classes}`}>
      {children}
    </span>
  )
}

export const th = 'px-4 py-3 text-left text-[11px] font-semibold tracking-wider text-espresso-500 uppercase'
export const td = 'px-4 py-3.5 text-sm'
export const inputCls =
  'rounded-lg border border-cream-200 bg-white px-2.5 py-1.5 text-sm outline-none focus:border-crema-400'
export const cardCls = 'rounded-2xl border border-cream-200 bg-white p-5 shadow-sm'
export const primaryBtn =
  'rounded-xl bg-espresso-700 px-4 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40'
export const secondaryBtn =
  'rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-semibold text-espresso-700 transition hover:border-crema-400 disabled:opacity-40'

export function Table({ headers, children }: { headers: string[]; children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-cream-200 bg-white shadow-sm">
      <table className="w-full min-w-160">
        <thead className="bg-cream-100/60">
          <tr>
            {headers.map((h) => (
              <th key={h} className={th}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-cream-200">{children}</tbody>
      </table>
    </div>
  )
}

export function PaneHeader({ title, subtitle, children }: { title: string; subtitle: string; children?: React.ReactNode }) {
  return (
    <div className="mb-5 flex items-center justify-between gap-3">
      <div>
        <h2 className="text-xl font-bold tracking-tight">{title}</h2>
        <p className="mt-0.5 text-sm text-espresso-500">{subtitle}</p>
      </div>
      {children && <div className="flex shrink-0 items-center gap-2">{children}</div>}
    </div>
  )
}

export function ErrorNote({ message, onDismiss }: { message: string; onDismiss: () => void }) {
  return (
    <div className="mb-4 flex items-center justify-between rounded-xl border border-danger-200 bg-danger-100 px-4 py-3 text-sm text-danger-700">
      {message}
      <button onClick={onDismiss} className="ml-3 font-semibold">
        ✕
      </button>
    </div>
  )
}

export function EmptyRow({ colSpan, message }: { colSpan: number; message: string }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-10 text-center text-sm text-espresso-500">
        {message}
      </td>
    </tr>
  )
}

// Round monogram used for shops in the switcher, overview cards, and order rows.
export function ShopAvatar({ name, size = 'md', tone = 'cream' }: { name: string; size?: 'sm' | 'md'; tone?: 'cream' | 'ink' }) {
  const dims = size === 'sm' ? 'size-6 text-[9px]' : 'size-9 text-[11px]'
  const fill = tone === 'ink' ? 'bg-espresso-700 text-cream-50' : 'bg-cream-100 text-espresso-700'
  return (
    <span className={`flex shrink-0 items-center justify-center rounded-full font-bold ${dims} ${fill}`}>
      {initials(name)}
    </span>
  )
}

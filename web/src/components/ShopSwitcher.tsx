import { useEffect, useRef, useState } from 'react'
import type { Seller, SellerShop } from '../api'
import { ShopAvatar, StatusPill, type Tone } from './hubBits'

export const ALL_SHOPS = 'all'
export type HubView = typeof ALL_SHOPS | string

// Sidebar trigger plus popover: All shops, each owned shop with open work,
// pending claims greyed, and Add another shop. Figma: "Shop Switcher / Popover".
export function ShopSwitcher({
  seller,
  view,
  onSelect,
  onAddShop,
}: {
  seller: Seller
  view: HubView
  onSelect: (view: HubView) => void
  onAddShop: () => void
}) {
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const { shops, pendingClaims, workload } = seller
  const current = shops.find((s) => s.id === view) ?? null
  const index = current ? shops.indexOf(current) + 1 : 0
  const pick = (next: HubView) => {
    setOpen(false)
    onSelect(next)
  }

  const subtitle = current
    ? shops.length > 1
      ? `${current.city} · ${index} of ${shops.length} shops`
      : '✓ Verified owner'
    : `${shops.length} shops${pendingClaims.length ? ` · ${pendingClaims.length} pending` : ''}`

  return (
    <div ref={root} className="relative mb-4">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        className={`flex w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition ${
          open ? 'border-crema-400 bg-white' : 'border-cream-200 bg-cream-100 hover:border-crema-400'
        }`}
      >
        {current ? <ShopAvatar name={current.name} /> : <AllShopsIcon />}
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-semibold">{current ? current.name : 'All shops'}</span>
          <span className={`block truncate text-[11px] ${current && shops.length === 1 ? 'text-ok-700' : 'text-espresso-500'}`}>
            {subtitle}
          </span>
        </span>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4 shrink-0 text-espresso-500">
          <path d="m7 15 5 5 5-5M7 9l5-5 5 5" />
        </svg>
      </button>

      {open && (
        <div
          role="listbox"
          className="absolute inset-x-0 top-full z-30 mt-2 flex flex-col overflow-hidden rounded-2xl border border-cream-200 bg-white shadow-lg"
        >
          <div className="flex items-center justify-between px-3.5 pt-3 pb-1.5">
            <span className="text-[10px] font-semibold tracking-wider text-espresso-500 uppercase">Your shops</span>
            <span className="text-[10px] text-espresso-500">
              {shops.length}
              {pendingClaims.length ? ` · ${pendingClaims.length} pending` : ''}
            </span>
          </div>

          <div className="max-h-[60vh] overflow-y-auto px-1.5 pb-1.5">
            {shops.length > 1 && (
              <>
                <Row
                  selected={view === ALL_SHOPS}
                  onClick={() => pick(ALL_SHOPS)}
                  avatar={<AllShopsIcon />}
                  title="All shops"
                  subtitle="Totals across every location"
                  badges={workload.toFulfill > 0 ? [{ tone: 'accent', label: `${workload.toFulfill} to fulfill` }] : []}
                />
                <div className="mx-2 my-1 border-t border-cream-200" />
              </>
            )}

            {shops.map((s) => (
              <Row
                key={s.id}
                selected={view === s.id}
                onClick={() => pick(s.id)}
                avatar={<ShopAvatar name={s.name} />}
                title={s.name}
                subtitle={`${s.address} · ${s.city}`}
                badges={shopBadges(s)}
              />
            ))}

            {pendingClaims.map((c) => (
              <Row
                key={c.id}
                disabled
                avatar={<ShopAvatar name={c.shop.name} />}
                title={c.shop.name}
                subtitle={c.shop.city}
                badges={[{ tone: 'muted', label: 'Pending review' }]}
              />
            ))}

            <div className="mx-2 my-1 border-t border-cream-200" />
            <button
              type="button"
              onClick={() => {
                setOpen(false)
                onAddShop()
              }}
              className="flex w-full items-center gap-3 rounded-xl px-2 py-2.5 text-left transition hover:bg-cream-100"
            >
              <span className="flex size-9 shrink-0 items-center justify-center rounded-full border border-dashed border-crema-400 text-lg leading-none text-crema-500">
                +
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-semibold text-crema-500">Add another shop</span>
                <span className="block text-[11px] text-espresso-500">Claim a location you own</span>
              </span>
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// Setup first, then work. Verified shops with nothing open get no badge.
export function shopBadges(shop: SellerShop): Badge[] {
  if (!shop.sellerOnboarded) return [{ tone: 'warn', label: 'Finish setup' }]
  const w = shop.workload
  if (!w) return []
  const out: Badge[] = []
  if (w.toFulfill > 0) out.push({ tone: 'accent', label: `${w.toFulfill} to fulfill` })
  if (w.lowStock > 0) out.push({ tone: 'warn', label: `${w.lowStock} low stock` })
  return out
}

export type Badge = { tone: Tone; label: string }

function Row({
  avatar,
  title,
  subtitle,
  selected = false,
  disabled = false,
  onClick,
  badges = [],
}: {
  avatar: React.ReactNode
  title: string
  subtitle: string
  selected?: boolean
  disabled?: boolean
  onClick?: () => void
  badges?: Badge[]
}) {
  return (
    <button
      type="button"
      role="option"
      aria-selected={selected}
      disabled={disabled}
      onClick={onClick}
      className={`flex w-full items-start gap-3 rounded-xl px-2 py-2.5 text-left transition ${
        selected ? 'bg-cream-100' : disabled ? 'opacity-50' : 'hover:bg-cream-100'
      }`}
    >
      {avatar}
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2">
          <span className="truncate text-sm font-semibold">{title}</span>
          {selected && <span className="ml-auto text-ok-700">✓</span>}
        </span>
        <span className="block truncate text-[11px] text-espresso-500">{subtitle}</span>
        {badges.length > 0 && (
          <span className="mt-1.5 flex flex-wrap gap-1.5">
            {badges.map((b) => (
              <StatusPill key={b.label} tone={b.tone}>
                {b.label}
              </StatusPill>
            ))}
          </span>
        )}
      </span>
    </button>
  )
}

function AllShopsIcon() {
  return (
    <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-espresso-700 text-cream-50">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" className="size-4">
        <path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z" />
      </svg>
    </span>
  )
}

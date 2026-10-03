import { useEffect, useState } from 'react'
import { fetchMyOrders, fetchProductCountsByShop, type Order, type ProductCounts, type Seller, type SellerShop } from '../api'
import { cardCls, EmptyRow, ErrorNote, money, ORDER_PILLS, PaneHeader, primaryBtn, secondaryBtn, ShopAvatar, StatusPill, Table, td } from './hubBits'
import { shopBadges } from './ShopSwitcher'

const RECENT = 8

// Cross-shop dashboard. Figma: "Web / Multi-shop — All shops overview".
export function AllShopsPane({
  seller,
  user,
  onOpenShop,
  onOpenOrders,
  onAddShop,
  onCopyListings,
}: {
  seller: Seller
  user: { name: string }
  onOpenShop: (id: string) => void
  onOpenOrders: () => void
  onAddShop: () => void
  onCopyListings: () => void
}) {
  const [counts, setCounts] = useState<Record<string, ProductCounts> | null>(null)
  const [orders, setOrders] = useState<Order[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const { shops, workload } = seller

  useEffect(() => {
    fetchProductCountsByShop(shops.map((s) => s.id)).then(setCounts).catch((e: Error) => setError(e.message))
    fetchMyOrders(null, 0, RECENT)
      .then((d) => setOrders(d.orders))
      .catch((e: Error) => setError(e.message))
  }, [shops])

  const activeListings = counts ? Object.values(counts).reduce((n, c) => n + c.inStock + c.lowStock, 0) : null
  const canCopy = shops.filter((s) => s.sellerOnboarded).length >= 2

  return (
    <section className="flex flex-col gap-6">
      <PaneHeader title={`${greeting()}, ${user.name.split(' ')[0]}`} subtitle={`Across your ${shops.length} shops today. Pick one in the switcher to drill in.`}>
        {canCopy && (
          <button onClick={onCopyListings} className={secondaryBtn}>
            Copy listings
          </button>
        )}
        <button onClick={onAddShop} className={primaryBtn}>
          + Add another shop
        </button>
      </PaneHeader>
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="To fulfill" value={workload.toFulfill} hint={hintShops(shops, 'toFulfill')} />
        <Stat label="To ship" value={workload.toShip} hint={hintShops(shops, 'toShip')} />
        <Stat label="Low stock" value={workload.lowStock} hint={hintShops(shops, 'lowStock')} tone="warn" />
        <Stat label="Active listings" value={activeListings} />
      </div>

      <div>
        <div className="mb-3 flex items-baseline justify-between gap-3">
          <h3 className="font-bold">Your shops</h3>
          <p className="text-xs text-espresso-500">Each shop keeps its own listings, orders and delivery settings.</p>
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {shops.map((s) => (
            <ShopCard key={s.id} shop={s} counts={counts?.[s.id]} onOpen={() => onOpenShop(s.id)} />
          ))}
          <button
            onClick={onAddShop}
            className="flex min-h-48 flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-cream-200 p-5 text-center transition hover:border-crema-400"
          >
            <span className="flex size-9 items-center justify-center rounded-full bg-crema-400/20 text-lg leading-none text-crema-500">+</span>
            <span className="text-sm font-semibold">Add another shop</span>
            <span className="text-[11px] text-espresso-500">Claim a location you own. Support reviews it in 1–2 days; then it joins your switcher.</span>
          </button>
        </div>
      </div>

      <div>
        <div className="mb-3 flex items-center justify-between gap-3">
          <h3 className="flex items-center gap-2 font-bold">
            Recent orders <StatusPill tone="muted">All shops</StatusPill>
          </h3>
          <button onClick={onOpenOrders} className="text-xs font-medium text-crema-500 hover:text-espresso-900">
            View all orders →
          </button>
        </div>
        {orders && (
          <Table headers={['Order', 'Shop', 'Buyer', 'Items', 'Total', 'Status']}>
            {orders.map((o) => (
              <tr key={o.id}>
                <td className={`${td} font-semibold`}>#{o.number}</td>
                <td className={td}>
                  <span className="flex items-center gap-2">
                    <ShopAvatar name={o.shop.name} size="sm" />
                    <span className="truncate">{o.shop.name}</span>
                  </span>
                </td>
                <td className={td}>{o.buyer?.name ?? '—'}</td>
                <td className={`${td} text-espresso-500`}>{o.items.map((i) => `${i.qty}× ${i.name}`).join(' · ')}</td>
                <td className={td}>{money(o.total)}</td>
                <td className={td}>
                  <StatusPill tone={ORDER_PILLS[o.status].tone}>{ORDER_PILLS[o.status].label}</StatusPill>
                </td>
              </tr>
            ))}
            {orders.length === 0 && <EmptyRow colSpan={6} message="No orders yet across your shops." />}
          </Table>
        )}
      </div>
    </section>
  )
}

function greeting() {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'
}

// "across 2 shops" when work is spread out; the shop's name when it is one.
function hintShops(shops: SellerShop[], key: 'toFulfill' | 'toShip' | 'lowStock') {
  const with_ = shops.filter((s) => (s.workload?.[key] ?? 0) > 0)
  if (with_.length === 0) return undefined
  return with_.length === 1 ? with_[0].name : `across ${with_.length} shops`
}

function Stat({ label, value, hint, tone = 'accent' }: { label: string; value: number | null; hint?: string; tone?: 'accent' | 'warn' }) {
  return (
    <div className={cardCls}>
      <p className="text-xs font-medium text-espresso-500">{label}</p>
      <div className="mt-2 flex items-center gap-2.5">
        <span className="text-2xl font-bold tabular-nums">{value ?? '·'}</span>
        {hint && <StatusPill tone={tone}>{hint}</StatusPill>}
      </div>
    </div>
  )
}

function ShopCard({ shop, counts, onOpen }: { shop: SellerShop; counts?: ProductCounts; onOpen: () => void }) {
  const w = shop.workload
  const badge = shopBadges(shop)[0] ?? { tone: 'ok' as const, label: '✓ Verified owner' }
  const listings = counts ? counts.inStock + counts.lowStock : null
  return (
    <div className={`${cardCls} flex flex-col gap-3`}>
      <div className="flex items-center gap-3">
        <ShopAvatar name={shop.name} />
        <div className="min-w-0">
          <p className="truncate text-sm font-bold">{shop.name}</p>
          <p className="truncate text-[11px] text-espresso-500">
            {shop.address} · {shop.city}
          </p>
        </div>
      </div>
      <div>
        <StatusPill tone={badge.tone}>{badge.label}</StatusPill>
      </div>
      {shop.sellerOnboarded ? (
        <div className="grid grid-cols-3 gap-2 border-t border-cream-200 pt-3">
          <Mini value={w?.toFulfill ?? 0} label="To fulfill" tone="accent" />
          <Mini value={w?.toShip ?? 0} label="To ship" />
          <Mini value={w?.lowStock ?? 0} label="Low stock" tone="warn" />
        </div>
      ) : (
        <div className="grid grid-cols-3 gap-2 border-t border-cream-200 pt-3">
          <Mini value="—" label="To fulfill" />
          <Mini value="—" label="To ship" />
          <Mini value={listings ?? 0} label="Listings" />
        </div>
      )}
      <button onClick={onOpen} className="mt-auto text-left text-xs font-semibold text-crema-500 hover:text-espresso-900">
        {shop.sellerOnboarded ? 'Open shop →' : 'Finish setup → 2 min'}
      </button>
    </div>
  )
}

function Mini({ value, label, tone }: { value: number | string; label: string; tone?: 'accent' | 'warn' }) {
  const color = typeof value === 'number' && value > 0 ? (tone === 'warn' ? 'text-warn-700' : tone === 'accent' ? 'text-crema-500' : '') : ''
  return (
    <div>
      <p className={`text-lg font-bold tabular-nums ${color}`}>{value}</p>
      <p className="text-[10px] text-espresso-500">{label}</p>
    </div>
  )
}

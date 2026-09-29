import { useEffect, useState } from 'react'
import {
  cancelOrder,
  fetchMyOrders,
  fetchMyProducts,
  fetchMyShipments,
  fetchSellerShop,
  markPickedUp,
  markReadyForPickup,
  updateDeliverySettings,
  updateProduct,
  updateShipment,
  updateShopProfile,
  type CoffeeShop,
  type ListingStatus,
  type Order,
  type OrderStatus,
  type Product,
  type ProductCounts,
  type Shipment,
  type ShipmentStatus,
  type User,
} from '../api'
import { ListingEditor } from './ListingEditor'
import { SellerOnboarding } from './SellerOnboarding'

type Tab = 'overview' | 'products' | 'orders' | 'shipments'

// The app header (73px) stays visible above the hub; the sidebar pins below it.
const BELOW_HEADER = 'top-[73px] h-[calc(100vh-73px)]'

const money = (n: number) => `$${n.toFixed(2)}`

const SHIPMENT_LABELS: Record<ShipmentStatus, string> = {
  LABEL_READY: 'Label ready',
  READY_FOR_DROPOFF: 'Ready for dropoff',
  IN_TRANSIT: 'In transit',
  DELIVERED: 'Delivered',
}

// One step at a time: print the label, drop it off, carrier scans, delivered.
const NEXT_SHIPMENT_STEP: Partial<Record<ShipmentStatus, { to: ShipmentStatus; label: string }>> = {
  LABEL_READY: { to: 'READY_FOR_DROPOFF', label: 'Mark ready for dropoff' },
  READY_FOR_DROPOFF: { to: 'IN_TRANSIT', label: 'Mark in transit' },
  IN_TRANSIT: { to: 'DELIVERED', label: 'Mark delivered' },
}

const ORDER_PILLS: Record<OrderStatus, { tone: Tone; label: string }> = {
  PLACED: { tone: 'accent', label: 'To fulfill' },
  SHIPPED: { tone: 'warn', label: 'Shipped' },
  DELIVERED: { tone: 'ok', label: 'Delivered' },
  READY_FOR_PICKUP: { tone: 'warn', label: 'Ready for pickup' },
  PICKED_UP: { tone: 'ok', label: 'Picked up' },
  CANCELED: { tone: 'muted', label: 'Canceled' },
}

// Shipped orders advance through their shipment, so only pickup has steps here.
const NEXT_PICKUP_STEP: Partial<Record<OrderStatus, { run: (id: string) => Promise<Order>; label: string }>> = {
  PLACED: { run: markReadyForPickup, label: 'Mark ready' },
  READY_FOR_PICKUP: { run: markPickedUp, label: 'Mark picked up' },
}

const CANCELABLE: OrderStatus[] = ['PLACED', 'READY_FOR_PICKUP']

type Tone = 'accent' | 'warn' | 'ok' | 'muted'

const LISTING_LABELS: Record<ListingStatus, string> = {
  IN_STOCK: 'In stock',
  LOW_STOCK: 'Low stock',
  HIDDEN: 'Hidden',
}
const LISTING_PILL_TONE: Record<ListingStatus, Tone> = { IN_STOCK: 'ok', LOW_STOCK: 'warn', HIDDEN: 'muted' }
const LISTING_COUNT_KEY: Record<ListingStatus, keyof ProductCounts> = {
  IN_STOCK: 'inStock',
  LOW_STOCK: 'lowStock',
  HIDDEN: 'hidden',
}

function StatusPill({ tone, children }: { tone: Tone; children: string }) {
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

function shipmentTone(status: ShipmentStatus): Tone {
  return status === 'LABEL_READY' ? 'accent' : status === 'DELIVERED' ? 'ok' : 'warn'
}

const th = 'px-4 py-3 text-left text-[11px] font-semibold tracking-wider text-espresso-500 uppercase'
const td = 'px-4 py-3.5 text-sm'
const inputCls =
  'rounded-lg border border-cream-200 bg-white px-2.5 py-1.5 text-sm outline-none focus:border-crema-400'
const cardCls = 'rounded-2xl border border-cream-200 bg-white p-5 shadow-sm'
const primaryBtn =
  'rounded-xl bg-espresso-700 px-4 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40'

function Table({ headers, children }: { headers: string[]; children: React.ReactNode }) {
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

// MARK: Overview

function StatCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className={`${cardCls} flex-1`}>
      <p className="text-2xl font-bold tabular-nums">{value}</p>
      <p className="mt-0.5 text-xs font-medium text-espresso-500">{label}</p>
      {hint && <p className="mt-1 text-[11px] text-crema-500">{hint}</p>}
    </div>
  )
}

function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button
      type="button"
      onClick={() => onChange(!on)}
      className="flex items-center justify-between gap-3 rounded-xl border border-cream-200 px-3.5 py-2.5 text-sm font-medium transition hover:border-crema-400"
    >
      {label}
      <span className={`flex h-5 w-9 items-center rounded-full p-0.5 transition ${on ? 'bg-crema-500' : 'bg-cream-200'}`}>
        <span className={`size-4 rounded-full bg-white shadow transition ${on ? 'translate-x-4' : ''}`} />
      </span>
    </button>
  )
}

function OverviewPane({
  shop,
  user,
  onShopChanged,
}: {
  shop: CoffeeShop | null
  user: User
  onShopChanged: (s: CoffeeShop) => void
}) {
  const [stats, setStats] = useState<{ listings: number; toFulfill: number; toShip: number } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState<string | null>(null)

  // Profile draft
  const [bio, setBio] = useState('')
  const [website, setWebsite] = useState('')
  const [savingProfile, setSavingProfile] = useState(false)

  // Fulfillment draft
  const [shipping, setShipping] = useState(true)
  const [pickup, setPickup] = useState(false)
  const [pickupNote, setPickupNote] = useState('')
  const [savingDelivery, setSavingDelivery] = useState(false)

  useEffect(() => {
    if (!shop) return
    setBio(shop.vibe ?? '')
    setWebsite(shop.website ?? '')
    setShipping(shop.deliverySettings?.shipping ?? true)
    setPickup(shop.deliverySettings?.pickup ?? false)
    setPickupNote(shop.deliverySettings?.pickupInstructions ?? '')
  }, [shop])

  useEffect(() => {
    if (!shop) return
    Promise.all([fetchMyProducts(shop.id), fetchMyOrders(shop.id), fetchMyShipments(shop.id)])
      .then(([{ myProductCounts: counts }, orders, shipments]) =>
        setStats({
          listings: counts.inStock + counts.lowStock,
          toFulfill: orders.filter((o) => CANCELABLE.includes(o.status)).length,
          toShip: shipments.filter((s) => s.status === 'LABEL_READY').length,
        }),
      )
      .catch((e: Error) => setError(e.message))
  }, [shop])

  const flash = (message: string) => {
    setSaved(message)
    setTimeout(() => setSaved(null), 2500)
  }

  const saveProfile = () => {
    if (!shop) return
    setSavingProfile(true)
    updateShopProfile(shop.id, { vibe: bio.trim(), website: website.trim() })
      .then((updated) => {
        onShopChanged({ ...shop, ...updated })
        flash('Shop profile saved.')
      })
      .catch((e: Error) => setError(e.message))
      .finally(() => setSavingProfile(false))
  }

  const saveDelivery = () => {
    if (!shop) return
    setSavingDelivery(true)
    updateDeliverySettings(shop.id, { shipping, pickup, pickupInstructions: pickupNote.trim() || null })
      .then((updated) => {
        onShopChanged({ ...shop, deliverySettings: updated.deliverySettings })
        flash('Fulfillment settings saved.')
      })
      .catch((e: Error) => setError(e.message))
      .finally(() => setSavingDelivery(false))
  }

  if (!shop) return <p className="text-sm text-espresso-500">Loading…</p>

  return (
    <section className="flex flex-col gap-5">
      <PaneHeader title={shop.name} subtitle={`${shop.address}, ${shop.city}`} />
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {saved && (
        <p className="rounded-xl bg-ok-100 px-4 py-2.5 text-sm font-medium text-ok-700">{saved}</p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        <StatCard label="Active listings" value={stats ? String(stats.listings) : '·'} />
        <StatCard
          label="Orders to fulfill"
          value={stats ? String(stats.toFulfill) : '·'}
          hint={stats?.toFulfill ? 'Buyers are waiting' : undefined}
        />
        <StatCard label="Shipments to send" value={stats ? String(stats.toShip) : '·'} />
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <div className={cardCls}>
          <h3 className="font-bold">Shop profile</h3>
          <p className="mt-0.5 text-xs text-espresso-500">What buyers see on your shop page.</p>
          <label className="mt-4 flex flex-col gap-1.5 text-xs font-semibold text-espresso-500">
            Bio
            <textarea
              className={`${inputCls} w-full resize-none`}
              rows={3}
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              placeholder="e.g. Family-run roastery pouring single origins on a Slayer since 2019."
            />
          </label>
          <label className="mt-3 flex flex-col gap-1.5 text-xs font-semibold text-espresso-500">
            Website
            <input
              className={`${inputCls} w-full`}
              value={website}
              onChange={(e) => setWebsite(e.target.value)}
              placeholder="yourshop.com"
            />
          </label>
          <p className="mt-3 text-[11px] text-espresso-500">
            Location: {shop.address}, {shop.city} — contact support to correct it.
          </p>
          <button onClick={saveProfile} disabled={savingProfile} className={`${primaryBtn} mt-4`}>
            {savingProfile ? 'Saving…' : 'Save profile'}
          </button>
        </div>

        <div className="flex flex-col gap-5">
          <div className={cardCls}>
            <h3 className="font-bold">Fulfillment</h3>
            <p className="mt-0.5 text-xs text-espresso-500">Offer at least one of shipping or pickup.</p>
            <div className="mt-4 flex flex-col gap-2">
              <Toggle on={shipping} onChange={setShipping} label="Shipping" />
              <Toggle on={pickup} onChange={setPickup} label="In-store pickup" />
              {pickup && (
                <input
                  className={`${inputCls} w-full`}
                  value={pickupNote}
                  onChange={(e) => setPickupNote(e.target.value)}
                  placeholder="Pickup instructions, e.g. Ask at the register. Open 7am–3pm."
                />
              )}
            </div>
            <button onClick={saveDelivery} disabled={savingDelivery || (!shipping && !pickup)} className={`${primaryBtn} mt-4`}>
              {savingDelivery ? 'Saving…' : 'Save fulfillment'}
            </button>
          </div>

          <div className={`${cardCls} flex items-center gap-3.5`}>
            {(shop.owner?.picture ?? user.picture) ? (
              <img src={shop.owner?.picture ?? user.picture ?? ''} alt="" className="size-11 rounded-full" referrerPolicy="no-referrer" />
            ) : (
              <span className="flex size-11 items-center justify-center rounded-full bg-espresso-700 text-sm font-semibold text-cream-50">
                {(shop.owner?.name ?? user.name)[0]}
              </span>
            )}
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold">{shop.owner?.name ?? user.name}</p>
              <p className="text-[11px] font-medium text-ok-700">✓ Verified owner</p>
              <p className="text-[11px] text-espresso-500">Shown on your public shop page.</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

// MARK: Products

function ProductsPane({
  shopId,
  onNew,
  onEdit,
}: {
  shopId: string
  onNew: () => void
  onEdit: (product: Product) => void
}) {
  const [filter, setFilter] = useState<ListingStatus | ''>('')
  const [products, setProducts] = useState<Product[] | null>(null)
  const [counts, setCounts] = useState<ProductCounts | null>(null)
  const [reload, setReload] = useState(0)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchMyProducts(shopId, filter || undefined)
      .then((d) => {
        setProducts(d.myProducts)
        setCounts(d.myProductCounts)
      })
      .catch((e: Error) => setError(e.message))
  }, [shopId, filter, reload])

  // Refetch rather than patch: a stock or visibility change can move the row out of the filter.
  const act = (fn: () => Promise<unknown>) =>
    fn()
      .then(() => setReload((n) => n + 1))
      .catch((e: Error) => setError(e.message))

  const chips: [ListingStatus | '', string, number | undefined][] = [
    ['', 'All', counts?.total],
    ...(Object.keys(LISTING_LABELS) as ListingStatus[]).map(
      (s) => [s, LISTING_LABELS[s], counts?.[LISTING_COUNT_KEY[s]]] as [ListingStatus, string, number | undefined],
    ),
  ]

  return (
    <section>
      <PaneHeader
        title="Listings"
        subtitle={counts ? `${counts.total} total${counts.lowStock ? ` · ${counts.lowStock} low on stock` : ''}` : '…'}
      >
        <button onClick={onNew} className={primaryBtn}>
          + New listing
        </button>
      </PaneHeader>
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {counts && counts.total > 0 && (
        <div className="mb-4 flex flex-wrap gap-1.5">
          {chips.map(([key, label, n]) => (
            <button
              key={key || 'all'}
              onClick={() => setFilter(key)}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                filter === key
                  ? 'bg-espresso-700 text-cream-50'
                  : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
              }`}
            >
              {label} · {n ?? '·'}
            </button>
          ))}
        </div>
      )}
      {products && (
        <Table headers={['Listing', 'Price', 'Stock', 'Status', '']}>
          {products.map((p) => (
            <tr key={p.id} className={p.active ? '' : 'opacity-50'}>
              <td className={td}>
                <div className="flex items-center gap-3">
                  {p.coverPhoto ? (
                    <img src={p.coverPhoto.data} alt="" className="size-10 shrink-0 rounded-lg object-cover" />
                  ) : (
                    <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-cream-100 text-base">☕️</span>
                  )}
                  <div>
                    <button onClick={() => onEdit(p)} className="text-left font-semibold hover:text-crema-500">
                      {p.name}
                    </button>
                    {p.variant && <div className="text-xs text-espresso-500">{p.variant}</div>}
                  </div>
                </div>
              </td>
              <td className={td}>{money(p.price)}</td>
              <td className={td}>
                <div className="flex items-center gap-1.5">
                  <StockButton label="−" onClick={() => act(() => updateProduct(p.id, { stockQty: Math.max(0, p.stockQty - 1) }))} />
                  <span className="w-8 text-center font-medium tabular-nums">{p.stockQty}</span>
                  <StockButton label="+" onClick={() => act(() => updateProduct(p.id, { stockQty: p.stockQty + 1 }))} />
                </div>
              </td>
              <td className={td}>
                <StatusPill tone={LISTING_PILL_TONE[p.status]}>{LISTING_LABELS[p.status]}</StatusPill>
              </td>
              <td className={`${td} text-right whitespace-nowrap`}>
                <button
                  onClick={() => act(() => updateProduct(p.id, { active: !p.active }))}
                  className="mr-3 text-xs font-medium text-espresso-500 hover:text-espresso-900"
                >
                  {p.active ? 'Hide' : 'Show'}
                </button>
                <button onClick={() => onEdit(p)} className="text-xs font-medium text-crema-500 hover:text-espresso-900">
                  Edit
                </button>
              </td>
            </tr>
          ))}
          {products.length === 0 && (
            <EmptyRow
              colSpan={5}
              message={
                filter
                  ? `No ${LISTING_LABELS[filter].toLowerCase()} listings.`
                  : 'No listings yet. Create your first bag, tote, or gift card.'
              }
            />
          )}
        </Table>
      )}
    </section>
  )
}

function StockButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="flex size-6 items-center justify-center rounded-md border border-cream-200 text-sm text-espresso-500 hover:border-crema-400 hover:text-espresso-900"
    >
      {label}
    </button>
  )
}

// MARK: Orders

function OrdersPane({ shopId }: { shopId: string }) {
  const [orders, setOrders] = useState<Order[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchMyOrders(shopId).then(setOrders).catch((e: Error) => setError(e.message))
  }, [shopId])

  const open = orders?.filter((o) => CANCELABLE.includes(o.status)).length ?? 0
  const run = (fn: Promise<Order>) =>
    fn
      .then((updated) => setOrders((prev) => prev!.map((x) => (x.id === updated.id ? updated : x))))
      .catch((e: Error) => setError(e.message))

  return (
    <section>
      <PaneHeader title="Orders" subtitle={orders ? `${orders.length} total · ${open} to fulfill` : '…'} />
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {orders && (
        <Table headers={['Order', 'Buyer', 'Items', 'Total', 'Method', 'Status', '']}>
          {orders.map((o) => {
            const step = o.fulfillment === 'PICKUP' ? NEXT_PICKUP_STEP[o.status] : undefined
            return (
              <tr key={o.id}>
                <td className={`${td} font-semibold`}>#{o.number}</td>
                <td className={td}>{o.buyer?.name ?? '—'}</td>
                <td className={`${td} text-espresso-500`}>
                  {o.items.map((i) => `${i.qty}× ${i.name}`).join(' · ')}
                </td>
                <td className={td}>{money(o.total)}</td>
                <td className={td}>
                  <StatusPill tone="muted">{o.fulfillment === 'PICKUP' ? 'Pickup' : 'Ship'}</StatusPill>
                </td>
                <td className={td}>
                  <StatusPill tone={ORDER_PILLS[o.status].tone}>{ORDER_PILLS[o.status].label}</StatusPill>
                </td>
                <td className={`${td} text-right whitespace-nowrap`}>
                  {step && (
                    <button
                      onClick={() => run(step.run(o.id))}
                      className="mr-3 text-xs font-medium text-crema-500 hover:text-espresso-900"
                    >
                      {step.label}
                    </button>
                  )}
                  {/* Auto-accepted like Whatnot: sellers cancel but never accept or decline. */}
                  {CANCELABLE.includes(o.status) && (
                    <button
                      onClick={() => run(cancelOrder(o.id))}
                      className="text-xs font-medium text-danger-600 hover:text-danger-700"
                    >
                      Cancel
                    </button>
                  )}
                </td>
              </tr>
            )
          })}
          {orders.length === 0 && <EmptyRow colSpan={7} message="No orders yet. They appear here the moment a buyer checks out." />}
        </Table>
      )}
    </section>
  )
}

// MARK: Shipments

function ShipmentsPane({ shopId }: { shopId: string }) {
  const [shipments, setShipments] = useState<Shipment[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<ShipmentStatus | ''>('')

  useEffect(() => {
    fetchMyShipments(shopId).then(setShipments).catch((e: Error) => setError(e.message))
  }, [shopId])

  const patch = (s: Shipment) => setShipments((prev) => prev!.map((x) => (x.id === s.id ? { ...x, ...s } : x)))
  const save = (id: string, p: Parameters<typeof updateShipment>[1]) =>
    updateShipment(id, p).then(patch).catch((e: Error) => setError(e.message))

  const visible = shipments?.filter((s) => !filter || s.status === filter)
  const toShip = shipments?.filter((s) => s.status === 'LABEL_READY').length ?? 0
  const cellInput =
    'w-full min-w-24 rounded-lg border border-transparent bg-transparent px-2 py-1 text-sm outline-none placeholder:text-espresso-500/50 hover:border-cream-200 focus:border-crema-400 focus:bg-cream-100'

  return (
    <section>
      <PaneHeader title="Shipments" subtitle={shipments ? `${shipments.length} total · ${toShip} to ship` : '…'} />
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {shipments && (
        <>
          <div className="mb-4 flex flex-wrap gap-1.5">
            {([['', `All · ${shipments.length}`], ...Object.entries(SHIPMENT_LABELS)] as [ShipmentStatus | '', string][]).map(
              ([key, label]) => (
                <button
                  key={key || 'all'}
                  onClick={() => setFilter(key)}
                  className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                    filter === key
                      ? 'bg-espresso-700 text-cream-50'
                      : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
                  }`}
                >
                  {label}
                </button>
              ),
            )}
          </div>
          <Table headers={['Order', 'Items', 'Ship by', 'Carrier', 'Tracking', 'Status', '']}>
            {visible!.map((s) => (
              <tr key={s.id}>
                <td className={td}>
                  <div className="font-semibold">#{s.order?.number}</div>
                  <div className="text-xs text-espresso-500">{s.order?.buyer?.name ?? '—'}</div>
                </td>
                <td className={`${td} text-espresso-500`}>
                  {s.order?.items.map((i) => `${i.qty}× ${i.name}`).join(' · ')}
                </td>
                <td className={td}>{s.shipBy ?? '—'}</td>
                {/* Carrier and tracking save on blur; no separate edit mode. */}
                <td className={td}>
                  <input
                    key={`${s.id}-carrier-${s.carrier ?? ''}`}
                    defaultValue={s.carrier ?? ''}
                    placeholder="USPS Ground"
                    className={cellInput}
                    onBlur={(e) => {
                      const v = e.target.value.trim()
                      if (v !== (s.carrier ?? '')) save(s.id, { carrier: v })
                    }}
                  />
                </td>
                <td className={td}>
                  <input
                    key={`${s.id}-tracking-${s.tracking ?? ''}`}
                    defaultValue={s.tracking ?? ''}
                    placeholder="9400 …"
                    className={cellInput}
                    onBlur={(e) => {
                      const v = e.target.value.trim()
                      if (v !== (s.tracking ?? '')) save(s.id, { tracking: v })
                    }}
                  />
                </td>
                <td className={td}>
                  <StatusPill tone={shipmentTone(s.status)}>{SHIPMENT_LABELS[s.status]}</StatusPill>
                </td>
                <td className={`${td} text-right whitespace-nowrap`}>
                  {NEXT_SHIPMENT_STEP[s.status] && (
                    <button
                      onClick={() => save(s.id, { status: NEXT_SHIPMENT_STEP[s.status]!.to })}
                      className="text-xs font-medium text-crema-500 hover:text-espresso-900"
                    >
                      {NEXT_SHIPMENT_STEP[s.status]!.label}
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {visible!.length === 0 && (
              <EmptyRow colSpan={7} message={filter ? 'Nothing in this state.' : 'No shipments yet. Every new order creates one automatically.'} />
            )}
          </Table>
        </>
      )}
    </section>
  )
}

// MARK: Shared pane bits

function PaneHeader({ title, subtitle, children }: { title: string; subtitle: string; children?: React.ReactNode }) {
  return (
    <div className="mb-5 flex items-center justify-between gap-3">
      <div>
        <h2 className="text-xl font-bold tracking-tight">{title}</h2>
        <p className="mt-0.5 text-sm text-espresso-500">{subtitle}</p>
      </div>
      {children}
    </div>
  )
}

function ErrorNote({ message, onDismiss }: { message: string; onDismiss: () => void }) {
  return (
    <div className="mb-4 flex items-center justify-between rounded-xl border border-danger-200 bg-danger-100 px-4 py-3 text-sm text-danger-700">
      {message}
      <button onClick={onDismiss} className="ml-3 font-semibold">
        ✕
      </button>
    </div>
  )
}

function EmptyRow({ colSpan, message }: { colSpan: number; message: string }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-10 text-center text-sm text-espresso-500">
        {message}
      </td>
    </tr>
  )
}

// MARK: Hub shell

const NAV: { key: Tab; label: string; icon: React.ReactNode }[] = [
  {
    key: 'overview',
    label: 'Overview',
    icon: <path d="M3 10.5 12 3l9 7.5V21h-6v-6h-6v6H3z" />,
  },
  {
    key: 'products',
    label: 'Listings',
    icon: <path d="M21 8v13H3V8M1 3h22v5H1zM10 12h4" />,
  },
  {
    key: 'orders',
    label: 'Orders',
    icon: <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4ZM3 6h18M16 10a4 4 0 0 1-8 0" />,
  },
  {
    key: 'shipments',
    label: 'Shipments',
    icon: (
      <path d="M1 5h14v11H1zM15 9h4l4 4v3h-8V9ZM7.5 18a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM20 18a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z" />
    ),
  },
]

// Renders below the persistent app header (no overlay): the logo in the
// header is the way back to the explorer.
export function SellerHub({
  shops,
  user,
}: {
  shops: { id: string; name: string; city: string }[]
  user: User
}) {
  const [shopId, setShopId] = useState(shops[0].id)
  const [tab, setTab] = useState<Tab>('overview')
  // Listing editor page within the Products tab: 'new' or the product being edited.
  const [listing, setListing] = useState<'new' | Product | null>(null)
  const [detail, setDetail] = useState<CoffeeShop | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [refresh, setRefresh] = useState(0)

  useEffect(() => {
    setDetail(null)
    setLoadError(null)
    fetchSellerShop(shopId)
      .then(setDetail)
      .catch((e: Error) => setLoadError(e.message))
  }, [shopId, refresh])

  const selectShop = (id: string) => {
    setShopId(id)
    setTab('overview')
    setListing(null)
  }

  const openTab = (key: Tab) => {
    setTab(key)
    setListing(null)
  }

  // Server-owned flag: completeSellerOnboarding already ran inside the
  // walkthrough, so a refetch is enough to flip it everywhere.
  if (!detail?.sellerOnboarded) {
    if (detail) return <SellerOnboarding shop={detail} onFinished={() => setRefresh((n) => n + 1)} />
    // Same full-page layer the walkthrough uses, so the header never
    // flashes through while the shop loads.
    return (
      <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-3 bg-cream-50 text-sm text-espresso-500">
        {loadError ? (
          <>
            <p className="text-danger-700">{loadError}</p>
            <button
              onClick={() => setRefresh((n) => n + 1)}
              className="rounded-xl border border-cream-200 bg-white px-4 py-2 font-medium hover:border-crema-400"
            >
              Retry
            </button>
          </>
        ) : (
          'Loading your shop…'
        )}
      </div>
    )
  }

  return (
    <div className="flex min-h-[calc(100vh-73px)]">
      <aside className={`sticky ${BELOW_HEADER} flex w-60 shrink-0 flex-col border-r border-cream-200 bg-white/60 p-4`}>
        <p className="mb-3 px-1 text-[11px] font-semibold tracking-wider text-espresso-500 uppercase">Seller Hub</p>

        {shops.length > 1 ? (
          <select
            value={shopId}
            onChange={(e) => selectShop(e.target.value)}
            className="mb-4 rounded-xl border border-cream-200 bg-cream-100 px-3 py-2.5 text-sm font-semibold outline-none"
          >
            {shops.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        ) : (
          <div className="mb-4 rounded-xl border border-cream-200 bg-cream-100 px-3 py-2.5">
            <div className="text-sm font-semibold">{shops[0].name}</div>
            <div className="text-[11px] text-ok-700">✓ Verified owner</div>
          </div>
        )}

        <nav className="flex flex-col gap-0.5">
          {NAV.map(({ key, label, icon }) => (
            <button
              key={key}
              onClick={() => openTab(key)}
              className={`flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-left text-sm transition ${
                tab === key
                  ? 'bg-espresso-700 font-semibold text-cream-50'
                  : 'text-espresso-500 hover:bg-cream-100 hover:text-espresso-900'
              }`}
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4 shrink-0">
                {icon}
              </svg>
              {label}
            </button>
          ))}
        </nav>

        <div className="mt-auto flex items-center gap-2.5 rounded-xl bg-cream-100 px-3 py-2.5">
          {user.picture ? (
            <img src={user.picture} alt="" className="size-8 rounded-full" referrerPolicy="no-referrer" />
          ) : (
            <span className="flex size-8 items-center justify-center rounded-full bg-espresso-700 text-xs font-semibold text-cream-50">
              {user.name[0]}
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-xs font-semibold">{user.name}</p>
            <p className="text-[10px] text-espresso-500">Owner</p>
          </div>
        </div>
      </aside>

      <main className="flex-1 px-8 py-7">
        {tab === 'overview' && (
          <OverviewPane
            key={shopId}
            shop={detail}
            user={user}
            onShopChanged={setDetail}
          />
        )}
        {tab === 'products' &&
          (listing ? (
            <ListingEditor
              key={listing === 'new' ? 'new' : listing.id}
              shopId={shopId}
              shopName={detail?.name ?? shops.find((s) => s.id === shopId)?.name ?? 'your shop'}
              product={listing === 'new' ? null : listing}
              onDone={() => setListing(null)}
              onCancel={() => setListing(null)}
            />
          ) : (
            <ProductsPane key={shopId} shopId={shopId} onNew={() => setListing('new')} onEdit={setListing} />
          ))}
        {tab === 'orders' && <OrdersPane key={shopId} shopId={shopId} />}
        {tab === 'shipments' && <ShipmentsPane key={shopId} shopId={shopId} />}
      </main>
    </div>
  )
}

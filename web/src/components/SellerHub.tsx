import { useEffect, useState } from 'react'
import { Link, Navigate, useNavigate, useParams } from 'react-router'
import {
  cancelOrder,
  fetchHubStats,
  fetchMyOrders,
  fetchMyProducts,
  fetchMySeller,
  fetchMyShipments,
  fetchProduct,
  fetchSellerShop,
  markPickedUp,
  markReadyForPickup,
  SELLER_PAGE_SIZE,
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
  type Seller,
  type Shipment,
  type ShipmentStatus,
  type User,
} from '../api'
import { AllShopsPane } from './AllShopsPane'
import { CopyListingsModal } from './CopyListingsModal'
import {
  cardCls,
  EmptyRow,
  ErrorNote,
  inputCls,
  money,
  ORDER_PILLS,
  PaneHeader,
  primaryBtn,
  secondaryBtn,
  ShopAvatar,
  StatusPill,
  Table,
  td,
  type Tone,
} from './hubBits'
import { ListingEditor } from './ListingEditor'
import { SellerApplicationModal } from './SellerApplication'
import { SellerOnboarding } from './SellerOnboarding'
import { hubPath, parseHubPath, rememberHubShop, type HubTab as Tab } from '../routes'
import { ALL_SHOPS, ShopSwitcher, type HubView } from './ShopSwitcher'

// The app header (73px) stays visible above the hub; the sidebar pins below it.
const BELOW_HEADER = 'top-[73px] h-[calc(100vh-73px)]'

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

// Shipped orders advance through their shipment, so only pickup has steps here.
const NEXT_PICKUP_STEP: Partial<Record<OrderStatus, { run: (id: string) => Promise<Order>; label: string }>> = {
  PLACED: { run: markReadyForPickup, label: 'Mark ready' },
  READY_FOR_PICKUP: { run: markPickedUp, label: 'Mark picked up' },
}

const CANCELABLE: OrderStatus[] = ['PLACED', 'READY_FOR_PICKUP']

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

function shipmentTone(status: ShipmentStatus): Tone {
  return status === 'LABEL_READY' ? 'accent' : status === 'DELIVERED' ? 'ok' : 'warn'
}

// Order and shipment rows in the All-shops view name the shop they belong to.
function ShopCell({ name }: { name: string }) {
  return (
    <td className={td}>
      <span className="flex items-center gap-2">
        <ShopAvatar name={name} size="sm" />
        <span className="truncate">{name}</span>
      </span>
    </td>
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
    fetchHubStats(shop.id)
      .then(({ workload, counts }) =>
        setStats({
          listings: counts.inStock + counts.lowStock,
          toFulfill: workload?.toFulfill ?? 0,
          toShip: workload?.toShip ?? 0,
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
      <PaneHeader title={shop.name} subtitle={`${shop.address}, ${shop.city}`}>
        <Link to={`/shops/${shop.id}`} className={secondaryBtn}>
          View shop page
        </Link>
      </PaneHeader>
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
  onCopy,
}: {
  shopId: string
  onNew: () => void
  onEdit: (product: Product) => void
  // Undefined when the seller owns no other shop to copy into.
  onCopy?: () => void
}) {
  const [filter, setFilter] = useState<ListingStatus | ''>('')
  const [offset, setOffset] = useState(0)
  const [products, setProducts] = useState<Product[] | null>(null)
  const [total, setTotal] = useState(0)
  const [counts, setCounts] = useState<ProductCounts | null>(null)
  const [reload, setReload] = useState(0)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchMyProducts(shopId, filter || undefined, offset)
      .then((d) => {
        // The last row on a page left the filter; step back rather than show an empty page.
        if (d.myProducts.products.length === 0 && offset > 0) return setOffset(Math.max(0, offset - SELLER_PAGE_SIZE))
        setProducts(d.myProducts.products)
        setTotal(d.myProducts.total)
        setCounts(d.myProductCounts)
      })
      .catch((e: Error) => setError(e.message))
  }, [shopId, filter, offset, reload])

  const pickFilter = (f: ListingStatus | '') => {
    setFilter(f)
    setOffset(0)
  }

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
        {onCopy && (counts?.total ?? 0) > 0 && (
          <button onClick={onCopy} className={secondaryBtn}>
            Copy listings
          </button>
        )}
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
              onClick={() => pickFilter(key)}
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
        <Table headers={['Listing', 'Price', 'Quantity', 'Status', '']}>
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
                    <div className="text-xs text-espresso-500">{p.subtitle ?? p.category.label}</div>
                  </div>
                </div>
              </td>
              <td className={td}>{money(p.price)}</td>
              <td className={td}>
                <div className="flex items-center gap-1.5">
                  <StockButton label="−" onClick={() => act(() => updateProduct(p.id, { quantity: Math.max(0, p.quantity - 1) }))} />
                  <span className="w-8 text-center font-medium tabular-nums">{p.quantity}</span>
                  <StockButton label="+" onClick={() => act(() => updateProduct(p.id, { quantity: p.quantity + 1 }))} />
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
      <Pager offset={offset} total={total} onChange={setOffset} />
    </section>
  )
}

// Server-side offset paging for the hub tables; hidden when everything fits on one page.
function Pager({ offset, total, onChange }: { offset: number; total: number; onChange: (offset: number) => void }) {
  if (total <= SELLER_PAGE_SIZE) return null
  const end = Math.min(offset + SELLER_PAGE_SIZE, total)
  const btn =
    'rounded-lg border border-cream-200 bg-white px-3 py-1.5 text-xs font-medium text-espresso-500 transition hover:border-crema-400 disabled:opacity-40 disabled:hover:border-cream-200'
  return (
    <div className="mt-3 flex items-center justify-end gap-2 text-xs text-espresso-500">
      <span className="mr-1 tabular-nums">
        {offset + 1}–{end} of {total}
      </span>
      <button className={btn} disabled={offset === 0} onClick={() => onChange(Math.max(0, offset - SELLER_PAGE_SIZE))}>
        Previous
      </button>
      <button className={btn} disabled={end >= total} onClick={() => onChange(offset + SELLER_PAGE_SIZE)}>
        Next
      </button>
    </div>
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

// shopId null = every owned shop, with a Shop column.
function OrdersPane({ shopId }: { shopId: string | null }) {
  const [offset, setOffset] = useState(0)
  const [orders, setOrders] = useState<Order[] | null>(null)
  const [total, setTotal] = useState(0)
  const [toFulfill, setToFulfill] = useState(0)
  const [reload, setReload] = useState(0)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchMyOrders(shopId, offset)
      .then((d) => {
        setOrders(d.orders)
        setTotal(d.total)
        setToFulfill(d.workload?.toFulfill ?? 0)
      })
      .catch((e: Error) => setError(e.message))
  }, [shopId, offset, reload])

  // Refetch so the to-fulfill count follows the status change.
  const run = (fn: Promise<Order>) =>
    fn.then(() => setReload((n) => n + 1)).catch((e: Error) => setError(e.message))

  const headers = ['Order', ...(shopId ? [] : ['Shop']), 'Buyer', 'Items', 'Total', 'Method', 'Status', '']

  return (
    <section>
      <PaneHeader
        title="Orders"
        subtitle={orders ? `${shopId ? '' : 'All shops · '}${total} total · ${toFulfill} to fulfill` : '…'}
      />
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {orders && (
        <Table headers={headers}>
          {orders.map((o) => {
            const step = o.fulfillment === 'PICKUP' ? NEXT_PICKUP_STEP[o.status] : undefined
            return (
              <tr key={o.id}>
                <td className={`${td} font-semibold`}>#{o.number}</td>
                {!shopId && <ShopCell name={o.shop.name} />}
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
          {orders.length === 0 && <EmptyRow colSpan={headers.length} message="No orders yet. They appear here the moment a buyer checks out." />}
        </Table>
      )}
      <Pager offset={offset} total={total} onChange={setOffset} />
    </section>
  )
}

// MARK: Shipments

function ShipmentsPane({ shopId }: { shopId: string | null }) {
  const [shipments, setShipments] = useState<Shipment[] | null>(null)
  const [total, setTotal] = useState(0)
  const [toShip, setToShip] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<ShipmentStatus | ''>('')
  const [offset, setOffset] = useState(0)
  const [reload, setReload] = useState(0)

  useEffect(() => {
    fetchMyShipments(shopId, filter || undefined, offset)
      .then((d) => {
        if (d.shipments.length === 0 && offset > 0) return setOffset(Math.max(0, offset - SELLER_PAGE_SIZE))
        setShipments(d.shipments)
        setTotal(d.total)
        setToShip(d.workload?.toShip ?? 0)
      })
      .catch((e: Error) => setError(e.message))
  }, [shopId, filter, offset, reload])

  const pickFilter = (f: ShipmentStatus | '') => {
    setFilter(f)
    setOffset(0)
  }
  const patch = (s: Shipment) => setShipments((prev) => prev!.map((x) => (x.id === s.id ? { ...x, ...s } : x)))
  // A status step can move the row out of the filter and changes the to-ship count, so refetch.
  const save = (id: string, p: Parameters<typeof updateShipment>[1]) =>
    updateShipment(id, p)
      .then((s) => (p.status ? setReload((n) => n + 1) : patch(s)))
      .catch((e: Error) => setError(e.message))

  const visible = shipments
  const cellInput =
    'w-full min-w-24 rounded-lg border border-transparent bg-transparent px-2 py-1 text-sm outline-none placeholder:text-espresso-500/50 hover:border-cream-200 focus:border-crema-400 focus:bg-cream-100'
  const headers = ['Order', ...(shopId ? [] : ['Shop']), 'Items', 'Ship by', 'Carrier', 'Tracking', 'Status', '']

  return (
    <section>
      <PaneHeader title="Shipments" subtitle={shipments ? `${shopId ? '' : 'All shops · '}${toShip} to ship` : '…'} />
      {error && <ErrorNote message={error} onDismiss={() => setError(null)} />}
      {shipments && (
        <>
          <div className="mb-4 flex flex-wrap gap-1.5">
            {([['', 'All'], ...Object.entries(SHIPMENT_LABELS)] as [ShipmentStatus | '', string][]).map(
              ([key, label]) => (
                <button
                  key={key || 'all'}
                  onClick={() => pickFilter(key)}
                  className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                    filter === key
                      ? 'bg-espresso-700 text-cream-50'
                      : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
                  }`}
                >
                  {filter === key ? `${label} · ${total}` : label}
                </button>
              ),
            )}
          </div>
          <Table headers={headers}>
            {visible!.map((s) => (
              <tr key={s.id}>
                <td className={td}>
                  <div className="font-semibold">#{s.order?.number}</div>
                  <div className="text-xs text-espresso-500">{s.order?.buyer?.name ?? '—'}</div>
                </td>
                {!shopId && <ShopCell name={s.order?.shop.name ?? '—'} />}
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
              <EmptyRow colSpan={headers.length} message={filter ? 'Nothing in this state.' : 'No shipments yet. Every new order creates one automatically.'} />
            )}
          </Table>
          <Pager offset={offset} total={total} onChange={setOffset} />
        </>
      )}
    </section>
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
    key: 'listings',
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
// header is the way back to the explorer. Mounted at /dashboard/*; the shop,
// tab and open listing all live in the URL (see routes.ts).
export function SellerHub({
  shops,
  user,
}: {
  shops: { id: string; name: string; city: string }[]
  user: User
}) {
  const navigate = useNavigate()
  const { shopId, tab, listing } = parseHubPath(useParams()['*'] ?? '')
  const view: HubView = shopId ?? ALL_SHOPS
  const knownShop = !shopId || shops.some((s) => s.id === shopId)
  // The product being edited. ProductsPane hands over the row it has so the
  // editor opens at once; a deep link fetches it instead.
  const [editing, setEditing] = useState<Product | null>(null)
  const [detail, setDetail] = useState<CoffeeShop | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [refresh, setRefresh] = useState(0)
  // Switcher badges and the All-shops overview; the shops prop is the fallback until it loads.
  const [seller, setSeller] = useState<Seller | null>(null)
  const [addingShop, setAddingShop] = useState(false)
  const [copyFrom, setCopyFrom] = useState<string | null>(null)
  const [flash, setFlash] = useState<string | null>(null)

  useEffect(() => {
    setDetail(null)
    setLoadError(null)
    if (!shopId) return
    fetchSellerShop(shopId)
      .then(setDetail)
      .catch((e: Error) => setLoadError(e.message))
  }, [shopId, refresh])

  useEffect(() => {
    if (shops.length > 1 && knownShop) rememberHubShop(shopId)
  }, [shopId, shops.length, knownShop])

  useEffect(() => {
    if (!listing || listing === 'new' || editing?.id === listing) return
    fetchProduct(listing)
      .then(setEditing)
      .catch((e: Error) => setLoadError(e.message))
  }, [listing, editing?.id])

  // Badges go stale as orders are handled; refetch whenever the seller moves around.
  useEffect(() => {
    fetchMySeller()
      .then((s) => s && setSeller(s))
      .catch(() => {})
  }, [view, tab, refresh])

  const sellerView: Seller = seller ?? {
    shops: shops.map((s) => ({ ...s, address: '', sellerOnboarded: true, workload: null })),
    workload: { toFulfill: 0, toShip: 0, lowStock: 0 },
    pendingClaims: [],
  }
  const otherShops = sellerView.shops.filter((s) => s.id !== shopId)

  const selectView = (next: HubView, nextTab: Tab = 'overview') => navigate(hubPath(next === ALL_SHOPS ? null : next, nextTab))
  const openTab = (key: Tab) => navigate(hubPath(shopId, key))
  const openListing = (product: Product | 'new') => {
    setEditing(product === 'new' ? null : product)
    navigate(hubPath(shopId, 'listings', product === 'new' ? 'new' : product.id))
  }
  const closeListing = () => navigate(hubPath(shopId, 'listings'))

  const say = (message: string) => {
    setFlash(message)
    setTimeout(() => setFlash(null), 3000)
  }

  const modals = (
    <>
      {addingShop && <SellerApplicationModal isSeller onClose={() => setAddingShop(false)} />}
      {copyFrom && sellerView.shops.length > 1 && (
        <CopyListingsModal
          shops={sellerView.shops}
          initialFromId={copyFrom}
          onClose={() => setCopyFrom(null)}
          onCopied={(n, to) => {
            setCopyFrom(null)
            setRefresh((k) => k + 1)
            say(`Copied ${n} ${n === 1 ? 'listing' : 'listings'} to ${to.name}. They are hidden with quantity 0 until you list them.`)
          }}
        />
      )}
    </>
  )

  // Unknown shop id, or a tab that needs one shop, falls back to all shops.
  if (!knownShop || (!shopId && tab === 'listings')) return <Navigate to={hubPath(null)} replace />

  // Server-owned flag: completeSellerOnboarding already ran inside the
  // walkthrough, so a refetch is enough to flip it everywhere.
  if (shopId && !detail?.sellerOnboarded) {
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

  // Listings need one shop; the All-shops view drops that tab.
  const nav = shopId ? NAV : NAV.filter((n) => n.key !== 'listings')

  return (
    <div className="flex min-h-[calc(100vh-73px)]">
      <aside className={`sticky ${BELOW_HEADER} flex w-72 shrink-0 flex-col border-r border-cream-200 bg-white/60 p-4`}>
        <p className="mb-3 px-1 text-[11px] font-semibold tracking-wider text-espresso-500 uppercase">Seller Hub</p>

        <ShopSwitcher seller={sellerView} view={view} onSelect={(v) => selectView(v)} onAddShop={() => setAddingShop(true)} />

        <nav className="flex flex-col gap-0.5">
          {nav.map(({ key, label, icon }) => (
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

      <main className="min-w-0 flex-1 px-8 py-7">
        {flash && <p className="mb-5 rounded-xl bg-ok-100 px-4 py-2.5 text-sm font-medium text-ok-700">{flash}</p>}
        {tab === 'overview' &&
          (shopId ? (
            <OverviewPane key={shopId} shop={detail} user={user} onShopChanged={setDetail} />
          ) : (
            <AllShopsPane
              seller={sellerView}
              user={user}
              onOpenShop={(id) => selectView(id)}
              onOpenOrders={() => openTab('orders')}
              onAddShop={() => setAddingShop(true)}
              onCopyListings={() => setCopyFrom(sellerView.shops.find((s) => s.sellerOnboarded)?.id ?? sellerView.shops[0].id)}
            />
          ))}
        {tab === 'listings' &&
          shopId &&
          (listing === 'new' || (listing && editing?.id === listing) ? (
            <ListingEditor
              key={listing}
              shopId={shopId}
              shopName={detail?.name ?? shops.find((s) => s.id === shopId)?.name ?? 'your shop'}
              product={listing === 'new' ? null : editing}
              onDone={closeListing}
              onCancel={closeListing}
            />
          ) : listing ? (
            loadError ? <ErrorNote message={loadError} onDismiss={closeListing} /> : <p className="text-sm text-espresso-500">Loading listing…</p>
          ) : (
            <ProductsPane
              key={`${shopId}-${refresh}`}
              shopId={shopId}
              onNew={() => openListing('new')}
              onEdit={openListing}
              onCopy={otherShops.length > 0 ? () => setCopyFrom(shopId) : undefined}
            />
          ))}
        {tab === 'orders' && <OrdersPane key={view} shopId={shopId} />}
        {tab === 'shipments' && <ShipmentsPane key={view} shopId={shopId} />}
      </main>
      {modals}
    </div>
  )
}

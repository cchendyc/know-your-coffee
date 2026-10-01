import { useEffect, useRef, useState, type ReactNode } from 'react'
import {
  deleteShop,
  fetchShopLite,
  fetchShopPreview,
  isAdmin,
  setShopStatus,
  type CoffeeShop,
  type ShopPreview,
  type User,
} from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, coffeeSummary, machineDisplay } from '../labels'
import { SellerApplicationModal } from './SellerApplication'
import { ShopExpanded } from './ShopExpanded'

const PREVIEW_TILES = 3

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2.5">
      <dt className="text-xs font-medium tracking-wide text-espresso-500 uppercase">{label}</dt>
      <dd className="text-right text-sm font-medium">{value}</dd>
    </div>
  )
}

function Pill({ tone, children }: { tone: 'ok' | 'accent' | 'muted'; children: ReactNode }) {
  const cls = {
    ok: 'bg-ok-100 text-ok-700',
    accent: 'bg-crema-400/20 text-crema-500',
    muted: 'bg-cream-100 text-espresso-500',
  }[tone]
  return <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold ${cls}`}>{children}</span>
}

function SectionLabel({ children }: { children: string }) {
  return <h3 className="text-[10px] font-semibold tracking-wider text-espresso-500 uppercase">{children}</h3>
}

// One icon-over-label action, Google Maps place-card style.
function ActionButton({
  label,
  title,
  active,
  activeCls,
  disabled,
  onClick,
  children,
}: {
  label: string
  title?: string
  active?: boolean
  // Circle style when active, e.g. filled bookmark amber.
  activeCls?: string
  disabled?: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      title={title}
      onClick={onClick}
      className="flex flex-1 flex-col items-center gap-1 rounded-xl py-1.5 transition hover:bg-cream-100 disabled:cursor-not-allowed disabled:opacity-50"
    >
      <span
        className={`flex size-10 items-center justify-center rounded-full border transition ${
          active ? (activeCls ?? '') : 'border-cream-200 bg-white text-espresso-500'
        }`}
      >
        {children}
      </span>
      <span className={`text-[11px] font-medium ${active ? 'text-espresso-900' : 'text-espresso-500'}`}>{label}</span>
    </button>
  )
}

function HeroButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="flex size-9 items-center justify-center rounded-full bg-white text-espresso-700 shadow-md transition hover:bg-cream-100"
    >
      {children}
    </button>
  )
}

function timeAgo(iso: string) {
  const mins = Math.max(1, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
  if (mins < 60) return `${mins} min ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `${hours} hr ago`
  const days = Math.round(hours / 24)
  if (days < 7) return `${days} day${days === 1 ? '' : 's'} ago`
  const weeks = Math.round(days / 7)
  if (weeks < 9) return `${weeks} week${weeks === 1 ? '' : 's'} ago`
  return `${Math.round(days / 30)} months ago`
}

function hostname(url: string) {
  try {
    return new URL(url).hostname.replace(/^www\./, '')
  } catch {
    return url
  }
}

function deliveryCopy(d: ShopPreview['deliverySettings'], city: string) {
  if (d.shipping && d.pickup) return `Ships or pick up in ${city}`
  if (d.shipping) return 'Ships to you'
  if (d.pickup) return `Pick up in ${city}`
  return ''
}

// Buyer-facing preview opened from a Home card or map pin. Paints from the
// list's copy with no fetch, then adds ownership, counts, and listings from
// one light query. Photos, reports, and chain locations live in
// ShopExpanded, which fetches them itself and hands the fresh shop back
// through onHydrated. Figma: "Web / Home — Shop preview drawer".
export function ShopDrawer({
  shopId,
  initialShop,
  user,
  isSeller = false,
  onShopChanged,
  onShopDeleted,
  onOpenShop,
  onOpenSellerHub,
  onClose,
}: {
  shopId: string
  // The list's copy of this shop, so the drawer paints instantly.
  initialShop?: CoffeeShop
  user: User | null
  // Viewer already owns a shop; claim copy reads "add another" instead of "become a seller".
  isSeller?: boolean
  onShopChanged: (shop: CoffeeShop) => void
  onShopDeleted: (id: string) => void
  onOpenShop: (id: string) => void
  // Owners get a "Manage in Seller Hub" CTA in place of "Shop online".
  onOpenSellerHub?: () => void
  onClose: () => void
}) {
  const [shop, setShop] = useState<CoffeeShop | null>(initialShop ?? null)
  const [preview, setPreview] = useState<ShopPreview | null>(null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [expanded, setExpanded] = useState(false)
  // "Update" opens the full page with the form already showing.
  const [reportOnExpand, setReportOnExpand] = useState(false)
  const [claiming, setClaiming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [shared, setShared] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  // Set when navigating between chain locations from the detail page, so
  // the new shop opens straight to its detail page too.
  const stayExpanded = useRef(false)
  const shopOnlineRef = useRef<HTMLDivElement>(null)

  // Keep drawer state and the main list in sync after a save/been toggle.
  const onStatusChanged = (updated: CoffeeShop) => {
    setShop((prev) => (prev ? { ...prev, savedByMe: updated.savedByMe, beenByMe: updated.beenByMe } : prev))
    onShopChanged(updated)
  }

  const removeShop = async () => {
    if (!shop || busy) return
    setBusy(true)
    setDeleteError(null)
    try {
      await deleteShop(shop.id)
      onShopDeleted(shop.id)
    } catch (e) {
      setDeleteError((e as Error).message)
      setConfirmDelete(false)
    } finally {
      setBusy(false)
    }
  }

  const toggleStatus = async (field: 'saved' | 'been') => {
    if (!user || !shop || busy) return
    setBusy(true)
    try {
      const updated = await setShopStatus(shop.id, {
        [field]: field === 'saved' ? !shop.savedByMe : !shop.beenByMe,
      })
      onStatusChanged(updated)
    } finally {
      setBusy(false)
    }
  }

  // App keeps ?shop=<id> in the URL, so the current URL is the share link.
  const share = async () => {
    if (!shop) return
    const url = window.location.href
    try {
      if (navigator.share) {
        await navigator.share({ title: shop.name, text: `${shop.name} · ${shop.address}, ${shop.city}`, url })
        return
      }
      await navigator.clipboard.writeText(url)
      setShared(true)
      setTimeout(() => setShared(false), 1500)
    } catch {
      // User dismissed the share sheet or clipboard is blocked; nothing to show.
    }
  }

  useEffect(() => {
    setExpanded(stayExpanded.current)
    stayExpanded.current = false
    setReportOnExpand(false)
    setLoadFailed(false)
    setConfirmDelete(false)
    setDeleteError(null)
    setClaiming(false)
    setPreview(null)
    fetchShopPreview(shopId)
      .then(setPreview)
      .catch(() => setPreview(null))
    if (initialShop && initialShop.id === shopId) {
      setShop(initialShop)
      return
    }
    // Shop isn't in the loaded list (e.g. a chain location): one light fetch.
    setShop(null)
    fetchShopLite(shopId)
      .then((s) => (s ? setShop(s) : setLoadFailed(true)))
      .catch(() => setLoadFailed(true))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shopId])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const products = preview?.products.filter((p) => p.status !== 'HIDDEN') ?? []
  const sellsOnline = products.length > 0
  const ownsThis = !!preview?.ownedByMe
  const amenities = shop ? AMENITIES.filter((a) => shop[a.key] !== null) : []
  const beanLabel = shop && shop.beanSource !== 'UNKNOWN' ? BEAN_SOURCE_LABELS[shop.beanSource] : null

  return (
    <div className="fixed inset-0 z-[1000]">
      <div className="absolute inset-0 bg-espresso-900/40 backdrop-blur-[2px]" onClick={onClose} />
      <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col overflow-y-auto bg-cream-50 shadow-2xl">
        {!shop ? (
          <div className="flex items-center justify-between p-6">
            <p className="text-sm text-espresso-500">{loadFailed ? "Couldn't load this shop." : 'Loading…'}</p>
            <HeroButton label="Close" onClick={onClose}>
              <CloseIcon />
            </HeroButton>
          </div>
        ) : (
          <>
            <div className="relative h-[200px] shrink-0 bg-crema-400/20">
              {shop.photoUrl ? (
                <img src={shop.photoUrl} alt={shop.name} className="size-full object-cover" />
              ) : (
                <div className="flex size-full items-center justify-center text-crema-400/70">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" className="size-20">
                    <path d="M17 8h1a4 4 0 1 1 0 8h-1M3 8h14v9a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4ZM6 2v2M10 2v2M14 2v2" />
                  </svg>
                </div>
              )}
              <div className="absolute top-4 right-4 flex gap-2">
                <HeroButton label="Expand: all photos and reports" onClick={() => setExpanded(true)}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
                    <path d="M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5" />
                  </svg>
                </HeroButton>
                <HeroButton label="Close" onClick={onClose}>
                  <CloseIcon />
                </HeroButton>
              </div>
              {!!preview?.photoCount && (
                <button
                  type="button"
                  onClick={() => setExpanded(true)}
                  className="absolute bottom-4 left-4 flex items-center gap-1.5 rounded-full bg-espresso-900/85 px-2.5 py-1 text-[11px] font-semibold text-cream-50 transition hover:bg-espresso-900"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-3.5">
                    <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z" />
                    <circle cx="12" cy="13" r="3" />
                  </svg>
                  {preview.photoCount} photo{preview.photoCount === 1 ? '' : 's'}
                </button>
              )}
            </div>

            <div className="flex flex-col gap-3 border-b border-cream-200 px-6 py-4">
              {(preview?.ownerId || beanLabel) && (
                <div className="flex flex-wrap gap-1.5">
                  {ownsThis ? (
                    <Pill tone="accent">You own this shop</Pill>
                  ) : (
                    preview?.ownerId && (
                      <Pill tone="ok">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" className="size-2.5">
                          <path d="M20 6 9 17l-5-5" />
                        </svg>
                        Verified owner
                      </Pill>
                    )
                  )}
                  {beanLabel && <Pill tone="muted">{beanLabel}</Pill>}
                </div>
              )}
              <div>
                <h2 className="text-[22px] leading-tight font-bold tracking-tight">{shop.name}</h2>
                <p className="mt-1 flex items-center gap-1.5 text-[13px] text-espresso-500">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-3.5 shrink-0">
                    <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
                    <circle cx="12" cy="10" r="3" />
                  </svg>
                  {shop.address}, {shop.city}
                </p>
              </div>
              <div className="flex gap-4">
                <a
                  href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${shop.name} ${shop.address} ${shop.city}`)}`}
                  target="_blank"
                  rel="noreferrer"
                  className="text-xs font-medium text-crema-500 hover:underline"
                >
                  Open in Google Maps
                </a>
                {shop.website && (
                  <a href={shop.website} target="_blank" rel="noreferrer" className="text-xs font-medium text-crema-500 hover:underline">
                    {hostname(shop.website)} ↗
                  </a>
                )}
              </div>

              <div className="flex items-start gap-1">
                <ActionButton
                  label={shop.savedByMe ? 'Saved' : 'Save'}
                  title={user ? undefined : 'Sign in to use lists'}
                  active={shop.savedByMe}
                  activeCls="border-transparent bg-crema-500 text-white"
                  disabled={!user || busy}
                  onClick={() => toggleStatus('saved')}
                >
                  <svg viewBox="0 0 24 24" fill={shop.savedByMe ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" className="size-4">
                    <path d="M6 4h12v17l-6-4-6 4V4Z" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton
                  label="Been"
                  title={user ? undefined : 'Sign in to use lists'}
                  active={shop.beenByMe}
                  activeCls="border-transparent bg-green-600 text-white"
                  disabled={!user || busy}
                  onClick={() => toggleStatus('been')}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" className="size-4">
                    <path d="m5 12.5 4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton
                  label="Update"
                  title={user ? undefined : 'Sign in to report updates'}
                  active={!!user}
                  activeCls="border-transparent bg-espresso-700 text-cream-50"
                  disabled={!user}
                  onClick={() => {
                    setReportOnExpand(true)
                    setExpanded(true)
                  }}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-4">
                    <path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17v3ZM14.5 7.5l3 3" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton label={shared ? 'Copied' : 'Share'} onClick={() => void share()}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
                    <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13" />
                  </svg>
                </ActionButton>
              </div>

              {!user && (
                <p className="rounded-xl border border-dashed border-crema-400 bg-crema-400/10 px-4 py-2.5 text-center text-xs text-espresso-700">
                  Sign in (top right) to save, mark been, and report updates.
                </p>
              )}

              {ownsThis && onOpenSellerHub ? (
                <button
                  type="button"
                  onClick={onOpenSellerHub}
                  className="flex w-full items-center justify-center gap-2 rounded-xl bg-espresso-700 px-4 py-3 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
                >
                  <StoreIcon />
                  Manage in Seller Hub
                  <span className="text-xs font-normal text-cream-50/80">
                    {products.length} listing{products.length === 1 ? '' : 's'}
                  </span>
                </button>
              ) : (
                sellsOnline &&
                preview && (
                  <button
                    type="button"
                    onClick={() => shopOnlineRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
                    className="flex w-full items-center justify-center gap-2 rounded-xl bg-crema-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-espresso-700"
                  >
                    <BagIcon className="size-4" />
                    Shop online · {products.length} listing{products.length === 1 ? '' : 's'}
                    <span className="text-xs font-normal text-white/80">{deliveryCopy(preview.deliverySettings, shop.city)}</span>
                  </button>
                )
              )}
            </div>

            <div className="flex flex-col gap-4 px-6 py-4">
              {shop.vibe && <p className="text-[13px] leading-relaxed text-espresso-500 italic">“{shop.vibe}”</p>}

              <dl className="divide-y divide-cream-200 rounded-2xl border border-cream-200 bg-white px-4 pt-3">
                <SectionLabel>On the bar</SectionLabel>
                <InfoRow
                  label={shop.machines.length > 1 ? 'Machines' : 'Machine'}
                  value={
                    shop.machines.length > 0
                      ? shop.machines.map((m) => machineDisplay(m.brand, m.model)).join(' · ')
                      : machineDisplay(shop.machine, shop.machineModel)
                  }
                />
                <InfoRow label="Beans" value={BEAN_SOURCE_LABELS[shop.beanSource]} />
                {shop.roaster && <InfoRow label="Roaster" value={shop.roaster} />}
                {shop.coffees.map((c, i) => (
                  <InfoRow key={i} label={i === 0 ? 'On bar' : ''} value={coffeeSummary(c)} />
                ))}
                {shop.coffees.length === 0 && shop.beanOrigins.length > 0 && (
                  <InfoRow label="Bean origins" value={shop.beanOrigins.join(', ')} />
                )}
                {shop.grinders.length > 0 && <InfoRow label="Grinders" value={shop.grinders.join(', ')} />}
                <InfoRow label="Milk" value={shop.milkBrands.length ? shop.milkBrands.join(', ') : 'Unknown'} />
              </dl>

              {amenities.length > 0 && (
                <div className="flex flex-col gap-2">
                  <SectionLabel>Good to know</SectionLabel>
                  <div className="flex flex-wrap gap-1.5">
                    {amenities.map((a) => {
                      const yes = !!shop[a.key]
                      return (
                        <span
                          key={a.key}
                          className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-medium ${
                            yes ? 'bg-ok-100 text-ok-700' : 'bg-cream-100 text-espresso-500'
                          }`}
                        >
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" className="size-3">
                            {yes ? <path d="M20 6 9 17l-5-5" /> : <path d="M6 6l12 12M18 6L6 18" />}
                          </svg>
                          {yes ? a.label : a.no}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )}

              {shop.drinks.length > 0 && (
                <div className="rounded-2xl border border-cream-200 bg-white px-4 py-3">
                  <SectionLabel>Drinks</SectionLabel>
                  <ul className="mt-1 divide-y divide-cream-200">
                    {shop.drinks.map((d) => (
                      <li key={d.name} className="flex items-center justify-between py-1.5 text-sm">
                        <span>{d.name}</span>
                        {d.price != null && <span className="font-medium text-espresso-500">${d.price.toFixed(2)}</span>}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {sellsOnline && preview && (
                <div ref={shopOnlineRef} className="flex scroll-mt-4 flex-col gap-3">
                  <div>
                    <h3 className="text-sm font-bold">{ownsThis ? 'Your listings' : 'Shop online'}</h3>
                    <p className="mt-0.5 text-[11px] text-espresso-500">
                      {ownsThis
                        ? 'This is what buyers see.'
                        : `Sold by the verified owner. ${deliveryCopy(preview.deliverySettings, shop.city)}.`}
                    </p>
                  </div>
                  <div className="grid grid-cols-3 gap-3">
                    {products.slice(0, PREVIEW_TILES).map((p) => (
                      <div key={p.id} className="flex flex-col gap-1.5">
                        <div className="flex aspect-square items-center justify-center rounded-xl bg-crema-400/20 text-crema-400">
                          <BagIcon className="size-6" />
                        </div>
                        <p className="line-clamp-2 text-xs leading-snug font-semibold">{p.name}</p>
                        <p className="text-xs text-espresso-500">
                          ${p.price.toFixed(2)}
                          {p.status === 'LOW_STOCK' && <span className="ml-1 text-warn-700">· few left</span>}
                        </p>
                      </div>
                    ))}
                  </div>
                  {products.length > PREVIEW_TILES && (
                    <p className="text-[11px] text-espresso-500">and {products.length - PREVIEW_TILES} more</p>
                  )}
                </div>
              )}

              {preview && !preview.ownerId && user && (
                <div className="flex items-center gap-3 rounded-2xl border border-dashed border-crema-400 bg-white px-4 py-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-crema-400/20 text-crema-500">
                    <StoreIcon />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-[13px] font-semibold">{isSeller ? 'Own this location too?' : 'Own this shop?'}</p>
                    <p className="text-[11px] leading-snug text-espresso-500">
                      Claim it to sell beans online and keep this page accurate. Review takes 1–2 days.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setClaiming(true)}
                    className="shrink-0 rounded-xl bg-espresso-700 px-3 py-2 text-xs font-semibold text-cream-50 transition hover:bg-espresso-900"
                  >
                    Claim
                  </button>
                </div>
              )}

              <div className="rounded-2xl bg-cream-100 px-4 py-3">
                {preview && (
                  <p className="flex items-center gap-2 text-xs text-espresso-500">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-3.5 shrink-0">
                      <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
                      <circle cx="9" cy="7" r="4" />
                    </svg>
                    <span>
                      {preview.reportCount} report{preview.reportCount === 1 ? '' : 's'} · {preview.photoCount} photo
                      {preview.photoCount === 1 ? '' : 's'}
                      {preview.latestReport && (
                        <>
                          {' '}
                          · updated {timeAgo(preview.latestReport.createdAt)}
                          {preview.latestReport.reporter && ` by ${preview.latestReport.reporter.name}`}
                        </>
                      )}
                    </span>
                  </p>
                )}
                <button
                  onClick={() => setExpanded(true)}
                  className="mt-2 flex w-full items-center justify-center gap-1 py-1 text-[13px] font-semibold text-crema-500 transition hover:text-espresso-700"
                >
                  See photos, reports & full details
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-4">
                    <path d="M9 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </button>
              </div>

              {isAdmin(user) && (
                <div className="border-t border-cream-200 pt-4">
                  {deleteError && <p className="mb-2 text-xs text-red-700">{deleteError}</p>}
                  {confirmDelete ? (
                    <div className="rounded-2xl border border-red-200 bg-red-50 p-3">
                      <p className="text-sm text-espresso-900">
                        Delete {shop.name}? Use this for listings that aren’t coffee shops. This cannot be undone.
                      </p>
                      <div className="mt-3 flex gap-2">
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void removeShop()}
                          className="rounded-xl bg-red-700 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-red-800 disabled:opacity-50"
                        >
                          {busy ? 'Deleting…' : 'Delete shop'}
                        </button>
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => setConfirmDelete(false)}
                          className="rounded-xl border border-cream-200 px-3 py-1.5 text-xs font-medium text-espresso-500"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <button type="button" onClick={() => setConfirmDelete(true)} className="text-xs font-medium text-red-700 hover:underline">
                      Not a coffee shop? Delete
                    </button>
                  )}
                </div>
              )}
            </div>
          </>
        )}
      </aside>
      {claiming && shop && <SellerApplicationModal shop={shop} isSeller={isSeller} onClose={() => setClaiming(false)} />}
      {expanded && shop && (
        <ShopExpanded
          shop={shop}
          user={user}
          isSeller={isSeller}
          initialReporting={reportOnExpand}
          onChanged={onStatusChanged}
          onDeleted={onShopDeleted}
          onHydrated={setShop}
          onOpenShop={(id) => {
            stayExpanded.current = true
            onOpenShop(id)
          }}
          onClose={() => {
            setExpanded(false)
            setReportOnExpand(false)
          }}
        />
      )}
    </div>
  )
}

function CloseIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="size-4">
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  )
}

function StoreIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
      <path d="M3 9.5 5 3h14l2 6.5M3 9.5h18v2a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0v-2ZM5 13v8h14v-8M10 21v-5h4v5" />
    </svg>
  )
}

function BagIcon({ className }: { className: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4ZM3 6h18M16 10a4 4 0 0 1-8 0" />
    </svg>
  )
}

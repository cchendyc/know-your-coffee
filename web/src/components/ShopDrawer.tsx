import { useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { fetchShopLite, fetchShopPreview, setShopStatus, type CoffeeShop, type ShopPreview, type User } from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, machineDisplay } from '../labels'

function Pill({ tone, children }: { tone: 'ok' | 'accent' | 'muted'; children: ReactNode }) {
  const cls = {
    ok: 'bg-ok-100 text-ok-700',
    accent: 'bg-crema-400/20 text-crema-500',
    muted: 'bg-cream-100 text-espresso-500',
  }[tone]
  return <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold ${cls}`}>{children}</span>
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

// Map-pin preview: enough to tell shops apart without leaving the map.
// Everything deeper (reports, menu, photos, listings, claim) lives on
// /shops/:id, which this links to with the shop as router state so the
// page paints before its own query returns.
export function ShopDrawer({
  shopId,
  initialShop,
  user,
  onShopChanged,
  onOpenSellerHub,
  onClose,
}: {
  shopId: string
  // The list's copy of this shop, so the drawer paints instantly.
  initialShop?: CoffeeShop
  user: User | null
  onShopChanged: (shop: CoffeeShop) => void
  onOpenSellerHub?: () => void
  onClose: () => void
}) {
  const [shop, setShop] = useState<CoffeeShop | null>(initialShop ?? null)
  const [preview, setPreview] = useState<ShopPreview | null>(null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [shared, setShared] = useState(false)

  useEffect(() => {
    setLoadFailed(false)
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

  const toggleStatus = async (field: 'saved' | 'been') => {
    if (!user || !shop || busy) return
    setBusy(true)
    try {
      const updated = await setShopStatus(shop.id, { [field]: field === 'saved' ? !shop.savedByMe : !shop.beenByMe })
      setShop((prev) => (prev ? { ...prev, savedByMe: updated.savedByMe, beenByMe: updated.beenByMe } : prev))
      onShopChanged(updated)
    } finally {
      setBusy(false)
    }
  }

  const share = async () => {
    if (!shop) return
    const url = `${window.location.origin}${import.meta.env.BASE_URL.replace(/\/$/, '')}/shops/${shop.id}`
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

  const listings = preview?.products.filter((p) => p.status !== 'HIDDEN').length ?? 0
  const ownsThis = !!preview?.ownedByMe
  const amenities = shop ? AMENITIES.filter((a) => shop[a.key] !== null) : []
  const beanLabel = shop && shop.beanSource !== 'UNKNOWN' ? BEAN_SOURCE_LABELS[shop.beanSource] : null
  const machines = shop ? (shop.machines.length > 0 ? shop.machines : [{ brand: shop.machine, model: shop.machineModel }]).filter((m) => m.brand !== 'UNKNOWN') : []

  return (
    <div className="fixed inset-0 z-[1000]">
      <div className="absolute inset-0 bg-espresso-900/40 backdrop-blur-[2px]" onClick={onClose} />
      <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col overflow-y-auto bg-cream-50 shadow-2xl">
        {!shop ? (
          <div className="flex items-center justify-between p-6">
            <p className="text-sm text-espresso-500">{loadFailed ? "Couldn't load this shop." : 'Loading…'}</p>
            <CloseButton onClick={onClose} />
          </div>
        ) : (
          <>
            <Link to={`/shops/${shop.id}`} state={{ shop }} className="relative block h-[200px] shrink-0 bg-crema-400/20">
              {shop.photoUrl ? (
                <img src={shop.photoUrl} alt={shop.name} className="size-full object-cover" />
              ) : (
                <div className="flex size-full items-center justify-center text-crema-400/70">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" className="size-20">
                    <path d="M17 8h1a4 4 0 1 1 0 8h-1M3 8h14v9a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4ZM6 2v2M10 2v2M14 2v2" />
                  </svg>
                </div>
              )}
            </Link>
            <div className="absolute top-4 right-4">
              <CloseButton onClick={onClose} />
            </div>

            <div className="flex flex-col gap-3 px-6 py-4">
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
              <Link to={`/shops/${shop.id}`} state={{ shop }} className="group">
                <h2 className="text-[22px] leading-tight font-bold tracking-tight group-hover:text-crema-500">{shop.name}</h2>
                <p className="mt-1 text-[13px] text-espresso-500">
                  {shop.address}, {shop.city}
                </p>
              </Link>

              <dl className="divide-y divide-cream-200 rounded-2xl border border-cream-200 bg-white px-4 text-sm">
                <div className="flex items-start justify-between gap-4 py-2.5">
                  <dt className="text-xs font-medium tracking-wide text-espresso-500 uppercase">{machines.length > 1 ? 'Machines' : 'Machine'}</dt>
                  <dd className="text-right font-medium">{machines.length ? machines.map((m) => machineDisplay(m.brand, m.model)).join(' · ') : 'Not reported'}</dd>
                </div>
                <div className="flex items-start justify-between gap-4 py-2.5">
                  <dt className="text-xs font-medium tracking-wide text-espresso-500 uppercase">Beans</dt>
                  <dd className="text-right font-medium">
                    {shop.coffees.length > 0
                      ? shop.coffees
                          .map((c) => c.roaster || c.name)
                          .filter(Boolean)
                          .slice(0, 2)
                          .join(' · ') || BEAN_SOURCE_LABELS[shop.beanSource]
                      : shop.roaster || BEAN_SOURCE_LABELS[shop.beanSource]}
                  </dd>
                </div>
              </dl>

              {amenities.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {amenities.map((a) => {
                    const yes = !!shop[a.key]
                    return (
                      <span key={a.key} className={`rounded-full px-2.5 py-1 text-[11px] font-medium ${yes ? 'bg-ok-100 text-ok-700' : 'bg-cream-100 text-espresso-500'}`}>
                        {yes ? a.label : a.no}
                      </span>
                    )
                  })}
                </div>
              )}

              <div className="flex items-start gap-1">
                <ActionButton
                  label={shop.savedByMe ? 'Saved' : 'Save'}
                  title={user ? undefined : 'Sign in to use lists'}
                  active={shop.savedByMe}
                  activeCls="border-transparent bg-crema-500 text-white"
                  disabled={!user || busy}
                  onClick={() => void toggleStatus('saved')}
                >
                  <svg viewBox="0 0 24 24" fill={shop.savedByMe ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" className="size-4">
                    <path d="M6 4h12v17l-6-4-6 4V4Z" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton
                  label="Been"
                  title={user ? undefined : 'Sign in to use lists'}
                  active={shop.beenByMe}
                  activeCls="border-transparent bg-ok-700 text-white"
                  disabled={!user || busy}
                  onClick={() => void toggleStatus('been')}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" className="size-4">
                    <path d="m5 12.5 4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton label={shared ? 'Copied' : 'Share'} onClick={() => void share()}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
                    <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13" />
                  </svg>
                </ActionButton>
              </div>

              <Link
                to={`/shops/${shop.id}`}
                state={{ shop }}
                className="flex w-full flex-col items-center rounded-xl bg-espresso-700 px-4 py-3 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
              >
                <span className="flex items-center gap-1">
                  View shop
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-4">
                    <path d="M9 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
                {preview && (
                  <span className="text-[11px] font-normal text-cream-50/80">
                    {preview.reportCount} report{preview.reportCount === 1 ? '' : 's'} · {preview.photoCount} photo{preview.photoCount === 1 ? '' : 's'}
                    {listings > 0 && ` · ${listings} listing${listings === 1 ? '' : 's'}`}
                  </span>
                )}
              </Link>
              {ownsThis && onOpenSellerHub && (
                <button
                  type="button"
                  onClick={onOpenSellerHub}
                  className="w-full rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-semibold text-espresso-700 transition hover:border-crema-400"
                >
                  Manage in Seller Hub
                </button>
              )}
            </div>
          </>
        )}
      </aside>
    </div>
  )
}

function CloseButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Close"
      title="Close"
      className="flex size-9 items-center justify-center rounded-full bg-white text-espresso-700 shadow-md transition hover:bg-cream-100"
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className="size-4">
        <path d="M6 6l12 12M18 6L6 18" />
      </svg>
    </button>
  )
}

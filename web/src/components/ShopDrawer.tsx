import { useEffect, useRef, useState, type ReactNode } from 'react'
import { fetchShopLite, setShopStatus, type CoffeeShop, type User } from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, coffeeSummary, machineDisplay } from '../labels'
import { ShopExpanded } from './ShopExpanded'

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2.5">
      <dt className="text-xs font-medium tracking-wide text-espresso-500 uppercase">{label}</dt>
      <dd className="text-right text-sm font-medium">{value}</dd>
    </div>
  )
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
        className={`flex size-9 items-center justify-center rounded-full border transition ${
          active ? (activeCls ?? '') : 'border-cream-200 bg-white text-espresso-500'
        }`}
      >
        {children}
      </span>
      <span className={`text-[11px] font-medium ${active ? 'text-espresso-900' : 'text-espresso-500'}`}>{label}</span>
    </button>
  )
}

// Lean preview: paints from the list's copy with no fetch and no photos.
// Photos, reports, and chain locations live in ShopExpanded, which fetches
// them itself and hands the fresh shop back through onHydrated.
export function ShopDrawer({
  shopId,
  initialShop,
  user,
  onShopChanged,
  onOpenShop,
  onClose,
}: {
  shopId: string
  // The list's copy of this shop, so the drawer paints instantly.
  initialShop?: CoffeeShop
  user: User | null
  onShopChanged: (shop: CoffeeShop) => void
  onOpenShop: (id: string) => void
  onClose: () => void
}) {
  const [shop, setShop] = useState<CoffeeShop | null>(initialShop ?? null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [expanded, setExpanded] = useState(false)
  // "Update" opens the full page with the form already showing.
  const [reportOnExpand, setReportOnExpand] = useState(false)
  const [busy, setBusy] = useState(false)
  // Set when navigating between chain locations from the detail page, so
  // the new shop opens straight to its detail page too.
  const stayExpanded = useRef(false)

  // Keep drawer state and the main list in sync after a save/been toggle.
  const onStatusChanged = (updated: CoffeeShop) => {
    setShop((prev) => (prev ? { ...prev, savedByMe: updated.savedByMe, beenByMe: updated.beenByMe } : prev))
    onShopChanged(updated)
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

  useEffect(() => {
    setExpanded(stayExpanded.current)
    stayExpanded.current = false
    setReportOnExpand(false)
    setLoadFailed(false)
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

  return (
    <div className="fixed inset-0 z-[1000]">
      <div className="absolute inset-0 bg-espresso-900/40 backdrop-blur-[2px]" onClick={onClose} />
      <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col overflow-y-auto bg-cream-50 shadow-2xl">
        {!shop ? (
          <p className="p-6 text-sm text-espresso-500">
            {loadFailed ? "Couldn't load this shop." : 'Loading…'}
          </p>
        ) : (
          <>
            <div className="sticky top-0 border-b border-cream-200 bg-cream-50/95 px-6 py-5 backdrop-blur">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="text-xl font-bold tracking-tight">{shop.name}</h2>
                  <p className="mt-1 text-sm text-espresso-500">
                    {shop.address}, {shop.city}
                  </p>
                </div>
                <div className="flex items-center">
                  <button
                    onClick={() => setExpanded(true)}
                    aria-label="Expand: all photos and reports"
                    title="Expand: all photos & reports"
                    className="rounded-full p-2 text-espresso-500 transition hover:bg-cream-100 hover:text-espresso-900"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-5">
                      <path d="M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </button>
                  <button
                    onClick={onClose}
                    aria-label="Close"
                    className="rounded-full p-2 text-espresso-500 transition hover:bg-cream-100 hover:text-espresso-900"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-5">
                      <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
                    </svg>
                  </button>
                </div>
              </div>
              <div className="mt-2 flex gap-4">
                <a
                  href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${shop.name} ${shop.address} ${shop.city}`)}`}
                  target="_blank"
                  rel="noreferrer"
                  className="text-xs font-medium text-crema-500 hover:underline"
                >
                  Open in Google Maps
                </a>
                {shop.website && (
                  <a
                    href={shop.website}
                    target="_blank"
                    rel="noreferrer"
                    className="text-xs font-medium text-crema-500 hover:underline"
                  >
                    Shop website ↗
                  </a>
                )}
              </div>

              <div className="mt-3 flex items-start gap-1">
                <ActionButton
                  label={shop.savedByMe ? 'Saved' : 'Save'}
                  title={user ? undefined : 'Sign in with Google to use lists'}
                  active={shop.savedByMe}
                  activeCls="border-transparent bg-crema-500 text-white"
                  disabled={!user || busy}
                  onClick={() => toggleStatus('saved')}
                >
                  <svg
                    viewBox="0 0 24 24"
                    fill={shop.savedByMe ? 'currentColor' : 'none'}
                    stroke="currentColor"
                    strokeWidth="2"
                    className="size-4"
                  >
                    <path d="M6 4h12v17l-6-4-6 4V4Z" strokeLinejoin="round" />
                  </svg>
                </ActionButton>
                <ActionButton
                  label="Been"
                  title={user ? undefined : 'Sign in with Google to use lists'}
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
                  title={user ? undefined : 'Sign in with Google to report updates'}
                  active
                  activeCls="border-transparent bg-espresso-700 text-cream-50"
                  disabled={!user}
                  onClick={() => {
                    setReportOnExpand(true)
                    setExpanded(true)
                  }}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-4">
                    <path
                      d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17v3ZM14.5 7.5l3 3"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </ActionButton>
              </div>
            </div>

            <div className="px-6 py-4">
              {shop.vibe && <p className="mb-4 text-sm text-espresso-500 italic">“{shop.vibe}”</p>}
              <dl className="divide-y divide-cream-200 rounded-2xl border border-cream-200 bg-white px-4">
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
                {AMENITIES.filter((a) => shop[a.key] !== null).map((a) => (
                  <InfoRow key={a.key} label={a.label} value={shop[a.key] ? 'Yes' : 'No'} />
                ))}
              </dl>

              {shop.drinks.length > 0 && (
                <div className="mt-4 rounded-2xl border border-cream-200 bg-white px-4 py-3">
                  <h3 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">Drinks</h3>
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

              <button
                onClick={() => setExpanded(true)}
                className="mt-4 flex w-full items-center justify-center gap-1 py-2 text-sm font-semibold text-crema-500 transition hover:text-espresso-700"
              >
                See photos, reports & full details
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-4">
                  <path d="M9 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>

              {!user && (
                <p className="mt-2 rounded-2xl border border-dashed border-crema-400 bg-crema-400/10 px-4 py-3 text-center text-sm text-espresso-700">
                  Sign in with Google (top right) to report updates, add photos, and keep lists.
                </p>
              )}
            </div>
          </>
        )}
      </aside>
      {expanded && shop && (
        <ShopExpanded
          shop={shop}
          user={user}
          initialReporting={reportOnExpand}
          onChanged={onStatusChanged}
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

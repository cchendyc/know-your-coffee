import { useCallback, useEffect, useState } from 'react'
import { fetchShop, type CoffeeShop, type User } from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, machineDisplay } from '../labels'
import { ChainLocations } from './ChainLocations'
import { ReportList } from './ReportList'
import { SaveBeenButtons } from './SaveBeen'
import { ShopExpanded } from './ShopExpanded'

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2.5">
      <dt className="text-xs font-medium tracking-wide text-espresso-500 uppercase">{label}</dt>
      <dd className="text-right text-sm font-medium">{value}</dd>
    </div>
  )
}

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
  // Paint immediately from the list's copy; photos/reports hydrate from fetchShop.
  const [shop, setShop] = useState<CoffeeShop | null>(initialShop ?? null)
  const [expanded, setExpanded] = useState(false)
  // "Report an update" opens the full page with the form already showing.
  const [reportOnExpand, setReportOnExpand] = useState(false)

  const load = useCallback(() => {
    fetchShop(shopId).then(setShop)
  }, [shopId])

  // Keep drawer state and the main list in sync after a save/been toggle.
  const onStatusChanged = (updated: CoffeeShop) => {
    setShop((prev) => (prev ? { ...prev, savedByMe: updated.savedByMe, beenByMe: updated.beenByMe } : prev))
    onShopChanged(updated)
  }

  useEffect(() => {
    // Selecting another shop while open: repaint from its list copy, not the old shop.
    setShop((prev) => (prev?.id === shopId ? prev : (initialShop ?? null)))
    setExpanded(false)
    setReportOnExpand(false)
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [load, shopId])

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
          <p className="p-6 text-sm text-espresso-500">Loading…</p>
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
              <div className="mt-2 flex items-center justify-between gap-2">
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
                {user && <SaveBeenButtons shop={shop} user={user} onChanged={onStatusChanged} />}
              </div>
            </div>

            <div className="px-6 py-4">
              {shop.photoUrl && (
                <img src={shop.photoUrl} alt={shop.name} className="mb-4 h-44 w-full rounded-2xl object-cover" />
              )}
              {shop.vibe && <p className="mb-4 text-sm text-espresso-500 italic">“{shop.vibe}”</p>}
              <dl className="divide-y divide-cream-200 rounded-2xl border border-cream-200 bg-white px-4">
                <InfoRow label="Machine" value={machineDisplay(shop.machine, shop.machineModel)} />
                <InfoRow label="Beans" value={BEAN_SOURCE_LABELS[shop.beanSource]} />
                {shop.roaster && <InfoRow label="Roaster" value={shop.roaster} />}
                {shop.beanOrigins.length > 0 && <InfoRow label="Bean origins" value={shop.beanOrigins.join(', ')} />}
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

              <ChainLocations shop={shop} onOpenShop={onOpenShop} />

              {!shop.photos && (
                <div className="mt-4 flex gap-2">
                  {[0, 1, 2].map((i) => (
                    <div key={i} className="size-20 animate-pulse rounded-xl bg-cream-100" />
                  ))}
                </div>
              )}
              {shop.photos && shop.photos.length > 0 && (
                <button onClick={() => setExpanded(true)} className="mt-4 block w-full text-left">
                  <h3 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">
                    Community photos · {shop.photoCount}
                  </h3>
                  <div className="mt-2 flex gap-2 overflow-hidden">
                    {shop.photos.map((p) => (
                      <img key={p.id} src={p.data} alt="" className="size-20 shrink-0 rounded-xl object-cover" />
                    ))}
                    {(shop.photoCount ?? 0) > 4 && (
                      <span className="flex size-20 shrink-0 items-center justify-center rounded-xl bg-cream-100 text-xs font-semibold text-espresso-500">
                        +{(shop.photoCount ?? 0) - 4}
                      </span>
                    )}
                  </div>
                </button>
              )}

              {user ? (
                <button
                  onClick={() => {
                    setReportOnExpand(true)
                    setExpanded(true)
                  }}
                  className="mt-4 w-full rounded-2xl bg-espresso-700 py-3 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
                >
                  Report an update
                </button>
              ) : (
                <p className="mt-4 rounded-2xl border border-dashed border-crema-400 bg-crema-400/10 px-4 py-3 text-center text-sm text-espresso-700">
                  Sign in with Google (top right) to report updates, add photos, and keep lists.
                </p>
              )}

              <h3 className="mt-6 text-xs font-semibold tracking-wide text-espresso-500 uppercase">
                Recent reports
              </h3>
              {shop.reports ? (
                <>
                  <ReportList reports={shop.reports} />
                  {(shop.reportCount ?? 0) > 3 && (
                    <button
                      onClick={() => setExpanded(true)}
                      className="mt-2 text-xs font-medium text-crema-500 hover:underline"
                    >
                      See all {shop.reportCount} reports
                    </button>
                  )}
                </>
              ) : (
                <div className="mt-2 h-16 animate-pulse rounded-2xl bg-cream-100" />
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
          onReload={load}
          onOpenShop={onOpenShop}
          onClose={() => {
            setExpanded(false)
            setReportOnExpand(false)
          }}
        />
      )}
    </div>
  )
}

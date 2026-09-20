import { useEffect, useRef, useState } from 'react'
import { fetchShopDetails, type CoffeeShop, type PhotoKind, type Report, type ShopPhoto, type User } from '../api'
import { BEAN_SOURCE_LABELS, machineDisplay, PHOTO_KINDS, PHOTO_KIND_LABELS } from '../labels'
import { ChainLocations } from './ChainLocations'
import { ReportForm } from './ReportForm'
import { ReportList } from './ReportList'
import { SaveBeenButtons } from './SaveBeen'

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-cream-200 bg-white px-4 py-3">
      <p className="text-xs font-medium tracking-wide text-espresso-500 uppercase">{label}</p>
      <p className="mt-1 text-sm font-medium">{value}</p>
    </div>
  )
}

// Full-page view: photo galleries grouped by section, the complete report
// history, and the update form itself.
export function ShopExpanded({
  shop,
  user,
  initialReporting = false,
  onChanged,
  onReload,
  onOpenShop,
  onClose,
}: {
  shop: CoffeeShop
  user: User | null
  initialReporting?: boolean
  onChanged: (shop: CoffeeShop) => void
  onReload: () => void
  onOpenShop: (id: string) => void
  onClose: () => void
}) {
  const [reporting, setReporting] = useState(initialReporting)
  const formRef = useRef<HTMLDivElement>(null)

  // Start with the drawer's preview slice, then hydrate the full galleries.
  const [photos, setPhotos] = useState<ShopPhoto[]>(shop.photos ?? [])
  const [reports, setReports] = useState<Report[]>(shop.reports ?? [])
  const [loadingDetails, setLoadingDetails] = useState(true)

  const loadDetails = () => {
    fetchShopDetails(shop.id)
      .then((d) => {
        if (d) {
          setPhotos(d.photos)
          setReports(d.reports)
        }
      })
      .finally(() => setLoadingDetails(false))
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(loadDetails, [shop.id])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  useEffect(() => {
    if (reporting) formRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [reporting])

  const byKind = new Map<PhotoKind, ShopPhoto[]>()
  for (const photo of photos) {
    byKind.set(photo.kind, [...(byKind.get(photo.kind) ?? []), photo])
  }

  return (
    <div className="fixed inset-0 z-[1100] overflow-y-auto bg-cream-50">
      <div className="sticky top-0 z-10 border-b border-cream-200 bg-cream-50/95 backdrop-blur">
        <div className="mx-auto flex max-w-3xl items-center gap-3 px-4 py-4 sm:px-6">
          <button
            onClick={onClose}
            aria-label="Back"
            className="rounded-full p-2 text-espresso-500 transition hover:bg-cream-100 hover:text-espresso-900"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-5">
              <path d="M15 5l-7 7 7 7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
          <div className="flex-1">
            <h2 className="text-lg font-bold tracking-tight">{shop.name}</h2>
            <p className="text-xs text-espresso-500">
              {shop.address}, {shop.city}
            </p>
          </div>
          <SaveBeenButtons shop={shop} user={user} onChanged={onChanged} />
        </div>
      </div>

      <div className="mx-auto max-w-3xl px-4 py-6 sm:px-6">
        {shop.photoUrl && (
          <img src={shop.photoUrl} alt={shop.name} className="h-64 w-full rounded-2xl object-cover" />
        )}

        <div className="mt-4 flex gap-4">
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
              Shop website ↗
            </a>
          )}
        </div>

        <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <Fact label="Machine" value={machineDisplay(shop.machine, shop.machineModel)} />
          <Fact label="Beans" value={BEAN_SOURCE_LABELS[shop.beanSource]} />
          {shop.roaster && <Fact label="Roaster" value={shop.roaster} />}
          {shop.beanOrigins.length > 0 && <Fact label="Bean origins" value={shop.beanOrigins.join(', ')} />}
          {shop.grinders.length > 0 && <Fact label="Grinders" value={shop.grinders.join(', ')} />}
          <Fact label="Milk" value={shop.milkBrands.length ? shop.milkBrands.join(', ') : 'Unknown'} />
        </div>

        <div ref={formRef} className="mt-6 scroll-mt-20">
          {user && !reporting && (
            <button
              onClick={() => setReporting(true)}
              className="w-full rounded-2xl bg-espresso-700 py-3 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
            >
              Report an update
            </button>
          )}
          {!user && (
            <p className="rounded-2xl border border-dashed border-crema-400 bg-crema-400/10 px-4 py-3 text-center text-sm text-espresso-700">
              Sign in with Google (top right on the main page) to report updates and add photos.
            </p>
          )}
          {reporting && (
            <ReportForm
              shop={shop}
              onDone={() => {
                setReporting(false)
                onReload()
                loadDetails()
              }}
              onCancel={() => setReporting(false)}
            />
          )}
        </div>

        {shop.drinks.length > 0 && (
          <div className="mt-4 rounded-2xl border border-cream-200 bg-white px-4 py-3">
            <h3 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">Drinks</h3>
            <ul className="mt-1 grid grid-cols-1 gap-x-8 sm:grid-cols-2">
              {shop.drinks.map((d) => (
                <li key={d.name} className="flex items-center justify-between border-b border-cream-200 py-1.5 text-sm last:border-0">
                  <span>{d.name}</span>
                  {d.price != null && <span className="font-medium text-espresso-500">${d.price.toFixed(2)}</span>}
                </li>
              ))}
            </ul>
          </div>
        )}

        <ChainLocations shop={shop} onOpenShop={onOpenShop} />

        <h3 className="mt-8 text-sm font-bold tracking-tight">Community photos</h3>
        {loadingDetails && photos.length === 0 && (
          <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <div key={i} className="h-40 animate-pulse rounded-xl bg-cream-100" />
            ))}
          </div>
        )}
        {!loadingDetails && photos.length === 0 && (
          <p className="mt-1 text-sm text-espresso-500">No photos yet. Add some with “Report an update” above.</p>
        )}
        {PHOTO_KINDS.filter((k) => byKind.has(k)).map((kind) => (
          <div key={kind} className="mt-4">
            <h4 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">
              {PHOTO_KIND_LABELS[kind]} · {byKind.get(kind)!.length}
            </h4>
            <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
              {byKind.get(kind)!.map((p) => (
                <figure key={p.id}>
                  <img src={p.data} alt={PHOTO_KIND_LABELS[kind]} className="h-40 w-full rounded-xl object-cover" />
                  <figcaption className="mt-0.5 text-[11px] text-espresso-500">
                    {p.uploader ? p.uploader.name : 'Anonymous'} · {new Date(p.createdAt).toLocaleDateString()}
                  </figcaption>
                </figure>
              ))}
            </div>
          </div>
        ))}

        <h3 className="mt-8 text-sm font-bold tracking-tight">
          All reports · {shop.reportCount ?? reports.length}
        </h3>
        {loadingDetails && reports.length === 0 ? (
          <div className="mt-2 h-16 animate-pulse rounded-2xl bg-cream-100" />
        ) : (
          <ReportList reports={reports} />
        )}
      </div>
    </div>
  )
}

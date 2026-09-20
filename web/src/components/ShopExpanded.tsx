import { useEffect, useState, type ReactNode } from 'react'
import { fetchShop, type CoffeeShop, type User } from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, coffeePills, machineDisplay, PHOTO_KIND_LABELS } from '../labels'
import { ChainLocations } from './ChainLocations'
import { QuickConfirm, buildConfirmFacts } from './QuickConfirm'
import { ReportForm } from './ReportForm'
import { ReportList } from './ReportList'
import { SaveBeenButtons } from './SaveBeen'

function SectionCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-cream-200 bg-white px-5 py-4">
      <h3 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">{title}</h3>
      <div className="mt-2.5">{children}</div>
    </div>
  )
}

function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  return (
    <div
      className="fixed inset-0 z-[1200] flex items-start justify-center overflow-y-auto overscroll-contain bg-espresso-900/40 p-4"
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div className="my-8 w-full max-w-2xl rounded-2xl border border-cream-200 bg-cream-50 p-6">{children}</div>
    </div>
  )
}

// Full-page view matching the Figma shop detail: section cards, the
// two-door report banner, community photos, and the report history.
export function ShopExpanded({
  shop,
  user,
  initialReporting = false,
  onChanged,
  onHydrated,
  onOpenShop,
  onClose,
}: {
  shop: CoffeeShop
  user: User | null
  initialReporting?: boolean
  onChanged: (shop: CoffeeShop) => void
  // Receives the fully-fetched shop (photos, reports, chain) so the drawer
  // underneath stays current without fetching anything itself.
  onHydrated: (shop: CoffeeShop) => void
  onOpenShop: (id: string) => void
  onClose: () => void
}) {
  const [modal, setModal] = useState<'none' | 'report' | 'confirm'>(initialReporting ? 'report' : 'none')
  const [allDrinks, setAllDrinks] = useState(false)
  const [loadingDetails, setLoadingDetails] = useState(true)

  // The drawer's list copy has no photos/reports; they arrive via loadDetails.
  const photos = shop.photos ?? []
  const reports = shop.reports ?? []

  const loadDetails = () => {
    fetchShop(shop.id)
      .then((full) => full && onHydrated(full))
      // On failure keep rendering the list copy instead of spinning.
      .catch(() => undefined)
      .finally(() => setLoadingDetails(false))
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(loadDetails, [shop.id])

  // The page behind keeps its scrollbar otherwise, and wheel events
  // chain to it once this overlay has nothing left to scroll.
  useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = prev
    }
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (modal !== 'none') setModal('none')
      else onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose, modal])

  const closeModalAndRefresh = () => {
    setModal('none')
    loadDetails()
  }

  const canConfirm = buildConfirmFacts(shop).length > 0
  const drinksShown = allDrinks ? shop.drinks : shop.drinks.slice(0, 5)

  return (
    <div className="fixed inset-0 z-[1100] overflow-y-auto overscroll-contain bg-cream-50">
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

        <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
          <SectionCard title="Gear">
            {(shop.machines.length > 0 ? shop.machines : [{ brand: shop.machine, model: shop.machineModel }]).map(
              (m, i) => (
                <p key={i} className="text-sm font-semibold">
                  {machineDisplay(m.brand, m.model)}
                </p>
              ),
            )}
            <p className="text-xs text-espresso-500">
              {shop.machines.length > 1 ? 'Espresso machines' : 'Espresso machine'}
            </p>
            {shop.grinders.length > 0 && (
              <div className="mt-2.5 flex flex-wrap gap-1.5">
                {shop.grinders.map((g) => (
                  <span
                    key={g}
                    className="rounded-full border border-cream-200 bg-cream-100 px-2 py-0.5 text-[11px] font-medium text-espresso-500"
                  >
                    {g}
                  </span>
                ))}
              </div>
            )}
          </SectionCard>

          <SectionCard title="Beans">
            <p className="text-sm font-semibold">
              {shop.beanSource === 'IN_HOUSE_ROAST' || !shop.roaster
                ? BEAN_SOURCE_LABELS[shop.beanSource]
                : `${BEAN_SOURCE_LABELS[shop.beanSource]} · ${shop.roaster}`}
            </p>
            {shop.coffees.length > 0 ? (
              <div className="mt-2.5 space-y-3">
                {shop.coffees.map((c, i) => (
                  <div key={i}>
                    {(c.name || c.roaster) && (
                      <p className="text-sm font-semibold">{[c.roaster, c.name].filter(Boolean).join(' — ')}</p>
                    )}
                    <div className="mt-1 flex flex-wrap gap-1.5">
                      {coffeePills(c).map((p) => (
                        <span
                          key={p}
                          className="rounded-full border border-cream-200 bg-cream-100 px-2 py-0.5 text-[11px] font-medium text-espresso-500"
                        >
                          {p}
                        </span>
                      ))}
                    </div>
                    {c.tastingNotes.length > 0 && (
                      <p className="mt-1 text-xs text-espresso-500">{c.tastingNotes.join(' · ')}</p>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              shop.beanOrigins.length > 0 && (
                <div className="mt-2.5 flex flex-wrap gap-1.5">
                  {shop.beanOrigins.map((o) => (
                    <span
                      key={o}
                      className="rounded-full border border-cream-200 bg-cream-100 px-2 py-0.5 text-[11px] font-medium text-espresso-500"
                    >
                      {o}
                    </span>
                  ))}
                </div>
              )
            )}
          </SectionCard>

          <SectionCard title="Menu">
            {shop.drinks.length === 0 && <p className="text-sm text-espresso-500">No menu reported yet.</p>}
            <ul>
              {drinksShown.map((d) => (
                <li key={d.name} className="flex items-center justify-between border-b border-cream-200 py-1.5 text-sm last:border-0">
                  <span>{d.name}</span>
                  {d.price != null && <span className="font-medium text-espresso-500">${d.price.toFixed(2)}</span>}
                </li>
              ))}
            </ul>
            {shop.milkBrands.length > 0 && (
              <p className="mt-2 text-xs text-espresso-500">Milk: {shop.milkBrands.join(' · ')}</p>
            )}
            {shop.drinks.length > 5 && !allDrinks && (
              <button
                onClick={() => setAllDrinks(true)}
                className="mt-2 text-xs font-medium text-crema-500 hover:underline"
              >
                See all {shop.drinks.length} drinks
              </button>
            )}
          </SectionCard>

          <SectionCard title="Space">
            {AMENITIES.map((a) => (
              <div key={a.key} className="flex items-center justify-between border-b border-cream-200 py-1.5 text-sm last:border-0">
                <span>{a.label}</span>
                {shop[a.key] !== null ? (
                  <span className="font-medium text-espresso-500">{shop[a.key] ? 'Yes' : 'No'}</span>
                ) : user ? (
                  <button onClick={() => setModal('report')} className="text-xs text-crema-500 hover:underline">
                    Unknown — know it?
                  </button>
                ) : (
                  <span className="text-xs text-espresso-500">Unknown</span>
                )}
              </div>
            ))}
            {shop.vibe && <p className="mt-2 text-xs text-espresso-500 italic">“{shop.vibe}”</p>}
          </SectionCard>
        </div>

        {user ? (
          <div className="mt-4 rounded-2xl border border-crema-400/60 bg-crema-400/10 p-3">
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => setModal('report')}
                className="rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
              >
                Report an update
              </button>
              <button
                onClick={() => setModal('confirm')}
                disabled={!canConfirm}
                className="rounded-xl border border-cream-200 bg-white py-2.5 text-sm font-semibold text-espresso-700 transition hover:border-crema-400 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Quick confirm
              </button>
            </div>
          </div>
        ) : (
          <p className="mt-4 rounded-2xl border border-dashed border-crema-400 bg-crema-400/10 px-4 py-3 text-center text-sm text-espresso-700">
            Sign in with Google (top right on the main page) to report updates and add photos.
          </p>
        )}

        <ChainLocations shop={shop} onOpenShop={onOpenShop} />

        {loadingDetails && photos.length === 0 && (
          <div className="mt-6 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[0, 1, 2, 3].map((i) => (
              <div key={i} className="h-28 animate-pulse rounded-xl bg-cream-100" />
            ))}
          </div>
        )}
        {photos.length > 0 && (
          <div className="mt-6 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {photos.map((p) => (
              <figure key={p.id}>
                <img src={p.data} alt={PHOTO_KIND_LABELS[p.kind]} className="h-28 w-full rounded-xl object-cover" />
                <figcaption className="mt-0.5 text-[11px] text-espresso-500">
                  {PHOTO_KIND_LABELS[p.kind]} · {p.uploader ? p.uploader.name : 'Anonymous'}
                </figcaption>
              </figure>
            ))}
          </div>
        )}

        <h3 className="mt-8 text-sm font-bold tracking-tight">
          All reports · {shop.reportCount ?? reports.length}
        </h3>
        {loadingDetails && reports.length === 0 ? (
          <div className="mt-2 h-16 animate-pulse rounded-2xl bg-cream-100" />
        ) : (
          <ReportList reports={reports} />
        )}
      </div>

      {modal === 'report' && (
        <Modal onClose={() => setModal('none')}>
          <ReportForm shop={shop} onDone={closeModalAndRefresh} onCancel={() => setModal('none')} />
        </Modal>
      )}
      {modal === 'confirm' && (
        <Modal onClose={() => setModal('none')}>
          <QuickConfirm
            shop={shop}
            onDone={closeModalAndRefresh}
            onCancel={() => setModal('none')}
            onChanged={() => setModal('report')}
          />
        </Modal>
      )}
    </div>
  )
}

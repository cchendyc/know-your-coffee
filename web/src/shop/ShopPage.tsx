import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router'
import { deleteShop, isAdmin, setShopStatus, type CoffeeShop, type User } from '../api'
import { Modal } from '../components/Modal'
import { QuickConfirm, buildConfirmFacts } from '../components/QuickConfirm'
import { ReportForm } from '../components/ReportForm'
import { SellerApplicationModal } from '../components/SellerApplication'
import { AboutSection } from './AboutSection'
import { ListingGrid } from './ListingGrid'
import { MenuSection } from './MenuSection'
import { PhotosSection } from './PhotosSection'
import { ProfileCard } from './ProfileCard'
import { RelatedShops } from './RelatedShops'
import { ReviewsSection } from './ReviewsSection'
import { useShopPage } from './shopData'
import { SECTION_LABELS, plural, type Section } from './util'

const sectionFromHash = (hash: string): Section => {
  const key = hash.replace(/^#/, '')
  return key in SECTION_LABELS ? (key as Section) : 'about'
}
import './shop.css'

// Public shop page at /shops/:shopId. About first, then photos when any
// exist, reviews on every shop, and the storefront when the owner sells.
export function ShopPage({ user, onShopChanged }: { user: User | null; onShopChanged?: (shop: CoffeeShop) => void }) {
  const { shopId = '' } = useParams()
  const navigate = useNavigate()
  const seed = (useLocation().state as { shop?: CoffeeShop } | null)?.shop
  const { state, refresh, patch, version } = useShopPage(shopId, seed)
  const [modal, setModal] = useState<'none' | 'report' | 'confirm' | 'claim' | 'delete'>('none')
  const [busy, setBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  // Tabs are panels, not scroll anchors. The hash (#shop) makes a tab
  // linkable and survives reload; About is the default.
  const { hash } = useLocation()
  const [active, setActive] = useState<Section>(() => sectionFromHash(hash))

  useEffect(() => {
    window.scrollTo(0, 0)
    setModal('none')
    setActive(sectionFromHash(hash))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shopId])

  const full = state.status === 'ready' ? state.shop : null
  const shop = full ?? (state.status === 'loading' ? state.shop : null)
  const sellsOnline = !!full?.ownerId && full.products.length > 0
  const sections: Section[] = full
    ? (['about', full.photoCount > 0 && 'photos', 'reviews', sellsOnline && 'shop'] as const).filter(
        (s): s is Section => Boolean(s),
      )
    : ['about']
  const tab: Section = sections.includes(active) ? active : 'about'

  const say = (message: string) => {
    setNotice(message)
    setTimeout(() => setNotice(null), 2500)
  }

  const toggle = async (field: 'saved' | 'been') => {
    if (!shop || !user || busy) return
    setBusy(true)
    try {
      const updated = await setShopStatus(shop.id, { [field]: field === 'saved' ? !shop.savedByMe : !shop.beenByMe })
      patch({ savedByMe: updated.savedByMe, beenByMe: updated.beenByMe })
      onShopChanged?.(updated)
    } finally {
      setBusy(false)
    }
  }

  const share = async () => {
    if (!shop) return
    const url = window.location.href
    try {
      if (navigator.share) {
        await navigator.share({ title: shop.name, text: `${shop.name} · ${shop.address}, ${shop.city}`, url })
        return
      }
      await navigator.clipboard.writeText(url)
      say('Link copied.')
    } catch {
      // Share sheet dismissed or clipboard blocked; nothing to show.
    }
  }

  const removeShop = async () => {
    if (!shop) return
    setBusy(true)
    setDeleteError(null)
    try {
      await deleteShop(shop.id)
      navigate('/', { replace: true })
    } catch (e) {
      setDeleteError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const jump = (s: Section) => {
    setActive(s)
    navigate({ hash: s === 'about' ? '' : s }, { replace: true, state: seed ? { shop: seed } : undefined })
  }
  const closeModalAndRefresh = () => {
    setModal('none')
    refresh()
  }

  if (state.status === 'missing' || state.status === 'error') {
    return (
      <div className="mx-auto max-w-6xl px-6 py-20 text-center text-sm text-espresso-500">
        <p>{state.status === 'missing' ? 'This shop does not exist.' : state.message}</p>
        <Link to="/" className="sp-link mt-3 inline-block">
          Back to shops
        </Link>
      </div>
    )
  }
  if (!shop) {
    return (
      <div className="sp">
        <div className="sp-cover" style={{ background: 'linear-gradient(156deg, #2b1c14 0%, #6f4e37 50%, #d4a35e 83%)' }} />
        <div className="sp-wrap">
          <div className="sp-profile h-[280px]" />
        </div>
      </div>
    )
  }

  const machines = (shop.machines.length > 0 ? shop.machines : [{ brand: shop.machine, model: shop.machineModel }]).filter(
    (m) => m.brand !== 'UNKNOWN',
  )
  return (
    <div className="sp">
      {notice && <p className="sp-notice">{notice}</p>}

      <ProfileCard
        shop={shop}
        user={user}
        busy={busy}
        sellsOnline={sellsOnline}
        sections={sections}
        active={tab}
        onJump={jump}
        onToggle={(f) => void toggle(f)}
        onShare={() => void share()}
      />

      {!full ? (
        <div className="sp-wrap flex flex-col gap-4 pt-10">
          <div className="sp-skeleton h-6 w-48" />
          <div className="grid gap-4 md:grid-cols-3">
            <div className="sp-skeleton h-36" />
            <div className="sp-skeleton h-36" />
            <div className="sp-skeleton h-36" />
          </div>
        </div>
      ) : (
        <div className="sp-wrap flex flex-col">
          <section className="sp-section" role="tabpanel">
            {tab === 'about' && (
              <AboutSection
                shop={full}
                user={user}
                machines={machines}
                canConfirm={buildConfirmFacts(full).length > 0}
                onReport={() => setModal('report')}
                onConfirm={() => setModal('confirm')}
                onJumpToShop={() => jump('shop')}
              >
                {full.drinks.length > 0 && <MenuSection shop={full} />}
              </AboutSection>
            )}
            {tab === 'photos' && <PhotosSection shopId={full.id} photoCount={full.photoCount} version={version} />}
            {tab === 'reviews' && (
              <ReviewsSection
                shopId={full.id}
                shopName={full.name}
                reviews={full.reviews}
                reviewCount={full.reviewCount}
                ratingAverage={full.ratingAverage}
                myReview={full.myReview}
                user={user}
                onSubmitted={refresh}
              />
            )}
            {tab === 'shop' && (
              <ListingGrid shop={full} onAdd={() => say('Checkout is coming soon. Visit the shop or message the owner to order.')} />
            )}
          </section>

          {full.chain && full.chain.shops.length > 1 && (
            <RelatedShops
              title={`Also at ${full.chain.name}`}
              subtitle={plural(full.chain.shops.length - 1, 'other location')}
              shops={full.chain.shops.filter((s) => s.id !== full.id)}
            />
          )}

          {!full.ownerId && user && (
            <div className="flex justify-end pt-10 pb-4">
              <button type="button" onClick={() => setModal('claim')} className="sp-pill sp-pill--outline sp-pill--sm">
                Own this shop? Claim it
              </button>
            </div>
          )}
        </div>
      )}

      <footer className="sp-footer">
        <div className="sp-wrap mx-auto flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-bold text-espresso-900">Know Your Coffee</p>
            <p>© {new Date().getFullYear()}</p>
          </div>
          <div className="flex gap-6 text-[13px]">
            {isAdmin(user) && (
              <button type="button" onClick={() => setModal('delete')} className="text-danger-700">
                Delete shop
              </button>
            )}
            <a href={`${import.meta.env.BASE_URL}privacy.html`}>Privacy</a>
            <a href={`${import.meta.env.BASE_URL}terms.html`}>Terms</a>
          </div>
        </div>
      </footer>

      {modal === 'report' && (
        <Modal onClose={() => setModal('none')}>
          <ReportForm shop={shop} onDone={closeModalAndRefresh} onCancel={() => setModal('none')} />
        </Modal>
      )}
      {modal === 'confirm' && (
        <Modal onClose={() => setModal('none')}>
          <QuickConfirm shop={shop} onDone={closeModalAndRefresh} onCancel={() => setModal('none')} onChanged={() => setModal('report')} />
        </Modal>
      )}
      {modal === 'claim' && <SellerApplicationModal shop={shop} onClose={() => setModal('none')} />}
      {modal === 'delete' && (
        <Modal onClose={() => setModal('none')}>
          <h3 className="text-lg font-bold tracking-tight">Delete {shop.name}?</h3>
          <p className="mt-2 text-sm text-espresso-500">Use this for listings that aren’t coffee shops. Reports, photos, and claims go with it.</p>
          {deleteError && <p className="mt-2 text-sm text-danger-700">{deleteError}</p>}
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" disabled={busy} onClick={() => setModal('none')} className="sp-pill sp-pill--outline sp-pill--sm">
              Cancel
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => void removeShop()}
              className="sp-pill sp-pill--sm bg-danger-700 text-white hover:bg-danger-600 disabled:opacity-50"
            >
              {busy ? 'Deleting…' : 'Delete shop'}
            </button>
          </div>
        </Modal>
      )}
    </div>
  )
}

import type { CoffeeShop, ShopPageData, User } from '../api'
import { timeAgo } from '../format'
import { BookmarkIcon, CheckIcon, DirectionsIcon, ShareIcon } from './bits'
import { SECTION_LABELS, initials, type Section } from './util'

// Renders from the explorer's copy first (no ownership, counts, or
// listings), then fills in when the page query lands.
export type ProfileShop = CoffeeShop & Partial<Pick<ShopPageData, 'ownerId' | 'reportCount' | 'photoCount' | 'reports' | 'products' | 'deliverySettings'>>

export function ProfileCard({
  shop,
  user,
  busy,
  sellsOnline,
  sections,
  active,
  onJump,
  onToggle,
  onShare,
}: {
  shop: ProfileShop
  user: User | null
  busy: boolean
  sellsOnline: boolean
  sections: Section[]
  active: Section
  onJump: (s: Section) => void
  onToggle: (field: 'saved' | 'been') => void
  onShare: () => void
}) {
  const latest = shop.reports?.[0]
  const mapsUrl = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${shop.name} ${shop.address} ${shop.city}`)}`

  return (
    <>
      <div
        className="sp-cover"
        style={{
          backgroundImage: shop.photoUrl
            ? `linear-gradient(156deg, rgba(43,28,20,0.85) 0%, rgba(111,78,55,0.6) 50%, rgba(212,163,94,0.4) 83%), url(${shop.photoUrl})`
            : 'linear-gradient(156deg, #2b1c14 0%, #6f4e37 50%, #d4a35e 83%)',
        }}
      />
      <div className="sp-wrap">
        <div className="sp-profile">
          <div className="flex flex-col gap-5 md:flex-row md:items-start md:gap-6">
            <div className="sp-avatar">
              {shop.photoUrl ? <img src={shop.photoUrl} alt="" /> : initials(shop.name)}
            </div>

            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <h1 className="text-2xl font-bold tracking-tight">{shop.name}</h1>
              <p className="text-[13px] text-espresso-500">
                {shop.address}, {shop.city}
              </p>
              {shop.reportCount != null && (
                <p className="sp-stats pt-1">
                  <span>
                    <b>{shop.reportCount}</b> {shop.reportCount === 1 ? 'report' : 'reports'}
                  </span>
                  <span>·</span>
                  <span>
                    <b>{shop.photoCount ?? 0}</b> {shop.photoCount === 1 ? 'photo' : 'photos'}
                  </span>
                  {latest && (
                    <>
                      <span>·</span>
                      <span>updated {timeAgo(latest.createdAt)}</span>
                    </>
                  )}
                </p>
              )}
            </div>

            <div className="flex flex-col items-start gap-4 md:items-end">
              <div className="flex flex-wrap items-center gap-2">
                <button type="button" aria-label="Share" title="Share" onClick={onShare} className="sp-icon-btn">
                  <ShareIcon className="size-[18px]" />
                </button>
                <a href={mapsUrl} target="_blank" rel="noreferrer" className="sp-pill sp-pill--light">
                  <DirectionsIcon />
                  Directions
                </a>
                <button
                  type="button"
                  disabled={!user || busy}
                  onClick={() => onToggle('saved')}
                  title={user ? undefined : 'Sign in to use lists'}
                  className={`sp-pill ${shop.savedByMe ? 'sp-pill--dark' : 'sp-pill--light'}`}
                >
                  <BookmarkIcon filled={shop.savedByMe} />
                  {shop.savedByMe ? 'Saved' : 'Save'}
                </button>
                <button
                  type="button"
                  aria-label={shop.beenByMe ? 'Remove from been list' : 'Mark as been here'}
                  title={shop.beenByMe ? 'Been here' : 'Mark as been here'}
                  disabled={!user || busy}
                  onClick={() => onToggle('been')}
                  className={`sp-icon-btn ${shop.beenByMe ? 'is-on' : ''}`}
                >
                  <CheckIcon className="size-[18px]" />
                </button>
              </div>
            </div>
          </div>

          {shop.vibe && <p className="text-sm leading-[22px]">{shop.vibe}</p>}

          <div className="flex flex-col gap-2 border-b border-cream-200 sm:flex-row sm:items-end sm:justify-between">
            <nav className="sp-tabs" role="tablist">
              {sections.map((s) => (
                <button key={s} type="button" role="tab" aria-selected={active === s} onClick={() => onJump(s)} className={`sp-tab ${active === s ? 'is-active' : ''}`}>
                  <span>{SECTION_LABELS[s]}</span>
                  <span />
                </button>
              ))}
            </nav>
            {sellsOnline && shop.deliverySettings?.pickup && (
              <p className="pb-3 text-xs text-espresso-500">Pickup in {shop.city}</p>
            )}
          </div>
        </div>
      </div>
    </>
  )
}

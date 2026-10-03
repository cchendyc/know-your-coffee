import { Link } from 'react-router'
import type { ChainLocation } from '../api'
import { BEAN_SOURCE_LABELS, machineDisplay } from '../labels'
import { initials } from './util'

// Horizontal rail of shop cards under the tab panel. Today it lists the
// other locations of a chain; the same rail will carry similar-shop
// suggestions once the backend ranks them.
export function RelatedShops({ title, subtitle, shops }: { title: string; subtitle?: string; shops: ChainLocation[] }) {
  if (shops.length === 0) return null
  return (
    <section className="sp-related" aria-label={title}>
      <div className="sp-section-head">
        <div>
          <h2>{title}</h2>
          {subtitle && <p>{subtitle}</p>}
        </div>
      </div>
      <ul className="sp-rail">
        {shops.map((s) => (
          <li key={s.id}>
            <RelatedShopCard shop={s} />
          </li>
        ))}
      </ul>
    </section>
  )
}

function RelatedShopCard({ shop }: { shop: ChainLocation }) {
  const machine = (shop.machines.length ? shop.machines : [{ brand: shop.machine, model: shop.machineModel }]).find(
    (m) => m.brand !== 'UNKNOWN',
  )
  const meta = [shop.city, machine ? machineDisplay(machine.brand, machine.model) : null].filter(Boolean).join(' · ')
  return (
    <Link to={`/shops/${shop.id}`} className="sp-rail-card">
      <div className="sp-rail-art" style={shop.photoUrl ? { backgroundImage: `url(${shop.photoUrl})` } : undefined}>
        {!shop.photoUrl && <span>{initials(shop.name)}</span>}
        {shop.beanSource === 'IN_HOUSE_ROAST' && <em className="sp-rail-tag">{BEAN_SOURCE_LABELS.IN_HOUSE_ROAST}</em>}
      </div>
      <p className="sp-rail-name">{shop.name}</p>
      <p className="sp-rail-meta">{meta}</p>
    </Link>
  )
}

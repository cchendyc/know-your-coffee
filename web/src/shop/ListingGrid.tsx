import { Link } from 'react-router'
import type { ShopPageData, ShopPageProduct } from '../api'
import { hubPath } from '../routes'
import { BagIcon, BeanIcon, SectionHeader } from './bits'
import { plural } from './util'

// Bag colours for listings without a cover, in listing order.
const BAG_COLORS = ['#6f4e37', '#3d5a80', '#c08c3e', '#5b3a29', '#8a9a7b', '#2b1d14']

export function ListingGrid({ shop, delivery, onAdd }: { shop: ShopPageData; delivery: string; onAdd: () => void }) {
  return (
    <>
      <SectionHeader
        title={`From ${shop.name}`}
        subtitle={[plural(shop.products.length, 'listing'), delivery].filter(Boolean).join(' · ')}
        action={
          shop.ownedByMe && (
            <Link to={hubPath(shop.id, 'listings')} className="sp-link">
              Manage listings →
            </Link>
          )
        }
      />
      <div className="sp-listings">
        {shop.products.map((p, i) => (
          <ProductCard key={p.id} product={p} shopName={shop.name} color={BAG_COLORS[i % BAG_COLORS.length]} delivery={delivery} onAdd={onAdd} />
        ))}
      </div>
    </>
  )
}

function ProductCard({
  product: p,
  shopName,
  color,
  delivery,
  onAdd,
}: {
  product: ShopPageProduct
  shopName: string
  color: string
  delivery: string
  onAdd: () => void
}) {
  return (
    <div className="sp-product">
      <div className="sp-product-img" style={{ backgroundColor: color }}>
        {p.coverPhoto ? (
          <img src={p.coverPhoto.data} alt="" loading="lazy" />
        ) : (
          <div className="sp-bag" style={{ color }}>
            <BeanIcon className="size-7" />
            <p className="sp-bag-name">{p.name}</p>
            <p className="sp-bag-shop">{shopName}</p>
          </div>
        )}
        {p.status === 'LOW_STOCK' && <span className="sp-product-badge">Low stock</span>}
      </div>
      <div className="flex flex-col gap-1">
        <p className="sp-product-name">{p.name}</p>
        <p className="flex items-baseline gap-1">
          <span className="sp-price">${p.price % 1 === 0 ? p.price.toFixed(0) : p.price.toFixed(2)}</span>
          {p.subtitle && <span className="truncate text-xs text-espresso-500">{p.subtitle}</span>}
        </p>
        {delivery && <p className="sp-ship">{delivery}</p>}
        <button type="button" onClick={onAdd} className="sp-pill sp-pill--dark sp-pill--sm mt-1 w-full">
          <BagIcon className="size-3.5" />
          Add to cart
        </button>
      </div>
    </div>
  )
}

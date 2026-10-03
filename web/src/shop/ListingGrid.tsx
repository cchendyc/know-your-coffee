import { Link } from 'react-router'
import type { ShopPageData, ShopPageProduct } from '../api'
import { hubPath } from '../routes'
import { BeanIcon, PlusIcon } from './bits'

// Bag colours for listings without a cover, in listing order.
const BAG_COLORS = ['#6f4e37', '#3d5a80', '#c08c3e', '#5b3a29', '#8a9a7b', '#2b1d14']

export function ListingGrid({ shop, onAdd }: { shop: ShopPageData; onAdd: () => void }) {
  return (
    <>
      <div className="sp-listings">
        {shop.ownedByMe && (
          <Link to={hubPath(shop.id, 'listings')} className="sp-link sp-listings-manage">
            Manage listings →
          </Link>
        )}
        {shop.products.map((p, i) => (
          <ProductCard key={p.id} product={p} shopName={shop.name} color={BAG_COLORS[i % BAG_COLORS.length]} onAdd={onAdd} />
        ))}
      </div>
    </>
  )
}

function ProductCard({
  product: p,
  shopName,
  color,
  onAdd,
}: {
  product: ShopPageProduct
  shopName: string
  color: string
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
      <div className="flex items-start gap-2 px-0.5">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <p className="sp-product-name">{p.name}</p>
          {p.subtitle && <p className="truncate text-xs text-espresso-500">{p.subtitle}</p>}
          <p className="sp-price">${p.price % 1 === 0 ? p.price.toFixed(0) : p.price.toFixed(2)}</p>
        </div>
        <button type="button" onClick={onAdd} aria-label={`Add ${p.name} to cart`} className="sp-add">
          <PlusIcon className="size-4" />
        </button>
      </div>
    </div>
  )
}

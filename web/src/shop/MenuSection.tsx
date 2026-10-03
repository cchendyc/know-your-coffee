import type { ShopPageData, User } from '../api'
import { SectionHeader } from './bits'
import { plural } from './util'

export function MenuSection({ shop, user, onReport }: { shop: ShopPageData; user: User | null; onReport: () => void }) {
  const half = Math.ceil(shop.drinks.length / 2)
  const cols = [shop.drinks.slice(0, half), shop.drinks.slice(half)].filter((c) => c.length > 0)
  return (
    <>
      <SectionHeader
        title="Menu"
        subtitle={`${plural(shop.drinks.length, 'drink')}${shop.milkBrands.length ? ` · Milk: ${shop.milkBrands.join(', ')}` : ''}`}
        action={
          user && (
            <button type="button" onClick={onReport} className="sp-link">
              Update menu
            </button>
          )
        }
      />
      <div className="grid gap-4 md:grid-cols-2">
        {cols.map((col, i) => (
          <div key={i} className="sp-card px-5 py-1.5">
            {col.map((d) => (
              <div key={d.name} className="sp-menu-row">
                <span className="font-medium">{d.name}</span>
                {d.price != null && <span className="font-semibold tabular-nums">${d.price.toFixed(2)}</span>}
              </div>
            ))}
          </div>
        ))}
      </div>
    </>
  )
}

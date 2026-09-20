import type { CoffeeShop } from '../api'

export function ChainLocations({
  shop,
  onOpenShop,
}: {
  shop: CoffeeShop
  onOpenShop: (id: string) => void
}) {
  const others = shop.chain?.shops.filter((s) => s.id !== shop.id) ?? []
  if (!shop.chain || others.length === 0) return null

  return (
    <div className="mt-4 rounded-2xl border border-cream-200 bg-white px-4 py-3">
      <h3 className="text-xs font-semibold tracking-wide text-espresso-500 uppercase">
        Other {shop.chain.name} locations · {others.length}
      </h3>
      <ul className="mt-1 divide-y divide-cream-200">
        {others.map((loc) => (
          <li key={loc.id}>
            <button
              type="button"
              onClick={() => onOpenShop(loc.id)}
              className="flex w-full items-start justify-between gap-3 py-2 text-left text-sm hover:text-crema-500"
            >
              <span className="font-medium">{loc.name}</span>
              <span className="shrink-0 text-right text-espresso-500">
                {loc.address}, {loc.city}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

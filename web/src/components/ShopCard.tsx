import type { CoffeeShop, User } from '../api'
import { AMENITIES, BEAN_SOURCE_LABELS, machineDisplay } from '../labels'
import { SaveBeenButtons } from './SaveBeen'

export function ShopCard({
  shop,
  user,
  onClick,
  onChanged,
}: {
  shop: CoffeeShop
  user: User | null
  onClick: () => void
  onChanged: (shop: CoffeeShop) => void
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => e.key === 'Enter' && onClick()}
      className="group flex cursor-pointer flex-col gap-3 rounded-2xl border border-cream-200 bg-white p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-crema-400 hover:shadow-md"
    >
      <div className="relative -mx-2 -mt-2">
        {shop.photoUrl ? (
          <img src={shop.photoUrl} alt={shop.name} loading="lazy" className="h-36 w-full rounded-xl object-cover" />
        ) : (
          <div className="flex h-36 items-center justify-center rounded-xl bg-cream-100">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              className="size-10 text-cream-200"
            >
              <path d="M4 8h12v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V8Z" />
              <path d="M16 9h1.5a2.5 2.5 0 0 1 0 5H16" />
            </svg>
          </div>
        )}
        {user && (
          <div className="absolute top-2 right-2">
            <SaveBeenButtons shop={shop} user={user} onChanged={onChanged} compact />
          </div>
        )}
      </div>
      <div>
        <h2 className="font-semibold tracking-tight group-hover:text-espresso-700">{shop.name}</h2>
        <p className="mt-0.5 text-xs text-espresso-500">
          {shop.address} · {shop.city}
        </p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        <span className="rounded-full bg-espresso-700 px-2.5 py-1 text-xs font-medium text-cream-50">
          {machineDisplay(shop.machine, shop.machineModel)}
        </span>
        <span className="rounded-full bg-crema-400/25 px-2.5 py-1 text-xs font-medium text-espresso-700">
          {/* In-house roasters would just repeat the shop name as "<name> beans". */}
          {shop.beanSource === 'IN_HOUSE_ROAST'
            ? BEAN_SOURCE_LABELS.IN_HOUSE_ROAST
            : shop.roaster
              ? `${shop.roaster} beans`
              : BEAN_SOURCE_LABELS[shop.beanSource]}
        </span>
      </div>

      {(shop.milkBrands.length > 0 || AMENITIES.some((a) => shop[a.key] !== null)) && (
        <div className="flex flex-wrap gap-1">
          {shop.milkBrands.map((b) => (
            <span key={b} className="rounded-full border border-cream-200 px-2 py-0.5 text-[11px] text-espresso-500">
              {b}
            </span>
          ))}
          {AMENITIES.filter((a) => shop[a.key] !== null).map((a) => (
            <span
              key={a.key}
              className={`rounded-full border px-2 py-0.5 text-[11px] ${
                shop[a.key]
                  ? 'border-crema-400/60 bg-crema-400/10 text-espresso-700'
                  : 'border-cream-200 text-espresso-500'
              }`}
            >
              {shop[a.key] ? a.label : a.no}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

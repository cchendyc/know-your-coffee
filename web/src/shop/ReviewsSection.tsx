import { SectionHeader, StarIcon } from './bits'

// No ratings model exists yet, so this is the empty state from the design.
export function ReviewsSection({ shopName }: { shopName: string }) {
  return (
    <>
      <SectionHeader title="Customer reviews" subtitle="From verified purchases" />
      <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
        <div className="sp-card flex w-full flex-col gap-4 p-5 lg:w-[340px] lg:shrink-0">
          <div className="flex items-center gap-3">
            <p className="text-[44px] leading-none font-bold text-espresso-500/40">–</p>
            <div>
              <div className="flex gap-0.5 text-cream-200">
                {[0, 1, 2, 3, 4].map((i) => (
                  <StarIcon key={i} />
                ))}
              </div>
              <p className="mt-1 text-[13px] text-espresso-500">No ratings yet</p>
            </div>
          </div>
          <div className="h-px bg-cream-200" />
          <div>
            <p className="text-sm font-semibold">Review this shop</p>
            <p className="text-xs text-espresso-500">Reviews open after your first order arrives.</p>
            <button type="button" disabled className="sp-pill sp-pill--outline sp-pill--sm mt-2 w-full border-espresso-700 text-espresso-700">
              Write a review
            </button>
          </div>
        </div>
        <div className="sp-card flex flex-1 items-center justify-center p-10 text-sm text-espresso-500">
          Reviews from buyers will show here once {shopName} starts shipping orders.
        </div>
      </div>
    </>
  )
}

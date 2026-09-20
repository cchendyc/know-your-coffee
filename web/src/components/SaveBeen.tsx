import { useState } from 'react'
import { setShopStatus, type CoffeeShop, type User } from '../api'

// "Saved" bookmark + "Been" check, the wording used by Beli and Google Maps lists.
export function SaveBeenButtons({
  shop,
  user,
  onChanged,
  compact = false,
}: {
  shop: CoffeeShop
  user: User | null
  onChanged: (shop: CoffeeShop) => void
  compact?: boolean
}) {
  const [busy, setBusy] = useState(false)

  const toggle = async (field: 'saved' | 'been') => {
    if (!user || busy) return
    setBusy(true)
    try {
      const updated = await setShopStatus(shop.id, {
        [field]: field === 'saved' ? !shop.savedByMe : !shop.beenByMe,
      })
      onChanged(updated)
    } finally {
      setBusy(false)
    }
  }

  const base = compact
    ? 'flex size-8 items-center justify-center rounded-full bg-white/90 shadow-sm backdrop-blur transition'
    : 'flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition'
  const title = user ? undefined : 'Sign in with Google to use lists'

  return (
    <div className={compact ? 'flex gap-1.5' : 'flex gap-2'}>
      <button
        type="button"
        disabled={!user || busy}
        title={title ?? (shop.savedByMe ? 'Remove from saved' : 'Save for later')}
        aria-label="Save"
        onClick={(e) => {
          e.stopPropagation()
          toggle('saved')
        }}
        className={`${base} ${
          shop.savedByMe
            ? compact
              ? 'text-crema-500'
              : 'border-crema-400 bg-crema-400/20 text-espresso-700'
            : compact
              ? 'text-espresso-500 hover:text-espresso-900'
              : 'border-cream-200 text-espresso-500 hover:border-crema-400'
        } disabled:cursor-not-allowed disabled:opacity-50`}
      >
        <svg viewBox="0 0 24 24" fill={shop.savedByMe ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" className="size-4">
          <path d="M6 4h12v17l-6-4-6 4V4Z" strokeLinejoin="round" />
        </svg>
        {!compact && (shop.savedByMe ? 'Saved' : 'Save')}
      </button>
      <button
        type="button"
        disabled={!user || busy}
        title={title ?? (shop.beenByMe ? 'Remove from been list' : 'Mark as been')}
        aria-label="Been"
        onClick={(e) => {
          e.stopPropagation()
          toggle('been')
        }}
        className={`${base} ${
          shop.beenByMe
            ? compact
              ? 'text-green-700'
              : 'border-green-600/40 bg-green-600/10 text-green-800'
            : compact
              ? 'text-espresso-500 hover:text-espresso-900'
              : 'border-cream-200 text-espresso-500 hover:border-crema-400'
        } disabled:cursor-not-allowed disabled:opacity-50`}
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" className="size-4">
          <path d="m5 12.5 4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {!compact && 'Been'}
      </button>
    </div>
  )
}

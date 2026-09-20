import { useState } from 'react'
import { addShop, type User } from '../api'

const inputCls =
  'w-full rounded-xl border border-cream-200 bg-white px-3 py-2 text-sm outline-none focus:border-crema-400 focus:ring-2 focus:ring-crema-400/40'

export function AddShopModal({
  user,
  onAdded,
  onClose,
}: {
  user: User | null
  onAdded: (id: string) => void
  onClose: () => void
}) {
  const [name, setName] = useState('')
  const [address, setAddress] = useState('')
  const [city, setCity] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setSaving(true)
    setError(null)
    try {
      const shop = await addShop(name.trim(), address.trim(), city.trim())
      onAdded(shop.id)
    } catch (e) {
      setError((e as Error).message)
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[1000] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-espresso-900/40 backdrop-blur-[2px]" onClick={onClose} />
      <div className="relative w-full max-w-sm space-y-3 rounded-2xl bg-cream-50 p-5 shadow-2xl">
        <div className="flex items-center justify-between">
          <h2 className="font-bold tracking-tight">Add a coffee shop</h2>
          <button onClick={onClose} className="text-xs text-espresso-500 hover:underline">
            Cancel
          </button>
        </div>
        {!user && (
          <p className="rounded-xl border border-dashed border-crema-400 bg-crema-400/10 px-3 py-2 text-xs text-espresso-700">
            Sign in with Google (top right) to add shops.
          </p>
        )}
        <p className="text-xs text-espresso-500">
          We look it up on Google Places to fill in the exact location and photo.
        </p>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Shop name" className={inputCls} />
        <input
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          placeholder="Street address"
          className={inputCls}
        />
        <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="City" className={inputCls} />
        {error && <p className="text-xs text-red-600">{error}</p>}
        <button
          onClick={submit}
          disabled={!user || saving || !name.trim() || !address.trim() || !city.trim()}
          className="w-full rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {saving ? 'Adding…' : 'Add shop'}
        </button>
      </div>
    </div>
  )
}

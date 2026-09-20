import { useEffect, useRef, useState } from 'react'
import {
  addShopFromPlace,
  fetchPlacePreview,
  searchPlaces,
  type PlacePreview,
  type PlaceSuggestion,
  type User,
} from '../api'

export function AddShopModal({
  user,
  onAdded,
  onClose,
}: {
  user: User | null
  onAdded: (id: string) => void
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [suggestions, setSuggestions] = useState<PlaceSuggestion[]>([])
  const [searching, setSearching] = useState(false)
  const [preview, setPreview] = useState<PlacePreview | null>(null)
  const [loadingPreview, setLoadingPreview] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const latestQuery = useRef('')

  // Debounced type-ahead against Google Places (via our API).
  useEffect(() => {
    if (preview) return // done searching once a place is picked
    const q = query.trim()
    latestQuery.current = q
    if (q.length < 3) {
      setSuggestions([])
      return
    }
    setSearching(true)
    const t = setTimeout(() => {
      searchPlaces(q)
        .then((results) => {
          if (latestQuery.current === q) setSuggestions(results)
        })
        .catch((e: Error) => setError(e.message))
        .finally(() => setSearching(false))
    }, 350)
    return () => clearTimeout(t)
  }, [query, preview])

  const pick = async (s: PlaceSuggestion) => {
    setSuggestions([])
    setQuery(s.name)
    setLoadingPreview(true)
    setError(null)
    try {
      const p = await fetchPlacePreview(s.placeId)
      if (!p) throw new Error('Could not load that place. Try another result.')
      setPreview(p)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoadingPreview(false)
    }
  }

  const confirm = async () => {
    if (!preview) return
    setSaving(true)
    setError(null)
    try {
      const shop = await addShopFromPlace(preview.placeId)
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

        <div className="relative">
          <input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setPreview(null)
            }}
            placeholder="Search shop name…"
            autoFocus
            className="w-full rounded-xl border border-cream-200 bg-white px-3 py-2 text-sm outline-none focus:border-crema-400 focus:ring-2 focus:ring-crema-400/40"
          />
          {suggestions.length > 0 && (
            <ul className="absolute inset-x-0 top-full z-10 mt-1 max-h-56 overflow-y-auto rounded-xl border border-cream-200 bg-white shadow-lg">
              {suggestions.map((s) => (
                <li key={s.placeId}>
                  <button
                    onClick={() => pick(s)}
                    className="w-full px-3 py-2 text-left transition hover:bg-cream-100"
                  >
                    <span className="block text-sm font-medium">{s.name}</span>
                    <span className="block truncate text-xs text-espresso-500">{s.address}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {searching && !preview && <p className="text-xs text-espresso-500">Searching Google Maps…</p>}
        {loadingPreview && <p className="text-xs text-espresso-500">Loading details…</p>}

        {preview && (
          <div className="overflow-hidden rounded-xl border border-cream-200 bg-white">
            {preview.photoUrl && <img src={preview.photoUrl} alt={preview.name} className="h-36 w-full object-cover" />}
            <div className="space-y-0.5 px-3 py-2.5">
              <p className="text-sm font-semibold">{preview.name}</p>
              <p className="text-xs text-espresso-500">
                {preview.address}
                {preview.city ? `, ${preview.city}` : ''}
              </p>
              {preview.website && <p className="truncate text-xs text-crema-500">{preview.website}</p>}
            </div>
          </div>
        )}

        {preview?.existing && (
          <p className="rounded-xl border border-crema-400 bg-crema-400/10 px-3 py-2 text-xs text-espresso-700">
            <span className="font-semibold">{preview.existing.name}</span> is already on the map — no need to add it
            again.
          </p>
        )}

        {error && <p className="text-xs text-red-600">{error}</p>}

        {preview?.existing ? (
          <button
            onClick={() => onAdded(preview.existing!.id)}
            className="w-full rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900"
          >
            Open {preview.existing.name}
          </button>
        ) : (
          <button
            onClick={confirm}
            disabled={!user || !preview || saving || loadingPreview}
            className="w-full rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {saving ? 'Adding…' : preview ? `Add ${preview.name}` : 'Pick a shop above'}
          </button>
        )}
      </div>
    </div>
  )
}

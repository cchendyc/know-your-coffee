import { useEffect, useRef, useState } from 'react'
import { fetchShopPage, fetchShopPhotos, type CoffeeShop, type ShopPageData, type ShopPhoto } from '../api'

// Stale-while-revalidate cache for /shops/:id. Back/forward and repeat
// visits paint from here at once; a fresh copy replaces it when it lands.
const FRESH_MS = 60_000
const pages = new Map<string, { data: ShopPageData; at: number }>()
const photoSets = new Map<string, ShopPhoto[]>()

export function cacheShopPage(data: ShopPageData) {
  pages.set(data.id, { data, at: Date.now() })
}

export function invalidateShopPage(id: string) {
  pages.delete(id)
  photoSets.delete(id)
}

export type ShopPageState =
  | { status: 'loading'; shop: CoffeeShop | null }
  | { status: 'ready'; shop: ShopPageData }
  | { status: 'missing' }
  | { status: 'error'; message: string }

// `seed` is the explorer's copy of the shop (from Link state), so the
// profile card renders before the page query returns.
export function useShopPage(id: string, seed: CoffeeShop | undefined) {
  const [state, setState] = useState<ShopPageState>(() => initial(id, seed))
  const [tick, setTick] = useState(0)
  const lastId = useRef<string | null>(null)

  useEffect(() => {
    let live = true
    if (lastId.current !== id) {
      lastId.current = id
      setState(initial(id, seed))
      const cached = pages.get(id)
      if (cached && Date.now() - cached.at < FRESH_MS) return
    }
    fetchShopPage(id)
      .then((data) => {
        if (!live) return
        if (!data) {
          setState({ status: 'missing' })
          return
        }
        cacheShopPage(data)
        setState({ status: 'ready', shop: data })
      })
      // A ready page stays up on a failed revalidate.
      .catch((e: Error) => live && setState((prev) => (prev.status === 'ready' ? prev : { status: 'error', message: e.message })))
    return () => {
      live = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, tick])

  // Refetch after a report, photo upload, or confirm; keeps the current
  // page on screen while the fresh copy loads.
  const refresh = () => {
    photoSets.delete(id)
    setTick((t) => t + 1)
  }
  const patch = (fields: Partial<ShopPageData>) =>
    setState((prev) => {
      if (prev.status !== 'ready') return prev
      const next = { ...prev.shop, ...fields }
      cacheShopPage(next)
      return { status: 'ready', shop: next }
    })

  return { state, refresh, patch, version: tick }
}

function initial(id: string, seed: CoffeeShop | undefined): ShopPageState {
  const cached = pages.get(id)
  if (cached) return { status: 'ready', shop: cached.data }
  return { status: 'loading', shop: seed && seed.id === id ? seed : null }
}

// Photos load when `enabled` flips true (the section scrolls near) and
// again whenever `version` changes after a refresh.
export function useShopPhotos(id: string, enabled: boolean, version: number) {
  const [fetched, setFetched] = useState<{ id: string; photos: ShopPhoto[] } | null>(null)
  const cached = photoSets.get(id)
  useEffect(() => {
    if (!enabled || photoSets.has(id)) return
    let live = true
    fetchShopPhotos(id)
      .then((p) => {
        photoSets.set(id, p)
        if (live) setFetched({ id, photos: p })
      })
      .catch(() => live && setFetched({ id, photos: [] }))
    return () => {
      live = false
    }
  }, [id, enabled, version])
  return cached ?? (fetched?.id === id ? fetched.photos : null)
}

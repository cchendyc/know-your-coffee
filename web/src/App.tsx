import { useEffect, useState } from 'react'
import { fetchShops, type CoffeeShop, type MachineBrand, type User } from './api'
import { MACHINE_BRANDS, MACHINE_LABELS } from './labels'
import { ShopCard } from './components/ShopCard'
import { ShopDrawer } from './components/ShopDrawer'
import { MapView } from './components/MapView'
import { AuthButton, loadStoredUser } from './components/AuthButton'
import { AddShopModal } from './components/AddShopModal'

export default function App() {
  const [search, setSearch] = useState('')
  const [machine, setMachine] = useState<MachineBrand | ''>('')
  const [shops, setShops] = useState<CoffeeShop[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [view, setView] = useState<'list' | 'map'>('list')
  const [user, setUser] = useState<User | null>(loadStoredUser)
  const [adding, setAdding] = useState(false)
  const [refresh, setRefresh] = useState(0)
  const [list, setList] = useState<'all' | 'saved' | 'been'>('all')
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)

  const PAGE_SIZE = 24

  useEffect(() => {
    setPage(1)
  }, [search, machine, list, view])

  useEffect(() => {
    const t = setTimeout(() => {
      setLoading(true)
      // The map needs every match; the list paginates.
      fetchShops({
        search,
        machine,
        saved: list === 'saved',
        been: list === 'been',
        limit: view === 'map' ? 1000 : PAGE_SIZE * page,
        offset: 0,
      })
        .then((res) => {
          setShops(res.shops)
          setTotal(res.total)
          setError(null)
        })
        .catch((e: Error) => setError(e.message))
        .finally(() => setLoading(false))
    }, 200)
    return () => clearTimeout(t)
  }, [search, machine, refresh, list, view, page])

  // Patch one shop in place after a save/been toggle, keeping list filters honest.
  const onShopChanged = (updated: CoffeeShop) => {
    setShops((prev) =>
      prev
        .map((s) => (s.id === updated.id ? { ...s, ...updated } : s))
        .filter((s) => (list === 'saved' ? s.savedByMe : list === 'been' ? s.beenByMe : true)),
    )
  }

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-10 border-b border-cream-200 bg-cream-50/90 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-4 sm:px-6">
          <div className="flex size-10 items-center justify-center rounded-xl bg-espresso-700 text-cream-50">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="size-6">
              <path d="M4 8h12v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V8Z" />
              <path d="M16 9h1.5a2.5 2.5 0 0 1 0 5H16" />
              <path d="M8 3.5c0 1-1 1.5-1 2.5M12 3.5c0 1-1 1.5-1 2.5" strokeLinecap="round" />
            </svg>
          </div>
          <div className="flex-1">
            <h1 className="text-lg font-bold tracking-tight">Know Your Coffee</h1>
            <p className="text-xs text-espresso-500">coffee snobs</p>
          </div>
          <AuthButton user={user} onChange={setUser} />
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
        <div className="flex flex-col gap-3 sm:flex-row">
          <div className="relative flex-1">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-espresso-500"
            >
              <circle cx="11" cy="11" r="7" />
              <path d="m20 20-3.5-3.5" strokeLinecap="round" />
            </svg>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search shops, roasters, machines, cities…"
              className="w-full rounded-2xl border border-cream-200 bg-white py-3 pr-4 pl-12 text-sm shadow-sm outline-none placeholder:text-espresso-500/60 focus:border-crema-400 focus:ring-2 focus:ring-crema-400/40"
            />
          </div>
          <select
            value={machine}
            onChange={(e) => setMachine(e.target.value as MachineBrand | '')}
            className="rounded-2xl border border-cream-200 bg-white px-4 py-3 text-sm shadow-sm outline-none focus:border-crema-400"
          >
            <option value="">Any machine</option>
            {MACHINE_BRANDS.filter((b) => b !== 'UNKNOWN').map((b) => (
              <option key={b} value={b}>
                {MACHINE_LABELS[b]}
              </option>
            ))}
          </select>
        </div>

        {error && (
          <div className="mt-6 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            Could not reach the API: {error}. Is the backend running on port 4000?
          </div>
        )}

        {user && (
          <div className="mt-3 flex gap-1.5">
            {(
              [
                ['all', 'All shops'],
                ['saved', 'Saved'],
                ['been', 'Been'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setList(key)}
                className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                  list === key
                    ? 'bg-espresso-700 text-cream-50'
                    : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        )}

        {!error && (
          <>
            <div className="mt-6 flex items-center justify-between">
              <p className="text-sm text-espresso-500">
                {loading
                  ? 'Searching…'
                  : `${total} shop${total === 1 ? '' : 's'}${list === 'saved' ? ' saved' : list === 'been' ? ' been to' : ' in the Bay Area'}`}
              </p>
              <div className="flex rounded-xl border border-cream-200 bg-white p-0.5 text-xs font-medium shadow-sm">
                {(['list', 'map'] as const).map((v) => (
                  <button
                    key={v}
                    onClick={() => setView(v)}
                    className={`rounded-[10px] px-3 py-1.5 capitalize transition ${
                      view === v ? 'bg-espresso-700 text-cream-50' : 'text-espresso-500 hover:text-espresso-900'
                    }`}
                  >
                    {v}
                  </button>
                ))}
              </div>
            </div>
            {view === 'map' ? (
              <div className="mt-3">
                <MapView shops={shops} onSelect={setSelectedId} showLegend={!!user} />
              </div>
            ) : (
              <div className="mt-3 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {shops.map((shop) => (
                  <ShopCard
                    key={shop.id}
                    shop={shop}
                    user={user}
                    onClick={() => setSelectedId(shop.id)}
                    onChanged={onShopChanged}
                  />
                ))}
              </div>
            )}
            {view === 'list' && shops.length < total && (
              <button
                onClick={() => setPage((p) => p + 1)}
                disabled={loading}
                className="mx-auto mt-6 block rounded-2xl border border-cream-200 bg-white px-6 py-2.5 text-sm font-medium text-espresso-700 transition hover:border-crema-400 disabled:opacity-50"
              >
                {loading ? 'Loading…' : `Load more (${shops.length} of ${total})`}
              </button>
            )}
            {!loading && shops.length === 0 && view === 'list' && (
              <div className="mt-10 rounded-2xl border border-dashed border-cream-200 p-10 text-center text-sm text-espresso-500">
                {list !== 'all'
                  ? `Nothing on your ${list} list yet. Tap the bookmark or check on any shop to add it.`
                  : search || machine
                    ? 'No shops match. Try a different search or clear the filters.'
                    : 'No shops yet. Import real shops with `python -m scripts.import_shops` in backend/ (needs a Yelp or Google Places key).'}
              </div>
            )}
          </>
        )}
      </main>

      <button
        onClick={() => setAdding(true)}
        aria-label="Add a coffee shop"
        title="Add a coffee shop"
        className="fixed right-6 bottom-6 z-10 flex size-14 items-center justify-center rounded-full bg-espresso-700 text-3xl font-light text-cream-50 shadow-lg transition hover:bg-espresso-900"
      >
        +
      </button>

      {adding && (
        <AddShopModal
          user={user}
          onClose={() => setAdding(false)}
          onAdded={(id) => {
            setAdding(false)
            setRefresh((n) => n + 1)
            setSelectedId(id)
          }}
        />
      )}

      {selectedId && (
        <ShopDrawer shopId={selectedId} user={user} onShopChanged={onShopChanged} onClose={() => setSelectedId(null)} />
      )}
    </div>
  )
}

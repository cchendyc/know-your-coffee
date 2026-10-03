import { useEffect, useState } from 'react'
import { copyProducts, fetchMyProducts, type Product, type SellerShop } from '../api'
import { money, primaryBtn, secondaryBtn, ShopAvatar, StatusPill } from './hubBits'

// The server caps a page at 100; a shop past that copies in two passes.
const PAGE = 100

// Figma: "Web / Multi-shop — Copy listings". Copies start hidden at stock 0,
// so the seller confirms stock at the target before buyers see them.
export function CopyListingsModal({
  shops,
  initialFromId,
  onClose,
  onCopied,
}: {
  shops: SellerShop[]
  initialFromId: string
  onClose: () => void
  onCopied: (count: number, to: SellerShop) => void
}) {
  const [fromId, setFromId] = useState(initialFromId)
  const from = shops.find((s) => s.id === fromId) ?? shops[0]
  const targets = shops.filter((s) => s.id !== from.id)
  const [toId, setToId] = useState(() => {
    const first = shops.filter((s) => s.id !== initialFromId)
    return first.find((t) => t.sellerOnboarded)?.id ?? first[0]?.id ?? ''
  })
  const [products, setProducts] = useState<Product[] | null>(null)
  const [existing, setExisting] = useState<Set<string>>(new Set())
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Picking the target as the source swaps them rather than emptying the list.
  const pickFrom = (id: string) => {
    if (id === toId) setToId(fromId)
    setFromId(id)
  }
  const to = targets.find((t) => t.id === toId) ?? null

  useEffect(() => {
    setProducts(null)
    fetchMyProducts(from.id, undefined, 0, PAGE)
      .then((d) => {
        setProducts(d.myProducts.products)
        setPicked(new Set(d.myProducts.products.map((p) => p.id)))
      })
      .catch((e: Error) => setError(e.message))
  }, [from.id])

  // Same name + subtitle at the target reads as "already there"; unticked by default.
  useEffect(() => {
    if (!toId) return
    fetchMyProducts(toId, undefined, 0, PAGE)
      .then((d) => {
        const keys = new Set(d.myProducts.products.map(key))
        setExisting(keys)
        setPicked((prev) => new Set([...prev].filter((id) => !keys.has(key(products?.find((p) => p.id === id))))))
      })
      .catch((e: Error) => setError(e.message))
  }, [toId, products])

  const toggle = (id: string) =>
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  const selectAll = () => products && setPicked(new Set(products.filter((p) => !existing.has(key(p))).map((p) => p.id)))

  const submit = () => {
    if (!to || picked.size === 0) return
    setBusy(true)
    copyProducts(from.id, to.id, [...picked])
      .then((copied) => onCopied(copied.length, to))
      .catch((e: Error) => setError(e.message))
      .finally(() => setBusy(false))
  }

  const notReady = targets.filter((t) => !t.sellerOnboarded)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-espresso-900/40 p-4" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div role="dialog" aria-modal="true" className="flex max-h-[90vh] w-full max-w-lg flex-col overflow-hidden rounded-2xl bg-white shadow-xl">
        <div className="flex items-start gap-3 px-5 pt-5">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-cream-100 text-espresso-700">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" className="size-4">
              <path d="M8 8h12v12H8zM4 16V4h12" />
            </svg>
          </span>
          <div className="min-w-0 flex-1">
            <h2 className="text-base font-bold">Copy listings to another shop</h2>
            <p className="text-xs text-espresso-500">
              From {from.name} · {from.city}
            </p>
          </div>
          <button onClick={onClose} aria-label="Close" className="text-espresso-500 hover:text-espresso-900">
            ✕
          </button>
        </div>

        <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
          <div className="flex flex-col gap-3">
            <ShopSelect label="Copy from" value={from.id} options={shops} onChange={pickFrom} />
            <ShopSelect label="Copy to" value={toId} options={targets} onChange={setToId} verified={to?.sellerOnboarded ?? false} />
          </div>
          <p className="-mt-2 text-[11px] text-espresso-500">
            Only shops you own appear here.
            {notReady.length > 0 && ` ${notReady.map((t) => t.name).join(', ')} needs setup before buyers can see copies.`}
          </p>

          {error && <p className="rounded-xl bg-danger-100 px-3 py-2 text-xs text-danger-700">{error}</p>}

          <div>
            <div className="mb-2 flex items-center justify-between text-xs">
              <span className="font-semibold text-espresso-500">
                {products ? `${products.length} listings · ${picked.size} selected` : 'Loading listings…'}
              </span>
              <button onClick={selectAll} className="font-medium text-crema-500 hover:text-espresso-900">
                Select all
              </button>
            </div>
            <ul className="divide-y divide-cream-200 rounded-xl border border-cream-200">
              {products?.map((p) => {
                const there = existing.has(key(p))
                return (
                  <li key={p.id}>
                    <label className={`flex items-center gap-3 px-3 py-2.5 ${there ? 'opacity-60' : 'cursor-pointer hover:bg-cream-100/60'}`}>
                      <input type="checkbox" checked={picked.has(p.id)} onChange={() => toggle(p.id)} className="size-4 accent-espresso-700" />
                      {p.coverPhoto ? (
                        <img src={p.coverPhoto.data} alt="" className="size-8 shrink-0 rounded-lg object-cover" />
                      ) : (
                        <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-cream-100 text-sm">☕️</span>
                      )}
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-semibold">{p.name}</span>
                        <span className="block truncate text-[11px] text-espresso-500">
                          {[p.subtitle, money(p.price)].filter(Boolean).join(' · ')}
                        </span>
                      </span>
                      {there && to && <StatusPill tone="muted">{`Already at ${to.name.split(' ')[0]}`}</StatusPill>}
                    </label>
                  </li>
                )
              })}
              {products && products.length === 0 && <li className="px-3 py-8 text-center text-sm text-espresso-500">No listings to copy yet.</li>}
            </ul>
          </div>

          <p className="rounded-xl bg-cream-100 px-3.5 py-2.5 text-[11px] leading-relaxed text-espresso-700">
            Copies keep the name, category, details, description, price, photos and low-stock alert. Quantity starts at 0 and each copy stays
            hidden until you set a quantity and list it{to ? ` at ${to.name}` : ''}.
          </p>
        </div>

        <div className="flex justify-end gap-2 border-t border-cream-200 bg-cream-50 px-5 py-3.5">
          <button onClick={onClose} className={secondaryBtn}>
            Cancel
          </button>
          <button onClick={submit} disabled={busy || !to || picked.size === 0} className={primaryBtn}>
            {busy ? 'Copying…' : `Copy ${picked.size} ${picked.size === 1 ? 'listing' : 'listings'}${to ? ` to ${to.name.split(' ')[0]}` : ''}`}
          </button>
        </div>
      </div>
    </div>
  )
}

function ShopSelect({
  label,
  value,
  options,
  onChange,
  verified = false,
}: {
  label: string
  value: string
  options: SellerShop[]
  onChange: (id: string) => void
  verified?: boolean
}) {
  const current = options.find((o) => o.id === value)
  return (
    <label className="flex min-w-0 flex-col gap-1.5 text-xs font-semibold text-espresso-500">
      {label}
      <span className="flex min-w-0 items-center gap-2 rounded-xl border border-cream-200 px-3 py-2">
        {current && <ShopAvatar name={current.name} size="sm" />}
        <select value={value} onChange={(e) => onChange(e.target.value)} className="min-w-0 flex-1 bg-transparent text-sm font-semibold text-espresso-900 outline-none">
          {options.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name} · {t.address}, {t.city}
              {t.sellerOnboarded ? '' : ' (needs setup)'}
            </option>
          ))}
        </select>
        {verified && <StatusPill tone="ok">Verified</StatusPill>}
      </span>
    </label>
  )
}

const key = (p: Product | undefined) => (p ? `${p.name.trim().toLowerCase()}|${(p.subtitle ?? '').trim().toLowerCase()}` : '')

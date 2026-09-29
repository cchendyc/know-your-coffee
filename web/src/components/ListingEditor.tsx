import { useEffect, useRef, useState } from 'react'
import {
  createProduct,
  deleteProduct,
  fetchProduct,
  MAX_PRODUCT_PHOTOS,
  setProductPhotos,
  updateProduct,
  type Product,
} from '../api'
import { downscaleImage } from '../image'

// Full-pane listing form for the Seller Hub: create or edit one product,
// with a live preview of the card buyers see. Replaces the old inline row.

const input =
  'w-full rounded-xl border border-cream-200 bg-white px-3.5 py-2.5 text-sm outline-none placeholder:text-espresso-500/60 focus:border-crema-400'
const fieldLabel = 'flex flex-col gap-1.5 text-xs font-semibold text-espresso-500'
const card = 'rounded-2xl border border-cream-200 bg-white p-5 shadow-sm'

const money = (n: number) => `$${n.toFixed(2)}`

// id is set for photos already on the server; new uploads carry only data.
type Slot = { key: string; id?: string; data: string }

export function ListingEditor({
  shopId,
  shopName,
  product,
  onDone,
  onCancel,
}: {
  shopId: string
  shopName: string
  product: Product | null // null = new listing
  onDone: () => void
  onCancel: () => void
}) {
  const [name, setName] = useState(product?.name ?? '')
  const [variant, setVariant] = useState(product?.variant ?? '')
  const [price, setPrice] = useState(product ? String(product.price) : '')
  const [stockQty, setStockQty] = useState(product ? String(product.stockQty) : '1')
  const [threshold, setThreshold] = useState(product ? String(product.lowStockThreshold) : '5')
  const [active, setActive] = useState(product?.active ?? true)
  const [photos, setPhotos] = useState<Slot[]>([])
  const [photosDirty, setPhotosDirty] = useState(false)
  const [loadingPhotos, setLoadingPhotos] = useState(Boolean(product))
  const [uploading, setUploading] = useState(false)
  const [busy, setBusy] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  // The list query only carries the cover; the editor needs every photo.
  useEffect(() => {
    if (!product) return
    fetchProduct(product.id)
      .then((full) => {
        if (full) setPhotos(full.photos!.map((p) => ({ key: p.id, id: p.id, data: p.data })))
      })
      .catch((e: Error) => setError(e.message))
      .finally(() => setLoadingPhotos(false))
  }, [product])

  const addFiles = async (files: FileList | null) => {
    if (!files?.length) return
    const room = MAX_PRODUCT_PHOTOS - photos.length
    if (room <= 0) {
      setError(`A listing can have at most ${MAX_PRODUCT_PHOTOS} photos.`)
      return
    }
    setUploading(true)
    setError(null)
    try {
      const picked = Array.from(files).slice(0, room)
      const added = await Promise.all(
        picked.map(async (f) => ({ key: `${f.name}-${f.lastModified}-${Math.random()}`, data: await downscaleImage(f) })),
      )
      setPhotos((prev) => [...prev, ...added])
      setPhotosDirty(true)
      if (files.length > room) setError(`Only the first ${room} were added — ${MAX_PRODUCT_PHOTOS} photos max.`)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setUploading(false)
      if (fileInput.current) fileInput.current.value = ''
    }
  }

  const movePhoto = (from: number, to: number) => {
    if (to < 0 || to >= photos.length) return
    setPhotos((prev) => {
      const next = [...prev]
      const [moved] = next.splice(from, 1)
      next.splice(to, 0, moved)
      return next
    })
    setPhotosDirty(true)
  }

  const removePhoto = (index: number) => {
    setPhotos((prev) => prev.filter((_, i) => i !== index))
    setPhotosDirty(true)
  }

  const priceNum = parseFloat(price)
  const stockNum = parseInt(stockQty, 10)
  const thresholdNum = parseInt(threshold, 10)
  const problems = [
    !name.trim() && 'Give the listing a name.',
    (Number.isNaN(priceNum) || priceNum <= 0) && 'Price must be more than $0.',
    (Number.isNaN(stockNum) || stockNum < 0) && 'Quantity must be 0 or more.',
    (Number.isNaN(thresholdNum) || thresholdNum < 0) && 'Low-stock alert must be 0 or more.',
  ].filter((p): p is string => Boolean(p))

  const save = async () => {
    if (problems.length) {
      setError(problems[0])
      return
    }
    setBusy(true)
    setError(null)
    const payload = {
      name: name.trim(),
      variant: variant.trim() || null,
      price: priceNum,
      stockQty: stockNum,
      lowStockThreshold: thresholdNum,
      active,
    }
    try {
      const saved = product ? await updateProduct(product.id, payload) : await createProduct(shopId, payload)
      if (photosDirty || (!product && photos.length)) {
        await setProductPhotos(
          saved.id,
          photos.map((p) => (p.id ? { id: p.id } : { data: p.data })),
        )
      }
      onDone()
    } catch (e) {
      setError((e as Error).message)
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!product) return
    setBusy(true)
    try {
      await deleteProduct(product.id)
      onDone()
    } catch (e) {
      setError((e as Error).message)
      setBusy(false)
    }
  }

  const previewLow = !Number.isNaN(stockNum) && !Number.isNaN(thresholdNum) && stockNum <= thresholdNum

  return (
    <section>
      <button
        onClick={onCancel}
        className="mb-4 flex items-center gap-1 text-xs font-medium text-espresso-500 hover:text-espresso-900"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="size-3.5">
          <path d="M15 5l-7 7 7 7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Products
      </button>
      <div className="mb-5 flex items-center justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold tracking-tight">{product ? 'Edit listing' : 'New listing'}</h2>
          <p className="mt-0.5 text-sm text-espresso-500">
            {product ? 'Changes go live as soon as you save.' : `What are you selling from ${shopName}?`}
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-xl border border-danger-200 bg-danger-100 px-4 py-3 text-sm text-danger-700">{error}</div>
      )}

      <div className="grid gap-5 lg:grid-cols-[1fr_320px]">
        <form
          className="flex flex-col gap-5"
          onSubmit={(e) => {
            e.preventDefault()
            void save()
          }}
        >
          <div className={card}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold">Photos</h3>
              <span className="text-xs text-espresso-500">
                {photos.length}/{MAX_PRODUCT_PHOTOS}
              </span>
            </div>
            <p className="mt-0.5 text-xs text-espresso-500">The first photo is the cover. Reorder with the arrows.</p>
            <input
              ref={fileInput}
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              onChange={(e) => void addFiles(e.target.files)}
            />
            <div className="mt-4 grid grid-cols-3 gap-2 sm:grid-cols-6">
              {photos.map((p, i) => (
                <figure key={p.key} className="group relative aspect-square overflow-hidden rounded-xl border border-cream-200">
                  <img src={p.data} alt="" className="size-full object-cover" />
                  {i === 0 && (
                    <span className="absolute top-1.5 left-1.5 rounded-full bg-espresso-900/80 px-2 py-0.5 text-[10px] font-semibold text-cream-50">
                      Cover
                    </span>
                  )}
                  <div className="absolute inset-x-0 bottom-0 flex justify-between bg-espresso-900/70 p-1 opacity-0 transition group-hover:opacity-100">
                    <button type="button" onClick={() => movePhoto(i, i - 1)} disabled={i === 0} aria-label="Move left" className="px-1 text-xs text-cream-50 disabled:opacity-30">
                      ←
                    </button>
                    <button type="button" onClick={() => removePhoto(i)} aria-label="Remove photo" className="px-1 text-xs text-cream-50">
                      ✕
                    </button>
                    <button type="button" onClick={() => movePhoto(i, i + 1)} disabled={i === photos.length - 1} aria-label="Move right" className="px-1 text-xs text-cream-50 disabled:opacity-30">
                      →
                    </button>
                  </div>
                </figure>
              ))}
              {loadingPhotos &&
                [0, 1].map((i) => <div key={i} className="aspect-square animate-pulse rounded-xl bg-cream-100" />)}
              {!loadingPhotos && photos.length < MAX_PRODUCT_PHOTOS && (
                <button
                  type="button"
                  onClick={() => fileInput.current?.click()}
                  disabled={uploading}
                  className="flex aspect-square flex-col items-center justify-center gap-1 rounded-xl border border-dashed border-cream-200 text-espresso-500 transition hover:border-crema-400 hover:text-espresso-900 disabled:opacity-50"
                >
                  <span className="text-xl leading-none">{uploading ? '…' : '+'}</span>
                  <span className="text-[10px] font-medium">{uploading ? 'Resizing' : 'Add'}</span>
                </button>
              )}
            </div>
          </div>

          <div className={card}>
            <h3 className="font-bold">The item</h3>
            <div className="mt-4 flex flex-col gap-3">
              <label className={fieldLabel}>
                Name
                <input className={input} value={name} onChange={(e) => setName(e.target.value)} placeholder="Urcunina, Colombia" autoFocus />
              </label>
              <label className={fieldLabel}>
                Variant (optional)
                <input className={input} value={variant} onChange={(e) => setVariant(e.target.value)} placeholder="12 oz whole bean" />
                <span className="font-normal text-espresso-500/80">Size, grind, roast date — anything that tells one option from another.</span>
              </label>
            </div>
          </div>

          <div className={card}>
            <h3 className="font-bold">Price and stock</h3>
            <div className="mt-4 grid gap-3 sm:grid-cols-3">
              <label className={fieldLabel}>
                Price
                <div className="relative">
                  <span className="pointer-events-none absolute top-1/2 left-3.5 -translate-y-1/2 text-sm text-espresso-500">$</span>
                  <input
                    className={`${input} pl-7`}
                    value={price}
                    onChange={(e) => setPrice(e.target.value)}
                    placeholder="22.00"
                    inputMode="decimal"
                  />
                </div>
              </label>
              <label className={fieldLabel}>
                Quantity
                <input className={input} value={stockQty} onChange={(e) => setStockQty(e.target.value)} inputMode="numeric" />
              </label>
              <label className={fieldLabel}>
                Low-stock alert at
                <input className={input} value={threshold} onChange={(e) => setThreshold(e.target.value)} inputMode="numeric" />
              </label>
            </div>
            <p className="mt-3 text-[11px] text-espresso-500">
              Stock drops automatically with each order and comes back if a buyer cancels.
            </p>
          </div>

          <div className={card}>
            <h3 className="font-bold">Visibility</h3>
            <div className="mt-4 flex gap-2">
              {(
                [
                  [true, 'Listed', 'Buyers can see and order it.'],
                  [false, 'Hidden', 'Saved, but not shown in your shop.'],
                ] as const
              ).map(([value, label, hint]) => (
                <button
                  key={label}
                  type="button"
                  onClick={() => setActive(value)}
                  className={`flex-1 rounded-xl border px-4 py-3 text-left transition ${
                    active === value ? 'border-crema-500 bg-crema-400/10' : 'border-cream-200 hover:border-crema-400'
                  }`}
                >
                  <p className="text-sm font-semibold">{label}</p>
                  <p className="text-[11px] text-espresso-500">{hint}</p>
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="submit"
              disabled={busy}
              className="rounded-xl bg-espresso-700 px-5 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40"
            >
              {busy ? 'Saving…' : product ? 'Save changes' : 'Publish listing'}
            </button>
            <button
              type="button"
              onClick={onCancel}
              disabled={busy}
              className="rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-medium text-espresso-500 hover:border-crema-400"
            >
              Cancel
            </button>
            {product && (
              <div className="ml-auto flex items-center gap-2">
                {confirmDelete ? (
                  <>
                    <span className="text-xs text-espresso-500">Delete this listing?</span>
                    <button
                      type="button"
                      onClick={() => void remove()}
                      disabled={busy}
                      className="rounded-xl bg-danger-600 px-3.5 py-2 text-xs font-semibold text-white hover:bg-danger-700"
                    >
                      Yes, delete
                    </button>
                    <button type="button" onClick={() => setConfirmDelete(false)} className="text-xs font-medium text-espresso-500">
                      Keep
                    </button>
                  </>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirmDelete(true)}
                    className="text-xs font-medium text-danger-600 hover:text-danger-700"
                  >
                    Delete listing
                  </button>
                )}
              </div>
            )}
          </div>
        </form>

        <aside className="lg:sticky lg:top-24 lg:self-start">
          <p className="mb-2 text-[11px] font-semibold tracking-wider text-espresso-500 uppercase">Buyer preview</p>
          <div className={`${card} ${active ? '' : 'opacity-60'}`}>
            {photos[0] ? (
              <img src={photos[0].data} alt="" className="h-40 w-full rounded-xl object-cover" />
            ) : (
              <div className="flex h-40 items-center justify-center rounded-xl bg-cream-100 text-3xl">☕️</div>
            )}
            <p className="mt-3 truncate font-semibold">{name.trim() || 'Listing name'}</p>
            <p className="truncate text-xs text-espresso-500">{variant.trim() || shopName}</p>
            <div className="mt-3 flex items-center justify-between">
              <span className="text-lg font-bold tabular-nums">{Number.isNaN(priceNum) ? '$—' : money(priceNum)}</span>
              {!active ? (
                <span className="rounded-full bg-cream-100 px-2.5 py-1 text-xs font-semibold text-espresso-500">Hidden</span>
              ) : stockNum === 0 ? (
                <span className="rounded-full bg-cream-100 px-2.5 py-1 text-xs font-semibold text-espresso-500">Sold out</span>
              ) : previewLow ? (
                <span className="rounded-full bg-warn-100 px-2.5 py-1 text-xs font-semibold text-warn-700">Only {stockNum} left</span>
              ) : (
                <span className="rounded-full bg-ok-100 px-2.5 py-1 text-xs font-semibold text-ok-700">In stock</span>
              )}
            </div>
          </div>
        </aside>
      </div>
    </section>
  )
}

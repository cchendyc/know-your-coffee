import { useState } from 'react'
import {
  addShopPhotos,
  identifyMachine,
  parseMenu,
  submitReport,
  type BeanSource,
  type CoffeeShop,
  type MachineBrand,
  type MachineGuess,
  type PhotoKind,
} from '../api'
import { downscaleImage } from '../image'
import {
  AMENITIES,
  BEAN_ORIGINS,
  BEAN_SOURCES,
  BEAN_SOURCE_LABELS,
  DRINKS,
  GRINDERS,
  MACHINE_BRANDS,
  MACHINE_LABELS,
  MILK_BRANDS,
  PHOTO_KINDS,
  PHOTO_KIND_LABELS,
  type AmenityKey,
} from '../labels'

const inputCls =
  'w-full rounded-xl border border-cream-200 bg-white px-3 py-2 text-sm outline-none focus:border-crema-400 focus:ring-2 focus:ring-crema-400/40'

interface DrinkEntry {
  name: string
  price: string
}

function toggle(list: string[], value: string): string[] {
  return list.includes(value) ? list.filter((x) => x !== value) : [...list, value]
}

function splitCustom(text: string): string[] {
  return text.split(',').map((s) => s.trim()).filter(Boolean)
}

function Chips({
  options,
  selected,
  onToggle,
}: {
  options: string[]
  selected: string[]
  onToggle: (value: string) => void
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map((o) => (
        <button
          key={o}
          type="button"
          onClick={() => onToggle(o)}
          className={`rounded-full px-2.5 py-1 text-xs font-medium transition ${
            selected.includes(o)
              ? 'bg-espresso-700 text-cream-50'
              : 'border border-cream-200 text-espresso-500 hover:border-crema-400'
          }`}
        >
          {o}
        </button>
      ))}
    </div>
  )
}

export function ReportForm({ shop, onDone, onCancel }: { shop: CoffeeShop; onDone: () => void; onCancel: () => void }) {
  const [machine, setMachine] = useState<MachineBrand | ''>('')
  const [otherBrand, setOtherBrand] = useState('')
  const [machineModel, setMachineModel] = useState('')
  const [beanSource, setBeanSource] = useState<BeanSource | ''>('')
  const [roaster, setRoaster] = useState('')
  const [beanOrigins, setBeanOrigins] = useState<string[]>([])
  const [customOrigins, setCustomOrigins] = useState('')
  const [grinders, setGrinders] = useState<string[]>([])
  const [customGrinders, setCustomGrinders] = useState('')
  const [drinks, setDrinks] = useState<DrinkEntry[]>([])
  const [parsingMenu, setParsingMenu] = useState(false)
  const [milkBrands, setMilkBrands] = useState<string[]>([])
  const [customMilk, setCustomMilk] = useState('')
  const [amenities, setAmenities] = useState<Record<AmenityKey, boolean | null>>({
    dogFriendly: null,
    wifi: null,
    outdoorSeating: null,
  })
  const [photos, setPhotos] = useState<{ kind: PhotoKind; data: string }[]>([])
  const [photoKind, setPhotoKind] = useState<PhotoKind>('VIBE')
  const [note, setNote] = useState('')
  const [usedPhoto, setUsedPhoto] = useState(false)
  const [identifying, setIdentifying] = useState(false)
  const [guess, setGuess] = useState<MachineGuess | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const allMilkBrands = () => [...milkBrands, ...splitCustom(customMilk)]
  const allOrigins = () => [...beanOrigins, ...splitCustom(customOrigins)]
  const allGrinders = () => [...grinders, ...splitCustom(customGrinders)]
  const cleanDrinks = () =>
    drinks
      .filter((d) => d.name.trim())
      .map((d) => {
        const price = Number.parseFloat(d.price)
        return { name: d.name.trim(), price: Number.isFinite(price) ? price : null }
      })

  const toggleDrink = (name: string) =>
    setDrinks((prev) =>
      prev.some((d) => d.name === name) ? prev.filter((d) => d.name !== name) : [...prev, { name, price: '' }],
    )

  const setDrinkPrice = (name: string, price: string) =>
    setDrinks((prev) => prev.map((d) => (d.name === name ? { ...d, price } : d)))

  const onMachinePhoto = async (file: File | undefined) => {
    if (!file) return
    setIdentifying(true)
    setGuess(null)
    setError(null)
    try {
      const data = await downscaleImage(file)
      setPhotos((prev) => [...prev, { kind: 'MACHINE', data }])
      const result = await identifyMachine(data)
      setGuess(result)
      if (result.machine !== 'UNKNOWN') {
        setMachine(result.machine)
        if (result.machineModel) setMachineModel(result.machineModel)
        setUsedPhoto(true)
      }
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setIdentifying(false)
    }
  }

  const onExtraPhotos = async (files: FileList | null) => {
    if (!files?.length) return
    setError(null)
    try {
      const added = await Promise.all([...files].map((f) => downscaleImage(f)))
      setPhotos((prev) => [...prev, ...added.map((data) => ({ kind: photoKind, data }))])
    } catch (e) {
      setError((e as Error).message)
    }
  }

  const onMenuPhoto = async (file: File | undefined) => {
    if (!file) return
    setParsingMenu(true)
    setError(null)
    try {
      const data = await downscaleImage(file)
      setPhotos((prev) => [...prev, { kind: 'MENU', data }])
      const items = await parseMenu(data)
      if (items.length === 0) {
        setError('No drinks found on that photo. Is it a menu?')
      } else {
        setDrinks((prev) => {
          const existing = new Set(prev.map((d) => d.name.toLowerCase()))
          const added = items
            .filter((i) => !existing.has(i.name.toLowerCase()))
            .map((i) => ({ name: i.name, price: i.price != null ? String(i.price) : '' }))
          return [...prev, ...added]
        })
        setUsedPhoto(true)
      }
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setParsingMenu(false)
    }
  }

  const onSubmit = async () => {
    setSaving(true)
    setError(null)
    try {
      const milk = allMilkBrands()
      const origins = allOrigins()
      const grinderList = allGrinders()
      const drinkList = cleanDrinks()
      // OTHER machines carry their brand as a model prefix, e.g. "Astoria Storm".
      const model = machine === 'OTHER' ? `${otherBrand.trim()} ${machineModel.trim()}`.trim() : machineModel.trim()
      await submitReport({
        shopId: shop.id,
        machine: machine || null,
        machineModel: model || null,
        beanSource: beanSource || null,
        roaster: roaster.trim() || null,
        beanOrigins: origins.length ? origins : null,
        grinders: grinderList.length ? grinderList : null,
        drinks: drinkList.length ? drinkList : null,
        milkBrands: milk.length ? milk : null,
        dogFriendly: amenities.dogFriendly,
        wifi: amenities.wifi,
        outdoorSeating: amenities.outdoorSeating,
        note: note.trim() || null,
        source: usedPhoto ? 'PHOTO' : 'TEXT',
      })
      if (photos.length) await addShopPhotos(shop.id, photos)
      onDone()
    } catch (e) {
      setError((e as Error).message)
      setSaving(false)
    }
  }

  const hasAnything =
    machine ||
    machineModel.trim() ||
    beanSource ||
    roaster.trim() ||
    allOrigins().length ||
    allGrinders().length ||
    cleanDrinks().length ||
    allMilkBrands().length ||
    Object.values(amenities).some((v) => v !== null) ||
    photos.length ||
    note.trim()

  return (
    <div className="space-y-4 rounded-2xl border border-cream-200 bg-white p-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Report an update</h3>
        <button onClick={onCancel} className="text-xs text-espresso-500 hover:underline">
          Cancel
        </button>
      </div>

      <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-crema-400 bg-crema-400/10 px-3 py-3 text-sm font-medium text-espresso-700 transition hover:bg-crema-400/20">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="size-5">
          <path d="M4 8a2 2 0 0 1 2-2h1.5l1-2h7l1 2H18a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8Z" />
          <circle cx="12" cy="12.5" r="3.5" />
        </svg>
        {identifying ? 'Identifying machine…' : 'Snap the espresso machine to auto-identify'}
        <input
          type="file"
          accept="image/*"
          capture="environment"
          className="hidden"
          disabled={identifying}
          onChange={(e) => onMachinePhoto(e.target.files?.[0])}
        />
      </label>

      {guess && (
        <p className="rounded-xl bg-cream-100 px-3 py-2 text-xs text-espresso-700">
          {guess.machine === 'UNKNOWN'
            ? (guess.notes ?? 'Could not identify a machine in that photo.')
            : `Looks like a ${MACHINE_LABELS[guess.machine]}${guess.machineModel ? ` ${guess.machineModel}` : ''} (${Math.round(guess.confidence * 100)}% confident). Fields pre-filled below.`}
        </p>
      )}

      <div className="grid grid-cols-2 gap-3">
        <select value={machine} onChange={(e) => setMachine(e.target.value as MachineBrand | '')} className={inputCls}>
          <option value="">Machine brand…</option>
          {MACHINE_BRANDS.map((b) => (
            <option key={b} value={b}>
              {MACHINE_LABELS[b]}
            </option>
          ))}
        </select>
        {machine === 'OTHER' && (
          <input
            value={otherBrand}
            onChange={(e) => setOtherBrand(e.target.value)}
            placeholder="Brand (e.g. Astoria)"
            className={inputCls}
          />
        )}
        <input
          value={machineModel}
          onChange={(e) => setMachineModel(e.target.value)}
          placeholder="Model (e.g. Linea PB)"
          className={inputCls}
        />
        <select
          value={beanSource}
          onChange={(e) => setBeanSource(e.target.value as BeanSource | '')}
          className={inputCls}
        >
          <option value="">Bean source…</option>
          {BEAN_SOURCES.map((b) => (
            <option key={b} value={b}>
              {BEAN_SOURCE_LABELS[b]}
            </option>
          ))}
        </select>
        <input
          value={roaster}
          onChange={(e) => setRoaster(e.target.value)}
          placeholder="Roaster (e.g. Sightglass)"
          className={inputCls}
        />
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Bean origins</p>
        <Chips options={BEAN_ORIGINS} selected={beanOrigins} onToggle={(o) => setBeanOrigins((p) => toggle(p, o))} />
        <input
          value={customOrigins}
          onChange={(e) => setCustomOrigins(e.target.value)}
          placeholder="Other origins (comma separated)"
          className={inputCls}
        />
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Grinders</p>
        <Chips options={GRINDERS} selected={grinders} onToggle={(g) => setGrinders((p) => toggle(p, g))} />
        <input
          value={customGrinders}
          onChange={(e) => setCustomGrinders(e.target.value)}
          placeholder="Other grinders (comma separated)"
          className={inputCls}
        />
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Drinks on the menu</p>
        <Chips
          options={DRINKS}
          selected={drinks.map((d) => d.name)}
          onToggle={toggleDrink}
        />
        <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-cream-200 px-3 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-700">
          {parsingMenu ? 'Reading the menu…' : 'Or snap the menu to import drinks & prices'}
          <input
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            disabled={parsingMenu}
            onChange={(e) => onMenuPhoto(e.target.files?.[0])}
          />
        </label>
        {drinks.length > 0 && (
          <ul className="space-y-1">
            {drinks.map((d) => (
              <li key={d.name} className="flex items-center gap-2">
                <span className="flex-1 truncate text-sm">{d.name}</span>
                <input
                  value={d.price}
                  onChange={(e) => setDrinkPrice(d.name, e.target.value)}
                  placeholder="$"
                  inputMode="decimal"
                  className="w-20 rounded-lg border border-cream-200 px-2 py-1 text-right text-sm outline-none focus:border-crema-400"
                />
                <button
                  type="button"
                  onClick={() => toggleDrink(d.name)}
                  aria-label={`Remove ${d.name}`}
                  className="text-espresso-500 hover:text-red-600"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Milk brands spotted</p>
        <Chips options={MILK_BRANDS} selected={milkBrands} onToggle={(b) => setMilkBrands((p) => toggle(p, b))} />
        <input
          value={customMilk}
          onChange={(e) => setCustomMilk(e.target.value)}
          placeholder="Other milk brands (comma separated)"
          className={inputCls}
        />
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Good to know</p>
        <div className="space-y-1">
          {AMENITIES.map((a) => (
            <div key={a.key} className="flex items-center justify-between gap-2">
              <span className="text-sm">{a.label}</span>
              <div className="flex gap-1">
                {([true, false] as const).map((v) => (
                  <button
                    key={String(v)}
                    type="button"
                    onClick={() =>
                      // Tapping the active answer clears it back to unknown.
                      setAmenities((prev) => ({ ...prev, [a.key]: prev[a.key] === v ? null : v }))
                    }
                    className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                      amenities[a.key] === v
                        ? 'bg-espresso-700 text-cream-50'
                        : 'border border-cream-200 text-espresso-500 hover:border-crema-400'
                    }`}
                  >
                    {v ? 'Yes' : 'No'}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-medium text-espresso-500">Photos for the shop's gallery</p>
        <div className="flex gap-2">
          <select
            value={photoKind}
            onChange={(e) => setPhotoKind(e.target.value as PhotoKind)}
            className={`${inputCls} w-auto`}
          >
            {PHOTO_KINDS.map((k) => (
              <option key={k} value={k}>
                {PHOTO_KIND_LABELS[k]}
              </option>
            ))}
          </select>
          <label className="flex flex-1 cursor-pointer items-center justify-center rounded-xl border border-dashed border-cream-200 px-3 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-700">
            Add photos…
            <input
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              onChange={(e) => {
                onExtraPhotos(e.target.files)
                e.target.value = ''
              }}
            />
          </label>
        </div>
        {photos.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {photos.map((p, i) => (
              <div key={i} className="relative">
                <img src={p.data} alt="" className="size-16 rounded-lg object-cover" />
                <span className="absolute bottom-0.5 left-0.5 rounded bg-espresso-900/70 px-1 text-[9px] font-medium text-cream-50">
                  {PHOTO_KIND_LABELS[p.kind]}
                </span>
                <button
                  type="button"
                  onClick={() => setPhotos((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="Remove photo"
                  className="absolute -top-1.5 -right-1.5 flex size-4 items-center justify-center rounded-full bg-espresso-700 text-[10px] text-cream-50"
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Anything else worth knowing?"
        rows={2}
        className={inputCls}
      />

      {error && <p className="text-xs text-red-600">{error}</p>}

      <button
        onClick={onSubmit}
        disabled={saving || !hasAnything}
        className="w-full rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:cursor-not-allowed disabled:opacity-40"
      >
        {saving ? 'Submitting…' : 'Submit report'}
      </button>
    </div>
  )
}

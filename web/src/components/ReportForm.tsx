import { useState, type ReactNode } from 'react'
import {
  addShopPhotos,
  identifyMachine,
  parseMenu,
  submitReport,
  type BeanSource,
  type CoffeeProcess,
  type CoffeeShop,
  type CoffeeType,
  type MachineBrand,
  type MachineGuess,
  type PhotoKind,
  type RoastLevel,
} from '../api'
import { downscaleImage } from '../image'
import {
  AMENITIES,
  BEAN_SOURCES,
  BEAN_SOURCE_LABELS,
  COFFEE_PROCESSES,
  COFFEE_TYPES,
  COFFEE_TYPE_LABELS,
  DRINKS,
  FERMENTATION_SUGGESTIONS,
  GRINDER_BRANDS,
  MACHINE_BRANDS,
  MACHINE_LABELS,
  MILK_BRANDS,
  ORIGIN_COUNTRIES,
  PHOTO_KIND_LABELS,
  PROCESS_LABELS,
  ROAST_LEVELS,
  ROAST_LEVEL_LABELS,
  type AmenityKey,
} from '../labels'

const inputCls =
  'w-full rounded-xl border border-cream-200 bg-white px-3 py-2 text-sm outline-none focus:border-crema-400 focus:ring-2 focus:ring-crema-400/40'

interface DrinkEntry {
  name: string
  price: string
}

// One grinder on bar; submits as one string, "brand model".
interface GrinderEntry {
  brand: string
  model: string
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
              : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
          }`}
        >
          {o}
        </button>
      ))}
    </div>
  )
}

// One-of chips; tapping the active value clears it back to unknown.
function EnumChips<T extends string>({
  options,
  labels,
  value,
  onChange,
}: {
  options: readonly T[]
  labels: Record<T, string>
  value: T | null
  onChange: (value: T | null) => void
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map((o) => (
        <button
          key={o}
          type="button"
          onClick={() => onChange(value === o ? null : o)}
          className={`rounded-full px-2.5 py-1 text-xs font-medium transition ${
            value === o
              ? 'bg-espresso-700 text-cream-50'
              : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
          }`}
        >
          {labels[o]}
        </button>
      ))}
    </div>
  )
}

// Single-select dropdown; picking the active value again clears it.
function EnumSelect<T extends string>({
  options,
  labels,
  value,
  placeholder,
  onChange,
}: {
  options: readonly T[]
  labels: Record<T, string>
  value: T | null
  placeholder: string
  onChange: (value: T | null) => void
}) {
  const [open, setOpen] = useState(false)
  return (
    <div className="relative flex-1">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        onBlur={() => setOpen(false)}
        className={`${inputCls} flex items-center justify-between text-left ${value ? '' : 'text-espresso-500/60'}`}
      >
        {value ? labels[value] : placeholder}
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className={`size-3.5 shrink-0 text-espresso-500 transition-transform ${open ? 'rotate-180' : ''}`}
        >
          <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open && (
        <ul className="absolute z-10 mt-1 max-h-48 w-full overflow-y-auto rounded-xl border border-cream-200 bg-white py-1 shadow-lg">
          {options.map((o) => (
            <li key={o}>
              <button
                type="button"
                // mousedown fires before the button's blur closes the list.
                onMouseDown={(e) => {
                  e.preventDefault()
                  onChange(value === o ? null : o)
                  setOpen(false)
                }}
                className="flex w-full items-center justify-between px-3 py-1.5 text-left text-sm hover:bg-cream-100"
              >
                {labels[o]}
                {value === o && <span className="text-crema-500">✓</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

// Row label matching the Figma micro-label style.
function RowLabel({ children }: { children: string }) {
  return (
    <span className="w-16 shrink-0 text-[10px] font-semibold tracking-wide text-espresso-500 uppercase">{children}</span>
  )
}

// Section card that collapses to a single row, per the Figma report modal.
function Collapsible({
  title,
  hint,
  open,
  onToggle,
  children,
}: {
  title: string
  hint?: string
  open: boolean
  onToggle: () => void
  children: ReactNode
}) {
  return (
    <div className={`rounded-2xl border bg-white ${open ? 'border-crema-400' : 'border-cream-200'}`}>
      <button type="button" onClick={onToggle} className="flex w-full items-center justify-between px-4 py-3">
        <span className={`text-sm font-medium ${open ? 'text-espresso-900' : 'text-espresso-500'}`}>{title}</span>
        <span className="flex items-center gap-2">
          {hint && <span className="text-[11px] text-crema-500">{hint}</span>}
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            className={`size-4 text-espresso-500 transition-transform ${open ? 'rotate-180' : ''}`}
          >
            <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
      </button>
      {open && <div className="space-y-3 px-4 pb-4">{children}</div>}
    </div>
  )
}

// Draft of one coffee card; strings stay raw until submit.
interface CoffeeDraft {
  name: string
  type: CoffeeType | null
  origins: string[]
  process: CoffeeProcess | null
  fermentation: string
  roastLevel: RoastLevel | null
  varieties: string
  tastingNotes: string
  detailOpen: boolean
}

const emptyCoffee = (): CoffeeDraft => ({
  name: '',
  type: null,
  origins: [],
  process: null,
  fermentation: '',
  roastLevel: null,
  varieties: '',
  tastingNotes: '',
  detailOpen: false,
})

// Pickable brands: OTHER is implied by free text, UNKNOWN is not a report.
const BRAND_OPTIONS = MACHINE_BRANDS.filter((b) => b !== 'OTHER' && b !== 'UNKNOWN')
const SOURCE_OPTIONS = BEAN_SOURCES.filter((b) => b !== 'UNKNOWN')

function Combobox({
  value,
  options,
  placeholder,
  unlisted,
  onPick,
}: {
  value: string
  options: string[]
  placeholder: string
  // Note shown when the text matches no option; omit if free text is normal.
  unlisted?: string
  onPick: (option: string | null, text: string) => void
}) {
  const [open, setOpen] = useState(false)
  const matches = options.filter((o) => o.toLowerCase().includes(value.trim().toLowerCase()))

  return (
    <div className="relative">
      <input
        value={value}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onChange={(e) => {
          const text = e.target.value
          // Typing the full label counts as picking it.
          const exact = options.find((o) => o.toLowerCase() === text.trim().toLowerCase())
          onPick(exact ?? null, text)
          setOpen(true)
        }}
        placeholder={placeholder}
        className={inputCls}
      />
      {open && matches.length > 0 && (
        <ul className="absolute z-10 mt-1 max-h-48 w-full overflow-y-auto rounded-xl border border-cream-200 bg-white py-1 shadow-lg">
          {matches.map((o) => (
            <li key={o}>
              <button
                type="button"
                // mousedown fires before the input's blur closes the list.
                onMouseDown={(e) => {
                  e.preventDefault()
                  onPick(o, o)
                  setOpen(false)
                }}
                className="w-full px-3 py-1.5 text-left text-sm hover:bg-cream-100"
              >
                {o}
              </button>
            </li>
          ))}
        </ul>
      )}
      {unlisted && value.trim() !== '' && matches.length === 0 && open && (
        <p className="absolute z-10 mt-1 w-full rounded-xl border border-cream-200 bg-white px-3 py-1.5 text-xs text-espresso-500 shadow-lg">
          {unlisted}
        </p>
      )}
    </div>
  )
}

// Searchable origin dropdown. Single-origin coffees replace the pick;
// blends accumulate. Unlisted countries are added from the typed text.
function OriginSelect({
  selected,
  single,
  onChange,
}: {
  selected: string[]
  single: boolean
  onChange: (next: string[]) => void
}) {
  const [text, setText] = useState('')
  const [open, setOpen] = useState(false)
  const query = text.trim().toLowerCase()
  const matches = ORIGIN_COUNTRIES.filter((o) => o.toLowerCase().includes(query))
  const custom =
    query !== '' &&
    !ORIGIN_COUNTRIES.some((o) => o.toLowerCase() === query) &&
    !selected.some((o) => o.toLowerCase() === query)

  const pick = (origin: string) => {
    if (single) {
      onChange([origin])
      setOpen(false)
    } else {
      onChange(toggle(selected, origin))
    }
    setText('')
  }

  // A single origin is complete at one country; removing its pill
  // brings the field back.
  const full = single && selected.length >= 1

  return (
    <div className="space-y-1.5">
      {selected.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {selected.map((o) => (
            <span
              key={o}
              className="flex items-center gap-1 rounded-full bg-espresso-700 px-2.5 py-1 text-xs font-medium text-cream-50"
            >
              {o}
              <button
                type="button"
                onClick={() => onChange(selected.filter((x) => x !== o))}
                aria-label={`Remove ${o}`}
                className="text-cream-50/70 hover:text-cream-50"
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}
      {!full && (
      <div className="relative">
        <input
          value={text}
          onFocus={() => setOpen(true)}
          onBlur={() => setOpen(false)}
          onChange={(e) => {
            setText(e.target.value)
            setOpen(true)
          }}
          placeholder={single ? 'Pick a country' : 'Pick countries'}
          className={inputCls}
        />
        {open && (matches.length > 0 || custom) && (
          <ul className="absolute z-10 mt-1 max-h-48 w-full overflow-y-auto rounded-xl border border-cream-200 bg-white py-1 shadow-lg">
            {matches.map((o) => (
              <li key={o}>
                <button
                  type="button"
                  // mousedown fires before the input's blur closes the list.
                  onMouseDown={(e) => {
                    e.preventDefault()
                    pick(o)
                  }}
                  className="flex w-full items-center justify-between px-3 py-1.5 text-left text-sm hover:bg-cream-100"
                >
                  {o}
                  {selected.includes(o) && <span className="text-crema-500">✓</span>}
                </button>
              </li>
            ))}
            {custom && (
              <li>
                <button
                  type="button"
                  onMouseDown={(e) => {
                    e.preventDefault()
                    pick(text.trim())
                  }}
                  className="w-full px-3 py-1.5 text-left text-sm text-espresso-500 hover:bg-cream-100"
                >
                  Add “{text.trim()}”
                </button>
              </li>
            )}
          </ul>
        )}
      </div>
      )}
    </div>
  )
}

interface MachineDraft {
  brand: MachineBrand | ''
  text: string
  model: string
}

const emptyMachine = (): MachineDraft => ({ brand: '', text: '', model: '' })

export function ReportForm({ shop, onDone, onCancel }: { shop: CoffeeShop; onDone: () => void; onCancel: () => void }) {
  const [machines, setMachines] = useState<MachineDraft[]>([emptyMachine()])
  const [beanSource, setBeanSource] = useState<BeanSource | null>(null)
  const [roaster, setRoaster] = useState('')
  const [coffees, setCoffees] = useState<CoffeeDraft[]>([emptyCoffee()])
  const [grinders, setGrinders] = useState<GrinderEntry[]>([{ brand: '', model: '' }])
  const [drinks, setDrinks] = useState<DrinkEntry[]>([])
  const [milkBrands, setMilkBrands] = useState<string[]>([])
  const [customMilk, setCustomMilk] = useState('')
  const [amenities, setAmenities] = useState<Record<AmenityKey, boolean | null>>({
    dogFriendly: null,
    wifi: null,
    outdoorSeating: null,
  })
  const [photos, setPhotos] = useState<{ kind: PhotoKind; data: string }[]>([])
  const [note, setNote] = useState('')
  const [usedPhoto, setUsedPhoto] = useState(false)
  const [gearFromPhoto, setGearFromPhoto] = useState(false)
  const [menuFromPhoto, setMenuFromPhoto] = useState(false)
  const [analyzing, setAnalyzing] = useState(false)
  const [guess, setGuess] = useState<MachineGuess | null>(null)
  const [beansOpen, setBeansOpen] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const [moreOpen, setMoreOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const allMilkBrands = () => [...milkBrands, ...splitCustom(customMilk)]
  const allGrinders = () =>
    grinders.map((g) => `${g.brand.trim()} ${g.model.trim()}`.trim()).filter(Boolean)

  const patchGrinder = (i: number, patch: Partial<GrinderEntry>) =>
    setGrinders((prev) => prev.map((g, j) => (j === i ? { ...g, ...patch } : g)))

  const patchMachine = (i: number, patch: Partial<MachineDraft>) =>
    setMachines((prev) => prev.map((m, j) => (j === i ? { ...m, ...patch } : m)))

  // Untouched rows are dropped. Unlisted brands go as OTHER with the
  // brand as a model prefix, e.g. "Astoria Storm".
  const buildMachines = () =>
    machines.flatMap((m) => {
      const freeBrand = !m.brand && m.text.trim()
      if (!m.brand && !freeBrand && !m.model.trim()) return []
      const model = freeBrand ? `${m.text.trim()} ${m.model.trim()}`.trim() : m.model.trim()
      return [{ brand: m.brand || 'OTHER', model: model || null }] as const
    })
  const cleanDrinks = () =>
    drinks
      .filter((d) => d.name.trim())
      .map((d) => {
        const price = Number.parseFloat(d.price)
        return { name: d.name.trim(), price: Number.isFinite(price) ? price : null }
      })

  const patchCoffee = (i: number, patch: Partial<CoffeeDraft>) =>
    setCoffees((prev) => prev.map((c, j) => (j === i ? { ...c, ...patch } : c)))

  // Untouched cards are dropped, so a lone empty card submits nothing.
  const buildCoffees = () =>
    coffees.flatMap((c) => {
      const originList = c.origins
      const varietyList = splitCustom(c.varieties)
      const noteList = splitCustom(c.tastingNotes)
      const touched =
        c.name.trim() || c.type || originList.length || c.process || c.fermentation.trim() || c.roastLevel || varietyList.length || noteList.length
      if (!touched) return []
      return [
        {
          name: c.name.trim() || null,
          type: c.type,
          origins: originList,
          process: c.process,
          fermentation: c.fermentation.trim() || null,
          roastLevel: c.roastLevel,
          varieties: varietyList,
          tastingNotes: noteList,
        },
      ]
    })

  const toggleDrink = (name: string) =>
    setDrinks((prev) =>
      prev.some((d) => d.name === name) ? prev.filter((d) => d.name !== name) : [...prev, { name, price: '' }],
    )

  const setDrinkPrice = (name: string, price: string) =>
    setDrinks((prev) => prev.map((d) => (d.name === name ? { ...d, price } : d)))

  const mergeDrinks = (items: { name: string; price: number | null }[]) =>
    setDrinks((prev) => {
      const existing = new Set(prev.map((d) => d.name.toLowerCase()))
      const added = items
        .filter((i) => !existing.has(i.name.toLowerCase()))
        .map((i) => ({ name: i.name, price: i.price != null ? String(i.price) : '' }))
      return [...prev, ...added]
    })

  // Route each photo to the section it fills: machine → Gear, menu →
  // Menu (auto-expanded), anything else joins the gallery as VIBE.
  const onCapture = async (files: FileList | null) => {
    if (!files?.length) return
    setAnalyzing(true)
    setError(null)
    try {
      for (const file of files) {
        const data = await downscaleImage(file)
        const result = await identifyMachine(data)
        if (result.machine !== 'UNKNOWN') {
          setPhotos((prev) => [...prev, { kind: 'MACHINE', data }])
          setGuess(result)
          // Fill the first untouched machine row, or add a new one.
          setMachines((prev) => {
            const draft: MachineDraft = {
              brand: result.machine,
              text: MACHINE_LABELS[result.machine],
              model: result.machineModel ?? '',
            }
            const idx = prev.findIndex((m) => !m.brand && !m.text.trim() && !m.model.trim())
            return idx >= 0 ? prev.map((m, j) => (j === idx ? draft : m)) : [...prev, draft]
          })
          setGearFromPhoto(true)
          setUsedPhoto(true)
          continue
        }
        const items = await parseMenu(data)
        if (items.length > 0) {
          setPhotos((prev) => [...prev, { kind: 'MENU', data }])
          mergeDrinks(items)
          setMenuFromPhoto(true)
          setMenuOpen(true)
          setUsedPhoto(true)
          continue
        }
        setPhotos((prev) => [...prev, { kind: 'VIBE', data }])
      }
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setAnalyzing(false)
    }
  }

  const onSubmit = async () => {
    setSaving(true)
    setError(null)
    try {
      const milk = allMilkBrands()
      const coffeeList = buildCoffees()
      const grinderList = allGrinders()
      const drinkList = cleanDrinks()
      const machineList = buildMachines()
      await submitReport({
        shopId: shop.id,
        // The backend derives the primary machine from the first entry.
        machines: machineList.length ? machineList : null,
        beanSource: beanSource || null,
        // In-house means the shop is the roaster; a name would repeat it.
        roaster: beanSource === 'IN_HOUSE_ROAST' ? null : roaster.trim() || null,
        coffees: coffeeList.length ? coffeeList : null,
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

  const sectionsUpdated = [
    buildMachines().length || allGrinders().length,
    beanSource || roaster.trim() || buildCoffees().length,
    cleanDrinks().length || allMilkBrands().length,
    Object.values(amenities).some((v) => v !== null) || note.trim(),
  ].filter(Boolean).length

  const hasAnything = sectionsUpdated > 0 || photos.length > 0

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-base font-bold tracking-tight">Report an update</h3>
        <button onClick={onCancel} aria-label="Close" className="text-lg text-espresso-500 hover:text-espresso-900">
          ×
        </button>
      </div>

      <label className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-2xl border border-dashed border-crema-400 bg-crema-400/10 px-3 py-5 transition hover:bg-crema-400/20">
        <span className="text-sm font-semibold text-espresso-900">{analyzing ? 'Reading your photo…' : 'Take a photo'}</span>
        <span className="text-xs text-espresso-500">Optional, autofilling matching section below</span>
        <input
          type="file"
          accept="image/*"
          multiple
          className="hidden"
          disabled={analyzing}
          onChange={(e) => {
            onCapture(e.target.files)
            e.target.value = ''
          }}
        />
      </label>

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

      {guess && guess.machine !== 'UNKNOWN' && (
        <p className="rounded-xl bg-cream-100 px-3 py-2 text-xs text-espresso-700">
          Looks like a {MACHINE_LABELS[guess.machine]}
          {guess.machineModel ? ` ${guess.machineModel}` : ''} ({Math.round(guess.confidence * 100)}% confident).
        </p>
      )}

      <div className="rounded-2xl border border-cream-200 bg-white px-4 py-3">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-espresso-900">Gear</span>
          {gearFromPhoto && <span className="text-[11px] text-crema-500">filled from your photo — edit anything</span>}
        </div>
        <div className="mt-2 space-y-1.5">
          <span className="text-[10px] font-semibold tracking-wide text-espresso-500 uppercase">Espresso machines</span>
          {machines.map((m, i) => (
            <div key={i} className="flex items-center gap-2">
              <div className="grid flex-1 grid-cols-2 gap-2">
                <Combobox
                  value={m.text}
                  options={BRAND_OPTIONS.map((b) => MACHINE_LABELS[b])}
                  placeholder="Machine brand (pick or type)"
                  unlisted={`Not a listed brand — “${m.text.trim()}” will be reported as-is.`}
                  onPick={(label, text) =>
                    patchMachine(i, { brand: BRAND_OPTIONS.find((b) => MACHINE_LABELS[b] === label) ?? '', text })
                  }
                />
                <input
                  value={m.model}
                  onChange={(e) => patchMachine(i, { model: e.target.value })}
                  placeholder="Model (e.g. Linea PB)"
                  className={inputCls}
                />
              </div>
              {machines.length > 1 && (
                <button
                  type="button"
                  onClick={() => setMachines((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="Remove machine"
                  className="shrink-0 text-espresso-500 hover:text-red-600"
                >
                  ×
                </button>
              )}
            </div>
          ))}
          <button
            type="button"
            onClick={() => setMachines((prev) => [...prev, emptyMachine()])}
            className="w-full rounded-xl border border-dashed border-cream-200 px-3 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-700"
          >
            + Add another machine
          </button>
        </div>
        <div className="mt-3 space-y-1.5">
          <RowLabel>Grinders</RowLabel>
          {grinders.map((g, i) => (
            <div key={i} className="flex items-center gap-2">
              <div className="grid flex-1 grid-cols-2 gap-2">
                <Combobox
                  value={g.brand}
                  options={GRINDER_BRANDS}
                  placeholder="Grinder brand (pick or type)"
                  onPick={(_, text) => patchGrinder(i, { brand: text })}
                />
                <input
                  value={g.model}
                  onChange={(e) => patchGrinder(i, { model: e.target.value })}
                  placeholder="Model (e.g. EK43)"
                  className={inputCls}
                />
              </div>
              {grinders.length > 1 && (
                <button
                  type="button"
                  onClick={() => setGrinders((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="Remove grinder"
                  className="shrink-0 text-espresso-500 hover:text-red-600"
                >
                  ×
                </button>
              )}
            </div>
          ))}
          <button
            type="button"
            onClick={() => setGrinders((prev) => [...prev, { brand: '', model: '' }])}
            className="w-full rounded-xl border border-dashed border-cream-200 px-3 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-700"
          >
            + Add grinder
          </button>
        </div>
      </div>

      <Collapsible title="Beans" open={beansOpen} onToggle={() => setBeansOpen((v) => !v)}>
        <div className="flex items-center gap-2">
          <RowLabel>Source</RowLabel>
          <EnumSelect
            options={SOURCE_OPTIONS}
            labels={BEAN_SOURCE_LABELS}
            value={beanSource}
            placeholder="Pick a source"
            onChange={setBeanSource}
          />
        </div>
        {beanSource !== 'IN_HOUSE_ROAST' && (
          <input
            value={roaster}
            onChange={(e) => setRoaster(e.target.value)}
            placeholder="Roaster (e.g. Sightglass)"
            className={inputCls}
          />
        )}
        {coffees.map((c, i) => (
          <div key={i} className="space-y-2 rounded-xl border border-cream-200 bg-cream-50/50 p-3">
            <div className="flex items-center gap-2">
              <input
                value={c.name}
                onChange={(e) => patchCoffee(i, { name: e.target.value })}
                placeholder="Coffee name (e.g. Urcunina)"
                className={inputCls}
              />
              {coffees.length > 1 && (
                <button
                  type="button"
                  onClick={() => setCoffees((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="Remove coffee"
                  className="shrink-0 text-espresso-500 hover:text-red-600"
                >
                  ×
                </button>
              )}
            </div>
            <div className="flex items-center gap-2">
              <RowLabel>Type</RowLabel>
              <EnumChips
                options={COFFEE_TYPES}
                labels={COFFEE_TYPE_LABELS}
                value={c.type}
                onChange={(v) =>
                  // A single origin has one country; keep the first pick.
                  patchCoffee(i, { type: v, origins: v === 'SINGLE_ORIGIN' ? c.origins.slice(0, 1) : c.origins })
                }
              />
            </div>
            <div className="flex items-start gap-2">
              <span className="mt-1.5 w-16 shrink-0 text-[10px] font-semibold tracking-wide text-espresso-500 uppercase">Origin</span>
              <div className="flex-1">
                <OriginSelect
                  selected={c.origins}
                  single={c.type === 'SINGLE_ORIGIN'}
                  onChange={(origins) => patchCoffee(i, { origins })}
                />
              </div>
            </div>
            <div className="flex items-center gap-2">
              <RowLabel>Process</RowLabel>
              <EnumChips
                options={COFFEE_PROCESSES}
                labels={PROCESS_LABELS}
                value={c.process}
                onChange={(v) => patchCoffee(i, { process: v })}
              />
            </div>
            <button
              type="button"
              onClick={() => patchCoffee(i, { detailOpen: !c.detailOpen })}
              className="flex w-full items-center gap-2 py-1 text-xs font-medium text-espresso-500 transition hover:text-espresso-900"
            >
              <span className="h-px flex-1 bg-cream-200" />
              {c.detailOpen ? 'Hide detail' : 'More detail · roast, fermentation, variety, notes'}
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                className={`size-3.5 shrink-0 transition-transform ${c.detailOpen ? 'rotate-180' : ''}`}
              >
                <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <span className="h-px flex-1 bg-cream-200" />
            </button>
            {c.detailOpen && (
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <RowLabel>Roast</RowLabel>
                  <EnumChips
                    options={ROAST_LEVELS}
                    labels={ROAST_LEVEL_LABELS}
                    value={c.roastLevel}
                    onChange={(v) => patchCoffee(i, { roastLevel: v })}
                  />
                </div>
                <div className="flex items-center gap-2">
                  <RowLabel>Ferment</RowLabel>
                  <div className="flex-1">
                    <Combobox
                      value={c.fermentation}
                      options={FERMENTATION_SUGGESTIONS}
                      placeholder="Fermentation (pick or type)"
                      onPick={(_, text) => patchCoffee(i, { fermentation: text })}
                    />
                  </div>
                </div>
                <input
                  value={c.varieties}
                  onChange={(e) => patchCoffee(i, { varieties: e.target.value })}
                  placeholder="Varieties, e.g. Gesha, SL28 (comma separated)"
                  className={inputCls}
                />
                <input
                  value={c.tastingNotes}
                  onChange={(e) => patchCoffee(i, { tastingNotes: e.target.value })}
                  placeholder="Tasting notes, e.g. plum, red grape (comma separated)"
                  className={inputCls}
                />
              </div>
            )}
          </div>
        ))}
        <button
          type="button"
          onClick={() => setCoffees((prev) => [...prev, emptyCoffee()])}
          className="w-full rounded-xl border border-dashed border-cream-200 px-3 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-700"
        >
          + 
        </button>
      </Collapsible>

      <Collapsible
        title="Menu"
        hint={menuFromPhoto ? 'filled from your menu photo — edit anything' : undefined}
        open={menuOpen}
        onToggle={() => setMenuOpen((v) => !v)}
      >
        <Chips options={DRINKS} selected={drinks.map((d) => d.name)} onToggle={toggleDrink} />
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
        <div className="space-y-1.5">
          <RowLabel>Milk</RowLabel>
          <Chips options={MILK_BRANDS} selected={milkBrands} onToggle={(b) => setMilkBrands((p) => toggle(p, b))} />
          <input
            value={customMilk}
            onChange={(e) => setCustomMilk(e.target.value)}
            placeholder="Other milk brands (comma separated)"
            className={inputCls}
          />
        </div>
      </Collapsible>

      <Collapsible title="More · space, note" open={moreOpen} onToggle={() => setMoreOpen((v) => !v)}>
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
                        : 'border border-cream-200 bg-white text-espresso-500 hover:border-crema-400'
                    }`}
                  >
                    {v ? 'Yes' : 'No'}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Anything else?"
          rows={2}
          className={inputCls}
        />
      </Collapsible>

      {error && <p className="text-xs text-red-600">{error}</p>}

      <button
        onClick={onSubmit}
        disabled={saving || !hasAnything}
        className="w-full rounded-xl bg-espresso-700 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:cursor-not-allowed disabled:opacity-40"
      >
        {saving
          ? 'Submitting…'
          : sectionsUpdated > 0
            ? `Submit — ${sectionsUpdated} section${sectionsUpdated > 1 ? 's' : ''} updated`
            : 'Submit'}
      </button>
    </div>
  )
}

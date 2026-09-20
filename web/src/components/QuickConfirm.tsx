import { useState } from 'react'
import { submitReport, type CoffeeShop, type ReportInput } from '../api'
import { BEAN_SOURCE_LABELS, coffeeSummary, machineDisplay } from '../labels'

interface Fact {
  label: string
  value: string
  question: string
  // Merged into one report when the fact is confirmed.
  fields: Partial<ReportInput>
}

// Facts worth re-asserting: only what the shop already knows.
export function buildConfirmFacts(shop: CoffeeShop): Fact[] {
  const facts: Fact[] = []
  if (shop.machines.length > 0) {
    facts.push({
      label: shop.machines.length > 1 ? 'MACHINES' : 'MACHINE',
      value: shop.machines.map((m) => machineDisplay(m.brand, m.model)).join(' · '),
      question: shop.machines.length > 1 ? 'All still on the bar?' : 'Still on the bar?',
      fields: { machines: shop.machines },
    })
  } else if (shop.machine !== 'UNKNOWN') {
    facts.push({
      label: 'MACHINE',
      value: machineDisplay(shop.machine, shop.machineModel),
      question: 'Still on the bar?',
      fields: { machine: shop.machine, machineModel: shop.machineModel },
    })
  }
  if (shop.coffees.length > 0) {
    facts.push({
      label: 'ON BAR',
      value: shop.coffees.map(coffeeSummary).join(' / '),
      question: 'Still what they’re serving?',
      fields: { coffees: shop.coffees },
    })
  } else if (shop.beanSource !== 'UNKNOWN' || shop.roaster) {
    facts.push({
      label: 'BEANS',
      value: [BEAN_SOURCE_LABELS[shop.beanSource], shop.roaster].filter(Boolean).join(' · '),
      question: 'Still right?',
      fields: { beanSource: shop.beanSource !== 'UNKNOWN' ? shop.beanSource : null, roaster: shop.roaster },
    })
  }
  if (shop.grinders.length > 0) {
    facts.push({
      label: 'GRINDERS',
      value: shop.grinders.join(', '),
      question: 'Still in use?',
      fields: { grinders: shop.grinders },
    })
  }
  if (shop.milkBrands.length > 0) {
    facts.push({
      label: 'MILK',
      value: shop.milkBrands.join(', '),
      question: 'Still what they serve?',
      fields: { milkBrands: shop.milkBrands },
    })
  }
  return facts.slice(0, 4)
}

export function QuickConfirm({
  shop,
  onDone,
  onCancel,
  onChanged,
}: {
  shop: CoffeeShop
  onDone: () => void
  onCancel: () => void
  // "Changed…" hands off to the full report form.
  onChanged: () => void
}) {
  const facts = buildConfirmFacts(shop)
  const [idx, setIdx] = useState(0)
  const [confirmed, setConfirmed] = useState<Partial<ReportInput>>({})
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const finish = async (fields: Partial<ReportInput>) => {
    if (Object.keys(fields).length === 0) {
      onDone()
      return
    }
    setSaving(true)
    setError(null)
    try {
      await submitReport({ shopId: shop.id, source: 'TEXT', ...fields })
      onDone()
    } catch (e) {
      setError((e as Error).message)
      setSaving(false)
    }
  }

  const advance = (fields: Partial<ReportInput>) => {
    const next = { ...confirmed, ...fields }
    setConfirmed(next)
    if (idx + 1 >= facts.length) {
      finish(next)
    } else {
      setIdx(idx + 1)
    }
  }

  const fact = facts[idx]

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-base font-bold tracking-tight">Quick confirm</h3>
        <button onClick={onCancel} aria-label="Close" className="text-lg text-espresso-500 hover:text-espresso-900">
          ×
        </button>
      </div>

      <div className="flex gap-1.5">
        {facts.map((_, i) => (
          <div
            key={i}
            className={`h-1 flex-1 rounded-full ${i < idx ? 'bg-espresso-700' : i === idx ? 'bg-crema-400' : 'bg-cream-200'}`}
          />
        ))}
      </div>

      <div className="rounded-2xl border border-cream-200 bg-white p-5">
        <p className="text-[10px] font-semibold tracking-wide text-espresso-500 uppercase">{fact.label}</p>
        <p className="mt-1.5 text-base font-semibold">
          {fact.value} <span className="font-normal text-espresso-500">— {fact.question}</span>
        </p>
        <div className="mt-4 grid grid-cols-3 gap-2">
          <button
            onClick={() => advance(fact.fields)}
            disabled={saving}
            className="rounded-xl bg-espresso-700 py-2 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40"
          >
            Yes, still right
          </button>
          <button
            onClick={onChanged}
            disabled={saving}
            className="rounded-xl border border-cream-200 py-2 text-sm font-medium text-espresso-700 transition hover:border-crema-400 disabled:opacity-40"
          >
            Changed…
          </button>
          <button
            onClick={() => advance({})}
            disabled={saving}
            className="rounded-xl border border-cream-200 py-2 text-sm font-medium text-espresso-500 transition hover:border-crema-400 disabled:opacity-40"
          >
            Skip
          </button>
        </div>
      </div>

      {error && <p className="text-xs text-red-600">{error}</p>}
      {saving && <p className="text-xs text-espresso-500">Saving your confirmations…</p>}
    </div>
  )
}

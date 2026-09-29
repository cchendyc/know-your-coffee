import { useEffect, useState } from 'react'
import { claimShop, fetchShops, type CoffeeShop } from '../api'

// Seller application, one stepped flow for both entries: the header
// "Become a seller" button and a shop page's claim link (which pre-selects
// the shop and skips the first step). Mirrors the iOS SellerApplicationFlow.
//
// Verification mirrors Google Business Profile and Yelp owner claims: prove
// control of a channel tied to the listing (the shop's phone, an email on
// its domain) or public proof. Review stays manual in the support console.

type Step = 'shop' | 'role' | 'verify' | 'review'

const METHODS = [
  {
    id: 'phone',
    title: 'Call the shop',
    detail: "Our team will call the shop's listed number and ask for you.",
    placeholder: '"Shop phone, best time to call, ..."',
  },
  {
    id: 'email',
    title: 'Business email',
    detail: "An email on the shop's own domain, e.g. you@yourshop.com.",
    placeholder: 'you@yourshop.com',
  },
  {
    id: 'link',
    title: 'Public proof',
    detail: 'A website, menu, or social page that names you as owner or staff.',
    placeholder: 'yourshop.com/about or instagram.com/yourshop',
  },
] as const

const ROLES = [
  { name: 'Owner', detail: 'You own the business or a stake in it.' },
  { name: 'Manager', detail: 'You run day-to-day operations.' },
  { name: 'Staff', detail: 'You work here and act for the owner.' },
] as const

export function SellerApplicationModal({
  shop,
  isSeller = false,
  onClose,
}: {
  shop?: CoffeeShop
  // Existing sellers skip the onboarding pitch: the shop joins their switcher.
  isSeller?: boolean
  onClose: () => void
}) {
  const steps: Step[] = shop ? ['role', 'verify', 'review'] : ['shop', 'role', 'verify', 'review']
  const [step, setStep] = useState<Step>(steps[0])
  const [selectedShop, setSelectedShop] = useState<CoffeeShop | null>(shop ?? null)

  const [query, setQuery] = useState('')
  const [results, setResults] = useState<CoffeeShop[]>([])
  const [searching, setSearching] = useState(true)

  const [role, setRole] = useState('Owner')
  const [method, setMethod] = useState<(typeof METHODS)[number]>(METHODS[0])
  const [proof, setProof] = useState('')
  const [link, setLink] = useState('')
  const [note, setNote] = useState('')

  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const stepIndex = steps.indexOf(step)
  const hasProof = [proof, link, note].some((v) => v.trim())
  const canContinue =
    step === 'shop' ? selectedShop != null : step === 'verify' ? hasProof : !busy

  useEffect(() => {
    if (shop || step !== 'shop') return
    let stale = false
    setSearching(true)
    const t = setTimeout(() => {
      fetchShops({ search: query || undefined, limit: 25, offset: 0 })
        .then((page) => {
          if (!stale) setResults(page.shops)
        })
        .finally(() => {
          if (!stale) setSearching(false)
        })
    }, 250)
    return () => {
      stale = true
      clearTimeout(t)
    }
  }, [query, step, shop])

  const advance = () => {
    setError(null)
    if (step === 'review') {
      submit()
    } else {
      setStep(steps[stepIndex + 1])
    }
  }

  const submit = () => {
    if (!selectedShop) return
    setBusy(true)
    // "Verify by" travels in the note so support knows which channel to use;
    // the schema has no dedicated field.
    const methodNote = `Verify by: ${method.title.toLowerCase()}`
    claimShop(selectedShop.id, {
      businessRole: role,
      contact: proof.trim() || undefined,
      website: link.trim() || undefined,
      note: note.trim() ? `${methodNote}. ${note.trim()}` : methodNote,
    })
      .then(() => setDone(true))
      .catch((e: Error) => setError(e.message))
      .finally(() => setBusy(false))
  }

  const card = (selected: boolean) =>
    `w-full rounded-xl border-[1.5px] bg-white p-3.5 text-left transition ${
      selected ? 'border-crema-500' : 'border-transparent hover:border-cream-200'
    }`
  const radio = (selected: boolean) => (
    <span
      className={`mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border-2 ${
        selected ? 'border-crema-500 bg-crema-500 text-white' : 'border-cream-200'
      }`}
    >
      {selected && (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" className="size-3">
          <path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </span>
  )
  const input =
    'w-full rounded-xl border border-cream-200 bg-white px-3.5 py-2.5 text-sm outline-none placeholder:text-espresso-500/60 focus:border-crema-400'
  const fieldLabel = 'flex flex-col gap-1.5 text-xs font-semibold text-espresso-500'

  const titles: Record<Step, [string, string]> = {
    shop: [
      'Which shop is yours?',
      "Find your shop in the directory. If it isn't listed, add it first.",
    ],
    role: [
      `Your role at ${selectedShop?.name ?? 'the shop'}`,
      'Support may ask the owner to confirm managers and staff.',
    ],
    verify: [
      "Prove it's really you",
      "Pick the way our team can verify you're connected to the shop.",
    ],
    review: [
      'Review your application',
      'A person on our support team reviews every application, usually within a few days.',
    ],
  }

  return (
    <div
      className="fixed inset-0 z-[1200] flex items-start justify-center overflow-y-auto overscroll-contain bg-espresso-900/40 p-4"
      onClick={onClose}
    >
      <div
        className="mt-10 flex w-full max-w-lg flex-col rounded-2xl bg-cream-50 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        {done ? (
          <div className="p-8 text-center">
            <div className="mx-auto mb-3 flex size-12 items-center justify-center rounded-full bg-green-100 text-green-700">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" className="size-6">
                <path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <h3 className="text-lg font-bold">Application submitted</h3>
            <p className="mx-auto mt-1 max-w-sm text-sm text-espresso-500">
              Support will verify you by {method.title.toLowerCase()} and review the application.{' '}
              {isSeller
                ? `Once approved, ${selectedShop?.name} appears in your Seller Hub's shop switcher.`
                : `Once approved, you'll see a brief onboarding and get access to the Seller Hub for ${selectedShop?.name}.`}
            </p>
            <button
              onClick={onClose}
              className="mt-5 rounded-xl bg-espresso-700 px-5 py-2.5 text-sm font-semibold text-cream-50 hover:bg-espresso-900"
            >
              Done
            </button>
          </div>
        ) : (
          <>
            <div className="flex gap-1.5 px-6 pt-5">
              {steps.map((s, i) => (
                <span
                  key={s}
                  className={`h-1 flex-1 rounded-full ${i <= stepIndex ? 'bg-crema-500' : 'bg-cream-200'}`}
                />
              ))}
            </div>

            <div className="max-h-[70vh] overflow-y-auto p-6">
              <h3 className="text-lg font-bold">{titles[step][0]}</h3>
              <p className="mt-0.5 text-sm text-espresso-500">{titles[step][1]}</p>

              <div className="mt-4 flex flex-col gap-2">
                {step === 'shop' && (
                  <>
                    <input
                      autoFocus
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                      placeholder="Shop name or city"
                      className={input}
                    />
                    {searching && results.length === 0 ? (
                      <p className="py-6 text-center text-sm text-espresso-500">Searching…</p>
                    ) : results.length === 0 ? (
                      <p className="py-6 text-center text-sm text-espresso-500">No shops match.</p>
                    ) : (
                      results.map((candidate) => (
                        <button
                          key={candidate.id}
                          onClick={() => setSelectedShop(candidate)}
                          className={card(selectedShop?.id === candidate.id)}
                        >
                          <span className="flex items-start gap-3">
                            {radio(selectedShop?.id === candidate.id)}
                            <span>
                              <span className="block text-sm font-semibold">{candidate.name}</span>
                              <span className="block text-xs text-espresso-500">
                                {[candidate.address, candidate.city].filter(Boolean).join(', ')}
                              </span>
                            </span>
                          </span>
                        </button>
                      ))
                    )}
                  </>
                )}

                {step === 'role' &&
                  ROLES.map((r) => (
                    <button key={r.name} onClick={() => setRole(r.name)} className={card(role === r.name)}>
                      <span className="flex items-start gap-3">
                        {radio(role === r.name)}
                        <span>
                          <span className="block text-sm font-semibold">{r.name}</span>
                          <span className="block text-xs text-espresso-500">{r.detail}</span>
                        </span>
                      </span>
                    </button>
                  ))}

                {step === 'verify' && (
                  <>
                    {METHODS.map((m) => (
                      <button key={m.id} onClick={() => setMethod(m)} className={card(method.id === m.id)}>
                        <span className="flex items-start gap-3">
                          {radio(method.id === m.id)}
                          <span>
                            <span className="block text-sm font-semibold">{m.title}</span>
                            <span className="block text-xs text-espresso-500">{m.detail}</span>
                          </span>
                        </span>
                      </button>
                    ))}
                    <label className={`${fieldLabel} mt-2`}>
                      {method.id === 'link' ? 'Link' : 'Where support reaches you'}
                      <input
                        className={input}
                        value={method.id === 'link' ? link : proof}
                        onChange={(e) => (method.id === 'link' ? setLink(e.target.value) : setProof(e.target.value))}
                        placeholder={method.placeholder}
                      />
                    </label>
                    <label className={fieldLabel}>
                      Anything else (optional)
                      <textarea
                        className={`${input} resize-none`}
                        rows={2}
                        value={note}
                        onChange={(e) => setNote(e.target.value)}
                        placeholder="e.g. I can show a business license or a video of the shop"
                      />
                    </label>
                  </>
                )}

                {step === 'review' && (
                  <div className="divide-y divide-cream-200 rounded-xl bg-white">
                    {(
                      [
                        ['Shop', selectedShop ? `${selectedShop.name}, ${selectedShop.city}` : '—'],
                        ['Role', role],
                        ['Verify by', method.title],
                        ...(proof.trim() ? [['Contact', proof.trim()]] : []),
                        ...(link.trim() ? [['Link', link.trim()]] : []),
                        ...(note.trim() ? [['Note', note.trim()]] : []),
                      ] as [string, string][]
                    ).map(([k, v]) => (
                      <div key={k} className="flex items-start gap-3 p-3.5">
                        <span className="w-20 shrink-0 text-xs font-semibold text-espresso-500">{k}</span>
                        <span className="text-sm">{v}</span>
                      </div>
                    ))}
                  </div>
                )}

                {error && <p className="text-sm text-red-700">{error}</p>}
              </div>
            </div>

            <div className="flex gap-2 border-t border-cream-200 p-4">
              {stepIndex > 0 ? (
                <button
                  onClick={() => setStep(steps[stepIndex - 1])}
                  className="rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-medium text-espresso-500 hover:border-crema-400"
                >
                  Back
                </button>
              ) : (
                <button
                  onClick={onClose}
                  className="rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-medium text-espresso-500 hover:border-crema-400"
                >
                  Cancel
                </button>
              )}
              <button
                onClick={advance}
                disabled={!canContinue}
                className="flex-1 rounded-xl bg-espresso-700 px-5 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40"
              >
                {step === 'review' ? (busy ? 'Submitting…' : 'Submit application') : 'Continue'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

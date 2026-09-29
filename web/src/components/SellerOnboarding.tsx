import { useState } from 'react'
import {
  completeSellerOnboarding,
  submitReport,
  updateShopProfile,
  type BeanSource,
  type CoffeeShop,
  type MachineBrand,
} from '../api'
import {
  AMENITIES,
  BEAN_SOURCE_LABELS,
  BEAN_SOURCES,
  MACHINE_BRANDS,
  MACHINE_LABELS,
  type AmenityKey,
} from '../labels'

// First-run seller walkthrough, required once per shop before the Seller Hub
// renders. Confirms the listing data we already hold (location, website,
// machine, beans, amenities) and collects a bio, then lands on the hub
// overview. The menu is left to the hub itself. Corrections reuse existing
// plumbing: profile fields go through updateShopProfile; the rest goes
// through submitReport, whose values fold into the shop record.

type Step = 'welcome' | 'basics' | 'details' | 'bio'

const STEPS: Step[] = ['welcome', 'basics', 'details', 'bio']

const input =
  'w-full rounded-xl border border-cream-200 bg-white px-3.5 py-2.5 text-sm outline-none placeholder:text-espresso-500/60 focus:border-crema-400'
const fieldLabel = 'flex flex-col gap-1.5 text-xs font-semibold text-espresso-500'
const sectionLabel = 'text-[11px] font-semibold tracking-wider text-espresso-500 uppercase'

export function SellerOnboarding({
  shop,
  onFinished,
}: {
  shop: CoffeeShop
  onFinished: () => void
}) {
  const [step, setStep] = useState<Step>('welcome')
  const [website, setWebsite] = useState(shop.website ?? '')
  const [machine, setMachine] = useState<MachineBrand>(shop.machine)
  const [machineModel, setMachineModel] = useState(shop.machineModel ?? '')
  const [beanSource, setBeanSource] = useState<BeanSource>(shop.beanSource)
  const [roaster, setRoaster] = useState(shop.roaster ?? '')
  // null = still unknown; untouched amenities stay unknown on the shop page.
  const [amenities, setAmenities] = useState<Record<AmenityKey, boolean | null>>({
    dogFriendly: shop.dogFriendly,
    wifi: shop.wifi,
    outdoorSeating: shop.outdoorSeating,
  })
  const [bio, setBio] = useState(shop.vibe ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const stepIndex = STEPS.indexOf(step)

  const finish = async () => {
    setBusy(true)
    setError(null)
    try {
      const profile: { vibe?: string; website?: string } = {}
      if (bio.trim() !== (shop.vibe ?? '')) profile.vibe = bio.trim()
      if (website.trim() !== (shop.website ?? '')) profile.website = website.trim()
      if (Object.keys(profile).length) await updateShopProfile(shop.id, profile)

      const machineChanged =
        machine !== shop.machine || (machineModel.trim() || null) !== shop.machineModel
      const beansChanged = beanSource !== shop.beanSource || (roaster.trim() || null) !== shop.roaster
      const amenityChanges = Object.fromEntries(
        AMENITIES.filter((a) => amenities[a.key] !== null && amenities[a.key] !== shop[a.key]).map((a) => [
          a.key,
          amenities[a.key],
        ]),
      )
      if (machineChanged || beansChanged || Object.keys(amenityChanges).length) {
        await submitReport({
          shopId: shop.id,
          ...(machineChanged ? { machine, machineModel: machineModel.trim() || null } : {}),
          ...(beansChanged ? { beanSource, roaster: roaster.trim() || null } : {}),
          ...amenityChanges,
          note: 'Seller onboarding',
          source: 'TEXT',
        })
      }
      // Server-side completion flag; the hub gates on shop.sellerOnboarded.
      await completeSellerOnboarding(shop.id)
      onFinished()
    } catch (e) {
      setError((e as Error).message)
    }
    setBusy(false)
  }

  const titles: Record<Step, [string, string]> = {
    welcome: [
      `Welcome to your Seller Hub`,
      `You're the verified owner of ${shop.name}. Before you start selling, take a minute to check the listing buyers see.`,
    ],
    basics: ['Confirm the basics', 'This is what we have on file. Fix anything that looks off.'],
    details: ['Your shop details', 'What buyers see on your shop page: the gear, the beans, and the space.'],
    bio: ['Tell buyers about your shop', 'A short bio shown on your shop page. What makes it worth the trip?'],
  }

  return (
    // Full-page takeover, above the app header: onboarding is the only
    // thing on screen until it finishes.
    <div className="fixed inset-0 z-50 flex justify-center overflow-y-auto overscroll-contain bg-cream-50 px-4 py-10">
      <div className="flex w-full max-w-xl flex-col">
        <div className="mb-6 flex items-center gap-2.5">
          <img src={`${import.meta.env.BASE_URL}icon-192.png`} alt="Know Your Coffee" className="size-8 rounded-lg" />
          <span className="text-sm font-bold tracking-tight">Know Your Coffee</span>
        </div>
        <p className="mb-3 text-[11px] font-semibold tracking-wider text-espresso-500 uppercase">
          Seller setup · Step {stepIndex + 1} of {STEPS.length}
        </p>
        <div className="flex gap-1.5">
          {STEPS.map((s, i) => (
            <span key={s} className={`h-1 flex-1 rounded-full ${i <= stepIndex ? 'bg-crema-500' : 'bg-cream-200'}`} />
          ))}
        </div>

        <div className="py-8">
          <h2 className="text-2xl font-bold">{titles[step][0]}</h2>
          <p className="mt-1 text-sm text-espresso-500">{titles[step][1]}</p>

          <div className="mt-6 flex flex-col gap-3">
            {step === 'welcome' && (
              <div className="flex items-center gap-4 rounded-2xl border border-cream-200 bg-white p-4">
                {shop.photoUrl ? (
                  <img src={shop.photoUrl} alt="" className="size-16 rounded-xl object-cover" />
                ) : (
                  <span className="flex size-16 items-center justify-center rounded-xl bg-cream-100 text-2xl">☕️</span>
                )}
                <div>
                  <p className="font-semibold">{shop.name}</p>
                  <p className="text-xs text-espresso-500">
                    {shop.address}, {shop.city}
                  </p>
                  <p className="mt-1 text-[11px] font-medium text-ok-700">✓ Verified owner</p>
                </div>
              </div>
            )}

            {step === 'basics' && (
              <>
                <div className="rounded-xl border border-cream-200 bg-white p-3.5">
                  <p className="text-xs font-semibold text-espresso-500">Location</p>
                  <p className="mt-0.5 text-sm">
                    {shop.address}, {shop.city}
                  </p>
                  <p className="mt-1 text-[11px] text-espresso-500">
                    Wrong address? Contact support — location edits are verified manually.
                  </p>
                </div>
                <label className={fieldLabel}>
                  Website
                  <input
                    className={input}
                    value={website}
                    onChange={(e) => setWebsite(e.target.value)}
                    placeholder="yourshop.com"
                  />
                </label>
              </>
            )}

            {step === 'details' && (
              <>
                <p className={sectionLabel}>Gear</p>
                <div className="flex gap-3">
                  <label className={`${fieldLabel} flex-1`}>
                    Machine brand
                    <select className={input} value={machine} onChange={(e) => setMachine(e.target.value as MachineBrand)}>
                      {MACHINE_BRANDS.map((b) => (
                        <option key={b} value={b}>
                          {MACHINE_LABELS[b]}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className={`${fieldLabel} flex-1`}>
                    Model (optional)
                    <input
                      className={input}
                      value={machineModel}
                      onChange={(e) => setMachineModel(e.target.value)}
                      placeholder="Linea PB"
                    />
                  </label>
                </div>
                <p className={`${sectionLabel} mt-3`}>Beans</p>
                <div className="flex gap-3">
                  <label className={`${fieldLabel} flex-1`}>
                    Bean sourcing
                    <select className={input} value={beanSource} onChange={(e) => setBeanSource(e.target.value as BeanSource)}>
                      {BEAN_SOURCES.map((s) => (
                        <option key={s} value={s}>
                          {BEAN_SOURCE_LABELS[s]}
                        </option>
                      ))}
                    </select>
                  </label>
                  {beanSource !== 'IN_HOUSE_ROAST' && (
                    <label className={`${fieldLabel} flex-1`}>
                      Roaster (optional)
                      <input
                        className={input}
                        value={roaster}
                        onChange={(e) => setRoaster(e.target.value)}
                        placeholder="Sightglass"
                      />
                    </label>
                  )}
                </div>
                <p className={`${sectionLabel} mt-3`}>Space</p>
                {AMENITIES.map((a) => (
                  <div
                    key={a.key}
                    className="flex items-center justify-between rounded-xl border border-cream-200 bg-white px-3.5 py-2.5"
                  >
                    <span className="text-sm font-medium">{a.label}</span>
                    <div className="flex gap-1.5">
                      {([true, false] as const).map((v) => (
                        <button
                          key={String(v)}
                          type="button"
                          onClick={() => setAmenities((prev) => ({ ...prev, [a.key]: prev[a.key] === v ? null : v }))}
                          className={`rounded-full px-3.5 py-1.5 text-xs font-semibold transition ${
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
                <p className="text-[11px] text-espresso-500">Leave both unselected if you're not sure — it shows as “Unknown”.</p>
              </>
            )}

            {step === 'bio' && (
              <textarea
                className={`${input} resize-none`}
                rows={4}
                value={bio}
                onChange={(e) => setBio(e.target.value)}
                placeholder="e.g. Family-run roastery pouring single origins on a Slayer since 2019."
              />
            )}

            {error && <p className="text-sm text-danger-700">{error}</p>}
          </div>
        </div>

        <div className="flex items-center gap-2 border-t border-cream-200 pt-5">
          {stepIndex > 0 && (
            <button
              onClick={() => setStep(STEPS[stepIndex - 1])}
              className="rounded-xl border border-cream-200 bg-white px-4 py-2.5 text-sm font-medium text-espresso-500 hover:border-crema-400"
            >
              Back
            </button>
          )}
          <button
            onClick={() => (step === 'bio' ? void finish() : setStep(STEPS[stepIndex + 1]))}
            disabled={busy}
            className="flex-1 rounded-xl bg-espresso-700 px-5 py-2.5 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-40"
          >
            {step === 'welcome' ? "Let's set up" : step === 'bio' ? (busy ? 'Saving…' : 'Finish setup') : 'Looks right — continue'}
          </button>
        </div>
      </div>
    </div>
  )
}

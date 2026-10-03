import { useState, type ReactNode } from 'react'
import type { Coffee, Report, ShopPageData, User } from '../api'
import { timeAgo } from '../format'
import { AMENITIES, BEAN_SOURCE_LABELS, coffeePills, machineDisplay, reportSummary } from '../labels'
import { SectionHeader } from './bits'
import { plural } from './util'

const RECORDS_SHOWN = 2
const AVATAR_COLORS = ['#c08c3e', '#3d5a80', '#6f4e37', '#5a7d5a', '#8a5a7d']

export function AboutSection({
  shop,
  user,
  machines,
  canConfirm,
  onReport,
  onConfirm,
  onJumpToShop,
  children,
}: {
  shop: ShopPageData
  user: User | null
  machines: { brand: ShopPageData['machine']; model: string | null }[]
  canConfirm: boolean
  onReport: () => void
  onConfirm: () => void
  onJumpToShop: () => void
  // Rendered between the gear/beans/space cards and the records (the menu).
  children?: ReactNode
}) {
  const [allRecords, setAllRecords] = useState(false)
  const latest = shop.reports[0]
  const inHouse = shop.beanSource === 'IN_HOUSE_ROAST'
  const beansLabel =
    shop.beanSource === 'UNKNOWN'
      ? 'Beans not reported yet'
      : inHouse
        ? 'Roasts in-house'
        : [BEAN_SOURCE_LABELS[shop.beanSource], shop.roaster].filter(Boolean).join(' · ')
  const records = allRecords ? shop.reports : shop.reports.slice(0, RECORDS_SHOWN)
  // "Buy this bean" links a reported coffee to the listing with the same name.
  const listingFor = (c: Coffee) =>
    c.name ? shop.products.find((p) => p.name.toLowerCase().includes(c.name!.toLowerCase())) : undefined

  return (
    <>
      <SectionHeader
        title="About this shop"
        subtitle="Gear, beans and space — kept current by regulars and the owner"
        action={
          shop.reportCount > 0 && (
            <span className="sp-link">
              Verified by {plural(shop.reportCount, 'report')}
              {latest ? ` · ${timeAgo(latest.createdAt)}` : ''}
            </span>
          )
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <div className="sp-card flex flex-col gap-2.5 px-[18px] py-4">
          <p className="sp-eyebrow">Gear</p>
          {machines.length > 0 ? (
            machines.map((m, i) => (
              <div key={i}>
                <p className="font-semibold">{machineDisplay(m.brand, m.model)}</p>
                <p className="text-xs text-espresso-500">Espresso machine</p>
              </div>
            ))
          ) : (
            <p className="text-sm text-espresso-500">Machine not reported yet.</p>
          )}
          {shop.grinders.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {shop.grinders.map((g) => (
                <span key={g} className="sp-chip">
                  {g}
                </span>
              ))}
            </div>
          )}
        </div>

        <div className="sp-card flex flex-col gap-2.5 px-[18px] py-4">
          <p className="sp-eyebrow">Beans</p>
          <p className="font-semibold">{beansLabel}</p>
          {shop.coffees.map((c, i) => {
            const listing = listingFor(c)
            return (
              <div key={i} className="flex flex-col gap-1.5">
                <div className="flex items-start justify-between gap-2">
                  <p className="text-[13px] font-semibold">{[c.roaster, c.name].filter(Boolean).join(' — ') || 'House coffee'}</p>
                  {listing && (
                    <button type="button" onClick={onJumpToShop} className="sp-link shrink-0 text-xs">
                      Buy this bean →
                    </button>
                  )}
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {coffeePills(c).map((p) => (
                    <span key={p} className="sp-chip">
                      {p}
                    </span>
                  ))}
                </div>
                {c.tastingNotes.length > 0 && <p className="text-[11px] text-espresso-500">{c.tastingNotes.join(' · ')}</p>}
              </div>
            )
          })}
          {shop.coffees.length === 0 && shop.beanOrigins.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {shop.beanOrigins.map((o) => (
                <span key={o} className="sp-chip">
                  {o}
                </span>
              ))}
            </div>
          )}
        </div>

        <div className="sp-card flex flex-col gap-2.5 px-[18px] py-4">
          <p className="sp-eyebrow">Space</p>
          {AMENITIES.map((a) => (
            <div key={a.key} className="sp-row">
              <span>{a.label}</span>
              {shop[a.key] !== null ? (
                <span className="font-medium">{shop[a.key] ? 'Yes' : 'No'}</span>
              ) : user ? (
                <button type="button" onClick={onReport} className="sp-link">
                  Unknown — know it?
                </button>
              ) : (
                <span className="text-espresso-500">Unknown</span>
              )}
            </div>
          ))}
          {shop.milkBrands.length > 0 && (
            <div className="sp-row">
              <span>Milk</span>
              <span className="font-medium">{shop.milkBrands.join(', ')}</span>
            </div>
          )}
        </div>
      </div>

      {children}

      <div className="flex items-end justify-between pt-4">
        <div>
          <h3 className="font-semibold">Records · {shop.reportCount}</h3>
          <p className="mt-0.5 text-[13px] text-espresso-500">Who reported what, and when — every fact above traces back to one of these</p>
        </div>
        <span className="sp-link">Newest first</span>
      </div>

      {user ? (
        <div className="sp-report-bar">
          <div className="flex-1">
            <p className="text-sm font-semibold">Been here recently?</p>
            <p className="text-xs text-espresso-500">Confirm what is still true or report a change — photos welcome.</p>
          </div>
          <button type="button" onClick={onReport} className="sp-pill sp-pill--dark sp-pill--sm">
            Report an update
          </button>
          <button type="button" disabled={!canConfirm} onClick={onConfirm} className="sp-pill sp-pill--outline sp-pill--sm">
            Quick confirm
          </button>
        </div>
      ) : (
        <p className="sp-report-bar text-sm text-espresso-700">Sign in (top right) to confirm or report what is on the bar.</p>
      )}

      {records.map((r) => (
        <RecordCard key={r.id} report={r} />
      ))}
      {shop.reports.length === 0 && <p className="text-sm text-espresso-500">No records yet. Be the first to confirm the setup.</p>}
      {shop.reports.length > RECORDS_SHOWN && (
        <button type="button" onClick={() => setAllRecords((v) => !v)} className="sp-link self-start">
          {allRecords ? 'Show fewer' : `See all ${plural(shop.reports.length, 'record')}`}
        </button>
      )}
    </>
  )
}

function RecordCard({ report: r }: { report: Report }) {
  const name = r.reporter?.name ?? 'Anonymous'
  const color = AVATAR_COLORS[name.charCodeAt(0) % AVATAR_COLORS.length]
  return (
    <div className="sp-card sp-record">
      {r.reporter?.picture ? (
        <img src={r.reporter.picture} alt="" className="size-8 shrink-0 rounded-full" referrerPolicy="no-referrer" />
      ) : (
        <span className="sp-avatar-sm" style={{ backgroundColor: color }}>
          {name[0].toUpperCase()}
        </span>
      )}
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <p className="flex flex-wrap items-center gap-2">
          <span className="text-[13px] font-semibold">{name}</span>
          <span className="text-xs text-espresso-500">
            {timeAgo(r.createdAt)} · {r.source === 'PHOTO' ? 'via photo' : 'via text'}
          </span>
        </p>
        <p className="text-sm">{reportSummary(r) || 'Confirmed the setup.'}</p>
      </div>
    </div>
  )
}

import { useState, type ReactNode } from 'react'
import type { Coffee, Report, ShopPageData, User } from '../api'
import { timeAgo } from '../format'
import { AMENITIES, BEAN_SOURCE_LABELS, coffeePills, machineDisplay, reportSummary } from '../labels'
import { Chip, Empty, InfoCard, Row, SubHeader } from './bits'
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
  const beanSource =
    shop.beanSource === 'UNKNOWN'
      ? null
      : shop.beanSource === 'IN_HOUSE_ROAST'
        ? 'Roasted in-house'
        : [BEAN_SOURCE_LABELS[shop.beanSource], shop.roaster].filter(Boolean).join(' · ')
  const records = allRecords ? shop.reports : shop.reports.slice(0, RECORDS_SHOWN)
  // "Buy this bean" links a reported coffee to the listing with the same name.
  const listingFor = (c: Coffee) =>
    c.name ? shop.products.find((p) => p.name.toLowerCase().includes(c.name!.toLowerCase())) : undefined

  return (
    <>
      {user ? (
        <div className="sp-report-bar">
          <div className="flex-1">
            <p className="text-sm font-semibold">Been here recently?</p>
            <p className="text-xs text-espresso-500">Confirm the setup below or report what changed.</p>
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

      <div className="grid gap-4 md:grid-cols-3">
        <InfoCard eyebrow="Gear">
          {machines.length > 0 ? (
            machines.map((m, i) => (
              <Row key={i} label={machineDisplay(m.brand, m.model)}>
                <Chip>Espresso</Chip>
              </Row>
            ))
          ) : (
            <Empty>Machine not reported yet.</Empty>
          )}
          {shop.grinders.map((g) => (
            <Row key={g} label={g}>
              <Chip>Grinder</Chip>
            </Row>
          ))}
        </InfoCard>

        <InfoCard eyebrow="Beans" tag={beanSource}>
          {shop.coffees.length > 0 ? (
            shop.coffees.map((c, i) => {
              // Unnamed coffees lead with their first attribute (usually the type) instead of a placeholder.
              const name = [c.roaster, c.name].filter(Boolean).join(' — ')
              const pills = [...coffeePills(c), ...c.tastingNotes]
              const title = name || pills.shift() || 'House coffee'
              return (
                <Row key={i} label={title}>
                  {pills.map((p) => (
                    <Chip key={p}>{p}</Chip>
                  ))}
                  {listingFor(c) && (
                    <button type="button" onClick={onJumpToShop} className="sp-link text-xs">
                      Buy this bean →
                    </button>
                  )}
                </Row>
              )
            })
          ) : shop.beanOrigins.length > 0 ? (
            <Row label="Origins">
              {shop.beanOrigins.map((o) => (
                <Chip key={o}>{o}</Chip>
              ))}
            </Row>
          ) : (
            <Empty>{beanSource ? 'Coffees not reported yet.' : 'Beans not reported yet.'}</Empty>
          )}
          {shop.milkBrands.length > 0 && (
            <Row label="Milk">
              {shop.milkBrands.map((m) => (
                <Chip key={m}>{m}</Chip>
              ))}
            </Row>
          )}
        </InfoCard>

        <InfoCard eyebrow="Space">
          {AMENITIES.map((a) => (
            <Row key={a.key} label={a.label}>
              {shop[a.key] !== null ? (
                <Chip>{shop[a.key] ? 'Yes' : 'No'}</Chip>
              ) : user ? (
                <button type="button" onClick={onReport} className="sp-link text-xs">
                  Unknown — know it?
                </button>
              ) : (
                <Chip>Unknown</Chip>
              )}
            </Row>
          ))}
        </InfoCard>
      </div>

      {children}

      <SubHeader title="Records" meta={latest ? `${plural(shop.reportCount, 'report')} · latest ${timeAgo(latest.createdAt)}` : undefined} />

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

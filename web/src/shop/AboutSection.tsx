import { useState } from 'react'
import type { Report, ShopPageData, User } from '../api'
import { timeAgo } from '../format'
import { AMENITIES, machineDisplay, reportSummary } from '../labels'
import { Chip, InfoCard, PlusIcon, Row, SubHeader } from './bits'
import { plural } from './util'

const RECORDS_SHOWN = 2
const AVATAR_COLORS = ['#c08c3e', '#3d5a80', '#6f4e37', '#5a7d5a', '#8a5a7d']

// Gear and Space only. Beans and the menu are not shown: sellers will
// manage those from the Shop tab.
export function AboutSection({
  shop,
  user,
  machines,
  canConfirm,
  onReport,
  onConfirm,
}: {
  shop: ShopPageData
  user: User | null
  machines: { brand: ShopPageData['machine']; model: string | null }[]
  canConfirm: boolean
  onReport: () => void
  onConfirm: () => void
}) {
  const [allRecords, setAllRecords] = useState(false)
  const latest = shop.reports[0]
  const records = allRecords ? shop.reports : shop.reports.slice(0, RECORDS_SHOWN)
  // A detail nobody has reported yet: a real button for signed-in visitors,
  // a plain chip otherwise (reporting needs an account).
  const unknown = user ? (
    <button
      type="button"
      onClick={onReport}
      className="inline-flex items-center gap-1 rounded-full border border-espresso-700/45 px-2.5 py-1 text-[11px] font-semibold text-espresso-700 transition hover:bg-cream-100"
    >
      <PlusIcon className="size-3" />
      Add
    </button>
  ) : (
    <Chip>Unknown</Chip>
  )

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

      <div className="grid gap-4 md:grid-cols-2">
        <InfoCard eyebrow="Gear">
          {machines.length > 0 ? (
            machines.map((m, i) => (
              <Row key={i} label={machineDisplay(m.brand, m.model)}>
                <Chip>Espresso machine</Chip>
              </Row>
            ))
          ) : (
            <Row label="Espresso machine">{unknown}</Row>
          )}
          {shop.grinders.map((g) => (
            <Row key={g} label={g}>
              <Chip>Grinder</Chip>
            </Row>
          ))}
        </InfoCard>

        <InfoCard eyebrow="Space">
          {AMENITIES.map((a) => (
            <Row key={a.key} label={a.label}>
              {shop[a.key] !== null ? <Chip>{shop[a.key] ? 'Yes' : 'No'}</Chip> : unknown}
            </Row>
          ))}
        </InfoCard>
      </div>

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

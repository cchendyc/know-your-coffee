import type { Report } from '../api'
import { MACHINE_LABELS } from '../labels'

export function ReportList({ reports }: { reports: Report[] }) {
  if (reports.length === 0) {
    return <p className="mt-2 text-sm text-espresso-500">No reports yet. Be the first to confirm the setup.</p>
  }
  return (
    <ul className="mt-2 space-y-2">
      {reports.map((r) => (
        <li key={r.id} className="rounded-2xl border border-cream-200 bg-white p-3 text-sm">
          <p className="flex items-center gap-1.5 text-xs text-espresso-500">
            {r.reporter?.picture && (
              <img src={r.reporter.picture} alt="" className="size-4 rounded-full" referrerPolicy="no-referrer" />
            )}
            {r.reporter ? `${r.reporter.name} · ` : ''}
            {new Date(r.createdAt).toLocaleString()} · {r.source === 'PHOTO' ? 'via photo' : 'via text'}
          </p>
          <p className="mt-1">
            {[
              r.machine && `Machine: ${MACHINE_LABELS[r.machine]}${r.machineModel ? ` ${r.machineModel}` : ''}`,
              r.roaster && `Roaster: ${r.roaster}`,
              r.beanOrigins?.length && `Origins: ${r.beanOrigins.join(', ')}`,
              r.grinders?.length && `Grinders: ${r.grinders.join(', ')}`,
              r.drinks?.length &&
                `Drinks: ${r.drinks
                  .map((d) => (d.price != null ? `${d.name} $${d.price.toFixed(2)}` : d.name))
                  .join(', ')}`,
              r.milkBrands?.length && `Milk: ${r.milkBrands.join(', ')}`,
              r.note,
            ]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </li>
      ))}
    </ul>
  )
}

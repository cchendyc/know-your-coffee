import type { ReactNode } from 'react'

export function SectionHeader({ title, subtitle, action }: { title: string; subtitle: string; action?: ReactNode }) {
  return (
    <div className="sp-section-head">
      <div>
        <h2>{title}</h2>
        <p>{subtitle}</p>
      </div>
      {action}
    </div>
  )
}

// Sub-heading inside a tab panel; the tab already names the section.
export function SubHeader({ title, meta, action }: { title: string; meta?: string; action?: ReactNode }) {
  return (
    <div className="sp-subhead">
      <div>
        <h3>{title}</h3>
        {meta && <p>{meta}</p>}
      </div>
      {action}
    </div>
  )
}

// About-tab card: eyebrow row (with an optional card-level note on the right), then rows.
export function InfoCard({ eyebrow, tag, children }: { eyebrow: string; tag?: string | null; children: ReactNode }) {
  return (
    <div className="sp-card flex flex-col gap-1.5 px-4.5 py-4">
      <div className="flex items-baseline justify-between gap-2">
        <p className="sp-eyebrow">{eyebrow}</p>
        {tag && <p className="sp-eyebrow text-right">{tag}</p>}
      </div>
      {children}
    </div>
  )
}

export function Row({ label, children }: { label: string; children?: ReactNode }) {
  return (
    <div className="sp-row items-start">
      <span className="shrink-0">{label}</span>
      <span className="flex flex-wrap items-center justify-end gap-1.5">{children}</span>
    </div>
  )
}

export function Chip({ children }: { children: ReactNode }) {
  return <span className="sp-chip">{children}</span>
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="py-1 text-sm text-espresso-500">{children}</p>
}

type IconProps = { className?: string }
const stroke = (className: string | undefined, d: string, width = 2) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" className={className ?? 'size-4'}>
    <path d={d} />
  </svg>
)

export const PlusIcon = ({ className }: IconProps) => stroke(className, 'M12 5v14M5 12h14', 2.5)
export const CheckIcon = ({ className }: IconProps) => stroke(className, 'm5 12.5 4.5 4.5L19 7.5', 3)
export const ShareIcon = ({ className }: IconProps) => stroke(className, 'M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13')
export const DirectionsIcon = ({ className }: IconProps) => stroke(className, 'm3 11 19-9-9 19-2-8-8-2Z')
export const TruckIcon = ({ className }: IconProps) =>
  stroke(className, 'M1 5h14v11H1zM15 9h4l4 4v3h-8V9ZM7.5 18a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM20 18a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z')
export const BagIcon = ({ className }: IconProps) => stroke(className, 'M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4ZM3 6h18M16 10a4 4 0 0 1-8 0')

export function BookmarkIcon({ className, filled }: IconProps & { filled: boolean }) {
  return (
    <svg viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinejoin="round" className={className ?? 'size-4'}>
      <path d="M6 4h12v17l-6-4-6 4V4Z" />
    </svg>
  )
}

export function StarIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className ?? 'size-4'}>
      <path d="m12 2 3 6.3 6.9 1-5 4.8 1.2 6.9L12 17.8 5.9 21l1.2-6.9-5-4.8 6.9-1z" />
    </svg>
  )
}

export function BeanIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" className={className ?? 'size-4'}>
      <ellipse cx="12" cy="12" rx="6.5" ry="9" transform="rotate(30 12 12)" />
      <path d="M9.5 5.5c3 2 3 5 2 7s-1 5 2 7" />
    </svg>
  )
}

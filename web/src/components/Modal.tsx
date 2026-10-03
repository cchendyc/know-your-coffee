import type { ReactNode } from 'react'

export function Modal({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  return (
    <div
      className="fixed inset-0 z-[1200] flex items-start justify-center overflow-y-auto overscroll-contain bg-espresso-900/40 p-4"
      onMouseDown={(e) => e.target === e.currentTarget && onClose()}
    >
      <div className="my-8 w-full max-w-2xl rounded-2xl border border-cream-200 bg-cream-50 p-6">{children}</div>
    </div>
  )
}

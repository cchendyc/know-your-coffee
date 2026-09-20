import { useEffect, useRef, useState } from 'react'
import { fetchMyStats, signInWithGoogle, TOKEN_KEY, USER_KEY, type User } from '../api'

const CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (config: { client_id: string; callback: (r: { credential: string }) => void }) => void
          renderButton: (el: HTMLElement, options: Record<string, unknown>) => void
        }
      }
    }
  }
}

export function loadStoredUser(): User | null {
  const raw = localStorage.getItem(USER_KEY)
  return raw ? (JSON.parse(raw) as User) : null
}

export function AuthButton({ user, onChange }: { user: User | null; onChange: (u: User | null) => void }) {
  const buttonRef = useRef<HTMLDivElement>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (user || !CLIENT_ID || !buttonRef.current) return
    let cancelled = false
    const tryRender = () => {
      if (cancelled) return
      if (!window.google) {
        setTimeout(tryRender, 300)
        return
      }
      window.google.accounts.id.initialize({
        client_id: CLIENT_ID,
        callback: async ({ credential }) => {
          try {
            const { token, user: signedIn } = await signInWithGoogle(credential)
            localStorage.setItem(TOKEN_KEY, token)
            localStorage.setItem(USER_KEY, JSON.stringify(signedIn))
            onChange(signedIn)
          } catch (e) {
            setError((e as Error).message)
          }
        },
      })
      window.google.accounts.id.renderButton(buttonRef.current!, { theme: 'outline', size: 'medium', shape: 'pill' })
    }
    tryRender()
    return () => {
      cancelled = true
    }
  }, [user, onChange])

  if (!CLIENT_ID) {
    return (
      <button
        disabled
        title="Set VITE_GOOGLE_CLIENT_ID in web/.env.local to enable Google sign-in"
        className="cursor-not-allowed rounded-full border border-cream-200 px-3 py-1.5 text-xs font-medium text-espresso-500 opacity-60"
      >
        Sign in
      </button>
    )
  }

  if (user) {
    return <ProfileMenu user={user} onSignOut={() => onChange(null)} />
  }

  return (
    <div>
      <div ref={buttonRef} />
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  )
}

function ProfileMenu({ user, onSignOut }: { user: User; onSignOut: () => void }) {
  const [open, setOpen] = useState(false)
  const [stats, setStats] = useState<{ savedCount: number; beenCount: number } | null>(null)

  useEffect(() => {
    if (open) fetchMyStats().then(setStats).catch(() => setStats(null))
  }, [open])

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label="Profile"
        className="flex items-center gap-2 rounded-full transition hover:opacity-80"
      >
        {user.picture ? (
          <img src={user.picture} alt="" className="size-9 rounded-full ring-2 ring-crema-400/50" referrerPolicy="no-referrer" />
        ) : (
          <span className="flex size-9 items-center justify-center rounded-full bg-espresso-700 text-sm font-semibold text-cream-50">
            {user.name[0]}
          </span>
        )}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-20" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-30 mt-2 w-60 rounded-2xl border border-cream-200 bg-white p-4 shadow-lg">
            <p className="text-sm font-semibold">{user.name}</p>
            <p className="truncate text-xs text-espresso-500">{user.email}</p>
            <div className="mt-3 flex gap-2">
              <div className="flex-1 rounded-xl bg-cream-100 px-3 py-2 text-center">
                <p className="text-lg font-bold">{stats ? stats.savedCount : '·'}</p>
                <p className="text-[11px] text-espresso-500">Saved</p>
              </div>
              <div className="flex-1 rounded-xl bg-cream-100 px-3 py-2 text-center">
                <p className="text-lg font-bold">{stats ? stats.beenCount : '·'}</p>
                <p className="text-[11px] text-espresso-500">Been</p>
              </div>
            </div>
            <button
              onClick={() => {
                localStorage.removeItem(TOKEN_KEY)
                localStorage.removeItem(USER_KEY)
                setOpen(false)
                onSignOut()
              }}
              className="mt-3 w-full rounded-xl border border-cream-200 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-900"
            >
              Sign out
            </button>
          </div>
        </>
      )}
    </div>
  )
}

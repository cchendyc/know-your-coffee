import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import {
  fetchMyStats,
  signInWithEmail,
  signInWithGoogle,
  startEmailSignIn,
  TOKEN_KEY,
  USER_KEY,
  type User,
} from '../api'

// trim(): a trailing newline pasted into the env/CI variable makes Google
// reject the client ID with "invalid_client: The OAuth client was not found".
const CLIENT_ID = (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined)?.trim()

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

export function AuthButton({
  user,
  onChange,
  isSeller = false,
  onOpenSellerHub,
  onBecomeSeller,
}: {
  user: User | null
  onChange: (u: User | null) => void
  isSeller?: boolean
  onOpenSellerHub?: () => void
  onBecomeSeller?: () => void
}) {
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

  if (user) {
    return (
      <ProfileMenu
        user={user}
        isSeller={isSeller}
        onOpenSellerHub={onOpenSellerHub}
        onBecomeSeller={onBecomeSeller}
        onSignOut={() => onChange(null)}
      />
    )
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex items-center gap-2">
        {CLIENT_ID ? (
          <div ref={buttonRef} />
        ) : (
          <button
            disabled
            title="Set VITE_GOOGLE_CLIENT_ID in web/.env.local to enable Google sign-in"
            className="cursor-not-allowed rounded-full border border-cream-200 px-3 py-1.5 text-xs font-medium text-espresso-500 opacity-60"
          >
            Google
          </button>
        )}
        <EmailSignIn onChange={onChange} />
      </div>
      {error && <p className="max-w-xs text-right text-xs text-red-600">{error}</p>}
    </div>
  )
}

// Email one-time code sign-in in a small popover: address, then the code.
function EmailSignIn({ onChange }: { onChange: (u: User | null) => void }) {
  const [open, setOpen] = useState(false)
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [codeSent, setCodeSent] = useState(false)
  const [devCode, setDevCode] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setBusy(true)
    setError(null)
    try {
      if (codeSent) {
        const { token, user } = await signInWithEmail(email, code)
        localStorage.setItem(TOKEN_KEY, token)
        localStorage.setItem(USER_KEY, JSON.stringify(user))
        setOpen(false)
        onChange(user)
      } else {
        const res = await startEmailSignIn(email)
        setDevCode(res.devCode)
        setCodeSent(true)
        setCode('')
      }
    } catch (e) {
      setError((e as Error).message)
    }
    setBusy(false)
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="rounded-full border border-cream-200 px-3 py-1.5 text-xs font-medium text-espresso-700 transition hover:border-crema-400"
      >
        Email
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-20" onClick={() => setOpen(false)} />
          <form
            className="absolute right-0 z-30 mt-2 w-64 rounded-2xl border border-cream-200 bg-white p-4 shadow-lg"
            onSubmit={(e) => {
              e.preventDefault()
              void submit()
            }}
          >
            <p className="text-xs text-espresso-500">
              {codeSent ? `Enter the code we sent to ${email}.` : "We'll email you a sign-in code."}
            </p>
            {codeSent ? (
              <input
                autoFocus
                value={code}
                onChange={(e) => setCode(e.target.value)}
                inputMode="numeric"
                placeholder="6-digit code"
                className="mt-2 w-full rounded-xl border border-cream-200 px-3 py-2 text-center font-mono text-sm outline-none focus:border-crema-400"
              />
            ) : (
              <input
                autoFocus
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                className="mt-2 w-full rounded-xl border border-cream-200 px-3 py-2 text-sm outline-none focus:border-crema-400"
              />
            )}
            {devCode && codeSent && (
              <p className="mt-1 font-mono text-[11px] text-crema-500">Dev backend, no email provider. Code: {devCode}</p>
            )}
            {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
            <button
              type="submit"
              disabled={busy || (codeSent ? code.length < 6 : email.length < 6)}
              className="mt-3 w-full rounded-xl bg-espresso-700 py-2 text-xs font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-50"
            >
              {busy ? '…' : codeSent ? 'Sign in' : 'Send code'}
            </button>
            {codeSent && (
              <button
                type="button"
                onClick={() => {
                  setCodeSent(false)
                  setCode('')
                  setDevCode(null)
                  setError(null)
                }}
                className="mt-2 w-full text-center text-[11px] text-espresso-500 hover:text-espresso-900"
              >
                Use a different email
              </button>
            )}
          </form>
        </>
      )}
    </div>
  )
}

function ProfileMenu({
  user,
  isSeller,
  onOpenSellerHub,
  onBecomeSeller,
  onSignOut,
}: {
  user: User
  isSeller: boolean
  onOpenSellerHub?: () => void
  onBecomeSeller?: () => void
  onSignOut: () => void
}) {
  const [open, setOpen] = useState(false)
  const [stats, setStats] = useState<{ savedCount: number; beenCount: number } | null>(null)

  useEffect(() => {
    if (!open) return
    fetchMyStats().then(setStats).catch(() => setStats(null))
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  return (
    <div>
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label="Profile"
        className={`flex items-center gap-2 rounded-full transition duration-200 hover:opacity-80 ${
          open ? 'pointer-events-none scale-75 opacity-0' : ''
        }`}
      >
        {user.picture ? (
          <img src={user.picture} alt="" className="size-9 rounded-full ring-2 ring-crema-400/50" referrerPolicy="no-referrer" />
        ) : (
          <span className="flex size-9 items-center justify-center rounded-full bg-espresso-700 text-sm font-semibold text-cream-50">
            {user.name[0]}
          </span>
        )}
      </button>

      {createPortal(
        // Portaled: the header's backdrop-blur would otherwise contain these fixed layers.
        <>
          {open && <div onClick={() => setOpen(false)} className="fixed inset-0 z-40" />}
          {/* Always mounted so the panel can slide in and out. */}
          <aside
            aria-hidden={!open}
            className={`fixed inset-y-0 right-0 z-50 flex w-80 max-w-[85vw] flex-col border-l border-cream-200 bg-white p-5 shadow-xl transition-transform duration-200 ${
              open ? 'translate-x-0' : 'pointer-events-none translate-x-full'
            }`}
          >
            <div className="flex items-start gap-3">
              {user.picture ? (
                <img src={user.picture} alt="" className="size-11 rounded-full" referrerPolicy="no-referrer" />
              ) : (
                <span className="flex size-11 shrink-0 items-center justify-center rounded-full bg-espresso-700 font-semibold text-cream-50">
                  {user.name[0]}
                </span>
              )}
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold">{user.name}</p>
                <p className="truncate text-xs text-espresso-500">{user.email ?? user.phone}</p>
              </div>
              <button
                onClick={() => setOpen(false)}
                aria-label="Close"
                className="rounded-lg px-2 py-1 text-espresso-500 hover:text-espresso-900"
              >
                ✕
              </button>
            </div>
            <div className="mt-5 flex gap-2">
              <div className="flex-1 rounded-xl bg-cream-100 px-3 py-2 text-center">
                <p className="text-lg font-bold">{stats ? stats.savedCount : '·'}</p>
                <p className="text-[11px] text-espresso-500">Saved</p>
              </div>
              <div className="flex-1 rounded-xl bg-cream-100 px-3 py-2 text-center">
                <p className="text-lg font-bold">{stats ? stats.beenCount : '·'}</p>
                <p className="text-[11px] text-espresso-500">Been</p>
              </div>
            </div>
            {isSeller ? (
              <button
                onClick={() => {
                  setOpen(false)
                  onOpenSellerHub?.()
                }}
                className="mt-3 flex w-full items-center gap-2.5 rounded-xl bg-espresso-700 px-3 py-2.5 text-left text-xs font-semibold text-cream-50 transition hover:bg-espresso-900"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
                  <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4ZM3 6h18M16 10a4 4 0 0 1-8 0" />
                </svg>
                Seller Hub
              </button>
            ) : (
              <button
                onClick={() => {
                  setOpen(false)
                  onBecomeSeller?.()
                }}
                className="mt-3 flex w-full items-center gap-2.5 rounded-xl border border-cream-200 px-3 py-2.5 text-left text-xs font-medium text-espresso-700 transition hover:border-crema-400"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-4">
                  <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4ZM3 6h18M16 10a4 4 0 0 1-8 0" />
                </svg>
                Become a seller
              </button>
            )}
            <button
              onClick={() => {
                localStorage.removeItem(TOKEN_KEY)
                localStorage.removeItem(USER_KEY)
                setOpen(false)
                onSignOut()
              }}
              className="mt-auto w-full rounded-xl border border-cream-200 py-2 text-xs font-medium text-espresso-500 transition hover:border-crema-400 hover:text-espresso-900"
            >
              Sign out
            </button>
          </aside>
        </>,
        document.body,
      )}
    </div>
  )
}

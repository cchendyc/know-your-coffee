import { useEffect, useState } from 'react'
import {
  fetchMe,
  fetchPendingApplications,
  resolveApplication,
  signInWithEmail,
  signOut,
  startEmailSignIn,
  storedToken,
  type Me,
  type SellerApplication,
} from './api'

function timeAgo(iso: string) {
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60_000)
  if (mins < 60) return `${Math.max(mins, 0)}m ago`
  if (mins < 24 * 60) return `${Math.floor(mins / 60)}h ago`
  return `${Math.floor(mins / (24 * 60))}d ago`
}

// MARK: Sign-in

function SignIn({ onSignedIn }: { onSignedIn: (me: Me) => void }) {
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [stage, setStage] = useState<'email' | 'code'>('email')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const input =
    'w-full rounded-xl border border-cream-200 bg-white px-4 py-3 text-sm outline-none focus:border-crema-400'

  const sendCode = () => {
    setBusy(true)
    setError(null)
    startEmailSignIn(email.trim())
      .then((r) => {
        setStage('code')
        setNotice(r.devCode ? `Dev code: ${r.devCode}` : 'Code sent — check your email.')
      })
      .catch((e: Error) => {
        // Resend cooldown means a code is already in their inbox; let them type it.
        if (/just sent/i.test(e.message)) {
          setStage('code')
          setNotice('A code was already sent — check your email.')
        } else {
          setError(e.message)
        }
      })
      .finally(() => setBusy(false))
  }

  const verify = () => {
    setBusy(true)
    setError(null)
    signInWithEmail(email.trim(), code.trim())
      .then((user) => {
        if (user.role !== 'ADMIN') {
          signOut()
          throw new Error('This console is for support staff. Your account is not an admin.')
        }
        onSignedIn(user)
      })
      .catch((e: Error) => setError(e.message))
      .finally(() => setBusy(false))
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <form
        className="w-full max-w-sm rounded-2xl border border-cream-200 bg-white p-6 shadow-sm"
        onSubmit={(e) => {
          e.preventDefault()
          stage === 'email' ? sendCode() : verify()
        }}
      >
        <h1 className="text-lg font-bold">KYC Support Console</h1>
        <p className="mt-1 mb-5 text-sm text-espresso-500">Admin accounts only. Sign in with your email.</p>
        {stage === 'email' ? (
          <input
            className={input}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@knowyourcoffee.app"
            type="email"
            autoFocus
          />
        ) : (
          <input
            className={`${input} text-center font-mono text-lg tracking-[0.4em]`}
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="000000"
            inputMode="numeric"
            autoFocus
          />
        )}
        {notice && <p className="mt-3 text-sm text-green-700">{notice}</p>}
        {error && <p className="mt-3 text-sm text-red-700">{error}</p>}
        <button
          type="submit"
          disabled={busy || (stage === 'email' ? !email.trim() : !code.trim())}
          className="mt-4 w-full rounded-xl bg-espresso-700 py-3 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-50"
        >
          {busy ? '…' : stage === 'email' ? 'Send code' : 'Sign in'}
        </button>
        {stage === 'email' ? (
          <button
            type="button"
            disabled={!email.trim()}
            onClick={() => {
              setError(null)
              setStage('code')
            }}
            className="mt-3 w-full text-center text-xs font-medium text-espresso-500 hover:text-espresso-900 disabled:opacity-50"
          >
            Already have a code?
          </button>
        ) : (
          <button
            type="button"
            onClick={() => {
              setError(null)
              setNotice(null)
              setCode('')
              setStage('email')
            }}
            className="mt-3 w-full text-center text-xs font-medium text-espresso-500 hover:text-espresso-900"
          >
            Use a different email
          </button>
        )}
      </form>
    </div>
  )
}

// MARK: Application queue

function ApplicationCard({
  application,
  onResolved,
}: {
  application: SellerApplication
  onResolved: (id: string) => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const resolve = (approve: boolean) => {
    setBusy(true)
    resolveApplication(application.id, approve)
      .then(() => onResolved(application.id))
      .catch((e: Error) => setError(e.message))
      .finally(() => setBusy(false))
  }

  const detail = (label: string, value: React.ReactNode) => (
    <div className="flex gap-2 text-sm">
      <span className="w-20 shrink-0 text-xs font-semibold tracking-wide text-espresso-500 uppercase">{label}</span>
      <span className="min-w-0">{value}</span>
    </div>
  )

  return (
    <article className="rounded-2xl border border-cream-200 bg-white p-5 shadow-sm">
      <header className="mb-3 flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          {application.applicant?.picture ? (
            <img src={application.applicant.picture} alt="" className="size-9 rounded-full" />
          ) : (
            <div className="flex size-9 items-center justify-center rounded-full bg-cream-100 text-sm font-semibold text-espresso-500">
              {(application.applicant?.name ?? '?').slice(0, 1)}
            </div>
          )}
          <div>
            <div className="text-sm font-semibold">{application.applicant?.name ?? 'Deleted account'}</div>
            <div className="text-xs text-espresso-500">
              applying for <span className="font-medium text-espresso-900">{application.shop.name}</span> ·{' '}
              {application.shop.city}
            </div>
          </div>
        </div>
        <span className="shrink-0 text-xs text-espresso-500">{timeAgo(application.createdAt)}</span>
      </header>

      <div className="flex flex-col gap-1.5 border-t border-cream-200 pt-3">
        {application.businessRole && detail('Role', application.businessRole)}
        {application.contact && detail('Contact', application.contact)}
        {application.website &&
          detail(
            'Proof',
            <a
              href={application.website.startsWith('http') ? application.website : `https://${application.website}`}
              target="_blank"
              rel="noreferrer"
              className="break-all text-crema-500 underline-offset-2 hover:underline"
            >
              {application.website}
            </a>,
          )}
        {application.note && detail('Note', <span className="text-espresso-500">{application.note}</span>)}
        {detail('Address', <span className="text-espresso-500">{application.shop.address}</span>)}
      </div>

      {error && <p className="mt-3 text-sm text-red-700">{error}</p>}

      <footer className="mt-4 flex gap-2">
        <button
          disabled={busy}
          onClick={() => resolve(true)}
          className="rounded-xl bg-espresso-700 px-4 py-2 text-sm font-semibold text-cream-50 transition hover:bg-espresso-900 disabled:opacity-50"
        >
          Approve — grant seller access
        </button>
        <button
          disabled={busy}
          onClick={() => resolve(false)}
          className="rounded-xl border border-cream-200 bg-white px-4 py-2 text-sm font-medium text-red-700 transition hover:border-red-300 disabled:opacity-50"
        >
          Reject
        </button>
      </footer>
    </article>
  )
}

function Console({ me }: { me: Me }) {
  const [applications, setApplications] = useState<SellerApplication[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = () => fetchPendingApplications().then(setApplications).catch((e: Error) => setError(e.message))

  useEffect(() => {
    load()
    // Support keeps this open all day; poll so new applications show up.
    const t = setInterval(load, 60_000)
    return () => clearInterval(t)
  }, [])

  return (
    <div className="flex min-h-screen">
      <aside className="flex w-60 shrink-0 flex-col border-r border-cream-200 bg-white/60 p-4">
        <div className="mb-4 px-1">
          <div className="text-sm font-bold">Know Your Coffee</div>
          <div className="text-[11px] text-espresso-500">Support console</div>
        </div>

        <nav className="flex flex-col gap-0.5">
          <div className="flex items-center justify-between rounded-xl bg-espresso-700 px-3 py-2.5 text-sm font-semibold text-cream-50">
            Seller applications
            {applications && applications.length > 0 && (
              <span className="rounded-full bg-cream-50/20 px-2 py-0.5 text-xs">{applications.length}</span>
            )}
          </div>
        </nav>

        <div className="mt-auto flex items-center justify-between px-1 text-xs text-espresso-500">
          <span className="truncate">{me.email ?? me.name}</span>
          <button
            onClick={() => {
              signOut()
              window.location.reload()
            }}
            className="ml-2 shrink-0 font-semibold hover:text-espresso-900"
          >
            Sign out
          </button>
        </div>
      </aside>

      <main className="flex-1 overflow-y-auto px-8 py-7">
        <div className="mb-5">
          <h2 className="text-xl font-bold tracking-tight">Seller applications</h2>
          <p className="mt-0.5 text-sm text-espresso-500">
            Oldest first. Approving grants the applicant Seller Hub access for their shop.
          </p>
        </div>

        {error && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>
        )}

        {applications && (
          <div className="flex max-w-2xl flex-col gap-4">
            {applications.map((application) => (
              <ApplicationCard
                key={application.id}
                application={application}
                onResolved={(id) => setApplications((prev) => prev!.filter((a) => a.id !== id))}
              />
            ))}
            {applications.length === 0 && (
              <div className="rounded-2xl border border-dashed border-cream-200 p-10 text-center text-sm text-espresso-500">
                Queue clear — no pending seller applications.
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  )
}

export default function App() {
  const [me, setMe] = useState<Me | null>(null)
  const [checking, setChecking] = useState(!!storedToken())

  // Restore the session; non-admins are treated as signed out.
  useEffect(() => {
    if (!storedToken()) return
    fetchMe()
      .then((user) => {
        if (user?.role === 'ADMIN') setMe(user)
        else signOut()
      })
      .catch(() => signOut())
      .finally(() => setChecking(false))
  }, [])

  if (checking) return null
  return me ? <Console me={me} /> : <SignIn onSignedIn={setMe} />
}

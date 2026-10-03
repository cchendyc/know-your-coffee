import { useState } from 'react'
import { submitReview, type Review, type User } from '../api'
import { timeAgo } from '../format'
import { StarIcon } from './bits'
import { plural } from './util'

const AVATAR_COLORS = ['#c08c3e', '#3d5a80', '#6f4e37', '#5a7d5a', '#8a5a7d']
const MAX_BODY = 2000

export function ReviewsSection({
  shopId,
  shopName,
  reviews,
  reviewCount,
  ratingAverage,
  myReview,
  user,
  onSubmitted,
}: {
  shopId: string
  shopName: string
  reviews: Review[]
  reviewCount: number
  ratingAverage: number | null
  myReview: Review | null
  user: User | null
  onSubmitted: () => void
}) {
  const [open, setOpen] = useState(false)
  const [needSignIn, setNeedSignIn] = useState(false)
  const [rating, setRating] = useState(myReview?.rating ?? 0)
  const [body, setBody] = useState(myReview?.body ?? '')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const start = () => {
    if (!user) {
      setNeedSignIn(true)
      return
    }
    setRating(myReview?.rating ?? 0)
    setBody(myReview?.body ?? '')
    setError(null)
    setOpen(true)
  }

  const send = async () => {
    if (!user) {
      setNeedSignIn(true)
      return
    }
    if (rating < 1) {
      setError('Pick a star rating.')
      return
    }
    setBusy(true)
    setError(null)
    try {
      await submitReview({ shopId, rating, body: body.trim() || null })
    } catch (e) {
      setError((e as Error).message)
      setBusy(false)
      return
    }
    setBusy(false)
    setOpen(false)
    onSubmitted()
  }

  return (
    <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
        <div className="sp-card flex w-full flex-col gap-4 p-5 lg:w-[340px] lg:shrink-0">
          <div className="flex items-center gap-3">
            <p className={`text-xl leading-none font-bold ${ratingAverage == null ? 'text-espresso-500/40' : ''}`}>
              {ratingAverage == null ? '–' : ratingAverage.toFixed(1)}
            </p>
            <div>
              <Stars value={ratingAverage == null ? 0 : Math.round(ratingAverage)} />
              <p className="mt-1 text-[13px] text-espresso-500">
                {reviewCount === 0 ? 'No ratings yet' : plural(reviewCount, 'rating')}
              </p>
            </div>
          </div>
          <div className="h-px bg-cream-200" />
          <div>
            <p className="text-sm font-semibold">Review this shop</p>
            {needSignIn && !user && <p className="text-xs text-espresso-500">Sign in (top right) to leave a review.</p>}
            {open ? (
              <form
                className="mt-3 flex flex-col gap-3"
                onSubmit={(e) => {
                  e.preventDefault()
                  void send()
                }}
              >
                <Stars value={rating} onPick={setRating} />
                <textarea
                  value={body}
                  maxLength={MAX_BODY}
                  rows={4}
                  onChange={(e) => setBody(e.target.value)}
                  placeholder={`What was ${shopName} like?`}
                  className="w-full resize-y rounded-xl border border-cream-200 bg-white px-3 py-2 text-sm"
                />
                {error && <p className="text-xs text-red-700">{error}</p>}
                <div className="flex gap-2">
                  <button type="submit" disabled={busy} className="sp-pill sp-pill--dark sp-pill--sm flex-1">
                    {busy ? 'Saving…' : myReview ? 'Update review' : 'Post review'}
                  </button>
                  <button type="button" onClick={() => setOpen(false)} className="sp-pill sp-pill--outline sp-pill--sm">
                    Cancel
                  </button>
                </div>
              </form>
            ) : (
              <button type="button" onClick={start} className="sp-pill sp-pill--outline sp-pill--sm mt-2 w-full">
                {myReview ? 'Edit your review' : 'Write a review'}
              </button>
            )}
          </div>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {reviews.length === 0 ? (
            <div className="sp-card flex items-center justify-center p-10 text-sm text-espresso-500">
              No reviews yet.
            </div>
          ) : (
            reviews.map((review) => <ReviewCard key={review.id} review={review} />)
          )}
        </div>
    </div>
  )
}

function ReviewCard({ review }: { review: Review }) {
  const name = review.author?.name ?? 'Anonymous'
  const color = AVATAR_COLORS[name.charCodeAt(0) % AVATAR_COLORS.length]
  return (
    <div className="sp-card sp-record">
      {review.author?.picture ? (
        <img src={review.author.picture} alt="" className="size-8 shrink-0 rounded-full" referrerPolicy="no-referrer" />
      ) : (
        <span className="sp-avatar-sm" style={{ backgroundColor: color }}>
          {name[0].toUpperCase()}
        </span>
      )}
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <p className="flex flex-wrap items-center gap-2">
          <span className="text-[13px] font-semibold">{name}</span>
          <Stars value={review.rating} size="size-3.5" />
          <span className="text-xs text-espresso-500">{timeAgo(review.createdAt)}</span>
        </p>
        {review.body && <p className="text-sm">{review.body}</p>}
      </div>
    </div>
  )
}

function Stars({
  value,
  onPick,
  size = 'size-4',
}: {
  value: number
  onPick?: (n: number) => void
  size?: string
}) {
  return (
    <div className="flex gap-0.5">
      {[1, 2, 3, 4, 5].map((n) => {
        const icon = <StarIcon className={`${size} ${n <= value ? 'text-crema-500' : 'text-cream-200'}`} />
        if (!onPick) return <span key={n}>{icon}</span>
        return (
          <button key={n} type="button" onClick={() => onPick(n)} aria-label={`${n} star${n === 1 ? '' : 's'}`}>
            {icon}
          </button>
        )
      })}
    </div>
  )
}

import type { DeliverySettings } from './api'

export function timeAgo(iso: string) {
  const mins = Math.max(1, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
  if (mins < 60) return `${mins} min ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `${hours} hr ago`
  const days = Math.round(hours / 24)
  if (days < 7) return `${days} day${days === 1 ? '' : 's'} ago`
  const weeks = Math.round(days / 7)
  if (weeks < 9) return `${weeks} week${weeks === 1 ? '' : 's'} ago`
  return `${Math.round(days / 30)} months ago`
}

export function hostname(url: string) {
  try {
    return new URL(url).hostname.replace(/^www\./, '')
  } catch {
    return url
  }
}

export function deliveryCopy(d: DeliverySettings, city: string) {
  if (d.shipping && d.pickup) return `Ships or pick up in ${city}`
  if (d.shipping) return 'Ships to you'
  if (d.pickup) return `Pick up in ${city}`
  return ''
}

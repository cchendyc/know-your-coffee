// Seller Hub URLs:
//   /dashboard                         all shops overview
//   /dashboard/orders|shipments        all shops, one tab
//   /dashboard/:shopId                 one shop overview
//   /dashboard/:shopId/listings        listings; /new or /:productId opens the editor
//   /dashboard/:shopId/orders|shipments

export const HUB_ROOT = '/dashboard'

export type HubTab = 'overview' | 'listings' | 'orders' | 'shipments'
const TABS: HubTab[] = ['overview', 'listings', 'orders', 'shipments']

export interface HubRoute {
  shopId: string | null // null = all shops
  tab: HubTab
  listing: 'new' | string | null // product id, only under listings
}

export function hubPath(shopId: string | null, tab: HubTab = 'overview', listing?: string | null): string {
  const parts = [HUB_ROOT]
  if (shopId) parts.push(shopId)
  if (tab !== 'overview') parts.push(tab)
  if (listing && tab === 'listings') parts.push(listing)
  return parts.join('/')
}

// `rest` is the splat after /dashboard/. Shop ids are numeric, so a leading
// tab name can never be mistaken for a shop.
export function parseHubPath(rest: string): HubRoute {
  const segments = rest.split('/').filter(Boolean)
  const shopId = segments[0] && !(TABS as string[]).includes(segments[0]) ? segments.shift()! : null
  const tab = (TABS as string[]).includes(segments[0] ?? '') ? (segments[0] as HubTab) : 'overview'
  const listing = tab === 'listings' && segments[1] ? segments[1] : null
  return { shopId, tab, listing }
}

// Last-opened shop per device; the PRD leaves server-side persistence open.
const VIEW_KEY = 'kyc_hub_view'

export function rememberHubShop(shopId: string | null) {
  localStorage.setItem(VIEW_KEY, shopId ?? '')
}

// Where the "Seller Hub" buttons land: the only shop, else the last one opened.
export function hubHome(shops: { id: string }[]): string {
  if (shops.length === 1) return hubPath(shops[0].id)
  const saved = localStorage.getItem(VIEW_KEY)
  return hubPath(saved && shops.some((s) => s.id === saved) ? saved : null)
}

export type MachineBrand =
  | 'LA_MARZOCCO'
  | 'SLAYER'
  | 'SYNESSO'
  | 'KEES_VAN_DER_WESTEN'
  | 'VICTORIA_ARDUINO'
  | 'NUOVA_SIMONELLI'
  | 'MODBAR'
  | 'ROCKET'
  | 'RANCILIO'
  | 'BREVILLE'
  | 'DECENT'
  | 'OTHER'
  | 'UNKNOWN'

export type BeanSource = 'IN_HOUSE_ROAST' | 'LOCAL_ROASTER' | 'NATIONAL_ROASTER' | 'MULTI_ROASTER' | 'UNKNOWN'

export interface DrinkItem {
  name: string
  price: number | null
}

export type PhotoKind = 'MACHINE' | 'BEANS' | 'DRINKS' | 'MENU' | 'VIBE' | 'OTHER'

export interface ShopPhoto {
  id: string
  kind: PhotoKind
  data: string
  uploader: { name: string; picture: string | null } | null
  createdAt: string
}

export interface Report {
  id: string
  machine: MachineBrand | null
  machineModel: string | null
  beanSource: BeanSource | null
  roaster: string | null
  beanOrigins: string[] | null
  grinders: string[] | null
  drinks: DrinkItem[] | null
  milkBrands: string[] | null
  dogFriendly: boolean | null
  wifi: boolean | null
  outdoorSeating: boolean | null
  note: string | null
  source: 'TEXT' | 'PHOTO'
  reporter: { name: string; picture: string | null } | null
  createdAt: string
}

export interface User {
  id: string
  name: string
  email: string
  picture: string | null
}

export interface CoffeeShop {
  id: string
  name: string
  address: string
  city: string
  lat: number
  lng: number
  machine: MachineBrand
  machineModel: string | null
  beanSource: BeanSource
  roaster: string | null
  beanOrigins: string[]
  grinders: string[]
  drinks: DrinkItem[]
  milkBrands: string[]
  vibe: string | null
  dogFriendly: boolean | null
  wifi: boolean | null
  outdoorSeating: boolean | null
  photoUrl: string | null
  website: string | null
  savedByMe: boolean
  beenByMe: boolean
  updatedAt: string
  photos: ShopPhoto[]
  reports: Report[]
}

export interface MachineGuess {
  machine: MachineBrand
  machineModel: string | null
  confidence: number
  notes: string | null
}

export interface ReportInput {
  shopId: string
  machine?: MachineBrand | null
  machineModel?: string | null
  beanSource?: BeanSource | null
  roaster?: string | null
  beanOrigins?: string[] | null
  grinders?: string[] | null
  drinks?: DrinkItem[] | null
  milkBrands?: string[] | null
  dogFriendly?: boolean | null
  wifi?: boolean | null
  outdoorSeating?: boolean | null
  note?: string | null
  source: 'TEXT' | 'PHOTO'
}

export const TOKEN_KEY = 'kyc_token'
export const USER_KEY = 'kyc_user'

// In production the API lives on another host (e.g. Render); locally Vite proxies /graphql.
const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.trim() || '/graphql'

async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const token = localStorage.getItem(TOKEN_KEY)
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ query, variables }),
  })
  const json = (await res.json()) as { data?: T; errors?: { message: string }[] }
  if (json.errors?.length) {
    const message = json.errors[0].message
    // Session token no longer valid (e.g. server restart): drop the stale
    // login instead of showing a signed-in header that can't do anything.
    if (token && message.includes('Sign in with Google')) {
      localStorage.removeItem(TOKEN_KEY)
      localStorage.removeItem(USER_KEY)
      window.dispatchEvent(new Event('kyc:session-expired'))
      throw new Error('Your session expired. Please sign in again (top right).')
    }
    throw new Error(message)
  }
  return json.data as T
}

const SHOP_FIELDS = `
  id name address city lat lng
  machine machineModel beanSource roaster beanOrigins grinders drinks { name price }
  milkBrands vibe dogFriendly wifi outdoorSeating photoUrl website savedByMe beenByMe updatedAt
`

export interface ShopPage {
  shops: CoffeeShop[]
  total: number
}

export function fetchShops(filter: {
  search?: string
  machine?: MachineBrand | ''
  saved?: boolean
  been?: boolean
  limit?: number
  offset?: number
}) {
  return gql<{ shops: ShopPage }>(
    `query Shops($search: String, $machine: MachineBrand, $saved: Boolean, $been: Boolean, $limit: Int!, $offset: Int!) {
      shops(search: $search, machine: $machine, saved: $saved, been: $been, limit: $limit, offset: $offset) {
        total
        shops { ${SHOP_FIELDS} }
      }
    }`,
    {
      search: filter.search || null,
      machine: filter.machine || null,
      saved: filter.saved || null,
      been: filter.been || null,
      limit: filter.limit ?? 24,
      offset: filter.offset ?? 0,
    },
  ).then((d) => d.shops)
}

export function fetchMyStats() {
  return gql<{ me: { savedCount: number; beenCount: number } | null }>(
    `query MyStats { me { savedCount beenCount } }`,
  ).then((d) => d.me)
}

export function fetchShop(id: string) {
  return gql<{ shop: CoffeeShop | null }>(
    `query Shop($id: ID!) {
      shop(id: $id) {
        ${SHOP_FIELDS}
        photos { id kind data createdAt uploader { name picture } }
        reports {
          id machine machineModel beanSource roaster beanOrigins grinders drinks { name price }
          milkBrands dogFriendly wifi outdoorSeating note source createdAt reporter { name picture }
        }
      }
    }`,
    { id },
  ).then((d) => d.shop)
}

export function submitReport(input: ReportInput) {
  return gql<{ submitReport: { id: string } }>(
    `mutation Submit($input: ReportInput!) { submitReport(input: $input) { id } }`,
    { input },
  )
}

export function signInWithGoogle(idToken: string) {
  return gql<{ signInWithGoogle: { token: string; user: User } }>(
    `mutation SignIn($idToken: String!) {
      signInWithGoogle(idToken: $idToken) { token user { id name email picture } }
    }`,
    { idToken },
  ).then((d) => d.signInWithGoogle)
}

export interface PlaceSuggestion {
  placeId: string
  name: string
  address: string
}

export interface PlacePreview {
  placeId: string
  name: string
  address: string
  city: string
  lat: number
  lng: number
  photoUrl: string | null
  website: string | null
  isCoffeeShop: boolean
  existing: CoffeeShop | null
}

export function searchPlaces(query: string) {
  return gql<{ searchPlaces: PlaceSuggestion[] }>(
    `query SearchPlaces($query: String!) { searchPlaces(query: $query) { placeId name address } }`,
    { query },
  ).then((d) => d.searchPlaces)
}

export function fetchPlacePreview(placeId: string) {
  return gql<{ placePreview: PlacePreview | null }>(
    `query PlacePreview($placeId: ID!) {
        placePreview(placeId: $placeId) {
        placeId name address city lat lng photoUrl website isCoffeeShop
        existing { ${SHOP_FIELDS} }
      }
    }`,
    { placeId },
  ).then((d) => d.placePreview)
}

export function addShopFromPlace(placeId: string) {
  return gql<{ addShopFromPlace: CoffeeShop }>(
    `mutation AddShopFromPlace($placeId: ID!) {
      addShopFromPlace(placeId: $placeId) { ${SHOP_FIELDS} }
    }`,
    { placeId },
  ).then((d) => d.addShopFromPlace)
}

export function identifyMachine(imageBase64: string) {
  return gql<{ identifyMachine: MachineGuess }>(
    `mutation Identify($imageBase64: String!) {
      identifyMachine(imageBase64: $imageBase64) { machine machineModel confidence notes }
    }`,
    { imageBase64 },
  ).then((d) => d.identifyMachine)
}

export function setShopStatus(shopId: string, status: { saved?: boolean; been?: boolean }) {
  return gql<{ setShopStatus: CoffeeShop }>(
    `mutation SetStatus($shopId: ID!, $saved: Boolean, $been: Boolean) {
      setShopStatus(shopId: $shopId, saved: $saved, been: $been) { ${SHOP_FIELDS} }
    }`,
    { shopId, saved: status.saved ?? null, been: status.been ?? null },
  ).then((d) => d.setShopStatus)
}

export function addShopPhotos(shopId: string, photos: { kind: PhotoKind; data: string }[]) {
  return gql<{ addShopPhotos: ShopPhoto[] }>(
    `mutation AddPhotos($shopId: ID!, $photos: [PhotoInput!]!) {
      addShopPhotos(shopId: $shopId, photos: $photos) { id kind data createdAt }
    }`,
    { shopId, photos },
  ).then((d) => d.addShopPhotos)
}

export function parseMenu(imageBase64: string) {
  return gql<{ parseMenu: DrinkItem[] }>(
    `mutation ParseMenu($imageBase64: String!) {
      parseMenu(imageBase64: $imageBase64) { name price }
    }`,
    { imageBase64 },
  ).then((d) => d.parseMenu)
}

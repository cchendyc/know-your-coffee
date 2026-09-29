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
  | 'FAEMA'
  | 'OTHER'
  | 'UNKNOWN'

export type BeanSource =
  | 'IN_HOUSE_ROAST'
  | 'LOCAL_ROASTER'
  | 'NATIONAL_ROASTER'
  | 'MULTI_ROASTER'
  | 'PRIVATE_LABEL'
  | 'DISTRIBUTOR'
  | 'UNKNOWN'

export interface DrinkItem {
  name: string
  price: number | null
}

export type PhotoKind = 'MACHINE' | 'BEANS' | 'DRINKS' | 'MENU' | 'VIBE' | 'OTHER'

// One espresso machine on the bar.
export interface Machine {
  brand: MachineBrand
  model: string | null
}

export interface MachineInput {
  brand: MachineBrand
  model?: string | null
}

export type CoffeeType = 'SINGLE_ORIGIN' | 'BLEND'
export type CoffeeProcess = 'WASHED' | 'NATURAL' | 'HONEY' | 'WET_HULLED' | 'OTHER'
export type RoastLevel = 'LIGHT' | 'MEDIUM' | 'DARK'

// One coffee on bar. Every field optional; report what the bag shows.
export interface Coffee {
  name: string | null
  roaster: string | null
  type: CoffeeType | null
  origins: string[]
  process: CoffeeProcess | null
  // Free text; legacy rows hold enum tokens like ANAEROBIC.
  fermentation: string | null
  roastLevel: RoastLevel | null
  varieties: string[]
  tastingNotes: string[]
}

export interface CoffeeInput {
  name?: string | null
  roaster?: string | null
  type?: CoffeeType | null
  origins?: string[]
  process?: CoffeeProcess | null
  fermentation?: string | null
  roastLevel?: RoastLevel | null
  varieties?: string[]
  tastingNotes?: string[]
}

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
  machines: Machine[] | null
  beanSource: BeanSource | null
  roaster: string | null
  beanOrigins: string[] | null
  coffees: Coffee[] | null
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

export type UserRole = 'USER' | 'ADMIN'

export interface User {
  id: string
  name: string
  email: string | null // null for phone-only accounts
  phone: string | null
  picture: string | null
  role?: UserRole
}

export function isAdmin(user: User | null | undefined): boolean {
  return user?.role === 'ADMIN'
}

export interface ChainLocation {
  id: string
  name: string
  address: string
  city: string
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
  machines: Machine[]
  beanSource: BeanSource
  roaster: string | null
  beanOrigins: string[]
  coffees: Coffee[]
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
  // Present only after fetchShop: a preview slice plus totals. The list
  // query skips them entirely — photos are full base64 payloads.
  photos?: ShopPhoto[]
  photoCount?: number
  reports?: Report[]
  reportCount?: number
  owner?: { name: string; picture: string | null } | null
  deliverySettings?: DeliverySettings
  sellerOnboarded?: boolean
  chain?: {
    id: string
    name: string
    shops: ChainLocation[]
  } | null
}

export interface DeliverySettings {
  shipping: boolean
  pickup: boolean
  pickupInstructions: string | null
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
  machines?: MachineInput[] | null
  beanSource?: BeanSource | null
  roaster?: string | null
  beanOrigins?: string[] | null
  coffees?: CoffeeInput[] | null
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

export async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
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
    if (token && message.includes('Sign in')) {
      localStorage.removeItem(TOKEN_KEY)
      localStorage.removeItem(USER_KEY)
      window.dispatchEvent(new Event('kyc:session-expired'))
      throw new Error('Your session expired. Please sign in again (top right).')
    }
    throw new Error(message)
  }
  return json.data as T
}

const COFFEE_FIELDS = `name roaster type origins process fermentation roastLevel varieties tastingNotes`

const SHOP_FIELDS = `
  id name address city lat lng
  machine machineModel machines { brand model }
  beanSource roaster beanOrigins coffees { ${COFFEE_FIELDS} }
  grinders drinks { name price }
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

const USER_FIELDS = `id name email phone picture role`

export function fetchMe() {
  return gql<{ me: User | null }>(`query Me { me { ${USER_FIELDS} } }`).then((d) => d.me)
}

export function fetchMyStats() {
  return gql<{ me: { savedCount: number; beenCount: number } | null }>(
    `query MyStats { me { savedCount beenCount } }`,
  ).then((d) => d.me)
}

const REPORT_FIELDS = `
  id machine machineModel machines { brand model }
  beanSource roaster beanOrigins coffees { ${COFFEE_FIELDS} }
  grinders drinks { name price }
  milkBrands dogFriendly wifi outdoorSeating note source createdAt reporter { name picture }
`

// Expanded-view payload: the full shop with all photos, reports, and chain.
// The drawer never calls this — it paints from the list's copy.
export function fetchShop(id: string) {
  return gql<{ shop: CoffeeShop | null }>(
    `query Shop($id: ID!) {
      shop(id: $id) {
        ${SHOP_FIELDS}
        photoCount
        reportCount
        owner { name picture }
        photos { id kind data createdAt uploader { name picture } }
        reports { ${REPORT_FIELDS} }
        chain { id name shops { id name address city } }
      }
    }`,
    { id },
  ).then((d) => d.shop)
}

// Drawer fallback for shops missing from the loaded list (e.g. a chain
// location): core fields only, no photo payloads.
export function fetchShopLite(id: string) {
  return gql<{ shop: CoffeeShop | null }>(
    `query ShopLite($id: ID!) { shop(id: $id) { ${SHOP_FIELDS} } }`,
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
      signInWithGoogle(idToken: $idToken) { token user { ${USER_FIELDS} } }
    }`,
    { idToken },
  ).then((d) => d.signInWithGoogle)
}

/** devCode is set only against a dev backend with no email provider. */
export function startEmailSignIn(email: string) {
  return gql<{ startEmailSignIn: { sent: boolean; devCode: string | null } }>(
    `mutation StartEmail($email: String!) {
      startEmailSignIn(email: $email) { sent devCode }
    }`,
    { email },
  ).then((d) => d.startEmailSignIn)
}

export function signInWithEmail(email: string, code: string) {
  return gql<{ signInWithEmail: { token: string; user: User } }>(
    `mutation EmailSignIn($email: String!, $code: String!) {
      signInWithEmail(email: $email, code: $code) { token user { ${USER_FIELDS} } }
    }`,
    { email, code },
  ).then((d) => d.signInWithEmail)
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

export function deleteShop(id: string) {
  return gql<{ deleteShop: boolean }>(
    `mutation DeleteShop($id: ID!) { deleteShop(id: $id) }`,
    { id },
  ).then((d) => d.deleteShop)
}

// MARK: Seller application

export interface SellerApplicationInput {
  businessRole?: string
  contact?: string
  website?: string
  note?: string
}

// Support reviews applications in the admin console; approval grants Seller Hub access.
export function claimShop(shopId: string, application: SellerApplicationInput) {
  return gql<{ claimShop: { id: string; status: 'PENDING' | 'APPROVED' | 'REJECTED' } }>(
    `mutation Claim($shopId: ID!, $application: SellerApplicationInput) {
      claimShop(shopId: $shopId, application: $application) { id status }
    }`,
    { shopId, application },
  ).then((d) => d.claimShop)
}

// MARK: Seller hub

export type OrderStatus = 'PLACED' | 'SHIPPED' | 'DELIVERED' | 'READY_FOR_PICKUP' | 'PICKED_UP' | 'CANCELED'
export type Fulfillment = 'SHIP' | 'PICKUP'
export type ShipmentStatus = 'LABEL_READY' | 'READY_FOR_DROPOFF' | 'IN_TRANSIT' | 'DELIVERED'

export type ListingStatus = 'IN_STOCK' | 'LOW_STOCK' | 'HIDDEN'

export interface ProductCounts {
  total: number
  inStock: number
  lowStock: number
  hidden: number
}

export interface Product {
  id: string
  shopId: string
  name: string
  variant: string | null
  price: number
  stockQty: number
  lowStockThreshold: number
  lowStock: boolean
  active: boolean
  status: ListingStatus
  coverPhoto: ProductPhoto | null
  photos?: ProductPhoto[] // fetchProduct only; each is a whole data URL
  createdAt: string
  updatedAt: string
}

export interface ProductPhoto {
  id: string
  data: string
  position: number
}

export const MAX_PRODUCT_PHOTOS = 6

export interface ProductInput {
  name?: string
  variant?: string | null
  price?: number
  stockQty?: number
  lowStockThreshold?: number
  active?: boolean
}

export interface OrderItem {
  productId: string
  name: string
  qty: number
  unitPrice: number
}

export interface Order {
  id: string
  number: number
  status: OrderStatus
  fulfillment: Fulfillment
  buyer: { name: string; picture: string | null } | null
  items: OrderItem[]
  total: number
  createdAt: string
  shipment: Shipment | null
}

export interface Shipment {
  id: string
  orderId: string
  carrier: string | null
  tracking: string | null
  shipBy: string | null
  status: ShipmentStatus
  createdAt: string
  order?: { number: number; buyer: { name: string } | null; items: OrderItem[] }
}

const PRODUCT_FIELDS = `id shopId name variant price stockQty lowStockThreshold lowStock active status coverPhoto { id data position } createdAt updatedAt`
const ORDER_FIELDS = `id number status fulfillment buyer { name picture } items { productId name qty unitPrice } total createdAt
  shipment { id orderId carrier tracking shipBy status createdAt }`

// Shops the viewer owns; drives the Seller Hub entry and shop switcher.
export function fetchMyShops() {
  return gql<{ myShops: { id: string; name: string; city: string }[] }>(
    `query MyShops { myShops { id name city } }`,
  ).then((d) => d.myShops)
}

// Hub payload: the full shop plus seller-only extras (delivery settings, owner).
export function fetchSellerShop(id: string) {
  return gql<{ shop: CoffeeShop | null }>(
    `query SellerShop($id: ID!) {
      shop(id: $id) {
        ${SHOP_FIELDS}
        owner { name picture }
        deliverySettings { shipping pickup pickupInstructions }
        sellerOnboarded
      }
    }`,
    { id },
  ).then((d) => d.shop)
}

export function completeSellerOnboarding(shopId: string) {
  return gql<{ completeSellerOnboarding: { id: string; sellerOnboarded: boolean } }>(
    `mutation CompleteOnboarding($shopId: ID!) {
      completeSellerOnboarding(shopId: $shopId) { id sellerOnboarded }
    }`,
    { shopId },
  ).then((d) => d.completeSellerOnboarding)
}

export function updateShopProfile(shopId: string, input: { vibe?: string; website?: string }) {
  return gql<{ updateShopProfile: CoffeeShop }>(
    `mutation UpdateShopProfile($shopId: ID!, $input: ShopProfileInput!) {
      updateShopProfile(shopId: $shopId, input: $input) { ${SHOP_FIELDS} }
    }`,
    { shopId, input },
  ).then((d) => d.updateShopProfile)
}

export function updateDeliverySettings(
  shopId: string,
  input: { shipping?: boolean; pickup?: boolean; pickupInstructions?: string | null },
) {
  return gql<{ updateDeliverySettings: CoffeeShop }>(
    `mutation UpdateDelivery($shopId: ID!, $input: DeliverySettingsInput!) {
      updateDeliverySettings(shopId: $shopId, input: $input) {
        id
        deliverySettings { shipping pickup pickupInstructions }
      }
    }`,
    { shopId, input },
  ).then((d) => d.updateDeliverySettings)
}

// Seller Hub tables page with limit/offset; the server caps limit at 100.
export const SELLER_PAGE_SIZE = 25

export function fetchMyProducts(shopId: string, status?: ListingStatus, offset = 0) {
  return gql<{ myProducts: { products: Product[]; total: number }; myProductCounts: ProductCounts }>(
    `query MyProducts($shopId: ID!, $status: ListingStatus, $limit: Int!, $offset: Int!) {
      myProducts(shopId: $shopId, status: $status, limit: $limit, offset: $offset) {
        products { ${PRODUCT_FIELDS} }
        total
      }
      myProductCounts(shopId: $shopId) { total inStock lowStock hidden }
    }`,
    { shopId, status: status ?? null, limit: SELLER_PAGE_SIZE, offset },
  )
}

export function fetchMyOrders(shopId: string, offset = 0) {
  return gql<{ myOrders: { orders: Order[]; total: number } }>(
    `query MyOrders($shopId: ID!, $limit: Int!, $offset: Int!) {
      myOrders(shopId: $shopId, limit: $limit, offset: $offset) { orders { ${ORDER_FIELDS} } total }
    }`,
    { shopId, limit: SELLER_PAGE_SIZE, offset },
  ).then((d) => d.myOrders)
}

export function fetchMyShipments(shopId: string, status?: ShipmentStatus, offset = 0) {
  return gql<{ myShipments: { shipments: Shipment[]; total: number } }>(
    `query MyShipments($shopId: ID!, $status: ShipmentStatus, $limit: Int!, $offset: Int!) {
      myShipments(shopId: $shopId, status: $status, limit: $limit, offset: $offset) {
        shipments {
          id orderId carrier tracking shipBy status createdAt
          order { number buyer { name } items { productId name qty unitPrice } }
        }
        total
      }
    }`,
    { shopId, status: status ?? null, limit: SELLER_PAGE_SIZE, offset },
  ).then((d) => d.myShipments)
}

export function createProduct(shopId: string, input: ProductInput) {
  return gql<{ createProduct: Product }>(
    `mutation CreateProduct($shopId: ID!, $input: ProductInput!) {
      createProduct(shopId: $shopId, input: $input) { ${PRODUCT_FIELDS} }
    }`,
    { shopId, input },
  ).then((d) => d.createProduct)
}

export function updateProduct(id: string, input: ProductInput) {
  return gql<{ updateProduct: Product }>(
    `mutation UpdateProduct($id: ID!, $input: ProductInput!) {
      updateProduct(id: $id, input: $input) { ${PRODUCT_FIELDS} }
    }`,
    { id, input },
  ).then((d) => d.updateProduct)
}

export function deleteProduct(id: string) {
  return gql<{ deleteProduct: boolean }>(
    `mutation DeleteProduct($id: ID!) { deleteProduct(id: $id) }`,
    { id },
  ).then((d) => d.deleteProduct)
}

// One listing with every photo; the editor's initial load.
export function fetchProduct(id: string) {
  return gql<{ product: Product | null }>(
    `query Product($id: ID!) { product(id: $id) { ${PRODUCT_FIELDS} photos { id data position } } }`,
    { id },
  ).then((d) => d.product)
}

// Final ordered list: {id} keeps an existing photo, {data} uploads a new one.
export function setProductPhotos(productId: string, photos: { id?: string; data?: string }[]) {
  return gql<{ setProductPhotos: Product }>(
    `mutation SetProductPhotos($productId: ID!, $photos: [ProductPhotoInput!]!) {
      setProductPhotos(productId: $productId, photos: $photos) { ${PRODUCT_FIELDS} }
    }`,
    { productId, photos },
  ).then((d) => d.setProductPhotos)
}

export function cancelOrder(id: string) {
  return gql<{ cancelOrder: Order }>(
    `mutation CancelOrder($id: ID!) { cancelOrder(id: $id) { ${ORDER_FIELDS} } }`,
    { id },
  ).then((d) => d.cancelOrder)
}

export function markReadyForPickup(id: string) {
  return gql<{ markReadyForPickup: Order }>(
    `mutation MarkReadyForPickup($id: ID!) { markReadyForPickup(id: $id) { ${ORDER_FIELDS} } }`,
    { id },
  ).then((d) => d.markReadyForPickup)
}

export function markPickedUp(id: string) {
  return gql<{ markPickedUp: Order }>(
    `mutation MarkPickedUp($id: ID!) { markPickedUp(id: $id) { ${ORDER_FIELDS} } }`,
    { id },
  ).then((d) => d.markPickedUp)
}

export function updateShipment(
  id: string,
  patch: { carrier?: string; tracking?: string; status?: ShipmentStatus },
) {
  return gql<{ updateShipment: Shipment }>(
    `mutation UpdateShipment($id: ID!, $carrier: String, $tracking: String, $status: ShipmentStatus) {
      updateShipment(id: $id, carrier: $carrier, tracking: $tracking, status: $status) {
        id orderId carrier tracking shipBy status createdAt
        order { number buyer { name } items { productId name qty unitPrice } }
      }
    }`,
    { id, carrier: patch.carrier ?? null, tracking: patch.tracking ?? null, status: patch.status ?? null },
  ).then((d) => d.updateShipment)
}

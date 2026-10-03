import Foundation

enum APIError: LocalizedError {
    case badURL
    case server(String)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .badURL: "The API URL in Settings is not a valid URL."
        case .server(let message): message
        case .emptyData: "The server returned no data."
        }
    }
}

// Thin GraphQL-over-POST client, the Swift twin of web/src/api.ts.
enum CoffeeAPI {
    static let endpointKey = "apiURL"
    // Ariadne serves GraphQL at the root path on Render (no /graphql).
    // Settings can override, e.g. http://127.0.0.1:4000/graphql for local dev.
    static let defaultEndpoint = "https://knowyourcoffee.onrender.com"

    static var endpoint: String {
        let stored = UserDefaults.standard.string(forKey: endpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false ? stored! : defaultEndpoint)
    }

    private struct Envelope<T: Decodable>: Decodable {
        struct GQLError: Decodable { let message: String }
        let data: T?
        let errors: [GQLError]?
    }

    private static func execute<T: Decodable>(
        _ query: String,
        variables: [String: Any?] = [:],
        as type: T.Type
    ) async throws -> T {
        guard let url = URL(string: endpoint) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = Keychain.read(AuthStore.tokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables.mapValues { $0 ?? NSNull() },
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let message = envelope.errors?.first?.message {
            // Stale session (server restart, expiry): drop the login instead
            // of failing every authorized action. Same rule as web api.ts.
            if message.contains("Sign in") {
                await AuthStore.shared.sessionExpired()
                throw APIError.server("Your session expired. Please sign in again.")
            }
            throw APIError.server(message)
        }
        guard let payload = envelope.data else { throw APIError.emptyData }
        return payload
    }

    private static let coffeeFields =
        "name roaster type origins process fermentation roastLevel varieties tastingNotes"

    private static let shopFields = """
        id name address city lat lng
        machine machineModel machines { brand model }
        beanSource roaster beanOrigins coffees { \(coffeeFields) }
        grinders drinks { name price }
        milkBrands vibe dogFriendly wifi outdoorSeating photoUrl website savedByMe beenByMe updatedAt
        """

    static func fetchShops(
        search: String?,
        machine: MachineBrand?,
        saved: Bool = false,
        been: Bool = false,
        limit: Int,
        offset: Int
    ) async throws -> ShopPage {
        struct Payload: Decodable { let shops: ShopPage }
        let query = """
            query Shops($search: String, $machine: MachineBrand, $saved: Boolean, $been: Boolean, $limit: Int!, $offset: Int!) {
              shops(search: $search, machine: $machine, saved: $saved, been: $been, limit: $limit, offset: $offset) {
                total
                shops { \(shopFields) }
              }
            }
            """
        return try await execute(query, variables: [
            "search": search?.isEmpty == false ? search : nil,
            "machine": machine?.rawValue,
            "saved": saved ? true : nil,
            "been": been ? true : nil,
            "limit": limit,
            "offset": offset,
        ], as: Payload.self).shops
    }

    // Full payload: photos, reports, chain. Only for the detail screen —
    // photos are whole base64 images.
    static func fetchShop(id: String) async throws -> CoffeeShop {
        struct Payload: Decodable { let shop: CoffeeShop? }
        let query = """
            query Shop($id: ID!) {
              shop(id: $id) {
                \(shopFields)
                photoCount
                reportCount
                ownerId ownedByMe
                deliverySettings { shipping pickup pickupInstructions }
                products { id name price subtitle status coverPhoto { id data } }
                photos { id kind data createdAt uploader { name picture } }
                reports {
                  id machine machineModel machines { brand model }
                  beanSource roaster beanOrigins coffees { \(coffeeFields) }
                  grinders drinks { name price }
                  milkBrands dogFriendly wifi outdoorSeating note source createdAt
                  reporter { name picture }
                }
                chain { id name shops { id name address city photoUrl machine machineModel machines { brand model } beanSource } }
              }
            }
            """
        guard let shop = try await execute(query, variables: ["id": id], as: Payload.self).shop else {
            throw APIError.server("Shop not found.")
        }
        return shop
    }

    // MARK: Auth

    private static let userFields = "id name email phone picture role savedCount beenCount"

    static func signInWithGoogle(idToken: String) async throws -> AuthPayload {
        struct Payload: Decodable { let signInWithGoogle: AuthPayload }
        let query = """
            mutation SignIn($idToken: String!) {
              signInWithGoogle(idToken: $idToken) { token user { \(userFields) } }
            }
            """
        return try await execute(query, variables: ["idToken": idToken], as: Payload.self).signInWithGoogle
    }

    static func signInWithApple(identityToken: String, name: String?) async throws -> AuthPayload {
        struct Payload: Decodable { let signInWithApple: AuthPayload }
        let query = """
            mutation AppleSignIn($t: String!, $n: String) {
              signInWithApple(identityToken: $t, name: $n) { token user { \(userFields) } }
            }
            """
        return try await execute(query, variables: ["t": identityToken, "n": name], as: Payload.self)
            .signInWithApple
    }

    /// Sends a 6-digit code by text or email. Returns the code itself only
    /// against a dev backend with no SMS/email provider configured.
    static func startCodeSignIn(method: CodeSignInMethod, identifier: String) async throws -> String? {
        struct Payload: Decodable {
            struct Request: Decodable { let devCode: String? }
            let startPhoneSignIn: Request?
            let startEmailSignIn: Request?
        }
        let query = method == .phone
            ? "mutation($i: String!) { startPhoneSignIn(phone: $i) { sent devCode } }"
            : "mutation($i: String!) { startEmailSignIn(email: $i) { sent devCode } }"
        let payload = try await execute(query, variables: ["i": identifier], as: Payload.self)
        return (payload.startPhoneSignIn ?? payload.startEmailSignIn)?.devCode
    }

    static func signInWithCode(method: CodeSignInMethod, identifier: String, code: String) async throws -> AuthPayload {
        struct Payload: Decodable {
            let signInWithPhone: AuthPayload?
            let signInWithEmail: AuthPayload?
        }
        let query = method == .phone
            ? "mutation($i: String!, $c: String!) { signInWithPhone(phone: $i, code: $c) { token user { \(userFields) } } }"
            : "mutation($i: String!, $c: String!) { signInWithEmail(email: $i, code: $c) { token user { \(userFields) } } }"
        let payload = try await execute(query, variables: ["i": identifier, "c": code], as: Payload.self)
        guard let auth = payload.signInWithPhone ?? payload.signInWithEmail else { throw APIError.emptyData }
        return auth
    }

    static func fetchMe() async throws -> User? {
        struct Payload: Decodable { let me: User? }
        return try await execute("query Me { me { \(userFields) } }", as: Payload.self).me
    }

    // MARK: Signed-in actions

    static func setShopStatus(shopID: String, saved: Bool? = nil, been: Bool? = nil) async throws -> CoffeeShop {
        struct Payload: Decodable { let setShopStatus: CoffeeShop }
        let query = """
            mutation SetStatus($shopId: ID!, $saved: Boolean, $been: Boolean) {
              setShopStatus(shopId: $shopId, saved: $saved, been: $been) { \(shopFields) }
            }
            """
        return try await execute(query, variables: [
            "shopId": shopID, "saved": saved, "been": been,
        ], as: Payload.self).setShopStatus
    }

    static func submitReport(_ input: [String: Any?]) async throws {
        struct Payload: Decodable {
            struct R: Decodable { let id: String }
            let submitReport: R
        }
        let query = "mutation Submit($input: ReportInput!) { submitReport(input: $input) { id } }"
        _ = try await execute(
            query,
            variables: ["input": input.compactMapValues { $0 }],
            as: Payload.self
        )
    }

    // MARK: Photo analysis & upload

    static func identifyMachine(imageBase64: String) async throws -> MachineGuess {
        struct Payload: Decodable { let identifyMachine: MachineGuess }
        let query = """
            mutation Identify($img: String!) {
              identifyMachine(imageBase64: $img) { machine machineModel confidence notes }
            }
            """
        return try await execute(query, variables: ["img": imageBase64], as: Payload.self).identifyMachine
    }

    static func parseMenu(imageBase64: String) async throws -> [DrinkItem] {
        struct Payload: Decodable { let parseMenu: [DrinkItem] }
        let query = "mutation Parse($img: String!) { parseMenu(imageBase64: $img) { name price } }"
        return try await execute(query, variables: ["img": imageBase64], as: Payload.self).parseMenu
    }

    static func addShopPhotos(shopID: String, photos: [[String: String]]) async throws {
        struct Payload: Decodable {
            struct P: Decodable { let id: String }
            let addShopPhotos: [P]
        }
        let query = """
            mutation AddPhotos($shopId: ID!, $photos: [PhotoInput!]!) {
              addShopPhotos(shopId: $shopId, photos: $photos) { id }
            }
            """
        _ = try await execute(query, variables: [
            "shopId": shopID, "photos": photos,
        ], as: Payload.self)
    }

    /// Submits a seller application; support reviews it in the admin console.
    static func claimShop(
        shopID: String, businessRole: String?, contact: String?, website: String?, note: String?
    ) async throws -> ShopClaim {
        struct Payload: Decodable { let claimShop: ShopClaim }
        let query = """
            mutation Claim($shopId: ID!, $application: SellerApplicationInput) {
              claimShop(shopId: $shopId, application: $application) {
                id status note createdAt shop { id name city }
              }
            }
            """
        let application: [String: Any?] = [
            "businessRole": businessRole?.isEmpty == false ? businessRole : nil,
            "contact": contact?.isEmpty == false ? contact : nil,
            "website": website?.isEmpty == false ? website : nil,
            "note": note?.isEmpty == false ? note : nil,
        ]
        return try await execute(query, variables: [
            "shopId": shopID, "application": application.compactMapValues { $0 },
        ], as: Payload.self).claimShop
    }

    static func deleteShop(id: String) async throws {
        struct Payload: Decodable { let deleteShop: Bool }
        _ = try await execute(
            "mutation DeleteShop($id: ID!) { deleteShop(id: $id) }",
            variables: ["id": id],
            as: Payload.self
        )
    }

    static func deleteAccount() async throws {
        struct Payload: Decodable { let deleteAccount: Bool }
        _ = try await execute("mutation { deleteAccount }", as: Payload.self)
    }

    /// Everything the Me tab needs in one round trip. `me` is nil when the
    /// server does not recognise the session token; callers treat that as
    /// signed out rather than as an empty account.
    static func fetchAccount() async throws -> Account {
        struct Payload: Decodable {
            struct Seller: Decodable { let shops: [SellerShop]; let workload: SellerWorkload }
            let me: User?
            let mySeller: Seller?
            let myClaims: [ShopClaim]
        }
        let query = """
            query Account {
              me { \(userFields) }
              mySeller { shops { id name address city sellerOnboarded \(workloadFields) } \(workloadFields) }
              myClaims { id status note createdAt shop { id name city } }
            }
            """
        let payload = try await execute(query, as: Payload.self)
        return Account(
            me: payload.me,
            seller: payload.mySeller.map {
                SellerAccount(shops: $0.shops, workload: $0.workload, pendingClaims: payload.myClaims.filter { $0.status == "PENDING" })
            },
            claims: payload.myClaims
        )
    }

    static func fetchMyClaims() async throws -> [ShopClaim] {
        struct Payload: Decodable { let myClaims: [ShopClaim] }
        let query = """
            query MyClaims { myClaims { id status note createdAt shop { id name city } } }
            """
        return try await execute(query, as: Payload.self).myClaims
    }

    // MARK: Seller hub

    private static let productFields = """
        id shopId name categoryId category { id slug label } attributes subtitle description
        price quantity lowStockThreshold lowStock active createdAt updatedAt
        """
    private static let categoryFields = """
        id slug label subtitleTemplate
        fields { key label valueType unit help options { value label } required showInSubtitle section }
        """
    private static let orderFields = """
        id number status fulfillment shop { id name } buyer { name picture } items { productId name qty unitPrice } total createdAt
        shipment { id orderId carrier tracking shipBy status createdAt }
        """
    private static let shipmentFields = """
        id orderId carrier tracking shipBy status createdAt
        order { number shop { id name } buyer { name picture } items { productId name qty unitPrice } }
        """
    private static let workloadFields = "workload { toFulfill toShip lowStock }"

    static func fetchMyShops() async throws -> [OwnedShop] {
        struct Payload: Decodable { let myShops: [OwnedShop] }
        return try await execute("query MyShops { myShops { id name city } }", as: Payload.self).myShops
    }

    /// Switcher and all-shops payload in one round trip. Nil when the viewer owns nothing.
    static func fetchMySeller() async throws -> SellerAccount? {
        struct Payload: Decodable {
            struct Seller: Decodable { let shops: [SellerShop]; let workload: SellerWorkload }
            let mySeller: Seller?
            let myClaims: [ShopClaim]
        }
        let query = """
            query MySeller {
              mySeller { shops { id name address city sellerOnboarded \(workloadFields) } \(workloadFields) }
              myClaims { id status note createdAt shop { id name city } }
            }
            """
        let payload = try await execute(query, as: Payload.self)
        guard let seller = payload.mySeller else { return nil }
        return SellerAccount(
            shops: seller.shops,
            workload: seller.workload,
            pendingClaims: payload.myClaims.filter { $0.status == "PENDING" }
        )
    }

    /// Duplicates listings into a sibling shop; copies start hidden with quantity 0.
    static func copyProducts(fromShopID: String, toShopID: String, productIDs: [String]? = nil) async throws -> Int {
        struct Payload: Decodable {
            struct Copied: Decodable { let id: String }
            let copyProducts: [Copied]
        }
        let query = """
            mutation CopyProducts($fromShopId: ID!, $toShopId: ID!, $productIds: [ID!]) {
              copyProducts(fromShopId: $fromShopId, toShopId: $toShopId, productIds: $productIds) { id }
            }
            """
        let variables: [String: Any?] = ["fromShopId": fromShopID, "toShopId": toShopID, "productIds": productIDs]
        return try await execute(query, variables: variables, as: Payload.self).copyProducts.count
    }

    // Seller Hub lists page with limit/offset; the server caps limit at 100.
    static let sellerPageSize = 25

    static func fetchHubStats(shopID: String) async throws -> HubStats {
        struct Payload: Decodable {
            struct Shop: Decodable { let workload: HubStats.Workload? }
            let shop: Shop?
            let myProductCounts: HubStats.ProductCounts
        }
        let query = """
            query HubStats($shopId: ID!) {
              shop(id: $shopId) { workload { toFulfill toShip lowStock } }
              myProductCounts(shopId: $shopId) { total inStock lowStock hidden }
            }
            """
        let payload = try await execute(query, variables: ["shopId": shopID], as: Payload.self)
        return HubStats(workload: payload.shop?.workload, products: payload.myProductCounts)
    }

    static func fetchMyProducts(
        shopID: String, status: ListingStatus? = nil, offset: Int = 0, limit: Int = sellerPageSize
    ) async throws -> Page<Product> {
        struct Payload: Decodable {
            struct Inner: Decodable { let products: [Product]; let total: Int }
            let myProducts: Inner
        }
        let query = """
            query MyProducts($shopId: ID!, $status: ListingStatus, $limit: Int!, $offset: Int!) {
              myProducts(shopId: $shopId, status: $status, limit: $limit, offset: $offset) { products { \(productFields) } total }
            }
            """
        let variables: [String: Any?] = [
            "shopId": shopID, "status": status?.rawValue, "limit": limit, "offset": offset,
        ]
        let inner = try await execute(query, variables: variables, as: Payload.self).myProducts
        return Page(items: inner.products, total: inner.total)
    }

    /// shopID nil = every owned shop (the All shops view).
    static func fetchMyOrders(
        shopID: String?, status: OrderStatus? = nil, offset: Int = 0, limit: Int = sellerPageSize
    ) async throws -> Page<Order> {
        struct Payload: Decodable {
            struct Inner: Decodable { let orders: [Order]; let total: Int }
            let myOrders: Inner
        }
        let query = """
            query MyOrders($shopId: ID, $status: OrderStatus, $limit: Int!, $offset: Int!) {
              myOrders(shopId: $shopId, status: $status, limit: $limit, offset: $offset) { orders { \(orderFields) } total }
            }
            """
        let variables: [String: Any?] = [
            "shopId": shopID, "status": status?.rawValue, "limit": limit, "offset": offset,
        ]
        let inner = try await execute(query, variables: variables, as: Payload.self).myOrders
        return Page(items: inner.orders, total: inner.total)
    }

    static func fetchMyShipments(
        shopID: String?, status: ShipmentStatus? = nil, offset: Int = 0
    ) async throws -> Page<Shipment> {
        struct Payload: Decodable {
            struct Inner: Decodable { let shipments: [Shipment]; let total: Int }
            let myShipments: Inner
        }
        let query = """
            query MyShipments($shopId: ID, $status: ShipmentStatus, $limit: Int!, $offset: Int!) {
              myShipments(shopId: $shopId, status: $status, limit: $limit, offset: $offset) { shipments { \(shipmentFields) } total }
            }
            """
        let variables: [String: Any?] = [
            "shopId": shopID, "status": status?.rawValue, "limit": sellerPageSize, "offset": offset,
        ]
        let inner = try await execute(query, variables: variables, as: Payload.self).myShipments
        return Page(items: inner.shipments, total: inner.total)
    }

    /// Listing categories with their form fields; the server owns the definitions.
    static func fetchCategories() async throws -> [Category] {
        struct Payload: Decodable { let categories: [Category] }
        return try await execute("query Categories { categories { \(categoryFields) } }", as: Payload.self).categories
    }

    /// `input` is a ProductInput: name, categoryId, attributes, description, price, quantity, lowStockThreshold, active.
    static func createProduct(shopID: String, input: [String: Any]) async throws -> Product {
        struct Payload: Decodable { let createProduct: Product }
        let query = """
            mutation CreateProduct($shopId: ID!, $input: ProductInput!) {
              createProduct(shopId: $shopId, input: $input) { \(productFields) }
            }
            """
        return try await execute(query, variables: ["shopId": shopID, "input": input], as: Payload.self).createProduct
    }

    /// Patch semantics: only the keys in `input` change.
    static func updateProduct(id: String, input: [String: Any]) async throws -> Product {
        struct Payload: Decodable { let updateProduct: Product }
        let query = """
            mutation UpdateProduct($id: ID!, $input: ProductInput!) {
              updateProduct(id: $id, input: $input) { \(productFields) }
            }
            """
        return try await execute(query, variables: ["id": id, "input": input], as: Payload.self).updateProduct
    }

    static func deleteProduct(id: String) async throws {
        struct Payload: Decodable { let deleteProduct: Bool }
        _ = try await execute(
            "mutation DeleteProduct($id: ID!) { deleteProduct(id: $id) }",
            variables: ["id": id],
            as: Payload.self
        )
    }

    static func cancelOrder(id: String) async throws -> Order {
        struct Payload: Decodable { let cancelOrder: Order }
        let query = "mutation CancelOrder($id: ID!) { cancelOrder(id: $id) { \(orderFields) } }"
        return try await execute(query, variables: ["id": id], as: Payload.self).cancelOrder
    }

    // status is the pickup step to move to: .readyForPickup or .pickedUp.
    static func advancePickup(id: String, to status: OrderStatus) async throws -> Order {
        struct Payload: Decodable {
            let markReadyForPickup: Order?
            let markPickedUp: Order?
        }
        let field = status == .pickedUp ? "markPickedUp" : "markReadyForPickup"
        let query = "mutation AdvancePickup($id: ID!) { \(field)(id: $id) { \(orderFields) } }"
        let payload = try await execute(query, variables: ["id": id], as: Payload.self)
        guard let order = payload.markPickedUp ?? payload.markReadyForPickup else {
            throw URLError(.badServerResponse)
        }
        return order
    }

    static func updateShipment(
        id: String, carrier: String? = nil, tracking: String? = nil, status: ShipmentStatus? = nil
    ) async throws -> Shipment {
        struct Payload: Decodable { let updateShipment: Shipment }
        let query = """
            mutation UpdateShipment($id: ID!, $carrier: String, $tracking: String, $status: ShipmentStatus) {
              updateShipment(id: $id, carrier: $carrier, tracking: $tracking, status: $status) { \(shipmentFields) }
            }
            """
        return try await execute(query, variables: [
            "id": id, "carrier": carrier, "tracking": tracking, "status": status?.rawValue,
        ], as: Payload.self).updateShipment
    }

    // MARK: Add shop (Google Places)

    static func searchPlaces(query text: String) async throws -> [PlaceSuggestion] {
        struct Payload: Decodable { let searchPlaces: [PlaceSuggestion] }
        let query = "query Search($query: String!) { searchPlaces(query: $query) { placeId name address } }"
        return try await execute(query, variables: ["query": text], as: Payload.self).searchPlaces
    }

    static func placePreview(placeID: String) async throws -> PlacePreview? {
        struct Payload: Decodable { let placePreview: PlacePreview? }
        let query = """
            query Preview($placeId: ID!) {
              placePreview(placeId: $placeId) {
                placeId name address city photoUrl website isCoffeeShop
                existing { \(shopFields) }
              }
            }
            """
        return try await execute(query, variables: ["placeId": placeID], as: Payload.self).placePreview
    }

    static func addShopFromPlace(placeID: String) async throws -> CoffeeShop {
        struct Payload: Decodable { let addShopFromPlace: CoffeeShop }
        let query = """
            mutation Add($placeId: ID!) { addShopFromPlace(placeId: $placeId) { \(shopFields) } }
            """
        return try await execute(query, variables: ["placeId": placeID], as: Payload.self).addShopFromPlace
    }
}

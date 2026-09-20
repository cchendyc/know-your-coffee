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
                photos { id kind data createdAt uploader { name picture } }
                reports {
                  id machine machineModel machines { brand model }
                  beanSource roaster beanOrigins coffees { \(coffeeFields) }
                  grinders drinks { name price }
                  milkBrands dogFriendly wifi outdoorSeating note source createdAt
                  reporter { name picture }
                }
                chain { id name shops { id name address city } }
              }
            }
            """
        guard let shop = try await execute(query, variables: ["id": id], as: Payload.self).shop else {
            throw APIError.server("Shop not found.")
        }
        return shop
    }

    // MARK: Auth

    private static let userFields = "id name email phone picture savedCount beenCount"

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

    static func claimShop(shopID: String, note: String?) async throws -> ShopClaim {
        struct Payload: Decodable { let claimShop: ShopClaim }
        let query = """
            mutation Claim($shopId: ID!, $note: String) {
              claimShop(shopId: $shopId, note: $note) {
                id status note createdAt shop { id name city }
              }
            }
            """
        return try await execute(query, variables: [
            "shopId": shopID, "note": note?.isEmpty == false ? note : nil,
        ], as: Payload.self).claimShop
    }

    static func fetchMyClaims() async throws -> [ShopClaim] {
        struct Payload: Decodable { let myClaims: [ShopClaim] }
        let query = """
            query MyClaims { myClaims { id status note createdAt shop { id name city } } }
            """
        return try await execute(query, as: Payload.self).myClaims
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

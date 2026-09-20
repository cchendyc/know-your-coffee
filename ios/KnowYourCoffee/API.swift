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
    // Simulator reaches the host Mac's uvicorn (make dev-backend) on 4000.
    // Point Settings at the Render URL for production.
    static let defaultEndpoint = "http://127.0.0.1:4000/graphql"

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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables.mapValues { $0 ?? NSNull() },
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let message = envelope.errors?.first?.message {
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
        limit: Int,
        offset: Int
    ) async throws -> ShopPage {
        struct Payload: Decodable { let shops: ShopPage }
        let query = """
            query Shops($search: String, $machine: MachineBrand, $limit: Int!, $offset: Int!) {
              shops(search: $search, machine: $machine, limit: $limit, offset: $offset) {
                total
                shops { \(shopFields) }
              }
            }
            """
        return try await execute(query, variables: [
            "search": search?.isEmpty == false ? search : nil,
            "machine": machine?.rawValue,
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
}

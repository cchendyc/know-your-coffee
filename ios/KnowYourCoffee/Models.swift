import CoreLocation
import Foundation

// Mirrors web/src/api.ts. Enums decode unknown backend values to a fallback
// case so a new brand server-side never crashes an old app build.

enum MachineBrand: String, Codable, CaseIterable, Identifiable {
    case laMarzocco = "LA_MARZOCCO"
    case slayer = "SLAYER"
    case synesso = "SYNESSO"
    case keesVanDerWesten = "KEES_VAN_DER_WESTEN"
    case victoriaArduino = "VICTORIA_ARDUINO"
    case nuovaSimonelli = "NUOVA_SIMONELLI"
    case modbar = "MODBAR"
    case rocket = "ROCKET"
    case rancilio = "RANCILIO"
    case breville = "BREVILLE"
    case decent = "DECENT"
    case faema = "FAEMA"
    case other = "OTHER"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MachineBrand(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .laMarzocco: "La Marzocco"
        case .slayer: "Slayer"
        case .synesso: "Synesso"
        case .keesVanDerWesten: "Kees van der Westen"
        case .victoriaArduino: "Victoria Arduino"
        case .nuovaSimonelli: "Nuova Simonelli"
        case .modbar: "Modbar"
        case .rocket: "Rocket"
        case .rancilio: "Rancilio"
        case .breville: "Breville"
        case .decent: "Decent"
        case .faema: "Faema"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}

enum BeanSource: String, Codable {
    case inHouseRoast = "IN_HOUSE_ROAST"
    case localRoaster = "LOCAL_ROASTER"
    case nationalRoaster = "NATIONAL_ROASTER"
    case multiRoaster = "MULTI_ROASTER"
    case privateLabel = "PRIVATE_LABEL"
    case distributor = "DISTRIBUTOR"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BeanSource(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .inHouseRoast: "Roasts in-house"
        case .localRoaster: "Local roaster"
        case .nationalRoaster: "National roaster"
        case .multiRoaster: "Multi-roaster"
        case .privateLabel: "Private label"
        case .distributor: "Commercial distributor"
        case .unknown: "Unknown"
        }
    }
}

struct Machine: Codable, Hashable {
    let brand: MachineBrand
    let model: String?

    // OTHER models carry their brand as a prefix ("Astoria Storm"),
    // so a leading "Other" is noise. Same rule as web labels.ts.
    var display: String {
        if brand == .other, let model, !model.isEmpty { return model }
        if let model, !model.isEmpty { return "\(brand.label) \(model)" }
        return brand.label
    }
}

struct Coffee: Codable, Hashable {
    let name: String?
    let roaster: String?
    let type: String?
    let origins: [String]
    let process: String?
    let fermentation: String?
    let roastLevel: String?
    let varieties: [String]
    let tastingNotes: [String]

    var title: String? {
        let parts = [roaster, name].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    // Attribute pills in display order, skipping unknowns. Mirrors coffeePills().
    var pills: [String] {
        var out: [String] = []
        if let type { out.append(Self.typeLabels[type] ?? type.capitalized) }
        out += origins
        if let process { out.append(Self.processLabels[process] ?? process.capitalized) }
        if let fermentation { out.append(Self.fermentationLabels[fermentation] ?? fermentation) }
        if let roastLevel { out.append("\(roastLevel.capitalized) roast") }
        out += varieties
        return out
    }

    static let typeLabels = ["SINGLE_ORIGIN": "Single origin", "BLEND": "Blend"]
    static let processLabels = [
        "WASHED": "Washed", "NATURAL": "Natural", "HONEY": "Honey",
        "WET_HULLED": "Wet-hulled", "OTHER": "Other",
    ]
    // Fermentation is free text; these map legacy enum tokens for display.
    static let fermentationLabels = [
        "ANAEROBIC": "Anaerobic", "CARBONIC_MACERATION": "Carbonic maceration",
        "CO_FERMENT": "Co-ferment", "THERMAL_SHOCK": "Thermal shock", "EXTENDED": "Extended ferment",
    ]
}

struct DrinkItem: Codable, Hashable {
    let name: String
    let price: Double?
}

struct MachineGuess: Codable {
    let machine: MachineBrand
    let machineModel: String?
    let confidence: Double
    let notes: String?
}

struct ShopReview: Codable, Identifiable, Hashable {
    let id: String
    let rating: Int
    let body: String?
    let author: Reporter?
    let createdAt: String
    let updatedAt: String
}

struct Reporter: Codable, Hashable {
    let name: String
    let picture: String?
}

struct ShopPhoto: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let data: String // "data:image/...;base64,..." URI
    let uploader: Reporter?
    let createdAt: String

    var kindLabel: String {
        ["MACHINE": "Machine", "BEANS": "Beans", "DRINKS": "Drinks",
         "MENU": "Menu", "VIBE": "Vibe", "OTHER": "Other"][kind] ?? kind
    }

    var imageData: Data? {
        guard let comma = data.firstIndex(of: ",") else { return Data(base64Encoded: data) }
        return Data(base64Encoded: String(data[data.index(after: comma)...]))
    }
}

struct Report: Codable, Identifiable, Hashable {
    let id: String
    let machine: MachineBrand?
    let machineModel: String?
    let machines: [Machine]?
    let beanSource: BeanSource?
    let roaster: String?
    let beanOrigins: [String]?
    let coffees: [Coffee]?
    let grinders: [String]?
    let drinks: [DrinkItem]?
    let milkBrands: [String]?
    let dogFriendly: Bool?
    let wifi: Bool?
    let outdoorSeating: Bool?
    let note: String?
    let source: String
    let reporter: Reporter?
    let createdAt: String
}

// Enough of a shop to draw a rail card; chain siblings now, similar shops later.
struct ChainLocation: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let city: String
    var photoUrl: String?
    var machine: MachineBrand?
    var machineModel: String?
    var machines: [Machine]?
    var beanSource: BeanSource?

    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }

    var knownMachine: Machine? {
        let list = (machines?.isEmpty == false) ? machines! : machine.map { [Machine(brand: $0, model: machineModel)] } ?? []
        return list.first { $0.brand != .unknown }
    }
}

struct Chain: Codable, Hashable {
    let id: String
    let name: String
    let shops: [ChainLocation]
}

struct DeliverySettings: Codable, Hashable {
    let shipping: Bool
    let pickup: Bool
    let pickupInstructions: String?

    /// "Ships to you · Pickup in Berkeley", or "" when neither is on.
    func copy(city: String) -> String {
        [shipping ? "Ships to you" : nil, pickup ? "Pickup in \(city)" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct ListingCover: Codable, Hashable {
    let id: String
    /// Data URL. nil until fetchShopMedia fills it in.
    var data: String?

    var imageData: Data? {
        guard let data else { return nil }
        guard let comma = data.firstIndex(of: ",") else { return Data(base64Encoded: data) }
        return Data(base64Encoded: String(data[data.index(after: comma)...]))
    }
}

/// Second half of the shop payload: every base64 image. Fetched only when a
/// panel needs it, so the page and tabs do not wait on megabytes of JSON.
struct ShopMedia: Decodable {
    struct ProductCover: Decodable {
        let id: String
        let coverPhoto: ListingCover?
    }

    let photos: [ShopPhoto]
    let products: [ProductCover]
}

// Buyer-facing listing on the shop page; the seller's Product carries more.
struct ShopListing: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
    let subtitle: String?
    let status: String // IN_STOCK / LOW_STOCK / OUT_OF_STOCK / HIDDEN
    var coverPhoto: ListingCover?
}

extension Report {
    // One-line "what changed", in field order. Mirrors web reportSummary().
    var summary: String {
        var parts: [String] = []
        if let machines, !machines.isEmpty {
            parts.append("Machine\(machines.count > 1 ? "s" : ""): \(machines.map(\.display).joined(separator: ", "))")
        } else if let machine, machine != .unknown {
            parts.append("Machine: \(Machine(brand: machine, model: machineModel).display)")
        }
        if let roaster, !roaster.isEmpty { parts.append("Roaster: \(roaster)") }
        if let beanOrigins, !beanOrigins.isEmpty { parts.append("Origins: \(beanOrigins.joined(separator: ", "))") }
        if let grinders, !grinders.isEmpty { parts.append("Grinders: \(grinders.joined(separator: ", "))") }
        if let drinks, !drinks.isEmpty {
            let list = drinks.map { d -> String in
                if let price = d.price { return "\(d.name) $\(String(format: "%.2f", price))" }
                return d.name
            }
            parts.append("Drinks: \(list.joined(separator: ", "))")
        }
        if let milkBrands, !milkBrands.isEmpty { parts.append("Milk: \(milkBrands.joined(separator: ", "))") }
        if let dogFriendly { parts.append(dogFriendly ? "Dog friendly" : "No dogs") }
        if let wifi { parts.append(wifi ? "Wi-Fi" : "No Wi-Fi") }
        if let outdoorSeating { parts.append(outdoorSeating ? "Outdoor seating" : "No outdoor seating") }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

struct CoffeeShop: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var address: String
    var city: String
    var lat: Double
    var lng: Double
    var machine: MachineBrand
    var machineModel: String?
    var machines: [Machine]
    var beanSource: BeanSource
    var roaster: String?
    var beanOrigins: [String]
    var coffees: [Coffee]
    var grinders: [String]
    var drinks: [DrinkItem]
    var milkBrands: [String]
    var vibe: String?
    var dogFriendly: Bool?
    var wifi: Bool?
    var outdoorSeating: Bool?
    var photoUrl: String?
    var website: String?
    var savedByMe: Bool
    var beenByMe: Bool
    var updatedAt: String
    // Present only in the full shop(id:) payload. ownerId and products
    // also ride on the feed so the tab bar renders before the detail fetch.
    var photos: [ShopPhoto]?
    var photoCount: Int?
    var reports: [Report]?
    var reportCount: Int?
    var reviews: [ShopReview]?
    var reviewCount: Int?
    var ratingAverage: Double?
    var myReview: ShopReview?
    var chain: Chain?
    var ownerId: String?
    var ownedByMe: Bool?
    var deliverySettings: DeliverySettings?
    var products: [ShopListing]?

    /// Owner has claimed the shop and published at least one listing.
    var sellsOnline: Bool { ownerId != nil && !(products ?? []).isEmpty }

    /// Lays the lazily fetched images over a payload that has none.
    func merging(_ media: ShopMedia) -> CoffeeShop {
        var copy = self
        copy.photos = media.photos
        let covers = Dictionary(media.products.map { ($0.id, $0.coverPhoto) }, uniquingKeysWith: { a, _ in a })
        copy.products = products?.map { listing in
            guard let cover = covers[listing.id] ?? nil else { return listing }
            var updated = listing
            updated.coverPhoto = cover
            return updated
        }
        return copy
    }

    /// Carries the detail-only fields over a core-fields payload (e.g. the
    /// setShopStatus response) so the page does not blank them.
    func keepingDetails(from other: CoffeeShop) -> CoffeeShop {
        var copy = self
        copy.photos = other.photos
        copy.photoCount = other.photoCount
        copy.reports = other.reports
        copy.reportCount = other.reportCount
        copy.reviews = other.reviews
        copy.reviewCount = other.reviewCount
        copy.ratingAverage = other.ratingAverage
        copy.myReview = other.myReview
        copy.chain = other.chain
        copy.ownerId = other.ownerId
        copy.ownedByMe = other.ownedByMe
        copy.deliverySettings = other.deliverySettings
        copy.products = other.products
        return copy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // Every machine on the bar, falling back to the legacy single field.
    var machineList: [Machine] {
        machines.isEmpty ? [Machine(brand: machine, model: machineModel)] : machines
    }

    var knownMachines: [Machine] {
        machineList.filter { $0.brand != .unknown }
    }

    var photoURL: URL? {
        photoUrl.flatMap(URL.init(string:))
    }
}

struct ShopPage: Codable {
    let shops: [CoffeeShop]
    let total: Int
}

enum UserRole: String, Codable {
    case user = "USER"
    case admin = "ADMIN"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserRole(rawValue: raw) ?? .user
    }
}

struct User: Codable, Hashable {
    let id: String
    let name: String
    let email: String? // nil for phone-only accounts
    let phone: String?
    let picture: String?
    var role: UserRole?
    var savedCount: Int?
    var beenCount: Int?

    var isAdmin: Bool { role == .admin }

    /// Email or phone, whichever the account signs in with.
    var contactLine: String? { email ?? phone }
}

struct AuthPayload: Codable {
    let token: String
    let user: User
}

struct ShopClaim: Codable, Identifiable, Hashable {
    struct ShopRef: Codable, Hashable {
        let id: String
        let name: String
        let city: String
    }

    let id: String
    let status: String // PENDING / APPROVED / REJECTED
    let note: String?
    let createdAt: String
    let shop: ShopRef
}

// MARK: Seller hub

// myShops slice for the hub; the full CoffeeShop payload is not needed.
struct OwnedShop: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
}

// Counts of open seller work; badges in the shop switcher and all-shops summary.
struct SellerWorkload: Codable, Hashable {
    let toFulfill: Int
    let toShip: Int
    let lowStock: Int

    static let zero = SellerWorkload(toFulfill: 0, toShip: 0, lowStock: 0)
}

// One row of the shop switcher: identity, setup state, open work.
struct SellerShop: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let city: String
    let sellerOnboarded: Bool
    let workload: SellerWorkload?

    var owned: OwnedShop { OwnedShop(id: id, name: name, city: city) }
}

// mySeller plus the viewer's pending claims, for the switcher and all-shops view.
struct SellerAccount: Hashable {
    let shops: [SellerShop]
    let workload: SellerWorkload
    let pendingClaims: [ShopClaim]
}

// The Me tab payload. `me` nil with a stored token means the session is dead.
struct Account: Hashable {
    let me: User?
    let seller: SellerAccount?
    let claims: [ShopClaim]
}

// One offset page of a seller list plus the unpaged match count.
struct Page<Item> {
    let items: [Item]
    let total: Int
}

// Hub row counts, computed server-side so the hub never loads whole lists.
struct HubStats {
    struct Workload: Decodable {
        let toFulfill: Int
        let toShip: Int
        let lowStock: Int
    }
    struct ProductCounts: Decodable {
        let total: Int
        let inStock: Int
        let lowStock: Int
        let hidden: Int
    }
    let workload: Workload?
    let products: ProductCounts
}

enum ListingStatus: String, Codable, Hashable, CaseIterable {
    case inStock = "IN_STOCK"
    case lowStock = "LOW_STOCK"
    case hidden = "HIDDEN"

    var label: String {
        switch self {
        case .inStock: "In stock"
        case .lowStock: "Low stock"
        case .hidden: "Hidden"
        }
    }
}

// Value of one product attribute; the GraphQL JSON scalar is untyped.
indirect enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let l = try? c.decode([JSONValue].self) { self = .list(l) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .list(let l): try c.encode(l)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    /// Foundation value for JSONSerialization when sent as a GraphQL variable.
    var any: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? Int(n) : n
        case .bool(let b): b
        case .list(let l): l.map(\.any)
        case .object(let o): o.mapValues(\.any)
        case .null: NSNull()
        }
    }
}

enum AttributeValueType: String, Codable, Hashable {
    case text = "TEXT"
    case int = "INT"
    case decimal = "DECIMAL"
    case bool = "BOOL"
    case single = "ENUM"
    case multi = "ENUM_MULTI"
    case textList = "TEXT_LIST"
}

// FORMAT = size/form/condition; DETAILS = origin/roast/materials.
enum AttributeSection: String, Codable, Hashable, CaseIterable {
    case format = "FORMAT"
    case details = "DETAILS"

    var title: String {
        switch self {
        case .format: "Size and format"
        case .details: "Details"
        }
    }
}

struct AttributeOption: Codable, Hashable {
    let value: String
    let label: String
}

// One field of a category's listing form; the server decides type, options, and required.
struct CategoryField: Codable, Hashable, Identifiable {
    let key: String
    let label: String
    let valueType: AttributeValueType
    let unit: String?
    let help: String?
    let options: [AttributeOption]
    let isRequired: Bool
    let showInSubtitle: Bool
    let section: AttributeSection

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, valueType, unit, help, options, showInSubtitle, section
        case isRequired = "required"
    }

    func optionLabel(_ value: String) -> String {
        options.first { $0.value == value }?.label ?? value
    }
}

struct Category: Codable, Hashable, Identifiable {
    let id: String
    let slug: String
    let label: String
    let fields: [CategoryField]
    let subtitleTemplate: String?
}

struct Product: Codable, Identifiable, Hashable {
    struct CategoryRef: Codable, Hashable {
        let id: String
        let slug: String
        let label: String
    }

    let id: String
    let shopId: String
    var name: String
    var categoryId: String
    var category: CategoryRef
    var attributes: [String: JSONValue]
    /// Server-rendered from the category's subtitle template, e.g. "340 g Whole bean · Light".
    var subtitle: String?
    var description: String?
    var price: Double
    var quantity: Int
    var lowStockThreshold: Int
    var lowStock: Bool
    var active: Bool
    let createdAt: String
    let updatedAt: String
}

// Name and unitPrice are purchase-time snapshots; deleting a product keeps history.
struct OrderItem: Codable, Hashable {
    let productId: String
    let name: String
    let qty: Int
    let unitPrice: Double
}

// SHIP orders advance through their shipment; PICKUP orders through the pickup steps.
enum OrderStatus: String, Codable, Hashable {
    case placed = "PLACED"
    case packed = "PACKED"
    case shipped = "SHIPPED"
    case delivered = "DELIVERED"
    case readyForPickup = "READY_FOR_PICKUP"
    case pickedUp = "PICKED_UP"
    case canceled = "CANCELED"
}

enum Fulfillment: String, Codable, Hashable {
    case ship = "SHIP"
    case pickup = "PICKUP"
}

enum ShipmentStatus: String, Codable, Hashable {
    case labelReady = "LABEL_READY"
    case readyForDropoff = "READY_FOR_DROPOFF"
    case inTransit = "IN_TRANSIT"
    case delivered = "DELIVERED"

    var label: String {
        switch self {
        case .labelReady: "Label ready"
        case .readyForDropoff: "Ready for dropoff"
        case .inTransit: "In transit"
        case .delivered: "Delivered"
        }
    }
}

struct Order: Codable, Identifiable, Hashable {
    struct ShopRef: Codable, Hashable {
        let id: String
        let name: String
    }

    let id: String
    let number: Int
    var status: OrderStatus
    let fulfillment: Fulfillment
    // Named in cross-shop lists; absent on older payloads.
    let shop: ShopRef?
    let buyer: Reporter?
    let items: [OrderItem]
    let total: Double
    let createdAt: String
    var shipment: Shipment?

    var itemsSummary: String {
        items.map { "\($0.qty)× \($0.name)" }.joined(separator: " · ")
    }

    var isPickup: Bool { fulfillment == .pickup }

    // A no-show pickup can still be canceled after it is packed.
    var isCancelable: Bool { status == .placed || status == .readyForPickup }

    // Shipped orders advance through their shipment, so only pickup has steps here.
    var nextPickupStep: (status: OrderStatus, label: String)? {
        guard isPickup else { return nil }
        switch status {
        case .placed: return (.readyForPickup, "Mark ready")
        case .readyForPickup: return (.pickedUp, "Mark picked up")
        default: return nil
        }
    }
}

struct Shipment: Codable, Identifiable, Hashable {
    struct OrderRef: Codable, Hashable {
        let number: Int
        let shop: Order.ShopRef?
        let buyer: Reporter?
        let items: [OrderItem]
    }

    let id: String
    let orderId: String
    var carrier: String?
    var tracking: String?
    let shipBy: String? // ISO date
    var status: ShipmentStatus
    let createdAt: String
    let order: OrderRef?

    // One step at a time: print → dropoff → carrier scan → delivered.
    var nextStep: (status: ShipmentStatus, label: String)? {
        switch status {
        case .labelReady: (.readyForDropoff, "Mark ready for dropoff")
        case .readyForDropoff: (.inTransit, "Mark in transit")
        case .inTransit: (.delivered, "Mark delivered")
        case .delivered: nil
        }
    }
}

struct PlaceSuggestion: Codable, Identifiable, Hashable {
    let placeId: String
    let name: String
    let address: String

    var id: String { placeId }
}

struct PlacePreview: Codable {
    let placeId: String
    let name: String
    let address: String
    let city: String
    let photoUrl: String?
    let website: String?
    let isCoffeeShop: Bool
    let existing: CoffeeShop?
}

enum RelativeDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func format(_ string: String) -> String {
        guard let date = iso.date(from: string) ?? isoPlain.date(from: string) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

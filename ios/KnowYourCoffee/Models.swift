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

struct ChainLocation: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let city: String
}

struct Chain: Codable, Hashable {
    let id: String
    let name: String
    let shops: [ChainLocation]
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
    // Present only in the full shop(id:) payload.
    var photos: [ShopPhoto]?
    var photoCount: Int?
    var reports: [Report]?
    var reportCount: Int?
    var chain: Chain?

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

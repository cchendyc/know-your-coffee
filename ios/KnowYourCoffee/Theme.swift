import SwiftUI

// Palette mirrors web/src/index.css so both clients feel like one product.
// Every color is dynamic: light values are the cream/espresso palette, dark
// values are the Dark Roast theme from the Figma iOS page. Roles, not hues:
// espresso700 is "accent", so in the dark theme it becomes glowing crema.
extension Color {
    static let cream50 = dynamic(light: 0xFBF8F3, dark: 0x1B120C)
    static let cream100 = dynamic(light: 0xF4EDE2, dark: 0x3A2A1D)
    static let cream200 = dynamic(light: 0xE9DCC9, dark: 0x3A2A1D)
    static let espresso500 = dynamic(light: 0x6F4E37, dark: 0xB99C82)
    static let espresso700 = dynamic(light: 0x4A3325, dark: 0xE0A458)
    static let espresso900 = dynamic(light: 0x2B1D14, dark: 0xF4EDE2)
    static let crema400 = dynamic(light: 0xD4A45F, dark: 0xE0A458)
    static let crema500 = dynamic(light: 0xC08C3E, dark: 0xE0A458)
    static let markerOrange = dynamic(light: 0xE85D04, dark: 0xF2762B)
    static let savedGreen = dynamic(light: 0x2E9E4F, dark: 0x6FBF8F)
    /// Card surface: white on cream in light, elevated umber on espresso black in dark.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x271A11)
    /// Shadows stay espresso-dark in both themes; a light shadow reads as a glow.
    static let shadowInk = Color(hex: 0x2B1D14)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// User theme choice: follow iOS, or force light / Dark Roast.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark Roast"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Text roles
//
// Two text colors, like Instagram (#262626 / #8E8E8E) and X (#0F1419 /
// #536471): everything readable is ink, everything supporting is inkMuted.
// inkFaint is only for placeholders and disabled states — never body copy.
// Crema, green, and red are reserved for actions and status, not prose.
extension Color {
    static let ink = espresso900
    static let inkMuted = espresso500
    static let inkFaint = espresso500.opacity(0.55)
    /// Text on espresso fills (buttons, selected chips).
    static let inkInverse = cream50
}

// MARK: - Type ramp
//
// Six roles, SF Pro only. Hierarchy comes from weight and the two ink
// colors, not from more sizes. Rounded is the brand voice: page titles only.
extension Font {
    /// Screen title; at most one per screen.
    static let kycPageTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    /// Card and section headers.
    static let kycSection = Font.system(size: 16, weight: .semibold)
    /// Primary content.
    static let kycBody = Font.system(size: 15)
    static let kycBodyBold = Font.system(size: 15, weight: .semibold)
    /// Supporting copy: subtitles, form fields, hints.
    static let kycSecondary = Font.system(size: 13)
    static let kycSecondaryBold = Font.system(size: 13, weight: .semibold)
    /// Timestamps, counts, chips, badges.
    static let kycMeta = Font.system(size: 12, weight: .medium)
    static let kycMetaBold = Font.system(size: 12, weight: .semibold)
    /// Uppercase eyebrow labels; always through EyebrowLabel.
    static let kycMicro = Font.system(size: 11, weight: .semibold)
}

// Uppercase micro-label above a group of fields or chips.
struct EyebrowLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.kycMicro)
            .tracking(0.6)
            .foregroundStyle(Color.inkMuted)
    }
}

// MARK: - Shape and spacing constants
//
// Three radii: cards 16, controls and inset layers 12, thumbnails 10.
enum KYCRadius {
    static let card: CGFloat = 16
    static let control: CGFloat = 12
    static let thumb: CGFloat = 10
}

// Reusable card container: surface fill, rounded, soft shadow — the web's ShopCard look.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
            .shadow(color: .shadowInk.opacity(0.06), radius: 8, y: 2)
    }
}

// Second elevation layer: cream inset inside a white card, for grouped
// sub-content (a coffee entry, a report row, a claim).
struct InsetCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cream50)
            .clipShape(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                    .stroke(Color.cream200, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
    func insetCardStyle() -> some View { modifier(InsetCardBackground()) }
}

// Small capsule tag, tinted per role (machine, roaster, origin...).
// Toolbar text button; the system default (17pt) towers over the app's 11–14pt scale.
struct ToolbarTextButton: View {
    let label: String
    var weight: Font.Weight = .medium
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: weight))
                .foregroundStyle(Color.espresso700)
        }
    }
}

struct Pill: View {
    let text: String
    var fill: Color = .cream100
    var foreground: Color = .espresso700

    var body: some View {
        Text(text)
            .font(.kycMeta)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
            .foregroundStyle(foreground)
    }
}

// Left-aligned wrapping layout for pill collections.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, position) in zip(subviews, arrange(proposal: proposal, subviews: subviews).positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            width = max(width, x + size.width)
            x += size.width + spacing
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

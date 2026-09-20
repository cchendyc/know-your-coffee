import SwiftUI

// Palette mirrors web/src/index.css so both clients feel like one product.
extension Color {
    static let cream50 = Color(hex: 0xFBF8F3)
    static let cream100 = Color(hex: 0xF4EDE2)
    static let cream200 = Color(hex: 0xE9DCC9)
    static let espresso500 = Color(hex: 0x6F4E37)
    static let espresso700 = Color(hex: 0x4A3325)
    static let espresso900 = Color(hex: 0x2B1D14)
    static let crema400 = Color(hex: 0xD4A45F)
    static let crema500 = Color(hex: 0xC08C3E)
    static let markerOrange = Color(hex: 0xE85D04)
    static let savedGreen = Color(hex: 0x2E9E4F)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// Reusable card container: white, rounded-2xl, soft shadow — the web's ShopCard look.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .espresso900.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

// Small capsule tag, tinted per role (machine, roaster, origin...).
struct Pill: View {
    let text: String
    var fill: Color = .cream100
    var foreground: Color = .espresso700

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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

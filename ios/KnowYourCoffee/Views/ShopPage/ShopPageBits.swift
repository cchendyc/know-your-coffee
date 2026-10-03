import SwiftUI

enum ShopPageFormat {
    /// "4.5" for 4.50, "4.25" otherwise; mirrors web format.ts.
    static func price(_ value: Double) -> String {
        let whole = value.rounded(.towardZero) == value
        return String(format: whole ? "%.0f" : "%.2f", value)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    static func plural(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Section title with optional meta line, and a trailing accent action.
struct ShopSectionHeader<Trailing: View>: View {
    let title: String
    var meta: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, meta: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.meta = meta
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.kycSection)
                    .foregroundStyle(Color.ink)
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Inline text action in the accent color ("Update menu", "See all 12 records").
struct ShopLinkButton: View {
    let label: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            }
            .font(.kycSecondaryBold)
            .foregroundStyle(Color.crema500)
        }
        .buttonStyle(.plain)
    }
}

/// Outlined full-width pill: "See all N listings", "Write a review".
struct ShopOutlinePill: View {
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Color.ink : Color.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Color.cream200, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Dark filled pill: "Report an update", "Add to cart".
struct ShopPrimaryPill: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkInverse)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.espresso700, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Reporter avatar: picture when present, else a tinted initial.
struct ReporterAvatar: View {
    let reporter: Reporter?
    var size: CGFloat = 30

    private var name: String { reporter?.name ?? "Anonymous" }

    var body: some View {
        ZStack {
            Circle().fill(tint)
            if let picture = reporter?.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
    }

    private var tint: Color {
        let palette: [Color] = [.espresso500, .crema500, .savedGreen, .markerOrange, .espresso700]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }
}

struct ShopMoreItem: Identifiable {
    let symbol: String
    let title: String
    let subtitle: String
    var destructive = false
    let action: () -> Void

    var id: String { title }
}

/// Bottom sheet behind the "…" nav button. Replaces the system Menu so it
/// matches the page: cream backdrop, surface cards, espresso icon wells.
struct ShopMoreSheet: View {
    let shopName: String
    let items: [ShopMoreItem]
    let onPick: (ShopMoreItem) -> Void

    private static let rowHeight: CGFloat = 62

    private var regular: [ShopMoreItem] { items.filter { !$0.destructive } }
    private var destructive: [ShopMoreItem] { items.filter(\.destructive) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(shopName)
                .font(.kycSection)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .padding(.top, 22)

            group(regular)
            if !destructive.isEmpty {
                group(destructive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cream50)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }

    private var height: CGFloat {
        let groups: CGFloat = destructive.isEmpty ? 1 : 2
        return 22 + 22 + 20 + CGFloat(items.count) * Self.rowHeight + groups * 14
    }

    private func group(_ items: [ShopMoreItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Color.cream200).padding(.leading, 62) }
                row(item)
            }
        }
        .cardStyle()
    }

    private func row(_ item: ShopMoreItem) -> some View {
        Button { onPick(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.destructive ? Color.red : Color.espresso700)
                    .frame(width: 36, height: 36)
                    .background(item.destructive ? Color.red.opacity(0.10) : Color.cream100, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.kycBodyBold)
                        .foregroundStyle(item.destructive ? Color.red : Color.ink)
                    Text(item.subtitle)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !item.destructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Grid of every uploaded photo; opened from the cover's "N photos" chip.
struct ShopPhotoSheet: View {
    let shop: CoffeeShop

    @State private var images: [(ShopPhoto, UIImage)] = []
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if images.isEmpty {
                    if shop.photos == nil, (shop.photoCount ?? 0) > 0 {
                        ProgressView()
                            .padding(.top, 40)
                    } else {
                        Text(shop.photos?.isEmpty == false ? "Decoding photos…" : "No photos yet.")
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                            .padding(.top, 40)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(images, id: \.0.id) { photo, image in
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Image(uiImage: image).resizable().scaledToFill())
                                .clipped()
                                .overlay(alignment: .bottomLeading) {
                                    Text(photo.kindLabel)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.45), in: Capsule())
                                        .padding(6)
                                }
                        }
                    }
                }
            }
            .background(Color.cream50)
            .navigationTitle(ShopPageFormat.plural(shop.photoCount ?? images.count, "photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarTextButton(label: "Done", weight: .semibold) { dismiss() }
                }
            }
        }
        .task(id: shop.photos?.map(\.id)) {
            // Base64 decode off the main thread; a dozen photos can be several MB.
            let photos = shop.photos ?? []
            let decoded: [(ShopPhoto, Data)] = await Task.detached(priority: .userInitiated) {
                photos.compactMap { photo in photo.imageData.map { (photo, $0) } }
            }.value
            images = decoded.compactMap { photo, data in UIImage(data: data).map { (photo, $0) } }
        }
    }
}

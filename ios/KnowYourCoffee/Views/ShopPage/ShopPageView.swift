import MapKit
import SwiftUI

struct ShopPageActions {
    var onBack: () -> Void = {}
    var shareURL: URL?
    var onToggleSaved: () -> Void = {}
    var onToggleBeen: () -> Void = {}
    /// Opens the report-an-update form.
    var onUpdate: () -> Void = {}
    /// Refetch the shop after a review is saved.
    var onReload: () -> Void = {}
    /// nil when the shop already has an owner or claiming is not offered here.
    var onClaim: (() -> Void)?
    /// Admin only.
    var onDelete: (() -> Void)?
}

enum ShopTab: String, CaseIterable, Identifiable {
    case about, reviews, shop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .about: "About"
        case .reviews: "Reviews"
        case .shop: "Shop"
        }
    }
}

private struct ShopPageFrames: Equatable {
    var coverBottom: CGFloat = .infinity
    var tabsTop: CGFloat = .infinity
}

private struct ShopPageFramesKey: PreferenceKey {
    static var defaultValue = ShopPageFrames()
    static func reduce(value: inout ShopPageFrames, nextValue: () -> ShopPageFrames) {
        let next = nextValue()
        value.coverBottom = min(value.coverBottom, next.coverBottom)
        value.tabsTop = min(value.tabsTop, next.tabsTop)
    }
}

/// Cover → identity card → action tiles → tabs → one panel at a time.
/// Tabs switch panels; they never scroll to an anchor. About is the default
/// so the community record is the first thing a visitor reads. Reviews and
/// Shop only exist once an owner has published listings.
struct ShopPageView: View {
    private let base: CoffeeShop
    var loadError: String?
    var isLoadingFull = false
    var actions = ShopPageActions()

    @State private var tab: ShopTab = .about
    @State private var frames = ShopPageFrames()
    @State private var showPhotos = false
    @State private var showMore = false
    @State private var pendingMoreAction: (() -> Void)?
    @State private var comingSoon = false
    // Images arrive in their own request, triggered by the first panel that
    // shows them. Overlaid on every render so a refreshed `base` keeps them.
    @State private var media: ShopMedia?
    @State private var mediaTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    init(shop: CoffeeShop, loadError: String? = nil, isLoadingFull: Bool = false, actions: ShopPageActions = ShopPageActions()) {
        base = shop
        self.loadError = loadError
        self.isLoadingFull = isLoadingFull
        self.actions = actions
    }

    private var shop: CoffeeShop { media.map(base.merging) ?? base }

    private static let navRowHeight: CGFloat = 44
    private static let coverHeight: CGFloat = 256
    private static let cardOverlap: CGFloat = 28

    private var tabs: [ShopTab] {
        shop.sellsOnline ? [.about, .reviews, .shop] : [.about, .reviews]
    }

    private var listings: [ShopListing] {
        (shop.products ?? []).filter { $0.status != "HIDDEN" }
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let chromeHeight = topInset + Self.navRowHeight
            let coverGone = frames.coverBottom <= chromeHeight
            let tabsPinned = tabs.count > 1 && frames.tabsTop <= chromeHeight

            ScrollViewReader { reader in
                ScrollView {
                    // Not lazy: the cover and tab row report their frames for
                    // the pinned header, and a LazyVStack drops them once
                    // they scroll off, which would un-pin the header.
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        identityCard
                        actionTiles
                        if tabs.count > 1 {
                            tabBar
                                .id("tabs")
                                .background(frameReporter { ShopPageFrames(tabsTop: $0.minY) })
                        }
                        panel
                            .frame(minHeight: proxy.size.height - Self.navRowHeight - 40, alignment: .top)
                        if let chain = shop.chain {
                            let others = chain.shops.filter { $0.id != shop.id }
                            if !others.isEmpty {
                                RelatedShopsRail(
                                    title: "Also at \(chain.name)",
                                    subtitle: ShopPageFormat.plural(others.count, "other location"),
                                    shops: others
                                )
                                .padding(.top, 32)
                            }
                        }
                        Color.clear.frame(height: 24)
                    }
                }
                .coordinateSpace(name: "shopScroll")
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ShopPageFramesKey.self) { frames = $0 }
                .onChange(of: tab) {
                    if tab == .shop { loadMediaIfNeeded() }
                    // Keep the header where the thumb is when switching panels
                    // from the pinned bar; otherwise the content just swaps.
                    guard tabsPinned else { return }
                    let total = proxy.size.height + topInset
                    reader.scrollTo("tabs", anchor: UnitPoint(x: 0, y: chromeHeight / total))
                }
                .overlay(alignment: .top) {
                    topChrome(topInset: topInset, solid: coverGone || tabsPinned, pinned: tabsPinned)
                }
            }
        }
        .background(Color.cream50)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onChange(of: showPhotos) {
            if showPhotos { loadMediaIfNeeded() }
        }
        .sheet(isPresented: $showPhotos) {
            ShopPhotoSheet(shop: shop)
        }
        .sheet(isPresented: $showMore, onDismiss: {
            // Run after the sheet is gone; presenting a second sheet while
            // this one animates out drops the new one.
            let action = pendingMoreAction
            pendingMoreAction = nil
            action?()
        }) {
            ShopMoreSheet(shopName: shop.name, items: moreItems) { item in
                pendingMoreAction = item.action
                showMore = false
            }
        }
        .alert("Checkout is coming soon", isPresented: $comingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You’ll be able to order from \(shop.name) right here. Save the shop to get notified.")
        }
    }

    private func loadMediaIfNeeded() {
        guard media == nil, mediaTask == nil else { return }
        let id = base.id
        mediaTask = Task {
            media = try? await CoffeeAPI.fetchShopMedia(id: id)
            mediaTask = nil
        }
    }

    private func frameReporter(_ make: @escaping (CGRect) -> ShopPageFrames) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: ShopPageFramesKey.self, value: make(geo.frame(in: .named("shopScroll"))))
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ShopCoverImage(url: shop.photoURL)
                .frame(height: Self.coverHeight)
                .frame(maxWidth: .infinity)
                .clipped()

            if let photos = shop.photoCount, photos > 0 {
                Button { showPhotos = true } label: {
                    CoverChip(symbol: "camera.fill", text: count(photos, "photo"))
                }
                .buttonStyle(.plain)
                .padding(.leading, 24)
                .padding(.bottom, Self.cardOverlap + 12)
            }
        }
        .background(frameReporter { ShopPageFrames(coverBottom: $0.maxY) })
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ShopAvatar(shop: shop, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shop.name)
                        .font(.kycPageTitle)
                        .foregroundStyle(Color.ink)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text("\(shop.address) · \(shop.city)")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                .padding(.top, 6)
            }

            if let vibe = shop.vibe, !vibe.isEmpty {
                Text(vibe)
                    .font(.kycSecondary)
                    .lineSpacing(4)
                    .foregroundStyle(Color.inkMuted)
            }

            if isLoadingFull {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading listings and records…")
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkFaint)
                }
            } else if let loadError {
                Text(loadError)
                    .font(.kycMeta)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
        .padding(.top, -Self.cardOverlap)
    }

    // MARK: Actions

    private var actionTiles: some View {
        HStack(spacing: 8) {
            ActionTile(symbol: "arrow.triangle.turn.up.right.diamond.fill", label: "Directions", style: .primary) {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: shop.coordinate))
                item.name = shop.name
                item.openInMaps()
            }
            ActionTile(symbol: shop.savedByMe ? "bookmark.fill" : "bookmark",
                       label: shop.savedByMe ? "Saved" : "Save",
                       style: shop.savedByMe ? .active : .plain,
                       action: actions.onToggleSaved)
            ActionTile(symbol: shop.beenByMe ? "checkmark.circle.fill" : "checkmark.circle",
                       label: shop.beenByMe ? "Been" : "Been here",
                       style: shop.beenByMe ? .active : .plain,
                       action: actions.onToggleBeen)
            if let url = actions.shareURL {
                ShareLink(item: url, subject: Text(shop.name),
                          message: Text("\(shop.name) — \(shop.address), \(shop.city)")) {
                    ActionTileLabel(symbol: "square.and.arrow.up", label: "Share", style: .plain)
                }
                .buttonStyle(.plain)
            } else if let website = shop.website, let url = URL(string: website) {
                Link(destination: url) {
                    ActionTileLabel(symbol: "safari", label: "Website", style: .plain)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.surface)
    }

    // MARK: Tabs

    private var tabBar: some View {
        ShopTabBar(tabs: tabs, selection: $tab, shopCount: listings.count)
    }

    @ViewBuilder
    private var panel: some View {
        switch tab {
        case .about:
            ShopAboutPanel(shop: shop, listings: listings, onUpdate: actions.onUpdate) {
                tab = .shop
            }
        case .reviews:
            ShopReviewsPanel(shop: shop, onReload: actions.onReload)
        case .shop:
            ShopListingsPanel(shop: shop, listings: listings) { comingSoon = true }
        }
    }

    // MARK: Chrome

    private func topChrome(topInset: CGFloat, solid: Bool, pinned: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                NavCircle(symbol: "chevron.left", action: actions.onBack)
                Spacer()
                if solid {
                    Text(shop.name)
                        .font(.kycBodyBold)
                        .lineLimit(1)
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                // Save and Share live in the action tiles; the nav row only
                // carries what the tiles do not.
                if !moreItems.isEmpty {
                    NavCircle(symbol: "ellipsis") { showMore = true }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.navRowHeight)
            .padding(.top, topInset)

            if pinned {
                tabBar
            }
        }
        .background {
            if solid {
                Rectangle().fill(.regularMaterial)
                    .overlay(alignment: .bottom) {
                        if pinned { Rectangle().fill(Color.cream200).frame(height: 0.5) }
                    }
            }
        }
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.15), value: solid)
    }

    private var moreItems: [ShopMoreItem] {
        var items: [ShopMoreItem] = []
        if let website = shop.website, let url = URL(string: website) {
            items.append(ShopMoreItem(
                symbol: "safari", title: "Visit website",
                subtitle: url.host?.replacingOccurrences(of: "www.", with: "") ?? website
            ) { openURL(url) })
        }
        if let onClaim = actions.onClaim {
            items.append(ShopMoreItem(
                symbol: "checkmark.shield", title: "Claim this shop",
                subtitle: "Own it? Verify to sell beans here", action: onClaim
            ))
        }
        if let onDelete = actions.onDelete {
            items.append(ShopMoreItem(
                symbol: "trash", title: "Delete shop",
                subtitle: "Admin · removes this listing", destructive: true, action: onDelete
            ))
        }
        return items
    }

    // The Shop tab already sells; only the claim prompt earns a bottom bar.
    @ViewBuilder
    private var bottomBar: some View {
        if shop.ownerId == nil, !isLoadingFull, let onClaim = actions.onClaim {
            ShopBottomBar(
                icon: "storefront.fill",
                badge: nil,
                title: "Own this shop?",
                titleMeta: nil,
                subline: "Claim it to sell beans here",
                sublineSymbol: "checkmark.seal.fill",
                buttonLabel: "Claim shop",
                buttonSymbol: "arrow.right",
                action: onClaim
            )
        }
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

// MARK: - Hero pieces

private struct ShopCoverImage: View {
    let url: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2B1D14), Color(hex: 0x6F4E37), Color(hex: 0xC08C3E)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
            // Keeps nav buttons and chips legible over any photo.
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x1B120C).opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color(hex: 0x1B120C).opacity(0.65), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

private struct CoverChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: 0x1B120C).opacity(0.38), in: Capsule())
    }
}

struct ShopAvatar: View {
    let shop: CoffeeShop
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.espresso700)
            if let url = shop.photoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.surface, lineWidth: 3))
    }

    private var initials: some View {
        Text(ShopPageFormat.initials(shop.name))
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(Color.inkInverse)
    }
}

// MARK: - Action tiles

enum ActionTileStyle {
    case primary, plain, active
}

private struct ActionTile: View {
    let symbol: String
    let label: String
    let style: ActionTileStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(symbol: symbol, label: label, style: style)
        }
        .buttonStyle(.plain)
    }
}

struct ActionTileLabel: View {
    let symbol: String
    let label: String
    let style: ActionTileStyle

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(label).font(.kycMetaBold).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(fill, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
    }

    private var fill: Color {
        switch style {
        case .primary: .espresso700
        case .plain: .surface
        case .active: .accentSoft
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: .inkInverse
        case .plain: .ink
        case .active: .crema500
        }
    }

    private var border: Color {
        switch style {
        case .primary: .clear
        case .plain: .cream200
        case .active: .crema400
        }
    }
}

// MARK: - Nav circles

// 36pt dark translucent circle inside a 44pt hit target; white glyph reads
// on photos and on the blurred header alike.
private struct NavCircle: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NavCircleLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

private struct NavCircleLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color(hex: 0x1B120C).opacity(0.38), in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Tabs

private struct ShopTabBar: View {
    let tabs: [ShopTab]
    @Binding var selection: ShopTab
    let shopCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.label)
                            .font(.system(size: 14, weight: .semibold))
                        if tab == .shop, shopCount > 0 {
                            Text("\(shopCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.crema500)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentSoft, in: Capsule())
                        }
                    }
                    .foregroundStyle(selection == tab ? Color.ink : Color.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selection == tab ? Color.crema500 : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.cream200).frame(height: 1)
        }
    }
}

// MARK: - Bottom bar

private struct ShopBottomBar: View {
    let icon: String
    let badge: String?
    let title: String
    let titleMeta: String?
    let subline: String
    let sublineSymbol: String
    let buttonLabel: String
    let buttonSymbol: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 40, height: 40)
                .background(Color.cream100, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.crema500, in: Capsule())
                            .overlay(Capsule().stroke(Color.surface, lineWidth: 2))
                            .offset(x: 6, y: -6)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    if let titleMeta {
                        Text(titleMeta)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                if !subline.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: sublineSymbol).font(.system(size: 9, weight: .semibold))
                        Text(subline).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color.savedGreen)
                }
            }

            Spacer(minLength: 8)

            Button(action: action) {
                HStack(spacing: 6) {
                    Text(buttonLabel).font(.system(size: 14, weight: .semibold))
                    Image(systemName: buttonSymbol).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.inkInverse)
                .padding(.leading, 18)
                .padding(.trailing, 16)
                .padding(.vertical, 12)
                .background(Color.espresso700, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cream200).frame(height: 1)
        }
        .shadow(color: .shadowInk.opacity(0.10), radius: 9, y: -6)
    }
}

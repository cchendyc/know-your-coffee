import SwiftUI

// App root: the bottom tab bar. Home and Me always; Seller Hub sits between
// them for verified owners only — buyer-only users never see seller chrome.
struct RootView: View {
    enum Tab: String, CaseIterable {
        case home, sellerHub, me

        var label: String {
            switch self {
            case .home: "Home"
            case .sellerHub: "Seller Hub"
            case .me: "Me"
            }
        }

        // Outline at rest, filled when selected, so the active tab reads
        // without relying on colour alone.
        func icon(active: Bool) -> String {
            switch self {
            case .home: active ? "house.fill" : "house"
            case .sellerHub: active ? "storefront.fill" : "storefront"
            case .me: active ? "person.crop.circle.fill" : "person.crop.circle"
            }
        }
    }

    @State private var auth = AuthStore.shared
    @State private var tab: Tab = .home
    @State private var ownedShops: [OwnedShop] = []
    // Orders waiting to be fulfilled; shown as a count on the Seller Hub tab.
    @State private var openOrders = 0

    private var tabs: [Tab] {
        ownedShops.isEmpty ? [.home, .me] : Tab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            // ZStack + opacity keeps every tab alive, so switching back does
            // not reload feeds or reset scroll positions.
            ZStack {
                // Home carries its own list/map toggle; the map is not a tab.
                // Saved and Been lists live under Me.
                HomeView(embedded: true)
                    .opacity(tab == .home ? 1 : 0)
                    .allowsHitTesting(tab == .home)
                if !ownedShops.isEmpty {
                    NavigationStack {
                        sellerHubRoot
                    }
                    .opacity(tab == .sellerHub ? 1 : 0)
                    .allowsHitTesting(tab == .sellerHub)
                }
                ProfileView(isTab: true, onEndpointChange: {})
                    .opacity(tab == .me ? 1 : 0)
                    .allowsHitTesting(tab == .me)
            }
            .frame(maxHeight: .infinity)

            tabBar
        }
        .background(Color.cream50.ignoresSafeArea())
        .task(id: auth.user?.id) {
            await refreshOwnedShops()
        }
        // Support may approve an application mid-session; re-check when the
        // user visits Me so the Seller Hub tab appears without a relaunch.
        .task(id: tab) {
            if tab == .me { await refreshOwnedShops() }
        }
    }

    // One shop opens straight into its hub; several open on All shops with the switcher.
    private var sellerHubRoot: some View {
        SellerHubView(shops: ownedShops)
            .id(ownedShops.map(\.id))
    }

    private func refreshOwnedShops() async {
        guard auth.isSignedIn else {
            ownedShops = []
            openOrders = 0
            if tab == .sellerHub { tab = .home }
            return
        }
        ownedShops = (try? await CoffeeAPI.fetchMyShops()) ?? []
        if ownedShops.isEmpty, tab == .sellerHub { tab = .home }
        // One cross-shop query covers every owned shop.
        let placed = ownedShops.isEmpty ? nil : try? await CoffeeAPI.fetchMyOrders(shopID: nil, status: .placed, limit: 1)
        openOrders = placed?.total ?? 0
    }

    // Figma tab bar: hairline divider, tiny semibold labels, ink active state.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        tabIcon(item)
                            .overlay(alignment: .topTrailing) {
                                if item == .sellerHub && openOrders > 0 {
                                    // Count of orders to fulfil; "9+" keeps the pill one size.
                                    Text(openOrders > 9 ? "9+" : String(openOrders))
                                        .font(.system(size: 10, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color(red: 0.89, green: 0.17, blue: 0.17), in: Capsule()) // Figma #e32b2b
                                        .overlay(Capsule().strokeBorder(Color.surface, lineWidth: 1.5))
                                        .offset(x: 10, y: -6)
                                }
                            }
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(tab == item ? Color.ink : Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 5)
        .background(
            Color.surface
                .overlay(alignment: .top) { Color.cream200.frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // Me shows the signed-in user's photo in a circle, ringed when active;
    // signed-out users and photo-less accounts get the SF Symbol.
    @ViewBuilder
    private func tabIcon(_ item: Tab) -> some View {
        if item == .me, let picture = auth.user?.picture, let url = URL(string: picture) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(Color.cream200)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(tab == item ? Color.ink : .clear, lineWidth: 1.5))
        } else {
            Image(systemName: item.icon(active: tab == item))
                .font(.system(size: 22, weight: .medium))
                .frame(width: 28, height: 26)
        }
    }
}

#Preview {
    RootView()
}

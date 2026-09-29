import SwiftUI

// App root: the Figma bottom tab bar. Seller Hub appears only for verified
// owners — buyer-only users get four tabs and never see seller chrome.
struct RootView: View {
    enum Tab: String, CaseIterable {
        case explore, map, saved, sellerHub, you

        var label: String {
            switch self {
            case .explore: "Explore"
            case .map: "Map"
            case .saved: "Saved"
            case .sellerHub: "Seller Hub"
            case .you: "You"
            }
        }

        var icon: String {
            switch self {
            case .explore: "safari"
            case .map: "map"
            case .saved: "bookmark"
            case .sellerHub: "storefront"
            case .you: "person.crop.circle"
            }
        }
    }

    @State private var auth = AuthStore.shared
    @State private var tab: Tab = .explore
    @State private var ownedShops: [OwnedShop] = []
    // Figma's red dot on the Seller Hub tab: orders waiting to be shipped.
    @State private var hasOpenOrders = false

    private var tabs: [Tab] {
        ownedShops.isEmpty ? [.explore, .map, .saved, .you] : Tab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            // ZStack + opacity keeps every tab alive, so switching back does
            // not reload feeds or reset scroll positions.
            ZStack {
                HomeView(embedded: true)
                    .opacity(tab == .explore ? 1 : 0)
                    .allowsHitTesting(tab == .explore)
                MapTabView()
                    .opacity(tab == .map ? 1 : 0)
                    .allowsHitTesting(tab == .map)
                HomeView(embedded: true, pinnedList: .saved)
                    .opacity(tab == .saved ? 1 : 0)
                    .allowsHitTesting(tab == .saved)
                if !ownedShops.isEmpty {
                    NavigationStack {
                        sellerHubRoot
                    }
                    .opacity(tab == .sellerHub ? 1 : 0)
                    .allowsHitTesting(tab == .sellerHub)
                }
                ProfileView(isTab: true, onEndpointChange: {})
                    .opacity(tab == .you ? 1 : 0)
                    .allowsHitTesting(tab == .you)
            }
            .frame(maxHeight: .infinity)

            tabBar
        }
        .background(Color.cream50.ignoresSafeArea())
        .task(id: auth.user?.id) {
            await refreshOwnedShops()
        }
        // Support may approve an application mid-session; re-check when the
        // user visits You so the Seller Hub tab appears without a relaunch.
        .task(id: tab) {
            if tab == .you { await refreshOwnedShops() }
        }
    }

    // One shop goes straight to its hub; multiple get a chooser.
    @ViewBuilder
    private var sellerHubRoot: some View {
        if ownedShops.count == 1, let shop = ownedShops.first {
            SellerHubView(shop: shop)
        } else {
            List(ownedShops) { shop in
                NavigationLink(shop.name) { SellerHubView(shop: shop) }
                    .font(.kycBody)
            }
            .navigationTitle("Seller Hub")
        }
    }

    private func refreshOwnedShops() async {
        guard auth.isSignedIn else {
            ownedShops = []
            hasOpenOrders = false
            if tab == .sellerHub { tab = .explore }
            return
        }
        ownedShops = (try? await CoffeeAPI.fetchMyShops()) ?? []
        if ownedShops.isEmpty, tab == .sellerHub { tab = .explore }
        var open = false
        for shop in ownedShops where !open {
            let orders = (try? await CoffeeAPI.fetchMyOrders(shopID: shop.id)) ?? []
            open = orders.contains { $0.status == .placed }
        }
        hasOpenOrders = open
    }

    // Figma tab bar: hairline divider, tiny semibold labels, ink active state.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: tab == item ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if item == .sellerHub && hasOpenOrders {
                                    Circle()
                                        .fill(Color(red: 0.89, green: 0.17, blue: 0.17)) // Figma #e32b2b
                                        .frame(width: 7, height: 7)
                                        .offset(x: 5, y: -3)
                                }
                            }
                        Text(item.label)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(tab == item ? Color.ink : Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 46)
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
}

// Map as its own tab; the explore feed no longer needs a list/map toggle.
private struct MapTabView: View {
    @State private var store = ShopStore()
    @State private var selected: CoffeeShop?

    var body: some View {
        ShopMapView(shops: store.shops) { selected = $0 }
            .ignoresSafeArea(edges: .bottom)
            .task { store.reload() }
            .fullScreenCover(item: $selected) { shop in
                ShopDetailView(
                    summary: shop,
                    onShopChanged: { store.patch($0) },
                    onDeleted: {
                        store.remove(shop.id)
                        selected = nil
                    }
                )
            }
    }
}

#Preview {
    RootView()
}

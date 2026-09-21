import SwiftUI

struct HomeView: View {
    @State private var store = ShopStore()
    @State private var auth = AuthStore.shared
    @State private var selectedShop: CoffeeShop?
    @State private var showProfile = false
    @State private var showAddShop = false
    @State private var showSignIn = false
    @State private var searchExpanded = false
    @FocusState private var searchFocused: Bool
    // Detail zooms out of the tapped card (matched transition source).
    @Namespace private var zoomNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.cream50.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if let message = store.errorMessage {
                    errorBanner(message)
                } else if store.viewMode == .list {
                    feed
                } else {
                    ShopMapView(shops: store.shops) { selectedShop = $0 }
                        .ignoresSafeArea(edges: .bottom)
                }
            }

            modeToggle
            addButton
        }
        .task { store.reload(); await auth.refreshUser() }
        .fullScreenCover(item: $selectedShop) { shop in
            ShopDetailView(
                summary: shop,
                onShopChanged: { store.patch($0) },
                onDeleted: {
                    store.remove(shop.id)
                    selectedShop = nil
                }
            )
            .navigationTransition(.zoom(sourceID: shop.id, in: zoomNamespace))
        }
        .sheet(isPresented: $showProfile) {
            ProfileView { store.reload() }
        }
        .sheet(isPresented: $showAddShop) {
            AddShopView { added in
                showAddShop = false
                store.reload()
                selectedShop = added
            }
        }
        // Adding a shop needs an account; continue into the form after sign-in.
        .sheet(isPresented: $showSignIn, onDismiss: {
            if auth.isSignedIn { showAddShop = true }
        }) {
            SignInSheet()
        }
    }

    // MARK: Header — profile left, tabs centered, search right. The search
    // icon expands into a full-width bar in place, xiaohongshu-style.

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                if searchExpanded {
                    expandedSearchRow
                        .transition(.opacity)
                } else {
                    collapsedHeaderRow
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.22), value: searchExpanded)
            machineChips
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .zIndex(1)
    }

    private var collapsedHeaderRow: some View {
        HStack(spacing: 0) {
            // 44pt frames keep the HIG minimum hit target; alignment pins the
            // small glyphs to the screen edges so the layout doesn't shift.
            Button {
                showProfile = true
            } label: {
                profileIcon
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
            listTabs
            Spacer()

            Button {
                searchExpanded = true
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A committed search keeps a small badge so active filtering stays visible.
            .overlay(alignment: .topTrailing) {
                if !store.draft.isEmpty {
                    Circle().fill(Color.crema500).frame(width: 7, height: 7).offset(x: -1, y: 8)
                }
            }
        }
        .frame(height: 44)
    }

    private var profileIcon: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.espresso700)
    }

    private var expandedSearchRow: some View {
        HStack(spacing: 10) {
            searchField
            Button {
                store.draft = ""
                store.clearSearchIfEmpty()
                searchFocused = false
                searchExpanded = false
            } label: {
                Text("Cancel")
                    .font(.kycBody)
                    .foregroundStyle(Color.espresso700)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    // Text tabs with an underline indicator, xiaohongshu-style.
    private var listTabs: some View {
        HStack(spacing: 22) {
            ForEach(ShopStore.ListFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.list = filter }
                } label: {
                    VStack(spacing: 4) {
                        Text(filter.label)
                            .font(.system(size: 15, weight: store.list == filter ? .semibold : .regular))
                            .foregroundStyle(store.list == filter ? Color.ink : Color.inkMuted)
                        Capsule()
                            .fill(store.list == filter ? Color.crema500 : .clear)
                            .frame(width: 18, height: 3)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.inkFaint)

            TextField("La Marzocco, Ethiopia, Oakland…", text: $store.draft)
                .font(.kycBody)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { store.commitSearch() }
                .onChange(of: store.draft) { store.clearSearchIfEmpty() }

            if !store.draft.isEmpty {
                Button {
                    store.draft = ""
                    store.clearSearchIfEmpty()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36) // Apple's standard search bar height
        .background(Color.espresso900.opacity(searchFocused ? 0.07 : 0.05), in: Capsule())
    }

    private var machineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All machines", isOn: store.machine == nil) {
                    store.machine = nil
                }
                ForEach(MachineBrand.allCases.filter { $0 != .unknown && $0 != .other }) { brand in
                    chip(label: brand.label, isOn: store.machine == brand) {
                        store.machine = store.machine == brand ? nil : brand
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.horizontal, -14)
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(isOn ? .kycMetaBold : .kycMeta)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    isOn ? Color.espresso900 : Color.espresso900.opacity(0.05),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? Color.inkInverse : Color.espresso700)
        }
        .buttonStyle(.plain)
    }

    // MARK: Feed — two-column staggered grid, xiaohongshu-style.

    private var feed: some View {
        // Wide photos otherwise push their column past half the screen;
        // masonry only works with hard column widths.
        GeometryReader { geo in
            let columnWidth = (geo.size.width - 8 * 2 - 6) / 2
            ScrollView {
                if store.isLoading && store.shops.isEmpty {
                    masonry(
                        left: { placeholderColumn([160, 210, 130], width: columnWidth) },
                        right: { placeholderColumn([220, 140, 180], width: columnWidth) }
                    )
                } else if store.shops.isEmpty {
                    emptyState
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                } else {
                    masonry(
                        left: { feedColumn(stride: 0, width: columnWidth) },
                        right: { feedColumn(stride: 1, width: columnWidth) }
                    )
                    if store.hasMore {
                        ProgressView()
                            .padding(.vertical, 16)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { store.reload() }
        }
    }

    private func masonry(
        @ViewBuilder left: () -> some View,
        @ViewBuilder right: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            LazyVStack(spacing: 6) { left() }
            LazyVStack(spacing: 6) { right() }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 90) // clears the floating toggle
    }

    private func feedColumn(stride: Int, width: CGFloat) -> some View {
        ForEach(columnShops(stride: stride)) { shop in
            Button {
                selectedShop = shop
            } label: {
                ShopCardView(shop: shop, width: width)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: shop.id, in: zoomNamespace)
            .onAppear { store.loadMoreIfNeeded(current: shop) }
        }
    }

    private func columnShops(stride: Int) -> [CoffeeShop] {
        store.shops.enumerated()
            .filter { $0.offset % 2 == stride }
            .map(\.element)
    }

    private func placeholderColumn(_ heights: [CGFloat], width: CGFloat) -> some View {
        ForEach(heights, id: \.self) { height in
            ShopCardPlaceholder(height: height, width: width)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 32))
                .foregroundStyle(Color.inkFaint)
            Text(emptyStateMessage)
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.cream200, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
    }

    private var emptyStateIcon: String {
        switch store.list {
        case .all: "cup.and.saucer"
        case .saved: "bookmark"
        case .been: "checkmark.circle"
        }
    }

    private var emptyStateMessage: String {
        switch store.list {
        case .all: "No shops match. Try a different search or clear the filters."
        case .saved: "Nothing saved yet. Tap the bookmark on a shop to keep it here."
        case .been: "No visits marked yet. Tap the checkmark on a shop you've been to."
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Could not reach the API: \(message)")
                .font(.kycSecondary)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Text("Check your connection, then try again.")
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
            Button("Retry") { store.reload() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Floating controls

    private var addButton: some View {
        HStack {
            Spacer()
            Button {
                if auth.isSignedIn { showAddShop = true } else { showSignIn = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.cream50)
                    .frame(width: 56, height: 56) // standard FAB size
                    .background(Color.espresso700, in: Circle())
                    // Same elevation as the List/Map pill.
                    .shadow(color: .black.opacity(0.28), radius: 16, y: 5)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ShopStore.ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.viewMode = mode }
                } label: {
                    Label(
                        mode == .list ? "List" : "Map",
                        systemImage: mode == .list ? "square.grid.2x2" : "map"
                    )
                    .font(.kycBodyBold)
                    // 44pt minimum tap target; the old 11pt pill misclicked.
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(
                        store.viewMode == mode ? Color.espresso700 : .clear,
                        in: Capsule()
                    )
                    .foregroundStyle(store.viewMode == mode ? Color.inkInverse : Color.inkMuted)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.espresso900.opacity(0.08), lineWidth: 0.5))
        // Small y-offsets: the pill sits near the screen bottom, so a big
        // downward shadow falls off-screen. Keep the halo around the pill.
        .shadow(color: .black.opacity(0.28), radius: 16, y: 5)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .padding(.bottom, 12)
    }
}

#Preview {
    HomeView()
}

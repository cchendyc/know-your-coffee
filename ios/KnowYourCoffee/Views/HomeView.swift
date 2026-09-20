import SwiftUI

struct HomeView: View {
    @State private var store = ShopStore()
    @State private var auth = AuthStore.shared
    @State private var selectedShop: CoffeeShop?
    @State private var showProfile = false
    @State private var showAddShop = false
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
        .task { store.reload() }
        .fullScreenCover(item: $selectedShop) { shop in
            ShopDetailView(summary: shop) { store.patch($0) }
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
        HStack(spacing: 12) {
            Button {
                showProfile = true
            } label: {
                profileIcon
            }

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
            }
            // A committed search keeps a small badge so active filtering stays visible.
            .overlay(alignment: .topTrailing) {
                if !store.draft.isEmpty {
                    Circle().fill(Color.crema500).frame(width: 7, height: 7).offset(x: 3, y: -2)
                }
            }
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var profileIcon: some View {
        if let picture = auth.user?.picture, let url = URL(string: picture) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.espresso500)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.espresso700)
        }
    }

    private var expandedSearchRow: some View {
        HStack(spacing: 10) {
            searchField
            Button("Cancel") {
                store.draft = ""
                store.clearSearchIfEmpty()
                searchFocused = false
                searchExpanded = false
            }
            .font(.subheadline)
            .foregroundStyle(Color.espresso500)
        }
        .frame(height: 34)
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
                            .font(.system(size: 16, weight: store.list == filter ? .bold : .regular))
                            .foregroundStyle(store.list == filter ? Color.espresso900 : Color.espresso500.opacity(0.7))
                        Capsule()
                            .fill(store.list == filter ? Color.crema500 : .clear)
                            .frame(width: 18, height: 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.espresso500.opacity(0.55))

            TextField("La Marzocco, Ethiopia, Oakland…", text: $store.draft)
                .font(.subheadline)
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
                        .foregroundStyle(Color.espresso500.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
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
                .font(.caption.weight(isOn ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isOn ? Color.espresso900 : Color.espresso900.opacity(0.05),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? Color.cream50 : Color.espresso700)
        }
        .buttonStyle(.plain)
    }

    // MARK: Feed — two-column staggered grid, xiaohongshu-style.

    private var feed: some View {
        // Wide photos otherwise push their column past half the screen;
        // masonry only works with hard column widths.
        GeometryReader { geo in
            let columnWidth = (geo.size.width - 12 * 2 - 10) / 2
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
        HStack(alignment: .top, spacing: 10) {
            LazyVStack(spacing: 10) { left() }
            LazyVStack(spacing: 10) { right() }
        }
        .padding(.horizontal, 12)
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
            Image(systemName: store.list == .all ? "cup.and.saucer" : "bookmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.espresso500.opacity(0.5))
            Text(
                store.list == .all
                    ? "No shops match. Try a different search or clear the filters."
                    : "Nothing here yet. Saved and been lists sync once sign-in lands in the app — track shops on the web for now."
            )
            .font(.footnote)
            .foregroundStyle(Color.espresso500)
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

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Could not reach the API: \(message)")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Text("Is the backend running? Set the API URL in Settings (gear, top right).")
                .font(.caption)
                .foregroundStyle(Color.espresso500)
            Button("Retry") { store.reload() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Floating controls

    private var addButton: some View {
        HStack {
            Spacer()
            Button {
                showAddShop = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.cream50)
                    .frame(width: 48, height: 48)
                    .background(Color.espresso700, in: Circle())
                    // The ring keeps the dark circle from melting into dark photos.
                    .overlay(Circle().strokeBorder(Color.cream50.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.30), radius: 14, y: 5)
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
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
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        store.viewMode == mode ? Color.espresso700 : .clear,
                        in: Capsule()
                    )
                    .foregroundStyle(store.viewMode == mode ? Color.cream50 : Color.espresso500)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
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

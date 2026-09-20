import SwiftUI

struct HomeView: View {
    @State private var store = ShopStore()
    @State private var selectedShop: CoffeeShop?
    @State private var showSettings = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.cream50.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if let message = store.errorMessage {
                    errorBanner(message)
                } else if store.viewMode == .list {
                    shopList
                } else {
                    ShopMapView(shops: store.shops) { selectedShop = $0 }
                        .ignoresSafeArea(edges: .bottom)
                }
            }

            modeToggle
        }
        .task { store.reload() }
        .onChange(of: store.shops) { if selectedShop == nil { selectedShop = store.shops.first } } // TEMP screenshot
        .sheet(item: $selectedShop) { shop in
            ShopDetailView(summary: shop)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.cream50)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView { store.reload() }
                .presentationDetents([.medium])
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.cream50)
                    .frame(width: 40, height: 40)
                    .background(Color.espresso700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text("Know Your Coffee")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.espresso900)
                    Text("coffee snobs")
                        .font(.caption)
                        .foregroundStyle(Color.espresso500)
                }

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.espresso500)
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                        .shadow(color: .espresso900.opacity(0.06), radius: 4, y: 1)
                }
            }

            searchField
            machineChips
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            Color.cream50
                .opacity(0.95)
                .shadow(color: .espresso900.opacity(0.05), radius: 6, y: 3)
                .ignoresSafeArea(edges: .top)
        )
        .zIndex(1)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.espresso500)

            TextField("Search anything, roaster, machine, city…", text: $store.draft)
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
                        .foregroundStyle(Color.espresso500.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(searchFocused ? Color.crema400 : Color.cream200, lineWidth: 1)
        )
    }

    private var machineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "Any machine", isOn: store.machine == nil) {
                    store.machine = nil
                }
                ForEach(MachineBrand.allCases.filter { $0 != .unknown && $0 != .other }) { brand in
                    chip(label: brand.label, isOn: store.machine == brand) {
                        store.machine = store.machine == brand ? nil : brand
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Color.espresso700 : .white, in: Capsule())
                .foregroundStyle(isOn ? Color.cream50 : Color.espresso500)
                .overlay(Capsule().strokeBorder(isOn ? .clear : Color.cream200, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var shopList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    Text(countLine)
                        .font(.footnote)
                        .foregroundStyle(Color.espresso500)
                    Spacer()
                }
                .padding(.top, 4)

                if store.isLoading && store.shops.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopCardPlaceholder()
                    }
                } else if store.shops.isEmpty {
                    emptyState
                } else {
                    ForEach(store.shops) { shop in
                        Button {
                            selectedShop = shop
                        } label: {
                            ShopCardView(shop: shop)
                        }
                        .buttonStyle(.plain)
                        .onAppear { store.loadMoreIfNeeded(current: shop) }
                    }
                    if store.hasMore {
                        ProgressView()
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90) // clears the floating toggle
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { store.reload() }
    }

    private var countLine: String {
        if store.isLoading { return "Searching…" }
        return "\(store.total) shop\(store.total == 1 ? "" : "s") in the Bay Area"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 32))
                .foregroundStyle(Color.espresso500.opacity(0.5))
            Text("No shops match. Try a different search or clear the filters.")
                .font(.footnote)
                .foregroundStyle(Color.espresso500)
                .multilineTextAlignment(.center)
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

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ShopStore.ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.viewMode = mode }
                } label: {
                    Label(
                        mode == .list ? "List" : "Map",
                        systemImage: mode == .list ? "list.bullet" : "map"
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
        .shadow(color: .espresso900.opacity(0.15), radius: 10, y: 4)
        .padding(.bottom, 12)
    }
}

#Preview {
    HomeView()
}

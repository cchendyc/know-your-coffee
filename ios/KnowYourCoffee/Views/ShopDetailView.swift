import SwiftUI

// Full-page shop detail (Figma "iOS / Shop Page — Unified"). Paints instantly
// from the feed's copy, then swaps in the full payload (owner, listings,
// photos, reports, chain) when shop(id:) lands. Owns every sheet and the
// sign-in gate; the page itself is stateless apart from its active tab.
struct ShopDetailView: View {
    let summary: CoffeeShop
    var onShopChanged: (CoffeeShop) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    @State private var full: CoffeeShop?
    @State private var loadError: String?
    @State private var showReportForm = false
    @State private var showClaim = false
    @State private var showSignIn = false
    // The gated action the user tapped; runs after a successful sign-in.
    @State private var pendingAction: (() -> Void)?
    @State private var actionError: String?
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var auth = AuthStore.shared
    @Environment(\.dismiss) private var dismiss

    private var shop: CoffeeShop { full ?? summary }

    var body: some View {
        NavigationStack {
            ShopPageView(
                shop: shop,
                loadError: loadError,
                isLoadingFull: full == nil && loadError == nil,
                actions: ShopPageActions(
                    onBack: { dismiss() },
                    shareURL: shareURL,
                    onToggleSaved: { gated { toggle(saved: !shop.savedByMe) } },
                    onToggleBeen: { gated { toggle(been: !shop.beenByMe) } },
                    onUpdate: { gated { showReportForm = true } },
                    onReload: { Task { await loadFull() } },
                    onClaim: shop.ownerId == nil ? { gated { showClaim = true } } : nil,
                    onDelete: auth.user?.isAdmin == true ? { confirmDelete = true } : nil
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ChainLocation.self) { location in
                ChainLocationPage(locationID: location.id, name: location.name)
            }
        }
        .task(id: summary.id) { await loadFull() }
        .sheet(isPresented: $showReportForm) {
            ReportFormView(shop: shop) {
                showReportForm = false
                Task { await loadFull() }
            }
        }
        .sheet(isPresented: $showClaim) {
            SellerApplicationFlow(shop: shop)
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            let action = pendingAction
            pendingAction = nil
            if AuthStore.shared.isSignedIn { action?() }
        }) {
            SignInSheet()
        }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog("Delete this shop?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete shop", role: .destructive) {
                Task { await deleteShop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(shop.name) will be removed. Use this for listings that aren’t coffee shops.")
        }
    }

    private func loadFull() async {
        do {
            full = try await CoffeeAPI.fetchShop(id: summary.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func gated(_ action: @escaping () -> Void) {
        if AuthStore.shared.isSignedIn {
            action()
        } else {
            pendingAction = action
            showSignIn = true
        }
    }

    // Deep link into our web app, not the shop's own site.
    private var shareURL: URL {
        let id = shop.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? shop.id
        return URL(string: "https://knowyourthings.top/shops/\(id)")!
    }

    private func toggle(saved: Bool? = nil, been: Bool? = nil) {
        Task {
            do {
                // The mutation returns core fields only; keep the loaded detail.
                let updated = try await CoffeeAPI.setShopStatus(shopID: shop.id, saved: saved, been: been)
                    .keepingDetails(from: shop)
                full = updated
                onShopChanged(updated)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func deleteShop() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await CoffeeAPI.deleteShop(id: shop.id)
            onDeleted()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// Pushed from the chain list: fetches its own full shop, same page layout.
private struct ChainLocationPage: View {
    let locationID: String
    let name: String

    @State private var shop: CoffeeShop?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let shop {
                ShopPageView(shop: shop, actions: ShopPageActions(
                    onBack: { dismiss() },
                    onReload: { Task { await reload() } }
                ))
            } else if let error {
                Text(error)
                    .font(.kycSecondary)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.cream50)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.cream50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await reload() }
    }

    private func reload() async {
        do {
            shop = try await CoffeeAPI.fetchShop(id: locationID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

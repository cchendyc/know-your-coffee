import SwiftUI

// Which shop the hub shows: every owned shop summed, or one of them.
enum HubSelection: Hashable {
    case all
    case shop(String)

    var shopID: String? {
        if case .shop(let id) = self { return id }
        return nil
    }
}

// Bottom sheet listing All shops, each owned shop with open work, pending
// claims greyed, and Add another shop. Figma: "iOS / Multi-shop — Shop switcher".
struct ShopSwitcherSheet: View {
    let seller: SellerAccount
    let selection: HubSelection
    let onSelect: (HubSelection) -> Void
    let onAddShop: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your shops")
                            .font(.kycPageTitle)
                            .foregroundStyle(Color.ink)
                        Text(subtitle)
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                    }
                    Spacer()
                    ToolbarTextButton(label: "Done", weight: .semibold) { dismiss() }
                }
                .padding(.top, 8)

                if seller.shops.count > 1 {
                    row(
                        avatar: AnyView(allShopsAvatar),
                        title: "All shops",
                        subtitle: "Totals and orders across every location",
                        badges: allBadges,
                        selected: selection == .all
                    ) { pick(.all) }
                    .cardStyle()
                }

                VStack(spacing: 0) {
                    ForEach(Array(seller.shops.enumerated()), id: \.element.id) { index, shop in
                        row(
                            avatar: AnyView(ShopMonogram(name: shop.name)),
                            title: shop.name,
                            subtitle: "\(shop.address) · \(shop.city)",
                            badges: shop.badges,
                            selected: selection == .shop(shop.id)
                        ) { pick(.shop(shop.id)) }
                        if index < seller.shops.count - 1 || !seller.pendingClaims.isEmpty {
                            Divider().padding(.leading, 66)
                        }
                    }
                    ForEach(Array(seller.pendingClaims.enumerated()), id: \.element.id) { index, claim in
                        row(
                            avatar: AnyView(ShopMonogram(name: claim.shop.name)),
                            title: claim.shop.name,
                            subtitle: claim.shop.city,
                            badges: [Badge(text: "Pending review", tone: .muted)],
                            selected: false,
                            disabled: true
                        ) {}
                        if index < seller.pendingClaims.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .cardStyle()

                Button {
                    dismiss()
                    onAddShop()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.crema500)
                            .frame(width: 38, height: 38)
                            .overlay(Circle().stroke(Color.crema400, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add another shop")
                                .font(.kycBodyBold)
                                .foregroundStyle(Color.crema500)
                            Text("Claim a location you own · reviewed by support")
                                .font(.kycSecondary)
                                .foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous)
                            .stroke(Color.cream200, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.cream50)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var subtitle: String {
        let verified = "\(seller.shops.count) verified"
        let pending = seller.pendingClaims.count
        return pending > 0 ? "\(verified) · \(pending) pending review" : verified
    }

    private var allBadges: [Badge] {
        var out: [Badge] = []
        if seller.workload.toFulfill > 0 { out.append(Badge(text: "\(seller.workload.toFulfill) to fulfill", tone: .accent)) }
        if seller.workload.toShip > 0 { out.append(Badge(text: "\(seller.workload.toShip) to ship", tone: .muted)) }
        return out
    }

    private var allShopsAvatar: some View {
        Image(systemName: "square.grid.2x2")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.inkInverse)
            .frame(width: 38, height: 38)
            .background(Color.espresso700, in: Circle())
    }

    private func pick(_ next: HubSelection) {
        dismiss()
        onSelect(next)
    }

    private func row(
        avatar: AnyView, title: String, subtitle: String, badges: [Badge],
        selected: Bool, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.kycBodyBold)
                        .foregroundStyle(disabled ? Color.inkFaint : Color.ink)
                    Text(subtitle)
                        .font(.kycSecondary)
                        .foregroundStyle(disabled ? Color.inkFaint : Color.inkMuted)
                        .lineLimit(1)
                    if !badges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(badges, id: \.text) { $0.pill }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.savedGreen)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(selected ? Color.cream50 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// Setup first, then work. Verified shops with nothing open get no badge.
extension SellerShop {
    var badges: [Badge] {
        guard sellerOnboarded else { return [Badge(text: "Finish setup", tone: .warn)] }
        guard let workload else { return [] }
        var out: [Badge] = []
        if workload.toFulfill > 0 { out.append(Badge(text: "\(workload.toFulfill) to fulfill", tone: .accent)) }
        if workload.lowStock > 0 { out.append(Badge(text: "\(workload.lowStock) low stock", tone: .warn)) }
        return out
    }
}

struct Badge: Hashable {
    enum Tone { case accent, warn, ok, muted }

    let text: String
    let tone: Tone

    var pill: Pill {
        switch tone {
        case .accent: Pill(text: text, fill: .crema400.opacity(0.18), foreground: .crema500)
        case .warn: Pill(text: text, fill: .markerOrange.opacity(0.14), foreground: .markerOrange)
        case .ok: Pill(text: text, fill: .savedGreen.opacity(0.12), foreground: .savedGreen)
        case .muted: Pill(text: text, fill: .cream100, foreground: .inkMuted)
        }
    }
}

// Two-letter monogram in a cream circle; the web ShopAvatar.
struct ShopMonogram: View {
    let name: String
    var size: CGFloat = 38

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.3, weight: .bold))
            .foregroundStyle(Color.espresso700)
            .frame(width: size, height: size)
            .background(Color.cream100, in: Circle())
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Copy listings

// Pick a target shop and the listings to duplicate. Copies start hidden at
// stock 0, so the seller confirms stock at the target before buyers see them.
struct CopyListingsSheet: View {
    let from: SellerShop
    let targets: [SellerShop]
    let onCopied: (Int, SellerShop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var toID: String
    @State private var products: [Product] = []
    @State private var picked: Set<String> = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    init(from: SellerShop, targets: [SellerShop], onCopied: @escaping (Int, SellerShop) -> Void) {
        self.from = from
        self.targets = targets
        self.onCopied = onCopied
        _toID = State(initialValue: targets.first(where: \.sellerOnboarded)?.id ?? targets.first?.id ?? "")
    }

    private var to: SellerShop? { targets.first { $0.id == toID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Copy to") {
                    Picker("Shop", selection: $toID) {
                        ForEach(targets) { shop in
                            Text("\(shop.name) · \(shop.address)\(shop.sellerOnboarded ? "" : " (needs setup)")").tag(shop.id)
                        }
                    }
                }
                Section {
                    if loading {
                        Text("Loading listings…").font(.kycSecondary).foregroundStyle(Color.inkMuted)
                    } else if products.isEmpty {
                        Text("No listings to copy yet.").font(.kycSecondary).foregroundStyle(Color.inkMuted)
                    }
                    ForEach(products) { product in
                        Button { toggle(product.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: picked.contains(product.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(picked.contains(product.id) ? Color.espresso700 : Color.inkFaint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.name).font(.kycBodyBold).foregroundStyle(Color.ink)
                                    Text([product.subtitle, product.price.formatted(.currency(code: "USD"))].compactMap { $0 }.joined(separator: " · "))
                                        .font(.kycSecondary)
                                        .foregroundStyle(Color.inkMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("\(products.count) listings · \(picked.count) selected")
                        Spacer()
                        Button("Select all") { picked = Set(products.map(\.id)) }
                            .font(.kycMetaBold)
                            .textCase(nil)
                    }
                } footer: {
                    Text("Copies keep the name, category, details, description, price, photos and low-stock alert. Quantity starts at 0 and each copy stays hidden until you set a quantity and list it\(to.map { " at \($0.name)" } ?? "").")
                }
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
            }
            .navigationTitle("Copy listings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarTextButton(label: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarTextButton(label: saving ? "Copying…" : "Copy \(picked.count)", weight: .semibold) { copy() }
                        .disabled(saving || picked.isEmpty || to == nil)
                }
            }
            .task { await load() }
        }
    }

    private func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func load() async {
        defer { loading = false }
        do {
            // Server caps a page at 100; larger catalogs copy in passes.
            let page = try await CoffeeAPI.fetchMyProducts(shopID: from.id, offset: 0, limit: 100)
            products = page.items
            picked = Set(products.map(\.id))
        } catch { self.error = error.localizedDescription }
    }

    private func copy() {
        guard let to else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let count = try await CoffeeAPI.copyProducts(fromShopID: from.id, toShopID: to.id, productIDs: Array(picked))
                onCopied(count, to)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

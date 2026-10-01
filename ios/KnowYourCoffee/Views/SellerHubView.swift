import SwiftUI

// Seller Hub home: Products, Orders, and Shipments for one owned shop, or
// totals across every shop. Mirrors the web Seller Hub; reached from the
// Seller Hub tab and the profile sheet.
struct SellerHubView: View {
    let shops: [OwnedShop]

    @State private var selection: HubSelection
    @State private var seller: SellerAccount?
    @State private var stats: HubStats?
    @State private var error: String?
    @State private var switching = false
    @State private var addingShop = false
    @State private var copying = false
    @State private var flash: String?

    // One shop opens directly; several open on All shops unless a shop is given.
    init(shops: [OwnedShop], selected: OwnedShop? = nil) {
        self.shops = shops
        let initial: HubSelection = selected.map { .shop($0.id) } ?? (shops.count == 1 ? .shop(shops[0].id) : .all)
        _selection = State(initialValue: initial)
    }

    private var sellerShops: [SellerShop] {
        seller?.shops ?? shops.map { SellerShop(id: $0.id, name: $0.name, address: "", city: $0.city, sellerOnboarded: true, workload: nil) }
    }

    private var currentShop: SellerShop? {
        guard let id = selection.shopID else { return nil }
        return sellerShops.first { $0.id == id }
    }

    private var copyTargets: [SellerShop] {
        sellerShops.filter { $0.id != selection.shopID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header.padding(.horizontal, 24)

                if let error {
                    Text(error)
                        .font(.kycSecondary)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
                if let flash {
                    Text(flash)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.savedGreen)
                        .padding(.horizontal, 24)
                }

                if let shop = currentShop {
                    shopRows(shop).padding(.horizontal, 24)
                } else {
                    allShopsBody.padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.cream50)
        .navigationTitle("Seller Hub")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selection) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $switching) {
            if let seller {
                ShopSwitcherSheet(seller: seller, selection: selection, onSelect: { selection = $0 }, onAddShop: { addingShop = true })
            }
        }
        .sheet(isPresented: $addingShop) {
            SellerApplicationFlow()
        }
        .sheet(isPresented: $copying) {
            if let shop = currentShop {
                CopyListingsSheet(from: shop, targets: copyTargets) { count, to in
                    flash = "Copied \(count) \(count == 1 ? "listing" : "listings") to \(to.name). They stay hidden with stock 0 until you list them."
                    Task { await load() }
                }
            }
        }
    }

    // Shop name plus "1 of 3 shops"; tapping opens the switcher when there is
    // more than one shop. Single-shop sellers keep the plain verified line.
    private var header: some View {
        Button {
            switching = true
        } label: {
            HStack(spacing: 6) {
                if let shop = currentShop {
                    Text(shop.name)
                        .font(.kycSecondaryBold)
                        .foregroundStyle(Color.ink)
                    if shops.count > 1 {
                        Text("· \(shop.city)")
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                    }
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.savedGreen)
                    Text(shops.count > 1 ? "\(index(of: shop)) of \(shops.count) shops" : "Verified owner")
                        .font(.kycMeta)
                        .foregroundStyle(Color.savedGreen)
                } else {
                    Text("All shops")
                        .font(.kycSecondaryBold)
                        .foregroundStyle(Color.ink)
                    Text("· \(shops.count) shops")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                }
                if shops.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(shops.count == 1 || seller == nil)
    }

    private func index(of shop: SellerShop) -> Int {
        (sellerShops.firstIndex { $0.id == shop.id } ?? 0) + 1
    }

    private func shopRows(_ shop: SellerShop) -> some View {
        VStack(spacing: 10) {
            hubRow(title: "Products", detail: productsDetail, icon: "shippingbox") {
                ProductsListView(shop: shop.owned)
            }
            hubRow(
                title: "Orders",
                detail: stats.map { "\($0.workload?.toFulfill ?? 0) to fulfill" } ?? "…",
                icon: "bag"
            ) {
                OrdersListView(shopID: shop.id)
            }
            hubRow(
                title: "Shipments",
                detail: stats.map { "\($0.workload?.toShip ?? 0) to ship" } ?? "…",
                icon: "truck.box"
            ) {
                ShipmentsListView(shopID: shop.id)
            }
            if !copyTargets.isEmpty, (stats?.products.total ?? 0) > 0 {
                Button { copying = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.espresso700)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copy listings to another shop")
                                .font(.kycBodyBold)
                                .foregroundStyle(Color.ink)
                            Text("Reuse this shop's catalog at a second location")
                                .font(.kycSecondary)
                                .foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Totals, a card per shop, then cross-shop Orders and Shipments.
    private var allShopsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            let workload = seller?.workload ?? .zero
            HStack(spacing: 0) {
                total(value: workload.toFulfill, label: "To fulfill", tint: .crema500)
                Divider().frame(height: 30)
                total(value: workload.toShip, label: "To ship", tint: .ink)
                Divider().frame(height: 30)
                total(value: workload.lowStock, label: "Low stock", tint: .markerOrange)
            }
            .padding(.vertical, 14)
            .cardStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Your shops")
                    .font(.kycSection)
                    .foregroundStyle(Color.ink)
                ForEach(sellerShops) { shop in
                    Button { selection = .shop(shop.id) } label: {
                        HStack(spacing: 12) {
                            ShopMonogram(name: shop.name)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shop.name).font(.kycBodyBold).foregroundStyle(Color.ink)
                                Text("\(shop.address) · \(shop.city)")
                                    .font(.kycSecondary)
                                    .foregroundStyle(Color.inkMuted)
                                    .lineLimit(1)
                                let badges = shop.badges.isEmpty ? [Badge(text: "Verified owner", tone: .ok)] : shop.badges
                                HStack(spacing: 6) {
                                    ForEach(badges, id: \.text) { $0.pill }
                                }
                                .padding(.top, 2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.inkFaint)
                        }
                        .padding(14)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 10) {
                hubRow(title: "Orders", detail: "\(workload.toFulfill) to fulfill · all shops", icon: "bag") {
                    OrdersListView(shopID: nil)
                }
                hubRow(title: "Shipments", detail: "\(workload.toShip) to ship · all shops", icon: "truck.box") {
                    ShipmentsListView(shopID: nil)
                }
            }
        }
    }

    private func total(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? tint : Color.ink)
            Text(label)
                .font(.kycMeta)
                .foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var productsDetail: String {
        guard let counts = stats?.products else { return "…" }
        return "\(counts.total) listed\(counts.lowStock > 0 ? " · \(counts.lowStock) low on stock" : "")"
    }

    private func load() async {
        do {
            // Badges go stale as orders are handled; refetch with every visit.
            seller = try await CoffeeAPI.fetchMySeller()
            if let id = selection.shopID {
                stats = try await CoffeeAPI.fetchHubStats(shopID: id)
            } else {
                stats = nil
            }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func hubRow<Destination: View>(
        title: String, detail: String, icon: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Products

struct ProductsListView: View {
    let shop: OwnedShop

    @State private var products: [Product] = []
    @State private var total = 0
    @State private var loading = false
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
                ForEach(products) { product in
                    productRow(product)
                        .onAppear {
                            if product.id == products.last?.id { Task { await load(reset: false) } }
                        }
                }
                if products.isEmpty && !loading {
                    Text("No products yet. Add your first bag, tote, or gift card.")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.cream50)
        .navigationTitle("Products")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarTextButton(label: "Add", weight: .semibold) { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            // Oldest first, so a new listing belongs on the last page; reload rather than append.
            AddProductSheet(shop: shop) { _ in Task { await load(reset: true) } }
        }
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading, reset || products.count < total else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CoffeeAPI.fetchMyProducts(shopID: shop.id, offset: reset ? 0 : products.count)
            let seen = reset ? [] : Set(products.map(\.id))
            products = (reset ? [] : products) + page.items.filter { !seen.contains($0.id) }
            total = page.total
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func productRow(_ product: Product) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.kycBodyBold)
                    .foregroundStyle(product.active ? Color.ink : Color.inkFaint)
                HStack(spacing: 6) {
                    Text(product.subtitle ?? product.category.label)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                    Text(product.price, format: .currency(code: "USD"))
                        .font(.kycSecondaryBold)
                        .foregroundStyle(Color.inkMuted)
                }
                if !product.active {
                    Pill(text: "Hidden", fill: .cream100, foreground: .inkMuted)
                } else if product.lowStock {
                    Pill(text: "Low stock", fill: .crema400.opacity(0.18), foreground: .crema500)
                }
            }
            Spacer()
            stepper(product)
        }
        .padding(14)
        .cardStyle()
        .contextMenu {
            Button(product.active ? "Hide from buyers" : "Show to buyers") {
                update(product, input: ["active": !product.active])
            }
            Button("Delete", role: .destructive) { delete(product) }
        }
    }

    private func stepper(_ product: Product) -> some View {
        HStack(spacing: 10) {
            stockButton("minus") {
                update(product, input: ["quantity": max(0, product.quantity - 1)])
            }
            Text("\(product.quantity)")
                .font(.kycBodyBold)
                .monospacedDigit()
                .frame(minWidth: 24)
                .foregroundStyle(Color.ink)
            stockButton("plus") {
                update(product, input: ["quantity": product.quantity + 1])
            }
        }
    }

    private func stockButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.espresso700)
                .frame(width: 28, height: 28)
                .background(Color.cream100, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func update(_ product: Product, input: [String: Any]) {
        Task {
            do {
                let updated = try await CoffeeAPI.updateProduct(id: product.id, input: input)
                if let i = products.firstIndex(where: { $0.id == updated.id }) { products[i] = updated }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func delete(_ product: Product) {
        Task {
            do {
                try await CoffeeAPI.deleteProduct(id: product.id)
                products.removeAll { $0.id == product.id }
                total -= 1
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

// The seller picks a category; its fields come from the server, grouped by section.
private struct AddProductSheet: View {
    let shop: OwnedShop
    let onAdded: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var categories: [Category] = []
    @State private var categoryID: String?
    @State private var name = ""
    @State private var texts: [String: String] = [:]
    @State private var flags: [String: Bool] = [:]
    @State private var picks: [String: Set<String>] = [:]
    @State private var description = ""
    @State private var price = ""
    @State private var quantity = ""
    @State private var saving = false
    @State private var error: String?

    private var category: Category? { categories.first { $0.id == categoryID } }
    private var priceValue: Double? { Double(price.replacingOccurrences(of: "$", with: "")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    Picker("Category", selection: $categoryID) {
                        Text("Choose…").tag(String?.none)
                        ForEach(categories) { Text($0.label).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                    TextField("Name, e.g. Urcunina", text: $name)
                }
                if let category {
                    ForEach(AttributeSection.allCases, id: \.self) { section in
                        let fields = category.fields.filter { $0.section == section }
                        if !fields.isEmpty {
                            Section(section.title) {
                                ForEach(fields) { fieldRow($0) }
                            }
                        }
                    }
                    Section("Description") {
                        TextField("Brewing tips, roast date, the farm's story", text: $description, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                Section("Price and quantity") {
                    TextField("Price, e.g. 22.00", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("Quantity on hand", text: $quantity)
                        .keyboardType(.numberPad)
                }
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarTextButton(label: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarTextButton(label: saving ? "Saving…" : "Save", weight: .semibold) { save() }
                }
            }
            // Fields differ per category; nothing carries over.
            .onChange(of: categoryID) { _, _ in
                texts = [:]
                flags = [:]
                picks = [:]
            }
            .task {
                do { categories = try await CoffeeAPI.fetchCategories() }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: CategoryField) -> some View {
        let title = field.isRequired ? "\(field.label) *" : field.label
        switch field.valueType {
        case .single:
            Picker(title, selection: Binding(
                get: { picks[field.key]?.first },
                set: { picks[field.key] = $0.map { [$0] } ?? [] }
            )) {
                if !field.isRequired { Text("—").tag(String?.none) }
                ForEach(field.options, id: \.value) { Text($0.label).tag(Optional($0.value)) }
            }
        case .multi:
            NavigationLink {
                MultiPickView(title: field.label, options: field.options, chosen: Binding(
                    get: { picks[field.key] ?? [] },
                    set: { picks[field.key] = $0 }
                ))
            } label: {
                LabeledContent(title) {
                    let chosen = picks[field.key] ?? []
                    Text(chosen.isEmpty ? "None" : field.options.filter { chosen.contains($0.value) }.map(\.label).joined(separator: ", "))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
            }
        case .bool:
            Toggle(field.label, isOn: Binding(
                get: { flags[field.key] ?? false },
                set: { flags[field.key] = $0 }
            ))
        case .int, .decimal:
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField("0", text: textBinding(field.key))
                        .keyboardType(field.valueType == .int ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.trailing)
                    if let unit = field.unit { Text(unit).foregroundStyle(Color.inkMuted) }
                }
            }
        case .textList:
            TextField("\(title), comma-separated", text: textBinding(field.key))
        case .text:
            TextField(title, text: textBinding(field.key))
        }
        if let help = field.help {
            Text(help).font(.kycMeta).foregroundStyle(Color.inkFaint)
        }
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(get: { texts[key] ?? "" }, set: { texts[key] = $0 })
    }

    /// Typed ProductInput.attributes; blanks are omitted. The server re-validates.
    private func attributes(for category: Category) throws -> [String: Any] {
        var out: [String: Any] = [:]
        for field in category.fields {
            let raw = (texts[field.key] ?? "").trimmingCharacters(in: .whitespaces)
            switch field.valueType {
            case .text:
                if !raw.isEmpty { out[field.key] = raw }
            case .int:
                if !raw.isEmpty {
                    guard let n = Int(raw) else { throw ListingError.notANumber(field.label) }
                    out[field.key] = n
                }
            case .decimal:
                if !raw.isEmpty {
                    guard let n = Double(raw) else { throw ListingError.notANumber(field.label) }
                    out[field.key] = n
                }
            case .bool:
                if flags[field.key] == true { out[field.key] = true }
            case .single:
                if let v = picks[field.key]?.first { out[field.key] = v }
            case .multi:
                if let v = picks[field.key], !v.isEmpty { out[field.key] = Array(v).sorted() }
            case .textList:
                let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !parts.isEmpty { out[field.key] = parts }
            }
            if field.isRequired, out[field.key] == nil { throw ListingError.missing(field.label) }
        }
        return out
    }

    private enum ListingError: LocalizedError {
        case missing(String)
        case notANumber(String)

        var errorDescription: String? {
            switch self {
            case .missing(let label): "\(label) is required."
            case .notANumber(let label): "\(label) must be a number."
            }
        }
    }

    private func save() {
        guard let category else {
            error = "Pick what kind of item this is."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, let priceValue, priceValue > 0 else {
            error = "A name and a price are required."
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                var input: [String: Any] = [
                    "name": trimmedName,
                    "categoryId": category.id,
                    "attributes": try attributes(for: category),
                    "price": priceValue,
                    "quantity": Int(quantity) ?? 0,
                ]
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedDescription.isEmpty { input["description"] = trimmedDescription }
                let product = try await CoffeeAPI.createProduct(shopID: shop.id, input: input)
                onAdded(product)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct MultiPickView: View {
    let title: String
    let options: [AttributeOption]
    @Binding var chosen: Set<String>

    var body: some View {
        List(options, id: \.value) { option in
            Button {
                if chosen.contains(option.value) { chosen.remove(option.value) } else { chosen.insert(option.value) }
            } label: {
                HStack {
                    Text(option.label).foregroundStyle(Color.ink)
                    Spacer()
                    if chosen.contains(option.value) {
                        Image(systemName: "checkmark").foregroundStyle(Color.espresso700)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Orders

// shopID nil = every owned shop; rows then name their shop.
struct OrdersListView: View {
    let shopID: String?

    @State private var orders: [Order] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var confirmCancel: Order?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
                ForEach(orders) { order in
                    orderRow(order)
                        .onAppear {
                            if order.id == orders.last?.id { Task { await load(reset: false) } }
                        }
                }
                if orders.isEmpty && !loading {
                    Text("No orders yet. They appear here the moment a buyer checks out.")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.cream50)
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Cancel order #\(confirmCancel?.number ?? 0)?",
            isPresented: Binding(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive) {
                if let order = confirmCancel { cancel(order) }
            }
            Button("Keep order", role: .cancel) {}
        } message: {
            Text("The buyer is refunded and the items go back into stock.")
        }
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading, reset || orders.count < total else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CoffeeAPI.fetchMyOrders(shopID: shopID, offset: reset ? 0 : orders.count)
            let seen = reset ? [] : Set(orders.map(\.id))
            orders = (reset ? [] : orders) + page.items.filter { !seen.contains($0.id) }
            total = page.total
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func orderRow(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(order.number)")
                    .font(.kycBodyBold)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                if let buyer = order.buyer {
                    Text(buyer.name).font(.kycSecondary).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Pill(text: order.isPickup ? "Pickup" : "Ship", fill: .cream100, foreground: .inkMuted)
                statusPill(order.status)
            }
            if shopID == nil, let shop = order.shop {
                HStack(spacing: 6) {
                    ShopMonogram(name: shop.name, size: 18)
                    Text(shop.name).font(.kycMeta).foregroundStyle(Color.inkMuted)
                }
            }
            Text(order.itemsSummary)
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
            HStack {
                Text(order.total, format: .currency(code: "USD"))
                    .font(.kycSecondaryBold)
                    .foregroundStyle(Color.ink)
                Text(RelativeDate.format(order.createdAt))
                    .font(.kycMeta)
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                if let step = order.nextPickupStep {
                    Button(step.label) { advance(order, to: step.status) }
                        .font(.kycMetaBold)
                        .foregroundStyle(Color.crema500)
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                }
                // Auto-accepted like Whatnot: sellers cancel but never accept or decline.
                if order.isCancelable {
                    Button("Cancel") { confirmCancel = order }
                        .font(.kycMetaBold)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    private func statusPill(_ status: OrderStatus) -> some View {
        switch status {
        case .placed: Pill(text: "To fulfill", fill: .crema400.opacity(0.18), foreground: .crema500)
        case .packed: Pill(text: "Packed", fill: .crema400.opacity(0.18), foreground: .crema500)
        case .shipped: Pill(text: "Shipped", fill: .cream100, foreground: .espresso700)
        case .delivered: Pill(text: "Delivered", fill: .savedGreen.opacity(0.12), foreground: .savedGreen)
        case .readyForPickup: Pill(text: "Ready for pickup", fill: .cream100, foreground: .espresso700)
        case .pickedUp: Pill(text: "Picked up", fill: .savedGreen.opacity(0.12), foreground: .savedGreen)
        case .canceled: Pill(text: "Canceled", fill: .cream100, foreground: .inkMuted)
        }
    }

    private func cancel(_ order: Order) {
        replace { try await CoffeeAPI.cancelOrder(id: order.id) }
    }

    private func advance(_ order: Order, to status: OrderStatus) {
        replace { try await CoffeeAPI.advancePickup(id: order.id, to: status) }
    }

    private func replace(_ call: @escaping () async throws -> Order) {
        Task {
            do {
                let updated = try await call()
                if let i = orders.firstIndex(where: { $0.id == updated.id }) { orders[i] = updated }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Shipments

struct ShipmentsListView: View {
    let shopID: String?

    @State private var shipments: [Shipment] = []
    @State private var total = 0
    @State private var loading = false
    @State private var filter: ShipmentStatus?
    @State private var editing: Shipment?
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Status", selection: $filter) {
                    Text("All").tag(ShipmentStatus?.none)
                    Text("To ship").tag(ShipmentStatus?.some(.labelReady))
                    Text("In transit").tag(ShipmentStatus?.some(.inTransit))
                    Text("Delivered").tag(ShipmentStatus?.some(.delivered))
                }
                .pickerStyle(.segmented)

                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
                ForEach(shipments) { shipment in
                    shipmentRow(shipment)
                        .onAppear {
                            if shipment.id == shipments.last?.id { Task { await load(reset: false) } }
                        }
                }
                if shipments.isEmpty && !loading {
                    Text(filter == nil
                        ? "No shipments yet. Every new order creates one automatically."
                        : "Nothing in this state.")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.cream50)
        .navigationTitle("Shipments")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { shipment in
            EditShipmentSheet(shipment: shipment) { patch($0) }
        }
        .task(id: filter) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard reset || (!loading && shipments.count < total) else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CoffeeAPI.fetchMyShipments(
                shopID: shopID, status: filter, offset: reset ? 0 : shipments.count
            )
            let seen = reset ? [] : Set(shipments.map(\.id))
            shipments = (reset ? [] : shipments) + page.items.filter { !seen.contains($0.id) }
            total = page.total
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func shipmentRow(_ shipment: Shipment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(shipment.order?.number ?? 0)")
                    .font(.kycBodyBold)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                if let buyer = shipment.order?.buyer {
                    Text(buyer.name).font(.kycSecondary).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                statusPill(shipment)
            }
            if shopID == nil, let shop = shipment.order?.shop {
                HStack(spacing: 6) {
                    ShopMonogram(name: shop.name, size: 18)
                    Text(shop.name).font(.kycMeta).foregroundStyle(Color.inkMuted)
                }
            }
            if let items = shipment.order?.items {
                Text(items.map { "\($0.qty)× \($0.name)" }.joined(separator: " · "))
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
            }
            HStack(spacing: 6) {
                if let shipBy = shipment.shipBy {
                    Text("Ship by \(shipBy)").font(.kycMeta).foregroundStyle(Color.crema500)
                }
                Text([shipment.carrier, shipment.tracking].compactMap { $0 }.joined(separator: " · "))
                    .font(.kycMeta)
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
            HStack {
                Button("Carrier & tracking") { editing = shipment }
                    .font(.kycMetaBold)
                    .foregroundStyle(Color.espresso700)
                    .buttonStyle(.plain)
                Spacer()
                if let next = shipment.nextStep {
                    Button(next.label) { advance(shipment, to: next.status) }
                        .font(.kycMetaBold)
                        .foregroundStyle(Color.crema500)
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .cardStyle()
    }

    private func statusPill(_ shipment: Shipment) -> some View {
        switch shipment.status {
        case .labelReady: Pill(text: shipment.status.label, fill: .crema400.opacity(0.18), foreground: .crema500)
        case .delivered: Pill(text: shipment.status.label, fill: .savedGreen.opacity(0.12), foreground: .savedGreen)
        case .readyForDropoff, .inTransit: Pill(text: shipment.status.label, fill: .cream100, foreground: .espresso700)
        }
    }

    private func advance(_ shipment: Shipment, to status: ShipmentStatus) {
        Task {
            do {
                let updated = try await CoffeeAPI.updateShipment(id: shipment.id, status: status)
                // Under a status filter the row now belongs elsewhere.
                if filter == nil { patch(updated) } else { await load(reset: true) }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func patch(_ updated: Shipment) {
        if let i = shipments.firstIndex(where: { $0.id == updated.id }) { shipments[i] = updated }
    }
}

private struct EditShipmentSheet: View {
    let shipment: Shipment
    let onSaved: (Shipment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var carrier: String
    @State private var tracking: String
    @State private var saving = false
    @State private var error: String?

    init(shipment: Shipment, onSaved: @escaping (Shipment) -> Void) {
        self.shipment = shipment
        self.onSaved = onSaved
        _carrier = State(initialValue: shipment.carrier ?? "")
        _tracking = State(initialValue: shipment.tracking ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shipment #\(shipment.order?.number ?? 0)") {
                    TextField("Carrier, e.g. USPS Ground", text: $carrier)
                    TextField("Tracking number", text: $tracking)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
            }
            .navigationTitle("Carrier & tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarTextButton(label: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarTextButton(label: saving ? "Saving…" : "Save", weight: .semibold) { save() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let updated = try await CoffeeAPI.updateShipment(
                    id: shipment.id,
                    carrier: carrier.trimmingCharacters(in: .whitespaces),
                    tracking: tracking.trimmingCharacters(in: .whitespaces)
                )
                onSaved(updated)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

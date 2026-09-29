import SwiftUI

// Seller Hub home: one owned shop's Products, Orders, and Shipments.
// Mirrors the web Seller Hub; reached from the profile sheet.
struct SellerHubView: View {
    let shop: OwnedShop

    @State private var stats: HubStats?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Text(shop.name)
                        .font(.kycSecondaryBold)
                        .foregroundStyle(Color.ink)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.savedGreen)
                    Text("Verified owner")
                        .font(.kycMeta)
                        .foregroundStyle(Color.savedGreen)
                }
                .padding(.horizontal, 24)

                if let error {
                    Text(error)
                        .font(.kycSecondary)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    hubRow(title: "Products", detail: productsDetail, icon: "shippingbox") {
                        ProductsListView(shop: shop)
                    }
                    hubRow(
                        title: "Orders",
                        detail: stats.map { "\($0.workload?.toFulfill ?? 0) to fulfill" } ?? "…",
                        icon: "bag"
                    ) {
                        OrdersListView(shop: shop)
                    }
                    hubRow(
                        title: "Shipments",
                        detail: stats.map { "\($0.workload?.toShip ?? 0) to ship" } ?? "…",
                        icon: "truck.box"
                    ) {
                        ShipmentsListView(shop: shop)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 16)
        }
        .background(Color.cream50)
        .navigationTitle("Seller Hub")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var productsDetail: String {
        guard let counts = stats?.products else { return "…" }
        return "\(counts.total) listed\(counts.lowStock > 0 ? " · \(counts.lowStock) low on stock" : "")"
    }

    private func load() async {
        do {
            stats = try await CoffeeAPI.fetchHubStats(shopID: shop.id)
            error = nil
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
                    if let variant = product.variant {
                        Text(variant).font(.kycSecondary).foregroundStyle(Color.inkMuted)
                    }
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
                update(product, input: ["stockQty": max(0, product.stockQty - 1)])
            }
            Text("\(product.stockQty)")
                .font(.kycBodyBold)
                .monospacedDigit()
                .frame(minWidth: 24)
                .foregroundStyle(Color.ink)
            stockButton("plus") {
                update(product, input: ["stockQty": product.stockQty + 1])
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

private struct AddProductSheet: View {
    let shop: OwnedShop
    let onAdded: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variant = ""
    @State private var price = ""
    @State private var stock = ""
    @State private var saving = false
    @State private var error: String?

    private var priceValue: Double? { Double(price.replacingOccurrences(of: "$", with: "")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Name, e.g. Urcunina", text: $name)
                    TextField("Variant, e.g. 12 oz whole bean", text: $variant)
                }
                Section("Pricing & stock") {
                    TextField("Price, e.g. 22.00", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("Stock on hand", text: $stock)
                        .keyboardType(.numberPad)
                }
                if let error {
                    Text(error).font(.kycSecondary).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add product")
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
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let priceValue else {
            error = "A name and a price are required."
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let product = try await CoffeeAPI.createProduct(
                    shopID: shop.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    variant: variant.trimmingCharacters(in: .whitespaces),
                    price: priceValue,
                    stockQty: Int(stock) ?? 0
                )
                onAdded(product)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Orders

struct OrdersListView: View {
    let shop: OwnedShop

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
            let page = try await CoffeeAPI.fetchMyOrders(shopID: shop.id, offset: reset ? 0 : orders.count)
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
    let shop: OwnedShop

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
                shopID: shop.id, status: filter, offset: reset ? 0 : shipments.count
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

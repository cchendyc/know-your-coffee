import MapKit
import SwiftUI

// Full-page detail, xiaohongshu note style: photo carousel bleeding into the
// status bar, floating back button, flat content, pinned action bar.
// Paints instantly from the feed's copy, then swaps in the full payload
// (photos, reports, chain) when shop(id:) lands.
struct ShopDetailView: View {
    let summary: CoffeeShop
    var onShopChanged: (CoffeeShop) -> Void = { _ in }

    @State private var full: CoffeeShop?
    @State private var loadError: String?
    @State private var showReportForm = false
    @State private var showClaim = false
    @State private var needSignIn = false
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss

    private var shop: CoffeeShop { full ?? summary }

    var body: some View {
        NavigationStack {
            ShopPageView(
                shop: shop,
                loadError: loadError,
                isLoadingFull: full == nil && loadError == nil,
                actions: ShopPageActions(
                    onToggleSaved: { toggle(saved: !shop.savedByMe) },
                    onToggleBeen: { toggle(been: !shop.beenByMe) },
                    onUpdate: { gated { showReportForm = true } }
                )
            )
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.espresso900)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(.leading, 14)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.espresso900)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                    }
                    Menu {
                        Button {
                            gated { showClaim = true }
                        } label: {
                            Label("Claim this shop", systemImage: "checkmark.shield")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.espresso900)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 14)
            }
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
            ClaimShopSheet(shop: shop)
                .presentationDetents([.medium])
        }
        .alert("Sign in required", isPresented: $needSignIn) {
            Button("Sign in") { Task { try? await AuthStore.shared.signIn() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving shops, reporting, and claiming need a signed-in account.")
        }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func loadFull() async {
        do {
            full = try await CoffeeAPI.fetchShop(id: summary.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func gated(_ action: () -> Void) {
        if AuthStore.shared.isSignedIn { action() } else { needSignIn = true }
    }

    private var shareText: String {
        var lines = [shop.name, "\(shop.address), \(shop.city)"]
        if let website = shop.website { lines.append(website) }
        return lines.joined(separator: "\n")
    }

    private func toggle(saved: Bool? = nil, been: Bool? = nil) {
        guard AuthStore.shared.isSignedIn else {
            needSignIn = true
            return
        }
        Task {
            do {
                // The mutation returns core fields only; keep the loaded
                // photos, reports, and chain instead of blanking them.
                var updated = try await CoffeeAPI.setShopStatus(shopID: shop.id, saved: saved, been: been)
                updated.photos = shop.photos
                updated.photoCount = shop.photoCount
                updated.reports = shop.reports
                updated.reportCount = shop.reportCount
                updated.chain = shop.chain
                full = updated
                onShopChanged(updated)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

struct ShopPageActions {
    let onToggleSaved: () -> Void
    let onToggleBeen: () -> Void
    let onUpdate: () -> Void
}

// The shared page content; also used for pushed chain locations.
struct ShopPageView: View {
    let shop: CoffeeShop
    var loadError: String?
    var isLoadingFull = false
    var actions: ShopPageActions?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoCarousel(shop: shop)

                VStack(alignment: .leading, spacing: 18) {
                    header
                    detailsCard
                    if !shop.coffees.isEmpty { coffeesOnBar }
                    if !shop.drinks.isEmpty { menuCard }
                    if let reports = shop.reports, !reports.isEmpty {
                        reportsThread(reports)
                    } else if isLoadingFull {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    if let chain = shop.chain, chain.shops.count > 1 {
                        chainSection(chain)
                    }
                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .background(Color.cream50)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: Header — name, address with directions, vibe, amenity chips.

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shop.name)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption)
                    Text("\(shop.address), \(shop.city)")
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.espresso500)

                Spacer(minLength: 0)

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: shop.coordinate))
                    item.name = shop.name
                    item.openInMaps()
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.espresso700, in: Capsule())
                        .foregroundStyle(Color.cream50)
                }
                .buttonStyle(.plain)

                if let website = shop.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.espresso700)
                            .frame(width: 28, height: 28)
                            .background(Color.espresso900.opacity(0.06), in: Circle())
                    }
                }
            }

            if let vibe = shop.vibe, !vibe.isEmpty {
                Text(vibe)
                    .font(.subheadline)
                    .foregroundStyle(Color.espresso700)
            }

            amenityChips
        }
    }

    @ViewBuilder
    private var amenityChips: some View {
        let items: [(String, String, Bool?)] = [
            ("Dog friendly", "pawprint.fill", shop.dogFriendly),
            ("Wi-Fi", "wifi", shop.wifi),
            ("Outdoor seating", "sun.max.fill", shop.outdoorSeating),
        ]
        let known = items.filter { $0.2 != nil }
        if !known.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(known, id: \.0) { label, symbol, value in
                    HStack(spacing: 5) {
                        Image(systemName: value == true ? symbol : "xmark")
                            .font(.caption2)
                        Text(value == true ? label : "No \(label.lowercased())")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        value == true ? Color.savedGreen.opacity(0.1) : Color.espresso900.opacity(0.04),
                        in: Capsule()
                    )
                    .foregroundStyle(value == true ? Color.savedGreen : Color.espresso500)
                }
            }
        }
    }

    // MARK: Details card — the shop's gear and beans, one labeled row each.

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.espresso900)
    }

    private var detailsCard: some View {
        let rows: [(symbol: String, label: String, value: String)] = [
            ("rectangle.compress.vertical", "Machines",
             shop.knownMachines.map(\.display).joined(separator: "\n")),
            ("circle.grid.2x1", "Grinders", shop.grinders.joined(separator: ", ")),
            ("flame", "Beans", [
                shop.roaster,
                shop.beanSource != .unknown ? shop.beanSource.label : nil,
            ].compactMap { $0 }.joined(separator: " · ")),
            ("globe.americas", "Origins", shop.beanOrigins.joined(separator: ", ")),
            ("drop", "Milk", shop.milkBrands.joined(separator: ", ")),
        ].filter { !$0.2.isEmpty }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.crema500)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.espresso500.opacity(0.8))
                            .textCase(.uppercase)
                        Text(row.value)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.espresso900)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                if index < rows.count - 1 {
                    Divider().overlay(Color.espresso900.opacity(0.05))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var coffeesOnBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("On the bar now")
            ForEach(Array(shop.coffees.enumerated()), id: \.offset) { _, coffee in
                coffeeCard(coffee)
            }
        }
    }

    private func coffeeCard(_ coffee: Coffee) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = coffee.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.espresso900)
            }
            if !coffee.pills.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(coffee.pills, id: \.self) { pill in
                        Pill(text: pill, fill: .white, foreground: .espresso500)
                    }
                }
            }
            if !coffee.tastingNotes.isEmpty {
                Text(coffee.tastingNotes.joined(separator: " · "))
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color.crema500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cream100.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Menu")
            VStack(spacing: 0) {
                ForEach(Array(shop.drinks.enumerated()), id: \.offset) { index, drink in
                    HStack {
                        Text(drink.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.espresso900)
                        Spacer()
                        if let price = drink.price {
                            Text(price, format: .currency(code: "USD").precision(.fractionLength(2)))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.espresso500)
                        }
                    }
                    .padding(.vertical, 9)
                    if index < shop.drinks.count - 1 {
                        Divider().overlay(Color.espresso900.opacity(0.05))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: Updates thread — community reports styled as comments.

    private func reportsThread(_ reports: [Report]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Updates · \(shop.reportCount ?? reports.count)")
            ForEach(reports) { report in
                HStack(alignment: .top, spacing: 10) {
                    avatar(report.reporter)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(report.reporter?.name ?? "Anonymous")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.espresso500)
                            if report.source == "PHOTO" {
                                Image(systemName: "camera.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.espresso500.opacity(0.6))
                            }
                            Text(RelativeDate.format(report.createdAt))
                                .font(.caption2)
                                .foregroundStyle(Color.espresso500.opacity(0.6))
                        }

                        if let note = report.note, !note.isEmpty {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color.espresso900)
                        }

                        let pills = reportPills(report)
                        if !pills.isEmpty {
                            FlowLayout(spacing: 5) {
                                ForEach(pills, id: \.self) { pill in
                                    Pill(text: pill, fill: .espresso900.opacity(0.05), foreground: .espresso500)
                                }
                            }
                        }
                    }
                }
                if report.id != reports.last?.id {
                    Divider().overlay(Color.espresso900.opacity(0.04))
                }
            }
        }
    }

    private func avatar(_ reporter: Reporter?) -> some View {
        Group {
            if let picture = reporter?.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback(reporter)
                    }
                }
            } else {
                avatarFallback(reporter)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private func avatarFallback(_ reporter: Reporter?) -> some View {
        Circle()
            .fill(Color.crema400.opacity(0.4))
            .overlay(
                Text(String(reporter?.name.prefix(1) ?? "?"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.espresso700)
            )
    }

    private func reportPills(_ report: Report) -> [String] {
        var pills: [String] = []
        if let machines = report.machines, !machines.isEmpty {
            pills += machines.map(\.display)
        } else if let machine = report.machine, machine != .unknown {
            pills.append(Machine(brand: machine, model: report.machineModel).display)
        }
        if let roaster = report.roaster, !roaster.isEmpty { pills.append(roaster) }
        if let source = report.beanSource, source != .unknown { pills.append(source.label) }
        pills += report.beanOrigins ?? []
        pills += (report.grinders ?? [])
        pills += (report.milkBrands ?? [])
        return pills
    }

    private func chainSection(_ chain: Chain) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("More \(chain.name) locations")
            let others = chain.shops.filter { $0.id != shop.id }
            ForEach(others) { location in
                NavigationLink(value: location) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.espresso900)
                            Text("\(location.address), \(location.city)")
                                .font(.caption)
                                .foregroundStyle(Color.espresso500)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.espresso500.opacity(0.4))
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Bottom bar — xiaohongshu comment bar: an input-look button that
    // opens the update form, then star (save) and seal (been).

    @ViewBuilder
    private var actionBar: some View {
        if let actions {
            HStack(spacing: 16) {
                Button(action: actions.onUpdate) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                        Text("Add an update…")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.espresso500.opacity(0.8))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.espresso900.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)

                barIcon(
                    symbol: shop.savedByMe ? "star.fill" : "star",
                    tint: shop.savedByMe ? .crema500 : .espresso500,
                    action: actions.onToggleSaved
                )
                barIcon(
                    symbol: shop.beenByMe ? "checkmark.circle.fill" : "checkmark.circle",
                    tint: shop.beenByMe ? .savedGreen : .espresso500,
                    action: actions.onToggleBeen
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.bar)
        }
    }

    private func barIcon(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Paging hero: the Places photo first, then user photos with kind badges.
// Swipes left/right; a "2/5" counter chip signals more pages, xiaohongshu-style.
private struct PhotoCarousel: View {
    let shop: CoffeeShop

    @State private var page = 0

    private enum Item {
        case remote(URL)
        case uploaded(UIImage, kind: String)
    }

    private var items: [Item] {
        var out: [Item] = []
        if let url = shop.photoURL { out.append(.remote(url)) }
        for photo in shop.photos ?? [] {
            if let data = photo.imageData, let image = UIImage(data: data) {
                out.append(.uploaded(image, kind: photo.kindLabel))
            }
        }
        return out
    }

    var body: some View {
        let items = items
        Group {
            if items.isEmpty {
                LinearGradient(colors: [.cream100, .cream200], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 220)
                    .overlay(
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.espresso500.opacity(0.25))
                    )
            } else {
                TabView(selection: $page) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        pageView(item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
                .frame(height: 360)
                .overlay(alignment: .topTrailing) {
                    if items.count > 1 {
                        Text("\(page + 1)/\(items.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.trailing, 14)
                            .padding(.top, 58) // clears the status bar; the image bleeds under it
                    }
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func pageView(_ item: Item) -> some View {
        switch item {
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.cream200
                }
            }
        case .uploaded(let image, let kind):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomTrailing) {
                    Text(kind)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(12)
                }
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
                ShopPageView(shop: shop)
            } else if let error {
                Text(error)
                    .font(.footnote)
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
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.espresso900)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
            }
            .padding(.leading, 14)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do {
                shop = try await CoffeeAPI.fetchShop(id: locationID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

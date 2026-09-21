import MapKit
import SwiftUI

// Full-page detail, xiaohongshu note style: photo carousel bleeding into the
// status bar, floating back button, flat content, pinned action bar.
// Paints instantly from the feed's copy, then swaps in the full payload
// (photos, reports, chain) when shop(id:) lands.
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
                    onToggleSaved: { gated { toggle(saved: !shop.savedByMe) } },
                    onToggleBeen: { gated { toggle(been: !shop.beenByMe) } },
                    onUpdate: { gated { showReportForm = true } }
                )
            )
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    FloatingCircleIcon(symbol: "chevron.left")
                }
                .padding(.leading, 10)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    ShareLink(
                        item: shareURL,
                        subject: Text(shop.name),
                        message: Text("\(shop.name) — \(shop.address), \(shop.city)")
                    ) {
                        FloatingCircleIcon(symbol: "square.and.arrow.up")
                    }
                    Menu {
                        Button {
                            gated { showClaim = true }
                        } label: {
                            Label("Claim this shop", systemImage: "checkmark.shield")
                        }
                        if auth.user?.isAdmin == true {
                            Divider()
                            Button("Delete shop", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        }
                    } label: {
                        FloatingCircleIcon(symbol: "ellipsis")
                    }
                }
                .padding(.trailing, 10)
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
        return URL(string: "https://knowyourthings.top/?shop=\(id)")!
    }

    private func toggle(saved: Bool? = nil, been: Bool? = nil) {
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

struct ShopPageActions {
    let onToggleSaved: () -> Void
    let onToggleBeen: () -> Void
    let onUpdate: () -> Void
}

// 34pt visual circle inside a 44pt hit target (HIG minimum).
struct FloatingCircleIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.espresso900)
            .frame(width: 34, height: 34)
            .background(.regularMaterial, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct ShopScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// The shared page content; also used for pushed chain locations.
struct ShopPageView: View {
    let shop: CoffeeShop
    var loadError: String?
    var isLoadingFull = false
    var actions: ShopPageActions?

    @State private var scrolledPastPhoto = false

    var body: some View {
        GeometryReader { proxy in
            scrollContent
                .overlay(alignment: .top) {
                    // Content scrolls under the clock/Dynamic Island; blur it once
                    // the carousel is gone so the status bar stays legible.
                    if scrolledPastPhoto {
                        Rectangle()
                            .fill(.regularMaterial)
                            .frame(height: proxy.safeAreaInsets.top)
                            .ignoresSafeArea(edges: .top)
                            .transition(.opacity)
                    }
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoCarousel(shop: shop)

                VStack(alignment: .leading, spacing: 14) {
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
                            .font(.kycSecondary)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ShopScrollOffsetKey.self,
                        value: geo.frame(in: .named("shopScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "shopScroll")
        .onPreferenceChange(ShopScrollOffsetKey.self) { minY in
            // 220 = carousel height; ~60 = status bar. Flip once the photo has left.
            let past = minY < -160
            if past != scrolledPastPhoto {
                withAnimation(.easeInOut(duration: 0.15)) { scrolledPastPhoto = past }
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
                .font(.kycPageTitle)
                .foregroundStyle(Color.ink)

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                    Text("\(shop.address), \(shop.city)")
                        .font(.kycSecondary)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.inkMuted)

                Spacer(minLength: 0)

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: shop.coordinate))
                    item.name = shop.name
                    item.openInMaps()
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.kycSecondaryBold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.espresso700, in: Capsule())
                        .foregroundStyle(Color.inkInverse)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let website = shop.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.espresso700)
                            .frame(width: 28, height: 28)
                            .background(Color.espresso900.opacity(0.06), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }

            if let vibe = shop.vibe, !vibe.isEmpty {
                Text(vibe)
                    .font(.kycBody)
                    .foregroundStyle(Color.inkMuted)
                    .lineSpacing(3) // ~1.4x line height for comfortable reading
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
                    HStack(spacing: 4) {
                        Image(systemName: value == true ? symbol : "xmark")
                            .font(.system(size: 10))
                        Text(value == true ? label : "No \(label.lowercased())")
                            .font(.kycMeta)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        value == true ? Color.savedGreen.opacity(0.1) : Color.espresso900.opacity(0.04),
                        in: Capsule()
                    )
                    .foregroundStyle(value == true ? Color.savedGreen : Color.inkMuted)
                }
            }
        }
    }

    // MARK: Details card — the shop's gear and beans, one labeled row each.

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.kycSection)
            .foregroundStyle(Color.ink)
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.crema500)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowLabel(row.label)
                        Text(row.value)
                            .font(.kycBody)
                            .foregroundStyle(Color.ink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                if index < rows.count - 1 {
                    Divider().overlay(Color.espresso900.opacity(0.05))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .cardStyle()
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
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
            }
            if !coffee.pills.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(coffee.pills, id: \.self) { pill in
                        Pill(text: pill, fill: .cream100, foreground: .espresso700)
                    }
                }
            }
            if !coffee.tastingNotes.isEmpty {
                Text(coffee.tastingNotes.joined(separator: " · "))
                    .font(.kycSecondary)
                    .italic()
                    .foregroundStyle(Color.crema500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle()
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Menu")
            VStack(spacing: 0) {
                ForEach(Array(shop.drinks.enumerated()), id: \.offset) { index, drink in
                    HStack {
                        Text(drink.name)
                            .font(.kycBody)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        if let price = drink.price {
                            Text(price, format: .currency(code: "USD").precision(.fractionLength(2)))
                                .font(.kycBody)
                                .monospacedDigit()
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    .padding(.vertical, 8)
                    if index < shop.drinks.count - 1 {
                        Divider().overlay(Color.espresso900.opacity(0.05))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .cardStyle()
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
                            // Instagram's comment pattern: name in ink
                            // semibold, timestamp one muted step down.
                            Text(report.reporter?.name ?? "Anonymous")
                                .font(.kycSecondaryBold)
                                .foregroundStyle(Color.ink)
                            if report.source == "PHOTO" {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            Text(RelativeDate.format(report.createdAt))
                                .font(.kycMeta)
                                .foregroundStyle(Color.inkMuted)
                        }

                        if let note = report.note, !note.isEmpty {
                            Text(note)
                                .font(.kycBody)
                                .foregroundStyle(Color.ink)
                                .lineSpacing(3)
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
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private func avatarFallback(_ reporter: Reporter?) -> some View {
        Circle()
            .fill(Color.crema400.opacity(0.4))
            .overlay(
                    Text(String(reporter?.name.prefix(1) ?? "?"))
                        .font(.kycMetaBold)
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
                                .font(.kycBody)
                                .foregroundStyle(Color.ink)
                            Text("\(location.address), \(location.city)")
                                .font(.kycSecondary)
                                .foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Bottom bar — xiaohongshu comment bar: an input-look button that
    // opens the update form, then bookmark (save) and seal (been).

    @ViewBuilder
    private var actionBar: some View {
        if let actions {
            // The 44pt icon frames carry ~11pt of their own padding.
            HStack(spacing: 2) {
                Button(action: actions.onUpdate) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13))
                        Text("Add an update…")
                            .font(.kycBody)
                    }
                    .foregroundStyle(Color.inkMuted)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.espresso900.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)

                barIcon(
                    symbol: shop.savedByMe ? "bookmark.fill" : "bookmark",
                    tint: shop.savedByMe ? .crema500 : .inkMuted,
                    action: actions.onToggleSaved
                )
                barIcon(
                    symbol: shop.beenByMe ? "checkmark.circle.fill" : "checkmark.circle",
                    tint: shop.beenByMe ? .savedGreen : .inkMuted,
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
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
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
                // Bottom-trailing: the top corners hold the floating back and
                // share buttons; the page dots sit bottom-center, clear of this.
                .overlay(alignment: .bottomTrailing) {
                    if items.count > 1 {
                        Text("\(page + 1)/\(items.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.trailing, 14)
                            .padding(.bottom, 14)
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

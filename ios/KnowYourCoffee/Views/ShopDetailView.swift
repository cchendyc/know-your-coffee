import MapKit
import SwiftUI

// Drawer-style detail. Paints instantly from the list's copy, then swaps in
// the full payload (photos, reports, chain) when shop(id:) lands.
struct ShopDetailView: View {
    let summary: CoffeeShop

    @State private var full: CoffeeShop?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    private var shop: CoffeeShop { full ?? summary }

    var body: some View {
        NavigationStack {
            content(for: shop)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: ChainLocation.self) { location in
                    ChainLocationDetail(locationID: location.id, name: location.name)
                }
        }
        .task(id: summary.id) {
            do {
                full = try await CoffeeAPI.fetchShop(id: summary.id)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func content(for shop: CoffeeShop) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero(shop)
                header(shop)
                if !shop.knownMachines.isEmpty || !shop.grinders.isEmpty {
                    barSection(shop)
                }
                coffeeSection(shop)
                if !shop.drinks.isEmpty { drinksSection(shop) }
                amenitiesSection(shop)
                if let photos = shop.photos, !photos.isEmpty { photosSection(photos) }
                if let reports = shop.reports, !reports.isEmpty { reportsSection(shop, reports) }
                if let chain = shop.chain, chain.shops.count > 1 { chainSection(shop, chain) }
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.cream50)
    }

    // MARK: Sections

    @ViewBuilder
    private func hero(_ shop: CoffeeShop) -> some View {
        if let url = shop.photoURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.cream200
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func header(_ shop: CoffeeShop) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shop.name)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)

            Text("\(shop.address), \(shop.city)")
                .font(.subheadline)
                .foregroundStyle(Color.espresso500)

            if let vibe = shop.vibe, !vibe.isEmpty {
                Text(vibe)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color.espresso500)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                Button {
                    openInMaps(shop)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.espresso700)

                if let website = shop.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Website", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.top, 8)
        }
    }

    private func barSection(_ shop: CoffeeShop) -> some View {
        section("On the bar", symbol: "dial.high") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shop.knownMachines, id: \.self) { machine in
                    Label(machine.display, systemImage: "rectangle.compress.vertical")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.espresso900)
                }
                if !shop.grinders.isEmpty {
                    Label(shop.grinders.joined(separator: " · "), systemImage: "circle.grid.2x1")
                        .font(.subheadline)
                        .foregroundStyle(Color.espresso500)
                }
            }
        }
    }

    private func coffeeSection(_ shop: CoffeeShop) -> some View {
        section("Coffee", symbol: "leaf.fill") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 6) {
                    if shop.beanSource != .unknown {
                        Pill(text: shop.beanSource.label, fill: .crema400.opacity(0.25))
                    }
                    if let roaster = shop.roaster, !roaster.isEmpty {
                        Pill(text: roaster, fill: .crema400.opacity(0.25))
                    }
                    ForEach(shop.beanOrigins, id: \.self) { origin in
                        Pill(text: origin)
                    }
                }

                ForEach(Array(shop.coffees.enumerated()), id: \.offset) { _, coffee in
                    coffeeCard(coffee)
                }

                if !shop.milkBrands.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(Color.espresso500)
                        Text("Milk: \(shop.milkBrands.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Color.espresso500)
                    }
                }
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
                        Pill(text: pill)
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
        .background(Color.cream100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func drinksSection(_ shop: CoffeeShop) -> some View {
        section("Drinks", symbol: "mug.fill") {
            VStack(spacing: 6) {
                ForEach(shop.drinks, id: \.self) { drink in
                    HStack {
                        Text(drink.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.espresso900)
                        Spacer()
                        if let price = drink.price {
                            Text(price, format: .currency(code: "USD").precision(.fractionLength(2)))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.espresso500)
                        }
                    }
                }
            }
        }
    }

    private func amenitiesSection(_ shop: CoffeeShop) -> some View {
        let items: [(String, String, Bool?)] = [
            ("Dog friendly", "pawprint.fill", shop.dogFriendly),
            ("Wi-Fi", "wifi", shop.wifi),
            ("Outdoor seating", "sun.max.fill", shop.outdoorSeating),
        ]
        let known = items.filter { $0.2 != nil }
        return Group {
            if !known.isEmpty {
                section("Good to know", symbol: "info.circle.fill") {
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
                                value == true ? Color.savedGreen.opacity(0.12) : Color.cream100,
                                in: Capsule()
                            )
                            .foregroundStyle(value == true ? Color.savedGreen : Color.espresso500)
                        }
                    }
                }
            }
        }
    }

    private func photosSection(_ photos: [ShopPhoto]) -> some View {
        section("Photos", symbol: "photo.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        if let data = photo.imageData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Text(photo.kindLabel)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.black.opacity(0.55), in: Capsule())
                                        .foregroundStyle(.white)
                                        .padding(6)
                                }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func reportsSection(_ shop: CoffeeShop, _ reports: [Report]) -> some View {
        section("Reports (\(shop.reportCount ?? reports.count))", symbol: "text.bubble.fill") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(reports) { report in
                    reportRow(report)
                }
            }
        }
    }

    private func reportRow(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.reporter?.name ?? "Anonymous")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.espresso900)
                if report.source == "PHOTO" {
                    Image(systemName: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.espresso500)
                }
                Spacer()
                Text(RelativeDate.format(report.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Color.espresso500)
            }

            let pills = reportPills(report)
            if !pills.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(pills, id: \.self) { pill in
                        Pill(text: pill)
                    }
                }
            }

            if let note = report.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.espresso500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cream100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func chainSection(_ shop: CoffeeShop, _ chain: Chain) -> some View {
        section("More \(chain.name) locations", symbol: "storefront.fill") {
            VStack(spacing: 0) {
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
                                .foregroundStyle(Color.espresso500.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                    }
                    if location.id != others.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func section(_ title: String, symbol: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso700)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func openInMaps(_ shop: CoffeeShop) {
        let placemark = MKPlacemark(coordinate: shop.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = shop.name
        item.openInMaps()
    }
}

// Pushed from the chain list: fetches its own shop and reuses the detail body.
private struct ChainLocationDetail: View {
    let locationID: String
    let name: String

    @State private var shop: CoffeeShop?
    @State private var error: String?

    var body: some View {
        Group {
            if let shop {
                ShopDetailBody(shop: shop)
            } else if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream50)
        .task {
            do {
                shop = try await CoffeeAPI.fetchShop(id: locationID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// Minimal embedded rendering for pushed chain locations (no recursion).
private struct ShopDetailBody: View {
    let shop: CoffeeShop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(shop.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.espresso900)
                Text("\(shop.address), \(shop.city)")
                    .font(.subheadline)
                    .foregroundStyle(Color.espresso500)
                FlowLayout(spacing: 6) {
                    ForEach(shop.knownMachines, id: \.self) { machine in
                        Pill(text: machine.display, fill: .espresso700.opacity(0.09))
                    }
                    if let roaster = shop.roaster, !roaster.isEmpty {
                        Pill(text: roaster, fill: .crema400.opacity(0.25))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

import SwiftUI

/// "Report something": a grid of square fact tiles for one shop, shown full
/// screen. Each tile pushes one form that saves one report. Values on tiles
/// are stacked, one per line. Photo capture lives on the Machine and Menu
/// forms, not here.
struct ReportLauncherView: View {
    let initialFact: ReportFact?

    @State private var session: ReportSession
    @State private var path = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    init(shop: CoffeeShop, initialFact: ReportFact? = nil) {
        self.initialFact = initialFact
        _session = State(initialValue: ReportSession(shop: shop))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    tiles
                    if let error = session.optionsError {
                        HStack(spacing: 8) {
                            Text(error).font(.kycMeta).foregroundStyle(.red)
                            Button("Retry") { Task { await session.loadOptions() } }
                                .font(.kycMetaBold)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.cream50)
            .navigationTitle(session.shop.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(session.saved.isEmpty ? .kycSecondary : .kycSecondaryBold)
                        .foregroundStyle(session.saved.isEmpty ? Color.inkMuted : Color.espresso700)
                }
            }
            .navigationDestination(for: ReportFact.self) { fact in
                FactSheet(fact: fact, session: session)
            }
        }
        .sheet(isPresented: $session.showSignIn, onDismiss: { session.signInDismissed() }) {
            SignInSheet()
        }
        .task {
            // Push first; the form shows a spinner until the lists arrive.
            if let initialFact, path.isEmpty { path.append(initialFact) }
            await session.loadOptions()
        }
    }

    // MARK: Tiles

    private static let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var tiles: some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(ReportFact.allCases) { fact in
                Button { path.append(fact) } label: {
                    FactTile(
                        fact: fact,
                        lines: TileLine.lines(for: fact, shop: session.shop, options: session.options),
                        saved: session.saved.contains(fact)
                    )
                }
                .buttonStyle(.plain)
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

// MARK: - Tile

/// One line on a tile: a value, or a label with its value for Space.
struct TileLine: Hashable {
    let label: String
    var value: String? = nil
    var unknown = false

    static let unknownLine = TileLine(label: "Unknown", unknown: true)

    static func lines(for fact: ReportFact, shop: CoffeeShop, options: ReportOptions?) -> [TileLine] {
        switch fact {
        case .machine:
            return orUnknown(shop.knownMachines.map { TileLine(label: $0.display) })
        case .grinder:
            return orUnknown(shop.grinders.map { TileLine(label: $0) })
        case .roaster:
            var out: [TileLine] = []
            if shop.beanSource != .unknown {
                out.append(TileLine(label: options?.label(in: \.beanSources, for: shop.beanSource.rawValue) ?? shop.beanSource.label))
            }
            if let roaster = shop.roaster, !roaster.isEmpty { out.append(TileLine(label: roaster)) }
            return orUnknown(out)
        case .coffee:
            return orUnknown(shop.coffees.map { TileLine(label: $0.title ?? $0.pills.first ?? "Coffee") })
        case .menu:
            return orUnknown(shop.drinks.map { drink in
                TileLine(label: drink.name, value: drink.price.map { "$" + ShopPageFormat.price($0) })
            })
        case .milk:
            return orUnknown(shop.milkBrands.map { TileLine(label: $0) })
        case .space:
            let amenities = options?.amenities ?? []
            return amenities.map { amenity in
                let value = shop.amenity(amenity.value)
                return TileLine(
                    label: amenity.label,
                    value: value.map { $0 ? "Yes" : "No" } ?? "Unknown",
                    unknown: value == nil
                )
            }
        case .other:
            return []
        }
    }

    private static func orUnknown(_ lines: [TileLine]) -> [TileLine] {
        lines.isEmpty ? [unknownLine] : lines
    }
}

extension CoffeeShop {
    /// Current value of a tri-state amenity, keyed by its ReportInput field name.
    func amenity(_ field: String) -> Bool? {
        switch field {
        case "dogFriendly": dogFriendly
        case "wifi": wifi
        case "outdoorSeating": outdoorSeating
        default: nil
        }
    }
}

private struct FactTile: View {
    let fact: ReportFact
    let lines: [TileLine]
    let saved: Bool

    private static let maxLines = 4
    private var hasGap: Bool { lines.contains { $0.unknown } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: fact.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 28, height: 28)
                    .background(Color.cream100, in: Circle())
                Text(fact.title)
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if saved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.savedGreen)
                } else if hasGap {
                    Circle().fill(Color.crema500).frame(width: 6, height: 6)
                }
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 6) {
                            Text(line.label)
                                .foregroundStyle(line.unknown && line.value == nil ? Color.crema500 : Color.inkMuted)
                                .lineLimit(1)
                            if let value = line.value {
                                Spacer(minLength: 0)
                                Text(value)
                                    .foregroundStyle(line.unknown ? Color.crema500 : Color.ink)
                                    .lineLimit(1)
                            }
                        }
                        .font(.kycSecondary)
                    }
                    if lines.count > Self.maxLines {
                        Text("+\(lines.count - Self.maxLines) more")
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkFaint)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous)
                .stroke(saved ? Color.savedGreen.opacity(0.6) : Color.cream200, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
    }
}

// MARK: - Sheet router

/// Waits for the option lists, then shows the sheet for one fact.
private struct FactSheet: View {
    let fact: ReportFact
    let session: ReportSession

    var body: some View {
        Group {
            if let options = session.options {
                switch fact {
                case .machine: MachineSheet(session: session, options: options)
                case .grinder: GrinderSheet(session: session, options: options)
                case .roaster: RoasterSheet(session: session, options: options)
                case .coffee: CoffeeListSheet(session: session, options: options)
                case .menu: MenuSheet(session: session, options: options)
                case .milk: MilkSheet(session: session, options: options)
                case .space: SpaceSheet(session: session, options: options)
                case .other: ElseSheet(session: session, options: options)
                }
            } else if let error = session.optionsError {
                VStack(spacing: 12) {
                    Text(error).font(.kycSecondary).foregroundStyle(Color.inkMuted)
                    Button("Retry") { Task { await session.loadOptions() } }.font(.kycSecondaryBold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.cream50)
        .navigationTitle(fact.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

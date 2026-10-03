import SwiftUI

/// About tab: update prompt, gear, beans, space, menu, then the record thread.
/// Mirrors web AboutSection: every card is an eyebrow row plus label/pill rows.
struct ShopAboutPanel: View {
    let shop: CoffeeShop
    let listings: [ShopListing]
    let onUpdate: () -> Void
    let onShop: () -> Void

    @State private var showAllDrinks = false
    @State private var showAllRecords = false

    private static let drinkPreview = 5
    private static let recordPreview = 3

    private var reports: [Report] { shop.reports ?? [] }
    private var reportCount: Int { shop.reportCount ?? reports.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UpdatePromptRow(action: onUpdate)
            gearCard
            beansCard
            spaceCard

            if !shop.drinks.isEmpty {
                menuCard
            }

            records
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: Gear

    private var gearCard: some View {
        AboutCard(eyebrow: "Gear") {
            if shop.knownMachines.isEmpty {
                UnknownRow(label: "Espresso machine", onKnow: onUpdate)
            } else {
                ForEach(Array(shop.knownMachines.enumerated()), id: \.offset) { _, machine in
                    InfoRow(label: machine.display) { Pill(text: "Espresso") }
                }
            }
            ForEach(shop.grinders, id: \.self) { grinder in
                InfoRow(label: grinder) { Pill(text: "Grinder") }
            }
        }
    }

    // MARK: Beans

    private var beanSource: String? {
        switch shop.beanSource {
        case .unknown: nil
        case .inHouseRoast: "Roasted in-house"
        default: [shop.beanSource.label, shop.roaster].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var beansCard: some View {
        AboutCard(eyebrow: "Beans", tag: beanSource) {
            if !shop.coffees.isEmpty {
                ForEach(Array(shop.coffees.enumerated()), id: \.offset) { _, coffee in
                    coffeeRow(coffee)
                }
            } else if !shop.beanOrigins.isEmpty {
                InfoRow(label: "Origins") {
                    ForEach(shop.beanOrigins, id: \.self) { Pill(text: $0) }
                }
            } else {
                UnknownRow(label: beanSource == nil ? "Who roasts the beans" : "Coffees on the bar", onKnow: onUpdate)
            }
            if shop.milkBrands.isEmpty {
                UnknownRow(label: "Milk", onKnow: onUpdate)
            } else {
                InfoRow(label: "Milk") {
                    ForEach(shop.milkBrands, id: \.self) { Pill(text: $0) }
                }
            }
        }
    }

    // Unnamed coffees lead with their first attribute (usually the type) instead of a placeholder.
    private func coffeeRow(_ coffee: Coffee) -> some View {
        var pills = coffee.pills + coffee.tastingNotes
        let title = coffee.title ?? (pills.isEmpty ? "House coffee" : pills.removeFirst())
        return InfoRow(label: title) {
            ForEach(pills, id: \.self) { Pill(text: $0) }
            if listingMatches(coffee) {
                ShopLinkButton(label: "Buy this bean", symbol: "arrow.right", action: onShop)
            }
        }
    }

    // A coffee is purchasable when a listing name mentions it.
    private func listingMatches(_ coffee: Coffee) -> Bool {
        guard let name = coffee.name?.lowercased(), name.count >= 3 else { return false }
        return listings.contains { $0.name.lowercased().contains(name) }
    }

    // MARK: Space

    private var spaceCard: some View {
        AboutCard(eyebrow: "Space") {
            amenityRow("Dog friendly", shop.dogFriendly)
            amenityRow("Wi-Fi", shop.wifi)
            amenityRow("Outdoor seating", shop.outdoorSeating)
        }
    }

    @ViewBuilder
    private func amenityRow(_ label: String, _ value: Bool?) -> some View {
        if let value {
            InfoRow(label: label) { Pill(text: value ? "Yes" : "No") }
        } else {
            UnknownRow(label: label, onKnow: onUpdate)
        }
    }

    // MARK: Menu

    private var visibleDrinks: [DrinkItem] {
        showAllDrinks ? shop.drinks : Array(shop.drinks.prefix(Self.drinkPreview))
    }

    private var menuCard: some View {
        AboutCard(eyebrow: "Menu") {
            ForEach(Array(visibleDrinks.enumerated()), id: \.offset) { _, drink in
                InfoRow(label: drink.name) {
                    if let price = drink.price {
                        Pill(text: "$\(ShopPageFormat.price(price))")
                    }
                }
            }
            if shop.drinks.count > Self.drinkPreview {
                ShopLinkButton(label: showAllDrinks ? "Show fewer" : "See all \(ShopPageFormat.plural(shop.drinks.count, "drink"))") {
                    withAnimation(.easeOut(duration: 0.2)) { showAllDrinks.toggle() }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: Records

    private var visibleReports: [Report] {
        showAllRecords ? reports : Array(reports.prefix(Self.recordPreview))
    }

    private var recordsMeta: String? {
        guard let latest = reports.first else { return nil }
        return "\(ShopPageFormat.plural(reportCount, "report")) · latest \(RelativeDate.format(latest.createdAt))"
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShopSectionHeader("Records", meta: recordsMeta)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                if reports.isEmpty {
                    Text("No records yet. Be the first to report what’s on the bar.")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.vertical, 14)
                }
                ForEach(Array(visibleReports.enumerated()), id: \.element.id) { index, report in
                    if index > 0 { Divider().overlay(Color.cream200) }
                    recordRow(report)
                }
                if reports.count > Self.recordPreview {
                    Divider().overlay(Color.cream200)
                    ShopLinkButton(label: showAllRecords ? "Show fewer" : "See all \(ShopPageFormat.plural(reports.count, "record"))") {
                        withAnimation(.easeOut(duration: 0.2)) { showAllRecords.toggle() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, 16)
            .cardStyle()
        }
    }

    private func recordRow(_ report: Report) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ReporterAvatar(reporter: report.reporter)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.reporter?.name ?? "Anonymous").font(.kycMetaBold).foregroundStyle(Color.ink)
                    Text("\(RelativeDate.format(report.createdAt)) · via \(report.source.lowercased())")
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkMuted)
                }
                let summary = report.summary
                Text(summary.isEmpty ? "Confirmed the current record." : summary)
                    .font(.kycSecondary)
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Pieces

/// Tappable row that opens the report form. A list-row shape instead of a
/// banner with two buttons, which reads as foreign inside an iOS scroll view.
private struct UpdatePromptRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 36, height: 36)
                    .background(Color.cream100, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report an update")
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    Text("Machine, beans, drinks, or photos")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
}

// White card: eyebrow row (with an optional card-level note on the right), then rows.
private struct AboutCard<Content: View>: View {
    let eyebrow: String
    var tag: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowLabel(eyebrow)
                Spacer(minLength: 8)
                if let tag { EyebrowLabel(tag).multilineTextAlignment(.trailing) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Label on the left, pills (or a link) right-aligned and wrapping.
private struct InfoRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.kycSecondary)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            FlowLayout(spacing: 6, trailing: true) { trailing }
        }
    }
}

private struct UnknownRow: View {
    let label: String
    let onKnow: () -> Void

    var body: some View {
        InfoRow(label: label) {
            ShopLinkButton(label: "Unknown — know it?", action: onKnow)
        }
    }
}

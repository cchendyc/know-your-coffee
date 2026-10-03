import SwiftUI

/// About tab: gear, beans, space, menu, then the record thread. One panel so
/// a visitor reads what the community knows before anything for sale.
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
            ShopSectionHeader(
                "About this shop",
                meta: "Verified by \(ShopPageFormat.plural(reportCount, "report")) · updated \(RelativeDate.format(shop.updatedAt))"
            )
            gearCard
            beansCard
            spaceCard

            if !shop.drinks.isEmpty {
                menu
            }

            records
            reportBar
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
                ForEach(Array(shop.knownMachines.enumerated()), id: \.offset) { index, machine in
                    if index > 0 { Divider().overlay(Color.cream200) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(machine.display).font(.kycBodyBold).foregroundStyle(Color.ink)
                        Text("Espresso machine").font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                    }
                }
            }
            if !shop.grinders.isEmpty {
                Divider().overlay(Color.cream200)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grinders").font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                    FlowLayout(spacing: 6) {
                        ForEach(shop.grinders, id: \.self) { Pill(text: $0) }
                    }
                }
            }
        }
    }

    // MARK: Beans

    private var beansCard: some View {
        AboutCard(eyebrow: "Beans") {
            if shop.beanSource == .unknown, shop.roaster == nil, shop.coffees.isEmpty {
                UnknownRow(label: "Who roasts the beans", onKnow: onUpdate)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shop.roaster ?? shop.beanSource.label).font(.kycBodyBold).foregroundStyle(Color.ink)
                    if shop.roaster != nil, shop.beanSource != .unknown {
                        Text(shop.beanSource.label).font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                    }
                }
                if !shop.beanOrigins.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(shop.beanOrigins, id: \.self) { Pill(text: $0) }
                    }
                }
            }
            ForEach(Array(shop.coffees.enumerated()), id: \.offset) { _, coffee in
                Divider().overlay(Color.cream200)
                coffeeRow(coffee)
            }
        }
    }

    private func coffeeRow(_ coffee: Coffee) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(coffee.title ?? "House coffee")
                    .font(.kycSecondaryBold)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                if listingMatches(coffee) {
                    ShopLinkButton(label: "Buy this bean", symbol: "arrow.right", action: onShop)
                }
            }
            if !coffee.pills.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(coffee.pills, id: \.self) { Pill(text: $0) }
                }
            }
            if !coffee.tastingNotes.isEmpty {
                Text("Notes: \(coffee.tastingNotes.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
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
            Divider().overlay(Color.cream200)
            amenityRow("Wi-Fi", shop.wifi)
            Divider().overlay(Color.cream200)
            amenityRow("Outdoor seating", shop.outdoorSeating)
            Divider().overlay(Color.cream200)
            HStack {
                Text("Milk").font(.kycSecondary).foregroundStyle(Color.ink)
                Spacer()
                if shop.milkBrands.isEmpty {
                    ShopLinkButton(label: "Unknown — know it?", action: onUpdate)
                } else {
                    Text(shop.milkBrands.joined(separator: ", "))
                        .font(.kycSecondaryBold)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func amenityRow(_ label: String, _ value: Bool?) -> some View {
        HStack {
            Text(label).font(.kycSecondary).foregroundStyle(Color.ink)
            Spacer()
            if let value {
                Text(value ? "Yes" : "No").font(.kycSecondaryBold).foregroundStyle(Color.ink)
            } else {
                ShopLinkButton(label: "Unknown — know it?", action: onUpdate)
            }
        }
    }

    // MARK: Menu

    private var visibleDrinks: [DrinkItem] {
        showAllDrinks ? shop.drinks : Array(shop.drinks.prefix(Self.drinkPreview))
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShopSectionHeader(
                "Menu",
                meta: [ShopPageFormat.plural(shop.drinks.count, "drink"),
                       shop.milkBrands.isEmpty ? nil : "Milk: \(shop.milkBrands.joined(separator: ", "))"]
                    .compactMap { $0 }.joined(separator: " · ")
            ) {
                ShopLinkButton(label: "Update menu", action: onUpdate)
            }
            .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(visibleDrinks.enumerated()), id: \.offset) { index, drink in
                    if index > 0 { Divider().overlay(Color.cream200) }
                    HStack {
                        Text(drink.name).font(.system(size: 14)).foregroundStyle(Color.ink)
                        Spacer()
                        Text(drink.price.map { "$\(ShopPageFormat.price($0))" } ?? "—")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(drink.price == nil ? Color.inkFaint : Color.ink)
                    }
                    .padding(.vertical, 11)
                }
                if shop.drinks.count > Self.drinkPreview {
                    Divider().overlay(Color.cream200)
                    ShopLinkButton(label: showAllDrinks ? "Show fewer" : "See all \(ShopPageFormat.plural(shop.drinks.count, "drink"))") {
                        withAnimation(.easeOut(duration: 0.2)) { showAllDrinks.toggle() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, 16)
            .cardStyle()
        }
    }

    // MARK: Records

    private var visibleReports: [Report] {
        showAllRecords ? reports : Array(reports.prefix(Self.recordPreview))
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Records · \(reportCount)").font(.kycBodyBold).foregroundStyle(Color.ink)
                    Text("Who reported what, and when").font(.kycMeta).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Text("Newest first").font(.kycMeta).foregroundStyle(Color.crema500)
            }
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
                        .font(.system(size: 11))
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

    private var reportBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Know something new?").font(.kycSecondaryBold).foregroundStyle(Color.ink)
                Text("Keep this page true for the next person.").font(.kycMeta).foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: 8)
            ShopPrimaryPill(label: "Report an update", action: onUpdate)
        }
        .padding(14)
        .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous)
                .strokeBorder(Color.crema400, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

}

// White card with an uppercase eyebrow; rows separate themselves with Dividers.
private struct AboutCard<Content: View>: View {
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(eyebrow)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct UnknownRow: View {
    let label: String
    let onKnow: () -> Void

    var body: some View {
        HStack {
            Text(label).font(.kycSecondary).foregroundStyle(Color.ink)
            Spacer()
            ShopLinkButton(label: "Unknown — know it?", action: onKnow)
        }
    }
}

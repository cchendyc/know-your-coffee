import SwiftUI

/// Shop tab: the owner's listings in a two-column grid.
struct ShopListingsPanel: View {
    let shop: CoffeeShop
    let listings: [ShopListing]
    let onAdd: () -> Void

    @State private var showAll = false

    private static let preview = 4
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var visible: [ShopListing] {
        showAll ? listings : Array(listings.prefix(Self.preview))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShopSectionHeader("From \(shop.name)", meta: deliveryMeta) {
                if listings.count > Self.preview, !showAll {
                    ShopLinkButton(label: "All \(listings.count)", symbol: "chevron.right") {
                        withAnimation(.easeOut(duration: 0.2)) { showAll = true }
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visible) { listing in
                    ListingCard(listing: listing, onAdd: onAdd)
                }
            }

            if listings.count > Self.preview {
                ShopOutlinePill(label: showAll ? "Show fewer" : "See all \(ShopPageFormat.plural(listings.count, "listing"))") {
                    withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
                }
            }

            if let instructions = shop.deliverySettings?.pickupInstructions, !instructions.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pickup").font(.kycMetaBold).foregroundStyle(Color.ink)
                        Text(instructions).font(.kycSecondary).foregroundStyle(Color.inkMuted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetCardStyle()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var deliveryMeta: String? {
        guard let copy = shop.deliverySettings?.copy(city: shop.city), !copy.isEmpty else { return nil }
        return copy
    }
}

private struct ListingCard: View {
    let listing: ShopListing
    let onAdd: () -> Void

    @State private var cover: UIImage?

    private var soldOut: Bool { listing.status == "OUT_OF_STOCK" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(listing.subtitle ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                HStack {
                    Text("$\(ShopPageFormat.price(listing.price))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.inkInverse)
                            .frame(width: 30, height: 30)
                            .background(soldOut ? Color.inkFaint : Color.espresso700, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(soldOut)
                    .accessibilityLabel("Add \(listing.name) to cart")
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous)
                .stroke(Color.cream200, lineWidth: 1)
        )
        .task(id: listing.coverPhoto?.id) {
            guard let photo = listing.coverPhoto else { cover = nil; return }
            let data = await Task.detached(priority: .userInitiated) { photo.imageData }.value
            cover = data.flatMap(UIImage.init(data:))
        }
    }

    private var art: some View {
        ZStack {
            Color.cream100
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                bag
            }
        }
        .frame(height: 148)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let badge {
                Text(badge.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(badge.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badge.fill, in: Capsule())
                    .padding(8)
            }
        }
    }

    // Placeholder bag with the listing name, for covers not yet uploaded.
    private var bag: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.espresso700)
            .frame(width: 72, height: 98)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Color.crema400).frame(height: 10)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            }
            .overlay {
                Text(listing.name.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.inkInverse)
                    .padding(8)
            }
    }

    private var badge: (text: String, tint: Color, fill: Color)? {
        switch listing.status {
        case "LOW_STOCK": ("Low stock", .markerOrange, .warnSoft)
        case "OUT_OF_STOCK": ("Sold out", .inkMuted, .cream100)
        default: nil
        }
    }
}

/// Reviews tab. No ratings exist yet in the backend; this is the honest
/// empty state from the design, not a placeholder histogram.
struct ShopReviewsPanel: View {
    let shop: CoffeeShop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShopSectionHeader("Customer reviews", meta: "From buyers who ordered from \(shop.name)")

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 2) {
                    Text("–")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                }
                .frame(width: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text("No ratings yet").font(.kycBodyBold).foregroundStyle(Color.ink)
                    Text("Reviews unlock after the first delivered order. They’ll show up here, newest first.")
                        .font(.kycSecondary)
                        .lineSpacing(3)
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            ShopOutlinePill(label: "Write a review", enabled: false) {}
            Text("Buy from \(shop.name) first to leave a review.")
                .font(.kycMeta)
                .foregroundStyle(Color.inkFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}

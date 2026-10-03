import SwiftUI

/// Shop tab: the owner's listings as rows, cover left, name and price right.
/// Scrolls with the page.
struct ShopListingsPanel: View {
    let shop: CoffeeShop
    let listings: [ShopListing]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                    ListingRow(listing: listing, onAdd: onAdd)
                    if index < listings.count - 1 {
                        Divider().overlay(Color.cream200).padding(.leading, 96)
                    }
                }
            }
            .cardStyle()

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
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(listing.subtitle ?? " ")
                    .font(.kycMeta)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                HStack {
                    Text("$\(ShopPageFormat.price(listing.price))")
                        .font(.kycBodyBold)
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
        .task(id: listing.coverPhoto) {
            guard let photo = listing.coverPhoto, photo.data != nil else { cover = nil; return }
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

/// Reviews tab. Any signed-in visitor can review any shop.
struct ShopReviewsPanel: View {
    let shop: CoffeeShop
    var onReload: () -> Void = {}

    @State private var open = false
    @State private var showSignIn = false
    @State private var needSignIn = false
    @State private var rating = 0
    @State private var bodyText = ""
    @State private var error: String?
    @State private var busy = false

    private var reviews: [ShopReview] { shop.reviews ?? [] }
    private var count: Int { shop.reviewCount ?? reviews.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 2) {
                    Text(shop.ratingAverage.map { String(format: "%.1f", $0) } ?? "–")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(shop.ratingAverage == nil ? Color.inkFaint : Color.ink)
                    ReviewStars(value: Int((shop.ratingAverage ?? 0).rounded()), size: 10)
                }
                .frame(width: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(count == 0 ? "No ratings yet" : ShopPageFormat.plural(count, "rating"))
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    if needSignIn {
                        Text("Sign in to leave a review.")
                            .font(.kycSecondary)
                            .lineSpacing(3)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            if open {
                reviewForm
            } else {
                ShopOutlinePill(label: shop.myReview == nil ? "Write a review" : "Edit your review") {
                    begin()
                }
            }

            if reviews.isEmpty {
                Text("No reviews yet.")
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .cardStyle()
            } else {
                ForEach(reviews) { review in
                    ReviewRow(review: review)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .onChange(of: shop.myReview) { _, review in
            guard open, rating == 0, bodyText.isEmpty, let review else { return }
            rating = review.rating
            bodyText = review.body ?? ""
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            if AuthStore.shared.isSignedIn {
                needSignIn = false
                onReload()
                beginWriting()
            }
        }) {
            SignInSheet()
        }
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewStars(value: rating, size: 22, onPick: { rating = $0 })
            TextField("What was \(shop.name) like?", text: $bodyText, axis: .vertical)
                .lineLimit(3...6)
                .font(.kycSecondary)
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cream200))
            if let error {
                Text(error).font(.kycMeta).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                ShopPrimaryPill(label: busy ? "Saving…" : (shop.myReview == nil ? "Post review" : "Update review")) {
                    Task { await send() }
                }
                .disabled(busy)
                ShopOutlinePill(label: "Cancel") { open = false }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func begin() {
        guard AuthStore.shared.isSignedIn else {
            needSignIn = true
            showSignIn = true
            return
        }
        beginWriting()
    }

    private func beginWriting() {
        rating = shop.myReview?.rating ?? 0
        bodyText = shop.myReview?.body ?? ""
        error = nil
        open = true
    }

    private func send() async {
        guard rating >= 1 else {
            error = "Pick a star rating."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await CoffeeAPI.submitReview(shopID: shop.id, rating: rating, body: bodyText)
            open = false
            onReload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReviewStars: View {
    let value: Int
    var size: CGFloat = 14
    var onPick: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { n in
                let mark = Image(systemName: n <= value ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(n <= value ? Color.crema500 : Color.inkFaint)
                if let onPick {
                    Button { onPick(n) } label: { mark }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                } else {
                    mark
                }
            }
        }
    }
}

private struct ReviewRow: View {
    let review: ShopReview

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ReporterAvatar(reporter: review.author, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(review.author?.name ?? "Anonymous")
                        .font(.kycMetaBold)
                        .foregroundStyle(Color.ink)
                    ReviewStars(value: review.rating, size: 10)
                    Text(RelativeDate.format(review.createdAt))
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkMuted)
                }
                if let body = review.body, !body.isEmpty {
                    Text(body)
                        .font(.kycSecondary)
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

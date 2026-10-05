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

private struct ListingRow: View {
    let listing: ShopListing
    let onAdd: () -> Void

    @State private var cover: UIImage?
    // Cart quantity for this row. Lives here until a real cart exists.
    @State private var quantity = 0

    private var soldOut: Bool { listing.status == "OUT_OF_STOCK" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            art
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name)
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let subtitle = listing.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("$\(ShopPageFormat.price(listing.price))")
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    if let badge {
                        Text(badge.text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(badge.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(badge.fill, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stepper
        }
        .padding(12)
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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // Placeholder bag with the listing name, for covers not yet uploaded.
    private var bag: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.espresso700)
            .frame(width: 36, height: 50)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Color.crema400).frame(height: 6)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
            }
            .overlay {
                Text(listing.name.uppercased())
                    .font(.system(size: 5, weight: .bold))
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.inkInverse)
                    .padding(4)
            }
    }

    @ViewBuilder
    private var stepper: some View {
        if quantity == 0 {
            roundButton("plus", enabled: !soldOut) {
                quantity = 1
                onAdd()
            }
            .accessibilityLabel("Add \(listing.name) to cart")
        } else {
            HStack(spacing: 0) {
                roundButton("minus", enabled: true) { quantity -= 1 }
                    .accessibilityLabel("Remove one \(listing.name)")
                Text("\(quantity)")
                    .font(.kycBodyBold)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 24)
                roundButton("plus", enabled: !soldOut) { quantity += 1 }
                    .accessibilityLabel("Add one more \(listing.name)")
            }
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Color.ink : Color.inkFaint)
                .frame(width: 30, height: 30)
                .background(Color.surface, in: Circle())
                .overlay(Circle().stroke(Color.cream200, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                        .font(.kycBodyBold)
                        .foregroundStyle(shop.ratingAverage == nil ? Color.inkFaint : Color.ink)
                    ReviewStars(value: Int((shop.ratingAverage ?? 0).rounded()), size: 11)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(count == 0 ? "No ratings yet" : ShopPageFormat.plural(count, "rating"))
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
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

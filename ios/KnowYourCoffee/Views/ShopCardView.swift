import SwiftUI

// Feed card, xiaohongshu-style: the photo carries the card, text stays minimal.
struct ShopCardView: View {
    let shop: CoffeeShop
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 5) {
                Text(shop.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.espresso900)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let tag = tagLine {
                    Text(tag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.crema500)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(shop.city)
                        .font(.caption2)
                        .foregroundStyle(Color.espresso500.opacity(0.8))
                    Spacer(minLength: 0)
                    amenityIcons
                }
            }
            .padding(10)
        }
        .frame(width: width)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .espresso900.opacity(0.05), radius: 6, y: 2)
    }

    // One line only: the most identifying gear/bean fact, not a pill wall.
    private var tagLine: String? {
        if let first = shop.knownMachines.first { return first.display }
        if let roaster = shop.roaster, !roaster.isEmpty { return roaster }
        if shop.beanSource != .unknown { return shop.beanSource.label }
        return nil
    }

    // Staggered feed heights, stable across launches (Swift's String hash is
    // per-launch randomized, so roll a tiny deterministic one).
    private var photoHeight: CGFloat {
        let heights: [CGFloat] = [130, 160, 190, 220]
        var h: UInt64 = 5381
        for byte in shop.id.utf8 { h = h &* 33 &+ UInt64(byte) }
        return heights[Int(h % UInt64(heights.count))]
    }

    private var photo: some View {
        AsyncImage(url: shop.photoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                LinearGradient(
                    colors: [.cream100, .cream200],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.espresso500.opacity(0.25))
                )
            }
        }
        .frame(width: width, height: photoHeight)
        .clipped()
        .overlay(alignment: .topTrailing) { statusBadge }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if shop.savedByMe || shop.beenByMe {
            Image(systemName: shop.savedByMe ? "bookmark.fill" : "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(shop.savedByMe ? Color.savedGreen : Color.espresso700)
                .padding(6)
                .background(.regularMaterial, in: Circle())
                .padding(6)
        }
    }

    private var amenityIcons: some View {
        HStack(spacing: 5) {
            if shop.dogFriendly == true {
                Image(systemName: "pawprint.fill")
            }
            if shop.wifi == true {
                Image(systemName: "wifi")
            }
            if shop.outdoorSeating == true {
                Image(systemName: "sun.max.fill")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.crema500.opacity(0.9))
    }
}

// Redacted feed shown while the first page loads.
struct ShopCardPlaceholder: View {
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: [.cream100, .cream200], startPoint: .leading, endPoint: .trailing)
                .frame(width: width, height: height)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color.cream200).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(Color.cream100).frame(width: 60, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .redacted(reason: .placeholder)
    }
}

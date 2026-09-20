import SwiftUI

struct ShopCardView: View {
    let shop: CoffeeShop

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shop.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.espresso900)
                        .lineLimit(1)
                    Spacer()
                    Text(shop.city)
                        .font(.caption)
                        .foregroundStyle(Color.espresso500)
                }

                FlowLayout(spacing: 6) {
                    ForEach(shop.knownMachines, id: \.self) { machine in
                        Pill(text: machine.display, fill: .espresso700.opacity(0.09), foreground: .espresso700)
                    }
                    if let roaster = shop.roaster, !roaster.isEmpty {
                        Pill(text: roaster, fill: .crema400.opacity(0.25), foreground: .espresso700)
                    } else if shop.beanSource != .unknown {
                        Pill(text: shop.beanSource.label, fill: .crema400.opacity(0.25), foreground: .espresso700)
                    }
                }

                if let vibe = shop.vibe, !vibe.isEmpty {
                    Text(vibe)
                        .font(.caption)
                        .foregroundStyle(Color.espresso500)
                        .lineLimit(2)
                }

                amenities
            }
            .padding(14)
        }
        .cardStyle()
    }

    private var photo: some View {
        GeometryReader { geo in
            AsyncImage(url: shop.photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: 150)
            .clipped()
        }
        .frame(height: 150)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [.cream100, .cream200],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.espresso500.opacity(0.25))
        )
    }

    private var amenities: some View {
        HStack(spacing: 12) {
            amenity("pawprint.fill", shop.dogFriendly)
            amenity("wifi", shop.wifi)
            amenity("sun.max.fill", shop.outdoorSeating)
            Spacer()
            if shop.savedByMe {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Color.savedGreen)
            }
            if shop.beenByMe {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.espresso500)
            }
        }
    }

    // Tri-state: colored = yes, struck-through gray = no, hidden = unknown.
    @ViewBuilder
    private func amenity(_ symbol: String, _ value: Bool?) -> some View {
        if let value {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(value ? Color.crema500 : Color.espresso500.opacity(0.3))
                .overlay {
                    if !value {
                        Rectangle()
                            .fill(Color.espresso500.opacity(0.5))
                            .frame(height: 1.5)
                            .rotationEffect(.degrees(-45))
                    }
                }
        }
    }
}

// Redacted card shown while the first page loads.
struct ShopCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: [.cream100, .cream200], startPoint: .leading, endPoint: .trailing)
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.cream200).frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Color.cream100).frame(width: 200, height: 10)
            }
            .padding(14)
        }
        .cardStyle()
        .redacted(reason: .placeholder)
    }
}

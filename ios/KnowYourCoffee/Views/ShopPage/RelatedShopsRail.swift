import SwiftUI

/// Horizontal rail of shop cards under the tab panel. Chain siblings today;
/// the same rail will carry similar-shop suggestions once the backend ranks them.
struct RelatedShopsRail: View {
    let title: String
    var subtitle: String?
    let shops: [ChainLocation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kycSection).foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle).font(.kycMeta).foregroundStyle(Color.inkMuted)
                }
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shops) { shop in
                        NavigationLink(value: shop) {
                            RelatedShopCard(shop: shop)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct RelatedShopCard: View {
    let shop: ChainLocation

    private static let width: CGFloat = 172

    private var meta: String {
        [shop.city, shop.knownMachine?.display].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            art
                .frame(width: Self.width, height: Self.width * 0.625)
                .clipShape(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                        .stroke(Color.cream200, lineWidth: 1)
                )
                .padding(.bottom, 5)
            Text(shop.name)
                .font(.kycSecondaryBold)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(meta)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var art: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2B1D14), Color(hex: 0x6F4E37), Color(hex: 0xC08C3E)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let url = shop.photoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .overlay(alignment: .topLeading) {
            if shop.beanSource == .inHouseRoast {
                Text("Roasts in-house")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0x1B120C).opacity(0.55), in: Capsule())
                    .padding(8)
            }
        }
    }

    private var initials: some View {
        Text(ShopPageFormat.initials(shop.name))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color(hex: 0xFBF8F3))
    }
}

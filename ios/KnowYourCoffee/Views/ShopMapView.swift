import MapKit
import SwiftUI

struct ShopMapView: View {
    let shops: [CoffeeShop]
    let onSelect: (CoffeeShop) -> Void

    @State private var position: MapCameraPosition = .region(Self.bayArea)
    @State private var didFit = false

    private static let bayArea = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.35),
        span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
    )

    var body: some View {
        Map(position: $position) {
            ForEach(shops) { shop in
                Annotation(shop.name, coordinate: shop.coordinate) {
                    MarkerDot(shop: shop)
                        .onTapGesture { onSelect(shop) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: shops) { fitToShops() }
        .onAppear { fitToShops() }
    }

    // Frame all pins once per result set; leave the camera alone afterward
    // so panning is never fought.
    private func fitToShops() {
        guard !shops.isEmpty else { return }
        let lats = shops.map(\.lat)
        let lngs = shops.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.3, 0.02),
                longitudeDelta: max((maxLng - minLng) * 1.3, 0.02)
            )
        )
        withAnimation(.easeOut(duration: 0.4)) {
            position = .region(region)
        }
    }
}

// Same hues as the web markers: orange = shop, green = saved, gray = been.
private struct MarkerDot: View {
    let shop: CoffeeShop

    private var fill: Color {
        if shop.beenByMe { return Color(hex: 0xA3968B) }
        if shop.savedByMe { return .savedGreen }
        return .markerOrange
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Color.cream50, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            // A 14pt dot is a cruel tap target; pad the hit area invisibly.
            .padding(8)
            .contentShape(Circle())
    }
}

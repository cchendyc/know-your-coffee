import MapKit
import SwiftUI

// Discovery map. Muted base so the pins carry the color; pins and clusters
// use the web's coding (orange shop, green saved, taupe been). Clusters are
// recomputed when a gesture ends: 1,000 bare pins are unreadable at Bay
// Area zoom and slow to lay out.
struct ShopMapView: View {
    let shops: [CoffeeShop]
    let onSelect: (CoffeeShop) -> Void

    @State private var position: MapCameraPosition = .region(Self.bayArea)
    @State private var viewport = Viewport(region: Self.bayArea)
    @State private var clusters: [ShopCluster] = []
    // Co-located shops that no zoom level can pull apart; picked from a sheet.
    @State private var stack: ShopCluster?
    // Chosen in the stack sheet; opened once the sheet is gone so the
    // full-screen detail never presents over a dismissing sheet.
    @State private var pendingSelection: CoffeeShop?
    @State private var tapCount = 0

    private static let bayArea = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.35),
        span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
    )
    /// Pins closer than this (points) merge. Web uses 28px for 14px dots;
    /// these pins are 28pt plus a name label.
    private static let clusterRadius: CGFloat = 44
    /// Tightest zoom a cluster tap goes to, ~65 m across.
    private static let minSpan = 0.0006

    var body: some View {
        // North-locked, 2D: rotation and pitch add nothing to a pin map.
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(clusters) { cluster in
                if let shop = cluster.single {
                    Annotation(shop.name, coordinate: shop.coordinate, anchor: .bottom) {
                        ShopPin(shop: shop)
                            .onTapGesture {
                                tapCount += 1
                                onSelect(shop)
                            }
                    }
                } else {
                    Annotation("", coordinate: cluster.coordinate) {
                        ClusterBadge(count: cluster.shops.count)
                            .onTapGesture {
                                tapCount += 1
                                open(cluster)
                            }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewport.region = context.region
            recluster()
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            viewport.size = size
            recluster()
        }
        .overlay(alignment: .top) { edgeFade(.top) }
        .overlay(alignment: .bottom) { edgeFade(.bottom) }
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .sheet(item: $stack, onDismiss: {
            if let shop = pendingSelection {
                pendingSelection = nil
                onSelect(shop)
            }
        }) { stack in
            StackedShopsSheet(shops: stack.shops) { shop in
                pendingSelection = shop
                self.stack = nil
            }
        }
        .onChange(of: shops) { old, new in
            // A save/been toggle only recolors a pin; a new result set reframes.
            if old.map(\.id) == new.map(\.id) { recluster() } else { fitToShops() }
        }
        .onAppear { fitToShops() }
    }

    // Header and floating controls melt into the map instead of ending on a hard edge.
    private func edgeFade(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: [Color.cream50.opacity(edge == .top ? 0.9 : 0.75), .clear],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: edge == .top ? 24 : 96)
        .allowsHitTesting(false)
    }

    private func recluster() {
        guard viewport.size.width > 0 else { return }
        let all = ShopClustering.cluster(shops, zoom: viewport.zoom, radius: Self.clusterRadius)
        // Keep pins well past the edges so a pan shows them before the gesture ends.
        let window = viewport.region.scaled(by: 3)
        clusters = all.filter { window.contains($0.coordinate) }
    }

    private func open(_ cluster: ShopCluster) {
        // Below this spread the members still overlap at minSpan, so zooming is a dead end.
        let metersPerPoint = Self.minSpan * 111_320 * cos(cluster.coordinate.latitude * .pi / 180)
            / max(viewport.size.width, 320)
        if cluster.spreadMeters < Double(Self.clusterRadius) * metersPerPoint {
            stack = cluster
            return
        }
        var region = cluster.bounds
        region.span.latitudeDelta = max(region.span.latitudeDelta * 1.6, Self.minSpan)
        region.span.longitudeDelta = max(region.span.longitudeDelta * 1.6, Self.minSpan)
        withAnimation(.easeInOut(duration: 0.45)) {
            position = .region(region)
        }
    }

    // Frame all pins once per result set; leave the camera alone afterward
    // so panning is never fought.
    private func fitToShops() {
        guard !shops.isEmpty else {
            clusters = []
            return
        }
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
        // Cluster for the target zoom now; waiting for the camera to settle
        // would show the old result set for the length of the animation.
        viewport.region = region
        recluster()
        withAnimation(.easeOut(duration: 0.4)) {
            position = .region(region)
        }
    }
}

// MARK: - Clustering

struct ShopCluster: Identifiable {
    let id: String
    let shops: [CoffeeShop]
    let coordinate: CLLocationCoordinate2D
    let bounds: MKCoordinateRegion

    init(shops: [CoffeeShop]) {
        self.shops = shops
        let lats = shops.map(\.lat), lngs = shops.map(\.lng)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        coordinate = CLLocationCoordinate2D(
            latitude: lats.reduce(0, +) / Double(shops.count),
            longitude: lngs.reduce(0, +) / Double(shops.count)
        )
        bounds = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLng - minLng)
        )
        id = shops.count == 1 ? shops[0].id : "cluster:\(shops[0].id):\(shops.count)"
    }

    var single: CoffeeShop? { shops.count == 1 ? shops[0] : nil }

    /// Longest side of the bounding box, in meters.
    var spreadMeters: Double {
        let lat = bounds.span.latitudeDelta * 111_320
        let lng = bounds.span.longitudeDelta * 111_320 * cos(coordinate.latitude * .pi / 180)
        return max(lat, lng)
    }
}

enum ShopClustering {
    /// Greedy radius clustering in Web Mercator points, like Leaflet.markercluster:
    /// each shop joins the nearest cluster whose anchor is within `radius`,
    /// else starts one. Anchors are the first member's position, not a moving
    /// centroid, so the grouping is deterministic for a given zoom.
    static func cluster(_ shops: [CoffeeShop], zoom: Double, radius: CGFloat) -> [ShopCluster] {
        struct Cell: Hashable { let x: Int; let y: Int }
        let worldSize = 256 * pow(2, zoom)
        func project(_ c: CLLocationCoordinate2D) -> CGPoint {
            let lat = c.latitude * .pi / 180
            return CGPoint(
                x: (c.longitude + 180) / 360 * worldSize,
                y: (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * worldSize
            )
        }

        var anchors: [CGPoint] = []
        var members: [[CoffeeShop]] = []
        // Cell edge = radius, so the 3×3 neighborhood holds every anchor in range.
        var grid: [Cell: [Int]] = [:]

        for shop in shops.sorted(by: { $0.id < $1.id }) {
            let point = project(shop.coordinate)
            let cell = Cell(x: Int((point.x / radius).rounded(.down)), y: Int((point.y / radius).rounded(.down)))
            var best: (index: Int, distance: CGFloat)?
            for dx in -1...1 {
                for dy in -1...1 {
                    for index in grid[Cell(x: cell.x + dx, y: cell.y + dy)] ?? [] {
                        let distance = hypot(anchors[index].x - point.x, anchors[index].y - point.y)
                        if distance <= radius, distance < (best?.distance ?? .infinity) {
                            best = (index, distance)
                        }
                    }
                }
            }
            if let best {
                members[best.index].append(shop)
            } else {
                anchors.append(point)
                members.append([shop])
                grid[cell, default: []].append(anchors.count - 1)
            }
        }
        return members.map(ShopCluster.init)
    }
}

private struct Viewport {
    var region: MKCoordinateRegion
    var size: CGSize = .zero

    /// Web Mercator zoom implied by the visible longitude span (256pt tiles).
    var zoom: Double {
        guard size.width > 0, region.span.longitudeDelta > 0 else { return 9 }
        return log2(size.width * 360 / (256 * region.span.longitudeDelta))
    }
}

private extension MKCoordinateRegion {
    func scaled(by factor: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(span.latitudeDelta * factor, 180),
                longitudeDelta: min(span.longitudeDelta * factor, 360)
            )
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude - center.latitude) <= span.latitudeDelta / 2
            && abs(coordinate.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}

// MARK: - Pins

// Glyph pin anchored at the tail tip. Status iconography matches the feed
// badges: bookmark = saved, check = been; everything else is a cup.
private struct ShopPin: View {
    let shop: CoffeeShop

    private var fill: Color {
        if shop.beenByMe { return .beenTaupe }
        if shop.savedByMe { return .savedGreen }
        return .markerOrange
    }

    // Been fades back, but a green ring keeps saved visible (web .is-saved.is-been).
    private var ring: Color {
        shop.beenByMe && shop.savedByMe ? .savedGreen : .white
    }

    private var glyph: String {
        if shop.beenByMe { return "checkmark" }
        if shop.savedByMe { return "bookmark.fill" }
        return "cup.and.saucer.fill"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(fill)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
                .offset(y: -4)
            Circle()
                .fill(fill)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(ring, lineWidth: 2))
                .overlay(
                    Image(systemName: glyph)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )
                .padding(.bottom, 7)
        }
        .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
        // 28pt is a cruel tap target; pad the hit area invisibly. No bottom
        // padding, so the anchor stays on the tail tip.
        .padding([.horizontal, .top], 8)
        .contentShape(Rectangle())
    }
}

// Orange disc with a soft halo, same as the web .shop-cluster.
private struct ClusterBadge: View {
    let count: Int

    private var size: CGFloat {
        count < 10 ? 30 : count < 100 ? 36 : 42
    }

    var body: some View {
        Text(count, format: .number.grouping(.never))
            .font(.system(size: count < 100 ? 13 : 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.markerOrange, in: Circle())
            .background(Color.markerOrange.opacity(0.22), in: Circle().inset(by: -3))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            .padding(6)
            .contentShape(Circle())
    }
}

// MARK: - Stacked shops

// Shops sharing one address (a food hall, a shared storefront) get a picker
// instead of an endless zoom.
private struct StackedShopsSheet: View {
    let shops: [CoffeeShop]
    let onPick: (CoffeeShop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(shops.count) shops here")
                .font(.kycSection)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shops) { shop in
                        Button {
                            onPick(shop)
                        } label: {
                            row(shop)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .presentationDetents([.height(min(CGFloat(shops.count) * 64 + 80, 440))])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surface)
    }

    private func row(_ shop: CoffeeShop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(shop.beenByMe ? Color.beenTaupe : shop.savedByMe ? Color.savedGreen : Color.markerOrange, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(shop.name)
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(shop.address)
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkFaint)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .contentShape(Rectangle())
    }
}

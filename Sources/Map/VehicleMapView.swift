import MapKit
import SwiftUI

/// The available base-map renderings the user can switch between, persisted as a raw `String`.
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    /// User-facing Norwegian label.
    var title: String {
        switch self {
        case .standard: "Kart"
        case .hybrid: "Hybrid"
        case .satellite: "Satellitt"
        }
    }

    /// SF Symbol shown next to the option in the menu.
    var symbolName: String {
        switch self {
        case .standard: "map"
        case .hybrid: "map.fill"
        case .satellite: "globe.europe.africa.fill"
        }
    }

    /// The MapKit style to apply to the map.
    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .hybrid: .hybrid
        case .satellite: .imagery
        }
    }
}

/// The map surface: one annotation per visible vehicle, with the camera bound to the parent so the
/// recenter / follow controls can drive it. Camera changes feed the viewport back to the model,
/// which re-scopes the Entur subscription. At wide zoom, dense vehicles collapse into count bubbles
/// (see `VehicleClustering`) so the map stays readable.
struct VehicleMapView: View {
    let model: VehiclesModel
    let mapStyle: MapStyleOption
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedVehicleID: String?
    @Binding var selectedStopID: String?
    @Binding var currentCamera: MapCamera?
    /// Latest visible region, used to size the clustering grid. Updated on camera changes.
    @Binding var currentRegion: MKCoordinateRegion?
    @Binding var isFollowing: Bool
    /// The selected vehicle's route line (empty when nothing is selected or it has no journey).
    let routeCoordinates: [CLLocationCoordinate2D]
    /// Colour for the route line + its stop dots — the line colour, or the mode-fallback tint.
    let routeColor: Color
    /// Stops along the selected journey, drawn as small dots over the route line.
    let journeyStops: [JourneyCall]
    /// The next stop the vehicle is heading to, drawn larger/filled.
    let nextStopID: String?

    /// Split the visible set into wide-zoom clusters and the markers drawn individually. The selected
    /// vehicle is always kept individual so follow mode + the detail panel keep working.
    private var clustered: (clusters: [VehicleCluster], singles: [Vehicle]) {
        VehicleClustering.cluster(
            model.visibleVehicles,
            region: currentRegion,
            excluding: selectedVehicleID
        )
    }

    var body: some View {
        let grouped = clustered
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // The selected vehicle's route, beneath everything else.
                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(
                            routeColor.opacity(0.85),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }

                // Journey stop dots sit above the route line but below the markers. Decorative only —
                // hit-testing is disabled so they don't interfere with empty-map-tap clearing.
                ForEach(journeyStops) { call in
                    Annotation(call.quayName, coordinate: call.coordinate) {
                        JourneyStopDot(color: routeColor, isNext: call.id == nextStopID)
                            .allowsHitTesting(false)
                    }
                    .annotationTitles(.hidden)
                }

                // Stops first so the colourful vehicle markers draw on top of them.
                ForEach(model.stops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        StopMarker(stop: stop, isSelected: selectedStopID == stop.id)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                            .onTapGesture { selectedStopID = stop.id }
                    }
                    .annotationTitles(.hidden)
                }

                // Wide-zoom clusters: a count bubble that zooms to fit its members on tap.
                ForEach(grouped.clusters) { cluster in
                    Annotation(cluster.id, coordinate: cluster.coordinate) {
                        ClusterBubble(count: cluster.count, tint: clusterTint(cluster))
                            .onTapGesture { zoom(to: cluster) }
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(grouped.singles) { vehicle in
                    Annotation(vehicle.shortLabel, coordinate: vehicle.coordinate) {
                        VehicleMarker(
                            vehicle: vehicle,
                            colors: model.lineColors.colors(for: vehicle),
                            isSelected: selectedVehicleID == vehicle.id,
                            isWatched: model.personalization.isWatched(lineRef: vehicle.lineRef ?? "")
                        )
                        .onTapGesture { select(vehicle) }
                    }
                    .annotationTitles(.hidden)
                }

                UserAnnotation()
            }
            .mapStyle(mapStyle.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                currentCamera = context.camera
                currentRegion = context.region
                model.updateViewport(context.region)
            }
            // Tap on empty map clears the selection (dismisses the inspector/sheet, releases follow).
            // `Map.onTapGesture` does not fire at all on iOS/macOS 26 (FB19394663), so we use a
            // `SpatialTapGesture` run alongside the map. Marker taps are handled by the annotations'
            // own gestures; here we hit-test the tap and only clear when it lands clear of every
            // marker — which also prevents this from racing with (and undoing) a marker selection.
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                    if !isNearAnyMarker(value.location, proxy: proxy) { clearSelection() }
                }
            )
            .simultaneousGesture(
                // A manual pan releases follow mode (matching Apple Maps). Runs alongside the map's
                // own pan gesture, so it only observes. The 10pt minimum keeps taps from counting
                // as drags.
                DragGesture(minimumDistance: 10).onChanged { _ in
                    if isFollowing { isFollowing = false }
                }
            )
        }
    }

    /// Whether a tap point (in the map's local space) lands on or near any drawn marker, in which
    /// case the marker's own tap gesture owns it and we must not treat the tap as "empty map".
    /// Cluster bubbles sit on their members' coordinates, so testing the vehicle set covers them too.
    private func isNearAnyMarker(_ point: CGPoint, proxy: MapProxy) -> Bool {
        let hitRadius: CGFloat = 26
        for stop in model.stops {
            if let screen = proxy.convert(stop.coordinate, to: .local),
                point.distance(to: screen) <= hitRadius {
                return true
            }
        }
        for vehicle in model.visibleVehicles {
            if let screen = proxy.convert(vehicle.coordinate, to: .local),
                point.distance(to: screen) <= hitRadius {
                return true
            }
        }
        return false
    }

    /// The dominant member mode's tint. Clusters mix lines, so a mode colour reads cleaner than any
    /// single line colour.
    private func clusterTint(_ cluster: VehicleCluster) -> Color {
        let counts = Dictionary(grouping: cluster.vehicles, by: \.mode).mapValues(\.count)
        let dominant = counts.max { $0.value < $1.value }?.key
        return dominant.fallbackColor
    }

    /// Zooms the camera to fit a tapped cluster's members, padded and clamped to a minimum span so a
    /// tightly-overlapping cluster doesn't slam to street level. Repeated taps drill in until it breaks
    /// apart.
    private func zoom(to cluster: VehicleCluster) {
        let lats = cluster.vehicles.map(\.latitude)
        let lons = cluster.vehicles.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
            let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.004)
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func select(_ vehicle: Vehicle) {
        selectedVehicleID = vehicle.id
        isFollowing = true
    }

    private func clearSelection() {
        selectedVehicleID = nil
        selectedStopID = nil
        isFollowing = false
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

/// A group of nearby vehicles collapsed into one bubble at wide zoom.
struct VehicleCluster: Identifiable {
    /// Stable grid-cell key ("row:col") so SwiftUI keeps annotation identity across frames.
    let id: String
    /// Centroid of the members.
    let coordinate: CLLocationCoordinate2D
    let vehicles: [Vehicle]

    var count: Int { vehicles.count }
}

/// Grid-based clustering for the vehicle layer. SwiftUI `Map` has no built-in annotation clustering,
/// so we bucket vehicles into a lat/lon grid whose cell size tracks the visible span (≈ a fixed
/// screen size at any zoom). Cells with one vehicle stay individual; cells with several merge.
enum VehicleClustering {
    /// Latitude span beyond which clustering engages (wider than `MKCoordinateSpan.city`). Below
    /// this the user is zoomed in enough to want every vehicle drawn individually.
    static let minClusterSpan = 0.03
    /// Number of grid cells across the visible span — higher → finer grid → fewer merges.
    static let cellsPerSpan = 9.0

    static func cluster(
        _ vehicles: [Vehicle],
        region: MKCoordinateRegion?,
        excluding excludedID: String?
    ) -> (clusters: [VehicleCluster], singles: [Vehicle]) {
        guard let region, region.span.latitudeDelta > minClusterSpan else {
            return ([], vehicles)
        }
        let latCell = region.span.latitudeDelta / cellsPerSpan
        let lonCell = region.span.longitudeDelta / cellsPerSpan
        guard latCell > 0, lonCell > 0 else { return ([], vehicles) }

        var buckets: [String: [Vehicle]] = [:]
        var singles: [Vehicle] = []
        for vehicle in vehicles {
            if vehicle.id == excludedID {
                singles.append(vehicle)  // never hide the selected/followed vehicle
                continue
            }
            let row = Int((vehicle.latitude / latCell).rounded(.down))
            let col = Int((vehicle.longitude / lonCell).rounded(.down))
            buckets["\(row):\(col)", default: []].append(vehicle)
        }

        var clusters: [VehicleCluster] = []
        for (key, members) in buckets {
            if members.count == 1 {
                singles.append(members[0])
                continue
            }
            let lat = members.reduce(0.0) { $0 + $1.latitude } / Double(members.count)
            let lon = members.reduce(0.0) { $0 + $1.longitude } / Double(members.count)
            clusters.append(
                VehicleCluster(
                    id: key,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    vehicles: members
                )
            )
        }
        return (clusters, singles)
    }
}

/// A glass count bubble standing in for a cluster of vehicles. Sized gently by member count and
/// tinted with the dominant mode colour.
private struct ClusterBubble: View {
    let count: Int
    let tint: Color

    /// Gentle log growth: ~36pt for a pair, ~52pt for a big crowd.
    private var size: CGFloat {
        min(52, 30 + CGFloat(log2(Double(count))) * 6)
    }

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.16)), in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            .accessibilityLabel("\(count) kjøretøy")
    }
}

/// A small dot marking a stop along the selected vehicle's route. The next stop is drawn larger and
/// filled in the line colour; the rest are subdued white pips with a coloured ring.
private struct JourneyStopDot: View {
    let color: Color
    let isNext: Bool

    var body: some View {
        Circle()
            .fill(isNext ? AnyShapeStyle(color) : AnyShapeStyle(.white))
            .frame(width: isNext ? 14 : 9, height: isNext ? 14 : 9)
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
    }
}

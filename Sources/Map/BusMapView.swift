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
/// which re-scopes the Entur subscription.
struct BusMapView: View {
    let model: VehiclesModel
    let mapStyle: MapStyleOption
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedVehicleID: String?
    @Binding var selectedStopID: String?
    @Binding var currentCamera: MapCamera?
    @Binding var isFollowing: Bool
    /// The selected vehicle's route line (empty when nothing is selected or it has no journey).
    let routeCoordinates: [CLLocationCoordinate2D]
    /// Colour for the route line + its stop dots — the line colour, or the mode-fallback tint.
    let routeColor: Color
    /// Stops along the selected journey, drawn as small dots over the route line.
    let journeyStops: [JourneyCall]
    /// The next stop the vehicle is heading to, drawn larger/filled.
    let nextStopID: String?

    var body: some View {
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

                ForEach(model.visibleVehicles) { vehicle in
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

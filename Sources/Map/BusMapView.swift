import MapKit
import SwiftUI

/// The map surface: one annotation per visible vehicle, with the camera bound to the parent so the
/// recenter / follow controls can drive it. Camera changes feed the viewport back to the model,
/// which re-scopes the Entur subscription.
struct BusMapView: View {
    let model: VehiclesModel
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedVehicleID: String?
    @Binding var selectedStopID: String?
    @Binding var currentCamera: MapCamera?
    @Binding var isFollowing: Bool

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
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
                            isSelected: selectedVehicleID == vehicle.id
                        )
                        .onTapGesture { select(vehicle) }
                    }
                    .annotationTitles(.hidden)
                }

                UserAnnotation()
            }
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

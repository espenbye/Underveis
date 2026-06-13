import MapKit
import SwiftUI

/// The map surface: one annotation per visible vehicle, with the camera bound to the parent so the
/// recenter / follow controls can drive it. Camera changes feed the viewport back to the model,
/// which re-scopes the Entur subscription.
struct BusMapView: View {
    let model: VehiclesModel
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedVehicleID: String?
    @Binding var currentCamera: MapCamera?
    @Binding var isFollowing: Bool

    var body: some View {
        Map(position: $cameraPosition) {
            // Stops first so the colourful vehicle markers draw on top of them.
            ForEach(model.stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    StopMarker(stop: stop)
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
        .simultaneousGesture(
            // A manual pan releases follow mode (matching Apple Maps). Runs alongside the map's own
            // pan gesture, so it only observes. The 10pt minimum keeps taps from counting as drags.
            DragGesture(minimumDistance: 10).onChanged { _ in
                if isFollowing { isFollowing = false }
            }
        )
    }

    private func select(_ vehicle: Vehicle) {
        selectedVehicleID = vehicle.id
        isFollowing = true
    }
}

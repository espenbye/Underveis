import SwiftUI

/// Sidebar section of per-mode toggles. A single enabled mode is filtered server-side; multiple
/// are filtered client-side (handled by `VehiclesModel`).
struct ModeFilterView: View {
    let model: VehiclesModel

    var body: some View {
        Section("Vis") {
            ForEach(VehicleMode.selectable) { mode in
                Toggle(isOn: binding(for: mode)) {
                    Label(mode.title, systemImage: mode.symbolName)
                }
            }
        }
        Section("Kart") {
            Toggle(isOn: stopsBinding) {
                Label("Holdeplasser", systemImage: "signpost.right.fill")
            }
        }
    }

    private func binding(for mode: VehicleMode) -> Binding<Bool> {
        Binding(
            get: { model.enabledModes.contains(mode) },
            set: { model.setMode(mode, enabled: $0) }
        )
    }

    private var stopsBinding: Binding<Bool> {
        Binding(
            get: { model.showStops },
            set: { model.setShowStops($0) }
        )
    }
}

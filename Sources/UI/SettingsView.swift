import SwiftUI

/// App-level settings — the content shown by the macOS `Settings` scene (⌘,) and the iOS gear sheet.
/// Holds genuinely global concerns (a factory reset + an About section); it deliberately does *not*
/// absorb the on-map Filtre, which stays on the map for in-context scoping.
struct SettingsView: View {
    let model: VehiclesModel

    /// Owned here so "Nullstill appen" can return the map style to its default — `VehiclesModel`
    /// doesn't know about this preference. Same key/default as `RootView`.
    @AppStorage("mapStyle") private var mapStyleRaw = MapStyleOption.standard.rawValue
    @State private var showResetConfirm = false

    private static let enturURL = URL(string: "https://developer.entur.org")
    private static let nlodURL = URL(string: "https://data.norge.no/nlod/en/2.0")

    var body: some View {
        Form {
            Section("Generelt") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Nullstill appen", systemImage: "trash")
                }
            }

            Section("Om Underveis") {
                LabeledContent("Versjon", value: Self.versionString)
                if let enturURL = Self.enturURL {
                    Link(destination: enturURL) {
                        Label("Sanntidsdata fra Entur", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                if let nlodURL = Self.nlodURL {
                    Link("Lisensiert under NLOD 2.0", destination: nlodURL)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Innstillinger")
        .confirmationDialog(
            "Nullstill appen?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Nullstill", role: .destructive) {
                model.resetApp()
                mapStyleRaw = MapStyleOption.standard.rawValue
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text(
                "Dette sletter favoritter, nylige, fulgte linjer, bufrede farger og innstillinger. "
                    + "Handlingen kan ikke angres."
            )
        }
    }

    /// "1.0 (1)" from the app bundle — marketing version + build number.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

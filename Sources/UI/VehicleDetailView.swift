import MapKit
import SwiftUI

/// Details for the selected vehicle, shown in the inspector panel.
struct VehicleDetailView: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors

    /// Drives the Look Around "ride along" preview, refetching as the vehicle moves.
    @State private var rideAlong = RideAlongModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                rideAlongSection
                Divider()
                facts
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Fetch on first appearance and reset + refetch when the selection switches vehicles.
        .task(id: vehicle.id) {
            rideAlong.reset()
            rideAlong.update(to: vehicle.coordinate, bearing: vehicle.bearing)
        }
        // Track the vehicle as it moves or turns (throttled inside the model). `CLLocationCoordinate2D`
        // isn't `Equatable`, so key the change on a lightweight string like `RootView.followKey` does.
        .onChange(of: "\(vehicle.latitude),\(vehicle.longitude),\(vehicle.bearing ?? -1)") {
            rideAlong.update(to: vehicle.coordinate, bearing: vehicle.bearing)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.tint)
                .frame(width: 52, height: 52)
                .overlay {
                    Text(vehicle.shortLabel)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(colors.label)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.lineName ?? vehicle.mode?.title ?? "Avgang")
                    .font(.title3.weight(.semibold))
                if let destination = vehicle.destinationName {
                    Text(destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Street-level Look Around preview at the vehicle's live position — the "ride along" view.
    @ViewBuilder
    private var rideAlongSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Se deg omkring", systemImage: "binoculars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                switch rideAlong.availability {
                case .available where rideAlong.scene != nil:
                    LookAroundPreview(scene: $rideAlong.scene, badgePosition: .bottomTrailing)
                case .unavailable:
                    placeholder("Ingen gatebilde her", systemImage: "eye.slash")
                default:
                    placeholder(nil, systemImage: nil)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Same-sized fill for the preview slot: a centred message, or a spinner while loading.
    private func placeholder(_ text: String?, systemImage: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let text, let systemImage {
                Label(text, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let origin = vehicle.originName, let destination = vehicle.destinationName {
                fact("Rute", "\(origin) → \(destination)", systemImage: "arrow.right")
            }
            if let mode = vehicle.mode {
                fact("Type", mode.title, systemImage: mode.symbolName)
            }
            if let delay = vehicle.delay {
                fact("Avvik", delayText(delay), systemImage: "clock")
            }
            if let speed = vehicle.speed {
                fact("Fart", String(format: "%.0f km/t", speed * 3.6), systemImage: "speedometer")
            }
            if let updated = vehicle.lastUpdated {
                fact("Oppdatert", updated.formatted(date: .omitted, time: .standard), systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

    private func fact(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func delayText(_ delay: Double) -> String {
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 { return "I rute" }
        return minutes > 0 ? "\(minutes) min forsinket" : "\(-minutes) min før rute"
    }
}

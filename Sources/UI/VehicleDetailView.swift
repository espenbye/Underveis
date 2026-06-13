import SwiftUI

/// Details for the selected vehicle, shown in the inspector panel.
struct VehicleDetailView: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                facts
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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

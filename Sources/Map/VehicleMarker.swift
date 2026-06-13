import SwiftUI

/// A single vehicle marker: a glass disc showing the public line number, with a small arrow that
/// orbits the disc to indicate the direction of travel (bearing).
struct VehicleMarker: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors
    var isSelected: Bool = false
    /// Whether this vehicle's line is watched — emphasized with a stronger ring and a star badge.
    var isWatched: Bool = false

    private var size: CGFloat { isSelected ? 38 : 30 }

    var body: some View {
        ZStack {
            if let bearing = vehicle.bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(colors.tint.opacity(isSelected ? 0.72 : 0.58))
                    .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
                    .offset(y: -(size / 2 + 6))
                    .rotationEffect(.degrees(bearing), anchor: .center)
            }

            ZStack {
                Circle()
                    .fill(colors.tint.opacity(isSelected ? 0.06 : 0.035))

                Text(vehicle.shortLabel)
                    .font(.system(size: size * 0.42, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 3)
            }
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(colors.tint.opacity(isSelected ? 0.16 : 0.09)), in: Circle())
            .overlay(Circle().strokeBorder(colors.tint.opacity(ringOpacity), lineWidth: ringWidth))
            .shadow(color: .black.opacity(0.22), radius: isSelected ? 4 : 2, y: 1)
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(2)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .animation(.snappy, value: isSelected)
    }

    private var ringOpacity: Double {
        if isSelected { return 0.48 }
        return isWatched ? 0.5 : 0.28
    }

    private var ringWidth: CGFloat {
        if isSelected { return 2 }
        return isWatched ? 2 : 1.25
    }
}

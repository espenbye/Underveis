import SwiftUI

/// A single vehicle glyph: a coloured disc showing the public line number, with a small arrow that
/// orbits the disc to indicate the direction of travel (bearing).
struct VehicleMarker: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors
    var isSelected: Bool = false

    private var size: CGFloat { isSelected ? 42 : 34 }

    var body: some View {
        ZStack {
            if let bearing = vehicle.bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colors.tint)
                    .offset(y: -(size / 2 + 5))
                    .rotationEffect(.degrees(bearing), anchor: .center)
            }

            Circle()
                .fill(colors.tint)
                .overlay {
                    Image(systemName: modeSymbol)
                        .font(.system(size: size * 0.28, weight: .semibold))
                        .foregroundStyle(colors.label.opacity(0.85))
                        .offset(y: -size * 0.22)
                    Text(vehicle.shortLabel)
                        .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                        .foregroundStyle(colors.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 2)
                        .offset(y: size * 0.14)
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 3 : 1.5))
                .shadow(color: .black.opacity(0.35), radius: isSelected ? 5 : 2, y: 1)
        }
        .animation(.snappy, value: isSelected)
    }

    private var modeSymbol: String {
        vehicle.mode?.symbolName ?? "bus.fill"
    }
}

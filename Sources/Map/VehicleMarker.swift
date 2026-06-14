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
            // A directional "sweep" cone fanning out from the disc toward the heading. Drawn under
            // the disc; the bearing is already eased frame-by-frame in `VehiclesModel`, so it turns
            // smoothly. Decorative — never intercepts taps.
            if let bearing = vehicle.bearing {
                HeadingCone()
                    .fill(coneGradient)
                    .frame(width: size * 2.3, height: size * 2.3)
                    .rotationEffect(.degrees(bearing))
                    .allowsHitTesting(false)
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

    /// Line tint near the disc fading to clear at the cone's outer edge.
    private var coneGradient: LinearGradient {
        LinearGradient(
            colors: [colors.tint.opacity(isSelected ? 0.55 : 0.4), .clear],
            startPoint: .center,
            endPoint: .top
        )
    }
}

/// A circular sector ("cone") fanning upward from the centre, used to show a vehicle's heading.
/// Drawn pointing north (up); callers rotate it by the bearing.
struct HeadingCone: Shape {
    /// Total angular width of the cone.
    var spread: Angle = .degrees(46)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90) - spread / 2,
            endAngle: .degrees(-90) + spread / 2,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

import SwiftUI

extension VehicleMode {
    /// Tint used for a vehicle until (or when) its line has no presentation colour.
    var fallbackColor: Color {
        switch self {
        case .bus: .red
        case .coach: .pink
        case .tram: .blue
        case .metro: .orange
        case .rail: .green
        case .ferry: .teal
        case .air: .purple
        case .taxi: .yellow
        }
    }
}

extension Optional where Wrapped == VehicleMode {
    /// Fallback tint for a possibly-unknown mode.
    var fallbackColor: Color {
        self?.fallbackColor ?? .gray
    }
}

import Foundation

/// Mirrors Entur's `VehicleModeEnumeration`. Raw values match the GraphQL enum names exactly,
/// so decoding a vehicle's `mode` string maps straight onto a case.
enum VehicleMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case air = "AIR"
    case bus = "BUS"
    case coach = "COACH"
    case ferry = "FERRY"
    case metro = "METRO"
    case taxi = "TAXI"
    case tram = "TRAM"
    case rail = "RAIL"

    var id: String { rawValue }

    /// User-facing Norwegian label.
    var title: String {
        switch self {
        case .air: "Fly"
        case .bus: "Buss"
        case .coach: "Ekspressbuss"
        case .ferry: "Ferge"
        case .metro: "T-bane"
        case .taxi: "Taxi"
        case .tram: "Trikk"
        case .rail: "Tog"
        }
    }

    /// SF Symbol used for the map glyph and filter rows.
    var symbolName: String {
        switch self {
        case .air: "airplane"
        case .bus: "bus.fill"
        case .coach: "bus.doubledecker.fill"
        case .ferry: "ferry.fill"
        case .metro: "tram.tunnel.fill"
        case .taxi: "car.fill"
        case .tram: "tram.fill"
        case .rail: "train.side.front.car"
        }
    }

    /// Modes offered in the filter, ordered the way they appear in the UI.
    static let selectable: [VehicleMode] = [.bus, .tram, .metro, .rail, .ferry, .coach, .air, .taxi]
}

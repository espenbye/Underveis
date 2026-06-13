import CoreLocation
import Foundation

/// A transit stop place from Entur's National Stop Register (NSR). Static — unlike vehicles, stops
/// don't move, so they aren't interpolated.
struct Stop: Identifiable, Sendable, Equatable {
    /// NSR id, e.g. `NSR:StopPlace:58357`.
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Journey Planner transport modes served (lowercase, e.g. `["tram", "bus"]`).
    let transportModes: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// SF Symbol for the stop's primary mode.
    var symbolName: String {
        switch transportModes.first {
        case "tram": "tram.fill"
        case "metro": "tram.tunnel.fill"
        case "rail": "train.side.front.car"
        case "water": "ferry.fill"
        case "air": "airplane"
        case "cableway", "funicular": "cablecar.fill"
        default: "bus.fill"  // bus, coach, trolleybus, or unspecified
        }
    }
}

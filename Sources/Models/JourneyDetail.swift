import CoreLocation
import Foundation

/// A selected vehicle's whole scheduled trip, fetched from Journey Planner v3 `serviceJourney(id:)`.
/// One `Sendable` value crossing the networking-actor → main-actor boundary, carrying both the route
/// geometry (for the map line) and every call (for the stop list). Line colours arrive inline as hex
/// strings so this stays free of any SwiftUI dependency, like `Departure`.
struct JourneyDetail: Sendable, Equatable {
    let serviceJourneyId: String
    let linePublicCode: String?
    let lineName: String?
    /// Entur presentation hex (no `#`), often `nil` — callers fall back to the mode tint.
    let colourHex: String?
    let textColourHex: String?
    /// Decoded `pointsOnLink`, ordered origin → destination.
    let routePoints: [Coordinate]
    let calls: [JourneyCall]
}

/// One scheduled stop on a journey, from a `serviceJourney`'s `estimatedCalls`.
///
/// All six time fields are kept rather than collapsed: the origin call has no arrival and the
/// terminus no departure, and the list shows aimed-vs-expected separately. `effectiveDeparture` /
/// `effectiveArrival` coalesce them for ordering and "has this stop been passed?" logic.
struct JourneyCall: Identifiable, Sendable, Equatable {
    /// `quayId` + aimed time — stable across polls, so SwiftUI keeps row identity when expected
    /// times refresh.
    let id: String
    let quayId: String
    let quayName: String
    let latitude: Double
    let longitude: Double
    /// Platform / quay public code, e.g. `"C"`. Nil at stops without distinct quays.
    let publicCode: String?
    let aimedArrival: Date?
    let expectedArrival: Date?
    let actualArrival: Date?
    let aimedDeparture: Date?
    let expectedDeparture: Date?
    let actualDeparture: Date?
    let isRealtime: Bool
    let isCancelled: Bool
    /// Entur sets this when the realtime prediction for this call is known to be unreliable.
    let predictionInaccurate: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Best representative departure time (actual → expected → aimed). Nil only at the terminus.
    var effectiveDeparture: Date? { actualDeparture ?? expectedDeparture ?? aimedDeparture }
    /// Best representative arrival time (actual → expected → aimed). Nil only at the origin.
    var effectiveArrival: Date? { actualArrival ?? expectedArrival ?? aimedArrival }
    /// A single time used to order the call and decide whether it's been passed: a real stop has at
    /// least one of these.
    var effectiveTime: Date? { effectiveDeparture ?? effectiveArrival }
    /// Whether the vehicle has confirmably left (or, at the terminus, reached) this stop.
    var hasDeparted: Bool { actualDeparture != nil || actualArrival != nil }
}

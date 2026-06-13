import CoreLocation
import Foundation

/// An immutable snapshot of a single vehicle's live state.
///
/// Coordinates are stored as plain `Double`s (rather than `CLLocationCoordinate2D`) so the value
/// is trivially `Sendable` and `Equatable`, letting it cross the networking-actor → main-actor
/// boundary without ceremony.
struct Vehicle: Identifiable, Sendable, Equatable {
    /// Entur `vehicleId` — stable for the lifetime of a service journey.
    let id: String
    var latitude: Double
    var longitude: Double
    var bearing: Double?
    var speed: Double?
    var delay: Double?
    var mode: VehicleMode?
    /// The scheduled trip this vehicle is running (e.g. `RUT:ServiceJourney:…`). Joins to a
    /// Journey Planner `Departure.serviceJourneyId`, letting a departure row locate its live vehicle.
    var serviceJourneyId: String?
    var lineRef: String?
    var lineName: String?
    var publicCode: String?
    var originName: String?
    var destinationName: String?
    var lastUpdated: Date?
    var expiration: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A short label for the marker — the public line number when known.
    var shortLabel: String {
        publicCode ?? lineName ?? "?"
    }

    /// Whether the server-provided expiry has passed (used for client-side eviction).
    func isExpired(asOf now: Date) -> Bool {
        guard let expiration else { return false }
        return expiration < now
    }
}

import Foundation

/// One upcoming departure from a stop, taken from Journey Planner v3 `estimatedCalls`. A `Sendable`
/// value type so it crosses the networking-actor → main-actor boundary without ceremony, mirroring
/// `Vehicle`. Line colours arrive inline (hex strings) so this carries no SwiftUI dependency.
struct Departure: Identifiable, Sendable, Equatable {
    /// `serviceJourney.id` + aimed time — stable across polls, so SwiftUI keeps row identity.
    let id: String
    /// The scheduled trip (e.g. `RUT:ServiceJourney:…`). Joins to a live `Vehicle.serviceJourneyId`.
    let serviceJourneyId: String
    /// Platform / quay public code, e.g. `"C"`. Nil at stops without distinct quays.
    let quayPublicCode: String?
    /// Public line number, e.g. `"12"`.
    let linePublicCode: String
    let lineName: String?
    /// Journey Planner transport mode (lowercase, e.g. `"tram"`).
    let transportMode: String?
    /// Front text shown on the vehicle, e.g. `"Kjelsås"`.
    let destinationFrontText: String
    let aimedDeparture: Date
    /// Real-time-adjusted departure; falls back to `aimedDeparture` when no prediction parses.
    let expectedDeparture: Date
    /// Set only once the vehicle has actually departed.
    let actualDeparture: Date?
    let isRealtime: Bool
    let isCancelled: Bool
    /// Entur presentation hex (no `#`), e.g. `"0B91EF"`. Nil when the line has no colour.
    let colourHex: String?
    let textColourHex: String?

    /// Signed difference between prediction and timetable. Positive = late, negative = early.
    var delaySeconds: TimeInterval { expectedDeparture.timeIntervalSince(aimedDeparture) }

    /// Punctuality bucket used to colour and annotate the row.
    var status: DepartureStatus {
        if isCancelled { return .cancelled }
        let delay = delaySeconds
        if delay <= -60 { return .early }
        if delay < 60 { return .onTime }
        return .delayed(minutes: Int((delay / 60).rounded()))
    }
}

/// Punctuality of a departure relative to its timetable.
enum DepartureStatus: Equatable {
    case onTime
    case early
    case delayed(minutes: Int)
    case cancelled
}

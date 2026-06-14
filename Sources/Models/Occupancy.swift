import Foundation

/// Mirrors Entur's `OccupancyStatus` enum (SIRI-derived). Raw values match the GraphQL enum names
/// exactly, so decoding a vehicle's `occupancyStatus` string maps straight onto a case. The API's
/// `noData` sentinel is *not* a case — it's normalized to `nil` at the decoding boundary, since the
/// app treats "no occupancy information" and "absent field" identically.
///
/// Kept free of any SwiftUI dependency (like `VehicleMode`); the colour for a `severity` lives in the
/// UI layer.
enum Occupancy: String, Sendable, Equatable {
    case empty
    case manySeatsAvailable
    case seatsAvailable
    case standingAvailable
    case fewSeatsAvailable
    case standingRoomOnly
    case crushedStandingRoomOnly
    case full
    case notAcceptingPassengers

    /// User-facing Norwegian label.
    var title: String {
        switch self {
        case .empty: "Tomt"
        case .manySeatsAvailable: "God plass"
        case .seatsAvailable: "Ledige seter"
        case .standingAvailable: "Ståplass ledig"
        case .fewSeatsAvailable: "Få ledige seter"
        case .standingRoomOnly: "Mest ståplass"
        case .crushedStandingRoomOnly: "Svært fullt"
        case .full: "Fullt"
        case .notAcceptingPassengers: "Tar ikke passasjerer"
        }
    }

    /// A crowd-density glyph that grows with how full the vehicle is.
    var symbolName: String {
        switch self {
        case .empty, .manySeatsAvailable, .seatsAvailable, .standingAvailable: "person.fill"
        case .fewSeatsAvailable: "person.2.fill"
        case .standingRoomOnly, .crushedStandingRoomOnly, .full: "person.3.fill"
        case .notAcceptingPassengers: "person.fill.xmark"
        }
    }

    /// 0 (plenty of room) → 3 (full / closed), used by the UI to pick a tint.
    var severity: Int {
        switch self {
        case .empty, .manySeatsAvailable, .seatsAvailable, .standingAvailable: 0
        case .fewSeatsAvailable: 1
        case .standingRoomOnly: 2
        case .crushedStandingRoomOnly, .full, .notAcceptingPassengers: 3
        }
    }
}

import CoreLocation

/// A plain latitude/longitude pair. Stored as `Double`s (like `Vehicle`/`Stop`) so it's trivially
/// `Sendable` and can cross the networking-actor → main-actor boundary — `CLLocationCoordinate2D`
/// is neither `Sendable` nor `Equatable`, so it never appears in value types.
struct Coordinate: Sendable, Equatable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

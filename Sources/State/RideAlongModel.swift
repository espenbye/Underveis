import MapKit
import Observation

/// Loads the Apple Look Around scene at a followed vehicle's position so the detail panel can show a
/// street-level "ride along" preview. Refetches are throttled by distance — a moving vehicle would
/// otherwise churn the preview every frame. Stays on the main actor throughout: `MKLookAroundScene`
/// is a non-`Sendable` class, and the fetch is cheap to drive from the UI.
@MainActor
@Observable
final class RideAlongModel {
    /// Coverage state for the current coordinate, so the UI can distinguish "still loading" from
    /// "there is no Look Around imagery here".
    enum Availability: Equatable { case idle, loading, available, unavailable }

    /// The displayed scene — bound by `LookAroundPreview` so it updates in place as we refetch.
    var scene: MKLookAroundScene?
    private(set) var availability: Availability = .idle

    private var request: MKLookAroundSceneRequest?
    private var task: Task<Void, Never>?
    private var lastFetched: CLLocationCoordinate2D?

    /// Only refetch once the vehicle has travelled this far (metres). The same displacement also
    /// gives us a reliable direction of travel, so we don't refetch on bearing changes at all.
    private static let refetchDistance: CLLocationDistance = 40
    /// How far ahead of the vehicle (metres) to aim the Look Around camera — see `lookTarget`. Kept
    /// well beyond the captured-panorama spacing so the forward vector dominates and the camera
    /// doesn't flip to face backwards.
    private static let lookAheadDistance: CLLocationDistance = 60

    /// Called as the followed vehicle moves; a cheap no-op until it has moved past `refetchDistance`.
    /// `bearing` only seeds the very first fetch — after that the direction comes from real movement.
    func update(to coordinate: CLLocationCoordinate2D, bearing: Double?) {
        if let last = lastFetched, availability != .idle,
            CLLocation(coordinate: last).distance(from: CLLocation(coordinate: coordinate)) < Self.refetchDistance {
            return
        }
        // Direction of travel: prefer the actual displacement since the last fetch (robust, and always
        // points the way the vehicle is moving); fall back to the reported bearing on the first fetch.
        let heading = lastFetched.map { Self.bearing(from: $0, to: coordinate) } ?? bearing
        fetch(at: coordinate, heading: heading)
    }

    /// Clears everything — used when the selection switches to a different vehicle or the panel closes.
    func reset() {
        task?.cancel()
        request?.cancel()
        task = nil
        request = nil
        scene = nil
        lastFetched = nil
        availability = .idle
    }

    private func fetch(at coordinate: CLLocationCoordinate2D, heading: Double?) {
        task?.cancel()
        request?.cancel()
        lastFetched = coordinate
        if availability == .idle { availability = .loading }

        let request = MKLookAroundSceneRequest(coordinate: Self.lookTarget(from: coordinate, bearing: heading))
        self.request = request
        task = Task { @MainActor [weak self] in
            // A failed/empty request is treated as "no coverage" (nil) — the same outcome the UI
            // shows for an absent scene.
            let scene = try? await request.scene
            guard let self, !Task.isCancelled else { return }
            self.scene = scene
            self.availability = scene == nil ? .unavailable : .available
        }
    }

    /// A point ~`lookAheadDistance` metres ahead of the vehicle along its bearing. `MKLookAroundScene`
    /// has no public heading control, but the initial camera looks from the nearest captured panorama
    /// *toward* the requested coordinate — so aiming the request ahead makes the scene face the
    /// direction of travel. Falls back to the vehicle's own position when the bearing is unknown.
    private static func lookTarget(from coordinate: CLLocationCoordinate2D, bearing: Double?) -> CLLocationCoordinate2D {
        guard let bearing else { return coordinate }
        let radians = bearing * .pi / 180
        let metersPerDegree = 111_320.0
        let dLat = lookAheadDistance * cos(radians) / metersPerDegree
        let dLon = lookAheadDistance * sin(radians) / (metersPerDegree * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }

    /// Initial great-circle bearing (degrees) from one coordinate to another — the direction the
    /// vehicle travelled between two fetches.
    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}

private extension CLLocation {
    convenience init(coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

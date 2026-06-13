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
    private var lastBearing: Double?

    /// Only refetch once the vehicle has travelled this far (metres)…
    private static let refetchDistance: CLLocationDistance = 40
    /// …or turned at least this much (degrees), so the view re-aims through corners and stops.
    private static let refetchBearing: Double = 30
    /// How far ahead of the vehicle (metres) to aim the Look Around camera — see `lookTarget`.
    private static let lookAheadDistance: CLLocationDistance = 20

    /// Called as the followed vehicle moves; a cheap no-op until it has moved past `refetchDistance`
    /// or turned past `refetchBearing`. `bearing` orients the scene along the direction of travel.
    func update(to coordinate: CLLocationCoordinate2D, bearing: Double?) {
        if let last = lastFetched, availability != .idle {
            let movedFar = CLLocation(coordinate: last)
                .distance(from: CLLocation(coordinate: coordinate)) >= Self.refetchDistance
            let turned = Self.bearingDelta(lastBearing, bearing) >= Self.refetchBearing
            if !movedFar && !turned { return }
        }
        fetch(at: coordinate, bearing: bearing)
    }

    /// Clears everything — used when the selection switches to a different vehicle or the panel closes.
    func reset() {
        task?.cancel()
        request?.cancel()
        task = nil
        request = nil
        scene = nil
        lastFetched = nil
        lastBearing = nil
        availability = .idle
    }

    private func fetch(at coordinate: CLLocationCoordinate2D, bearing: Double?) {
        task?.cancel()
        request?.cancel()
        lastFetched = coordinate
        lastBearing = bearing
        if availability == .idle { availability = .loading }

        let request = MKLookAroundSceneRequest(coordinate: Self.lookTarget(from: coordinate, bearing: bearing))
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

    /// Shortest absolute difference between two headings (degrees), or 0 when either is unknown.
    private static func bearingDelta(_ a: Double?, _ b: Double?) -> Double {
        guard let a, let b else { return 0 }
        let delta = abs((a - b).truncatingRemainder(dividingBy: 360))
        return delta > 180 ? 360 - delta : delta
    }
}

private extension CLLocation {
    convenience init(coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

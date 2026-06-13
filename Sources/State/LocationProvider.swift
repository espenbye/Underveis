import CoreLocation
import Observation

/// Thin Core Location wrapper used to centre the initial map camera on the user. Works the same
/// on iOS and macOS (both support when-in-use authorization).
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Increments on every fix — gives views an `Equatable` value to observe via `onChange`
    /// (`CLLocationCoordinate2D` isn't `Equatable`).
    private(set) var fixCount = 0

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Asks for permission (if undetermined) and starts a location fix.
    func requestAndStart() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate
    // Callbacks arrive on the thread the manager was created on — the main thread here, since this
    // object is @MainActor — so `assumeIsolated` is safe.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationStatus = status
            if Self.isAuthorized(status) {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        let latitude = latest.coordinate.latitude
        let longitude = latest.coordinate.longitude
        MainActor.assumeIsolated {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            fixCount += 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: we simply fall back to the default camera.
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
            return status == .authorizedAlways
        #else
            return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }
}

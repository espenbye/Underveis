import Foundation

/// Value sent as `ET-Client-Name` to Entur's APIs. Entur asks every caller to identify itself, and
/// deriving it from the bundle identifier means forks automatically send their own name.
enum EnturClientName {
    static let `default`: String = Bundle.main.bundleIdentifier ?? "underveis"
}

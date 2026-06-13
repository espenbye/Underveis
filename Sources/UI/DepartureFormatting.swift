import SwiftUI

/// Presentation helpers shared by the departure board (`StopDetailView`) and the nearby previews
/// (`NearbyView`). Kept in the UI layer — not on the `Departure` model in `Models/` — so the
/// Norwegian on-screen copy stays out of the value type.
extension Departure {
    /// Short countdown for the right-hand column / inline previews: "Avreist" once it has left,
    /// "Innstilt" if cancelled, "Nå" under a minute out, "N min" within the hour, otherwise the clock
    /// time ("kl. 14:05"). `now` is passed in so callers can drive a live, ticking value.
    func countdownLabel(now: Date) -> String {
        if actualDeparture != nil { return "Avreist" }
        if isCancelled { return "Innstilt" }
        let remaining = expectedDeparture.timeIntervalSince(now)
        if remaining < 60 { return "Nå" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "kl. " + expectedDeparture.formatted(date: .omitted, time: .shortened)
    }

    /// Tint for the countdown: grey once departed, red cancelled, orange when running late, green
    /// otherwise. `AnyShapeStyle` so `.secondary` and concrete colours can share one return type.
    var countdownTint: AnyShapeStyle {
        if actualDeparture != nil { return AnyShapeStyle(.secondary) }
        switch status {
        case .cancelled: return AnyShapeStyle(Color.red)
        case .delayed: return AnyShapeStyle(Color.orange)
        case .onTime, .early: return AnyShapeStyle(Color.green)
        }
    }

    /// Destination to show: the vehicle's front text, falling back to the line name.
    var displayDestination: String {
        destinationFrontText.isEmpty ? (lineName ?? "Avgang") : destinationFrontText
    }
}

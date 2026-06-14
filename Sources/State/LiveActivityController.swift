import Foundation
import Observation

#if os(iOS)
    import ActivityKit
#endif

/// Starts, updates, and ends the "next departure" Live Activity. Owned as `@State` by `RootView`
/// (one instance, the same lifecycle pattern as `ReminderStore`). App-driven only — no push tokens
/// (`pushType: nil`) — so the countdown advances locally on the Lock Screen / Dynamic Island, pinned
/// to the real-time prediction at the moment the user starts it (mirroring `ReminderStore`'s
/// deliberate simplification: it doesn't chase later delay changes).
///
/// On macOS (no ActivityKit) the type compiles as a no-op shell so `RootView` stays platform-clean.
@MainActor
@Observable
final class LiveActivityController {

    /// `Departure.id`s with an active Live Activity, so the board can show a filled/outline toggle.
    private(set) var activeDepartureIDs: Set<String> = []
    /// True once the user has switched Live Activities off in Settings.
    private(set) var activitiesDisabled = false

    func isActive(_ departure: Departure) -> Bool {
        activeDepartureIDs.contains(departure.id)
    }

    /// Rehydrates from any still-running activities (e.g. after relaunch) and refreshes the auth flag.
    /// Cheap; call when the app appears. `Activity` isn't `Sendable`, so we never store the instances —
    /// only their `departureID`s (the `Activity.activities` lookup is how `end` finds them again).
    func refresh() {
        #if os(iOS)
            activitiesDisabled = !ActivityAuthorizationInfo().areActivitiesEnabled
            var live: Set<String> = []
            for activity in Activity<DepartureActivityAttributes>.activities
            where activity.activityState == .active || activity.activityState == .stale {
                live.insert(activity.attributes.departureID)
            }
            activeDepartureIDs = live
        #endif
    }

    /// Starts or ends the Live Activity for a departure (idempotent per `Departure.id`).
    func toggle(_ departure: Departure, stopName: String) {
        #if os(iOS)
            if activeDepartureIDs.contains(departure.id) {
                end(departure)
            } else {
                start(departure, stopName: stopName)
            }
        #endif
    }

    #if os(iOS)
        private func start(_ departure: Departure, stopName: String) {
            // Nothing to count down to once the trip has departed or been cancelled.
            guard departure.actualDeparture == nil, !departure.isCancelled,
                departure.expectedDeparture > Date()
            else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                activitiesDisabled = true
                return
            }

            let attributes = DepartureActivityAttributes(
                departureID: departure.id,
                linePublicCode: departure.linePublicCode,
                destination: departure.displayDestination,
                stopName: stopName,
                colourHex: departure.colourHex,
                textColourHex: departure.textColourHex
            )
            let state = DepartureActivityAttributes.ContentState(
                expectedDeparture: departure.expectedDeparture,
                delayMinutes: max(0, Int((departure.delaySeconds / 60).rounded())),
                isCancelled: departure.isCancelled
            )
            // Go stale shortly after departure so the system can retire the activity on its own.
            let staleDate = departure.expectedDeparture.addingTimeInterval(120)
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: staleDate),
                    pushType: nil
                )
                activeDepartureIDs.insert(departure.id)
            } catch {
                // Starting can fail (e.g. too many active activities); leave state unchanged.
            }
        }

        private func end(_ departure: Departure) {
            let id = departure.id
            activeDepartureIDs.remove(id)
            // Capture only the `id` (a Sendable String) — the non-Sendable activity is looked up and
            // ended inside the task, so nothing crosses the isolation boundary.
            Task {
                for activity in Activity<DepartureActivityAttributes>.activities
                where activity.attributes.departureID == id {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    #endif
}

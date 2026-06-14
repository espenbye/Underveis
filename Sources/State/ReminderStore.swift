import Foundation
import Observation
import UserNotifications

/// Schedules and tracks local "departure reminders": a notification fired a configurable number of
/// minutes before a chosen departure leaves its stop. Owned as `@State` by `RootView` (one instance,
/// the same lifecycle pattern as `LocationProvider`/`DeparturesModel`).
///
/// The system's pending-notification set is the source of truth that survives relaunches; `refresh()`
/// rehydrates `reminderIDs` from it. Each reminder uses the `Departure.id` (serviceJourney + aimed
/// time) as its request identifier, so a departure maps to at most one reminder and toggling is
/// idempotent. The schedule is pinned to the departure's real-time prediction *at the moment of
/// tapping* — it doesn't follow later delay changes (a deliberate MVP simplification).
@MainActor
@Observable
final class ReminderStore {

    /// `Departure.id`s with a pending local notification. Drives the filled/outline bell in the board.
    private(set) var reminderIDs: Set<String> = []
    /// True once the user has refused notification permission, so the UI can explain why nothing fires.
    private(set) var permissionDenied = false

    private let center = UNUserNotificationCenter.current()
    private let foregroundDelegate = ForegroundNotificationDelegate()

    /// Minutes-before-departure used when the user hasn't picked a value in Innstillinger.
    static let defaultLeadMinutes = 5
    /// `@AppStorage` key shared with `SettingsView`'s lead-time picker.
    static let leadMinutesKey = "reminderLeadMinutes"

    init() {
        // Present reminder banners even when Underveis is foremost (a reminder you're staring at is
        // still useful), rather than the default of suppressing them in the foreground.
        center.delegate = foregroundDelegate
    }

    /// Chosen lead time (minutes), read straight from `UserDefaults` like `VehiclesModel` does for the
    /// Filtre selection — the store isn't a View, so it can't use `@AppStorage`. Zero means "unset".
    var leadMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.leadMinutesKey)
        return stored > 0 ? stored : Self.defaultLeadMinutes
    }

    func isReminderSet(for departure: Departure) -> Bool {
        reminderIDs.contains(departure.id)
    }

    /// Rehydrates `reminderIDs` from the notifications still pending with the system (fired ones drop
    /// out automatically) and refreshes the denied-permission flag. Cheap; call when a board opens.
    func refresh() async {
        let pending = await center.pendingNotificationRequests()
        reminderIDs = Set(pending.map(\.identifier))
        let settings = await center.notificationSettings()
        permissionDenied = settings.authorizationStatus == .denied
    }

    /// Toggles a reminder for a departure: cancels an existing one, or (requesting authorization on
    /// first use) schedules a new notification `leadMinutes` before the predicted departure.
    func toggle(_ departure: Departure, stopName: String) async {
        if reminderIDs.contains(departure.id) {
            cancel(departure)
            return
        }
        guard await ensureAuthorized() else { return }
        schedule(departure, stopName: stopName)
    }

    func cancel(_ departure: Departure) {
        center.removePendingNotificationRequests(withIdentifiers: [departure.id])
        reminderIDs.remove(departure.id)
    }

    private func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            permissionDenied = true
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            permissionDenied = !granted
            return granted
        @unknown default:
            return false
        }
    }

    private func schedule(_ departure: Departure, stopName: String) {
        // Nothing to remind about once the trip has departed.
        let now = Date()
        guard departure.actualDeparture == nil, !departure.isCancelled, departure.expectedDeparture > now
        else { return }

        // Fire `leadMinutes` ahead, but never in the past: if the lead window has already elapsed (the
        // bus leaves sooner than the lead time) fall back to firing right away.
        let lead = TimeInterval(leadMinutes * 60)
        let fireDate = departure.expectedDeparture.addingTimeInterval(-lead)
        let interval = max(fireDate.timeIntervalSince(now), 1)

        let content = UNMutableNotificationContent()
        content.title = departure.reminderTitle
        content.body = departure.reminderBody(stopName: stopName)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: departure.id, content: content, trigger: trigger)
        center.add(request)
        reminderIDs.insert(departure.id)
    }
}

/// Foreground presenter for departure reminders. Stateless, so safe to share across executors; held
/// strongly by `ReminderStore` because `UNUserNotificationCenter.delegate` is `weak`.
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

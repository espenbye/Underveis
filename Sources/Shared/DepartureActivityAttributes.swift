#if os(iOS)
    import ActivityKit
    import Foundation

    /// Static + dynamic content for the "next departure" Live Activity. The static fields describe the
    /// trip (line, destination, stop, colours); the `ContentState` carries what changes over time — the
    /// target departure `Date` (which the views render as a self-advancing countdown) and the
    /// punctuality flags. Shared by the app (which starts / ends activities, see `LiveActivityController`)
    /// and the widget extension (which renders them, see `DepartureActivityWidget`).
    ///
    /// iOS-only: Live Activities don't exist on macOS, and the widget extension is iOS-only.
    struct DepartureActivityAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            /// Real-time-predicted departure instant; the countdown ticks toward this locally.
            var expectedDeparture: Date
            /// Minutes late versus timetable (0 when on time or early), shown as a small note.
            var delayMinutes: Int
            var isCancelled: Bool
        }

        /// `Departure.id`, so the app can map a running activity back to its departure after relaunch.
        let departureID: String
        /// Public line number, e.g. "12".
        let linePublicCode: String
        /// Front text / destination, e.g. "Kjelsås".
        let destination: String
        let stopName: String
        /// Entur presentation hex (no `#`) for the line badge, when known.
        let colourHex: String?
        let textColourHex: String?
    }
#endif

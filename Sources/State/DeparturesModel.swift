import Observation

/// Drives the stop-departures view: polls Journey Planner for the selected stop's real-time
/// departures and runs a once-a-second ticker so the on-screen countdowns stay live between fetches.
///
/// Owned as `@State` by `RootView` (one instance, reused as the selection changes) — the same
/// lifecycle pattern as `LocationProvider`. All state lives on the main actor; the only cross-actor
/// hop is the `await journeyPlanner.departures(_:)` call, which returns a `Sendable` value.
@MainActor
@Observable
final class DeparturesModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var departures: [Departure] = []
    private(set) var stopName: String = ""
    /// SF Symbol for the selected stop's primary mode, shown in the header.
    private(set) var stopSymbol: String = "bus.fill"
    private(set) var loadState: LoadState = .idle
    /// Bumped every second; views read it to recompute relative countdowns without storing a `Date`.
    private(set) var tickID: Int = 0
    /// Seconds until the next network refresh, surfaced in the footer ("Oppdateres om N s").
    private(set) var nextRefreshIn: Int = pollInterval

    private let journeyPlanner: JourneyPlannerClient
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// Seconds between network refreshes. The countdown still ticks every second locally in between.
    private static let pollInterval = 30

    init(journeyPlanner: JourneyPlannerClient = JourneyPlannerClient()) {
        self.journeyPlanner = journeyPlanner
    }

    /// Begin tracking a stop: show its name immediately, then poll departures + start the ticker.
    func select(stop: Stop) {
        cancelTasks()
        stopName = stop.name
        stopSymbol = stop.symbolName
        departures = []
        loadState = .loading
        nextRefreshIn = Self.pollInterval
        startPolling(stopID: stop.id)
        startTicking()
    }

    /// Stop tracking and reset — called when the stop is deselected or the panel dismissed.
    func deselect() {
        cancelTasks()
        departures = []
        stopName = ""
        stopSymbol = "bus.fill"
        loadState = .idle
        nextRefreshIn = Self.pollInterval
    }

    private func startPolling(stopID: String) {
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let result = await self.journeyPlanner.departures(stopPlaceID: stopID)
                guard !Task.isCancelled else { return }

                if let result {
                    if !result.stopName.isEmpty { self.stopName = result.stopName }
                    self.departures = result.departures
                    self.loadState = .loaded
                } else if self.loadState == .loading {
                    // Only surface an error on the initial load; on a refresh failure keep the
                    // last-known departures on screen rather than blanking the list.
                    self.loadState = .failed("Kunne ikke laste avganger.")
                }

                self.nextRefreshIn = Self.pollInterval
                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
        }
    }

    private func startTicking() {
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tickID &+= 1
                if self.nextRefreshIn > 0 { self.nextRefreshIn -= 1 }
            }
        }
    }

    private func cancelTasks() {
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
    }
}

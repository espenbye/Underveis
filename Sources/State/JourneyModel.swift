import CoreLocation
import Observation

/// Drives the "journey view + route line": fetches a selected vehicle's whole scheduled trip from
/// Journey Planner, then keeps its live call times fresh. The route geometry is static per journey,
/// so it's decoded once and the cached `CLLocationCoordinate2D` line is held stable across refreshes;
/// only the call times re-poll. A once-a-second tick keeps the list countdowns moving in between.
///
/// Owned as `@State` by `RootView` (one instance, reused as the selection changes) — the same
/// lifecycle pattern as `DeparturesModel`. The cached `CLLocationCoordinate2D` array never crosses an
/// actor boundary (it stays here on the main actor), which is why this is the one place the app holds
/// `CLLocationCoordinate2D` in stored state.
@MainActor
@Observable
final class JourneyModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where a call sits relative to the vehicle's progress, used to style the list and map dots.
    enum CallStatus { case passed, next, upcoming }

    private(set) var detail: JourneyDetail?
    /// The route line, pre-mapped to MapKit coordinates once when the journey first loads and held
    /// stable across polls (geometry doesn't change), so the `Map` body never rebuilds it per frame.
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    private(set) var loadState: LoadState = .idle
    /// Bumped every second; views read it to recompute relative countdowns without storing a `Date`.
    private(set) var tickID: Int = 0

    /// All calls on the loaded journey (empty until loaded), for convenience at the call site.
    var calls: [JourneyCall] { detail?.calls ?? [] }

    private let journeyPlanner: JourneyPlannerClient
    /// The service journey currently loaded/loading — guards against re-fetching when the same vehicle
    /// is re-selected (e.g. interpolation re-triggers selection).
    private var loadedID: String?
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// Seconds between call-time refreshes. The countdown still ticks every second locally in between.
    private static let pollInterval = 30

    init(journeyPlanner: JourneyPlannerClient = JourneyPlannerClient()) {
        self.journeyPlanner = journeyPlanner
    }

    /// Begin showing a service journey: fetch its route + calls, then poll the calls. A no-op when the
    /// same journey is already loaded, so vehicle re-selection / movement doesn't refetch.
    func select(serviceJourneyId id: String) {
        guard id != loadedID else { return }
        cancelTasks()
        loadedID = id
        detail = nil
        routeCoordinates = []
        loadState = .loading
        startPolling(serviceJourneyId: id)
        startTicking()
    }

    /// Stop tracking and reset — called when the vehicle is deselected or has no service journey.
    func deselect() {
        cancelTasks()
        loadedID = nil
        detail = nil
        routeCoordinates = []
        loadState = .idle
    }

    // MARK: - Classification (pure reads; safe to call from view bodies each frame)

    /// The id of the next stop the vehicle is heading to — the map highlight.
    func nextStopID(for vehicle: Vehicle?) -> String? {
        guard let index = nextIndex(for: vehicle, now: Date()) else { return nil }
        return detail?.calls[index].id
    }

    /// The next call the vehicle is heading to — its whole record (name + times), for the live status
    /// card. Nil once every call is behind us (at/after the terminus) or before the journey loads.
    func nextCall(for vehicle: Vehicle?) -> JourneyCall? {
        guard let calls = detail?.calls, let index = nextIndex(for: vehicle, now: Date()),
            calls.indices.contains(index)
        else { return nil }
        // Suppress the terminus when it's already in the past (nextIndex clamps to the last call).
        if index == calls.count - 1, let time = calls[index].effectiveTime, time < Date() { return nil }
        return calls[index]
    }

    /// Per-call status keyed by call id, so a row can style itself without knowing its position.
    func statuses(for vehicle: Vehicle?) -> [String: CallStatus] {
        guard let calls = detail?.calls, !calls.isEmpty else { return [:] }
        let next = nextIndex(for: vehicle, now: Date())
        var result: [String: CallStatus] = [:]
        result.reserveCapacity(calls.count)
        for (i, call) in calls.enumerated() {
            if let next {
                result[call.id] = i < next ? .passed : (i == next ? .next : .upcoming)
            } else {
                result[call.id] = .passed  // whole journey is behind us
            }
        }
        return result
    }

    /// Index of the next not-yet-passed call. Time is authoritative (it matches the realtime feed and
    /// the list); the live vehicle position may only *advance* the pointer, never rewind it — routes
    /// can pass close to earlier stops, so position alone is unreliable.
    private func nextIndex(for vehicle: Vehicle?, now: Date) -> Int? {
        guard let calls = detail?.calls, !calls.isEmpty else { return nil }

        // Time-derived: first call whose effective time is still in the future. If every call is in
        // the past, the vehicle is at/near the terminus.
        let timeIndex =
            calls.firstIndex { call in
                guard let time = call.effectiveTime else { return true }  // no time → treat as upcoming
                return time >= now
            } ?? (calls.count - 1)

        guard let vehicle else { return timeIndex }

        // Advance-only refinement: if the nearest call to the live position is further along than the
        // time-derived one, the bus is running ahead of the last poll — trust the position.
        let here = vehicle.coordinate
        guard
            let nearest = calls.indices.min(by: {
                planarDistanceSq(calls[$0], to: here) < planarDistanceSq(calls[$1], to: here)
            })
        else { return timeIndex }
        return max(timeIndex, nearest)
    }

    /// Cheap squared planar distance (longitude scaled by latitude) — only used to compare which call
    /// is nearest, so absolute units don't matter.
    private func planarDistanceSq(_ call: JourneyCall, to point: CLLocationCoordinate2D) -> Double {
        let dLat = call.latitude - point.latitude
        let dLon = (call.longitude - point.longitude) * cos(point.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    // MARK: - Polling

    private func startPolling(serviceJourneyId id: String) {
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let result = await self.journeyPlanner.serviceJourney(id: id)
                guard !Task.isCancelled else { return }

                if let result {
                    // Decode the route line once, on the first successful load, and keep it stable —
                    // geometry is fixed for a journey, so later polls only refresh the call times.
                    if self.routeCoordinates.isEmpty {
                        self.routeCoordinates = result.routePoints.map(\.clCoordinate)
                    }
                    self.detail = result
                    self.loadState = .loaded
                } else if self.loadState == .loading {
                    // Only surface an error on the initial load; on a refresh failure keep the
                    // last-known journey on screen rather than blanking it.
                    self.loadState = .failed("Kunne ikke laste ruten.")
                }

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

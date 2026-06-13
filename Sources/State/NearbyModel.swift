import CoreLocation
import MapKit
import Observation

/// Drives the "Nær meg" sheet: finds transit stops around the user, sorts them by distance, and
/// previews each stop's next departures. Polls every 30 s while open and runs a once-a-second ticker
/// so the inline countdowns stay live in between — the same lifecycle shape as `DeparturesModel`.
///
/// All state lives on the main actor; the only cross-actor hops are the `JourneyPlannerClient` calls,
/// which return `Sendable` values.
@MainActor
@Observable
final class NearbyModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
    }

    private(set) var nearby: [NearbyStop] = []
    private(set) var loadState: LoadState = .idle
    /// Bumped every second; views read it to recompute relative countdowns without storing a `Date`.
    private(set) var tickID: Int = 0

    private let journeyPlanner: JourneyPlannerClient
    /// Latest known user location, updated as fixes arrive.
    private var coordinate: CLLocationCoordinate2D?
    /// Location used for the last fetch — we refetch only after the user moves meaningfully from it.
    private var lastFetchCoordinate: CLLocationCoordinate2D?
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// Seconds between network refreshes. The countdown still ticks every second locally in between.
    private static let pollInterval = 30
    /// Edge length (metres) of the square search box centred on the user — a comfortable walking area.
    private static let searchMeters: CLLocationDistance = 2000
    /// How many of the nearest stops to show (and fetch departures for).
    private static let stopCount = 8
    /// Refetch when the user has moved at least this far from the last fetch location.
    private static let refetchDistance: CLLocationDistance = 150

    init(journeyPlanner: JourneyPlannerClient = JourneyPlannerClient()) {
        self.journeyPlanner = journeyPlanner
    }

    /// Begin tracking nearby stops around `coordinate` (nil until the first fix arrives). Starts the
    /// ticker immediately; kicks the first fetch + poll as soon as a coordinate is available.
    func start(near coordinate: CLLocationCoordinate2D?) {
        cancelTasks()
        self.coordinate = coordinate
        lastFetchCoordinate = nil
        nearby = []
        startTicking()
        if coordinate != nil {
            loadState = .loading
            startPolling()
        } else {
            loadState = .idle
        }
    }

    /// Feed a fresh location fix. Triggers a refetch on the first fix or after meaningful movement.
    func update(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        guard let last = lastFetchCoordinate else {
            if pollTask == nil {  // first fix since opening with no location
                loadState = .loading
                startPolling()
            }
            return
        }
        if distance(from: last, to: coordinate) >= Self.refetchDistance {
            startPolling()
        }
    }

    /// Stop tracking and reset — called when the sheet is dismissed.
    func stop() {
        cancelTasks()
        nearby = []
        loadState = .idle
        coordinate = nil
        lastFetchCoordinate = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let coordinate = self.coordinate else { return }
                await self.refresh(around: coordinate)
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
        }
    }

    private func refresh(around coordinate: CLLocationCoordinate2D) async {
        lastFetchCoordinate = coordinate
        let box = BoundingBox(
            region: MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: Self.searchMeters,
                longitudinalMeters: Self.searchMeters
            )
        )

        let stops = await journeyPlanner.stopPlaces(in: box)
        guard !Task.isCancelled else { return }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = stops
            .map { stop in
                (stop: stop, distance: origin.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)))
            }
            .sorted { $0.distance < $1.distance }
            .prefix(Self.stopCount)

        guard !nearest.isEmpty else {
            // `stopPlaces` returns `[]` on a network failure too, so only blank on the initial load
            // (genuinely no stops nearby); on a later poll keep the last list rather than clearing it.
            if loadState != .loaded {
                nearby = []
                loadState = .loaded
            }
            return
        }

        // Fetch the nearest stops' departures concurrently. Bind a local actor reference first so the
        // @Sendable task closures don't capture this @MainActor model.
        let planner = journeyPlanner
        let departuresByStop = await withTaskGroup(of: (String, [Departure]).self) { group in
            for entry in nearest {
                let id = entry.stop.id
                group.addTask { (id, await planner.departures(stopPlaceID: id)?.departures ?? []) }
            }
            var map: [String: [Departure]] = [:]
            for await (id, departures) in group { map[id] = departures }
            return map
        }
        guard !Task.isCancelled else { return }

        nearby = nearest.map { entry in
            NearbyStop(
                stop: entry.stop,
                distanceMeters: entry.distance,
                departures: departuresByStop[entry.stop.id] ?? []
            )
        }
        loadState = .loaded
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

    private func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// One nearby stop with its straight-line distance from the user and a preview of its next
/// departures. A `Sendable` value type, like `Stop` / `Departure`, so it crosses the
/// networking-actor → main-actor boundary cleanly.
struct NearbyStop: Identifiable, Sendable, Equatable {
    let stop: Stop
    /// Straight-line distance from the user, in metres (a conventional proxy for walking distance).
    let distanceMeters: Double
    let departures: [Departure]
    var id: String { stop.id }
}

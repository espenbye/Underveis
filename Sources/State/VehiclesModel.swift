import MapKit
import Observation

/// The app's central state. Owns the live vehicle set, tracks the map viewport, applies the mode
/// filter, and bridges the networking actor's `AsyncStream`s onto the main actor for SwiftUI.
///
/// Movement smoothing: the network gives discrete position jumps. `targets` holds the latest truth;
/// `vehicles` holds the *displayed* state, which an interpolation ticker eases toward `targets`
/// every frame so markers glide instead of snapping. (SwiftUI `Map` doesn't tween an annotation's
/// placement, so we animate the coordinate ourselves.)
@MainActor
@Observable
final class VehiclesModel {
    /// Displayed (interpolated) vehicles the map draws, keyed by `vehicleId`.
    private(set) var vehicles: [String: Vehicle] = [:]
    /// Which modes are shown. A single enabled mode is pushed to the server; multiple/all are
    /// filtered client-side.
    private(set) var enabledModes: Set<VehicleMode> = [.bus]
    private(set) var status: ConnectionStatus = .idle

    /// Transit stops in the visible area (only populated when zoomed in — see `stopsMaxSpan`).
    private(set) var stops: [Stop] = []
    private(set) var showStops = true

    /// Service-journey ids of vehicles currently drawn on the map (mode-filtered). The stop
    /// departures view reads this to mark which rows have a live, tappable vehicle. Reassigned only
    /// when membership changes, so it never churns on the per-frame interpolation path.
    private(set) var liveServiceJourneyIDs: Set<String> = []

    let lineColors: LineColorStore

    /// Latest reported truth, eased toward by the interpolation ticker.
    private var targets: [String: Vehicle] = [:]

    private let client: EnturVehiclesClient
    private let journeyPlanner: JourneyPlannerClient
    private var currentBox: BoundingBox?
    private var viewportTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var evictionTask: Task<Void, Never>?
    private var interpolationTask: Task<Void, Never>?
    private var stopsTask: Task<Void, Never>?

    /// Hide stops when zoomed out wider than this (degrees latitude) — they'd be too dense to read.
    private static let stopsMaxSpan = 0.06

    // Easing tuned for ~30 fps: a fraction of the remaining distance closed each frame, settling in
    // roughly half a second while staying smooth.
    private static let frameInterval: Duration = .milliseconds(33)
    private static let positionLerp = 0.16
    private static let bearingLerp = 0.22
    private static let positionEpsilon = 1e-6  // ~0.1 m in latitude degrees → snap when this close

    init(
        lineColors: LineColorStore,
        client: EnturVehiclesClient = EnturVehiclesClient(),
        journeyPlanner: JourneyPlannerClient = JourneyPlannerClient()
    ) {
        self.lineColors = lineColors
        self.client = client
        self.journeyPlanner = journeyPlanner
    }

    /// Vehicles to draw: those whose mode is currently enabled.
    var visibleVehicles: [Vehicle] {
        let modes = enabledModes
        return vehicles.values.filter { vehicle in
            guard let mode = vehicle.mode else { return false }
            return modes.contains(mode)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard consumeTask == nil else { return }

        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await batch in client.updates {
                merge(batch)
            }
        }
        statusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await newStatus in client.status {
                status = newStatus
            }
        }
        evictionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.evictStale()
            }
        }
        interpolationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: VehiclesModel.frameInterval)
                self?.stepInterpolation()
            }
        }
    }

    func stop() {
        viewportTask?.cancel()
        consumeTask?.cancel()
        statusTask?.cancel()
        evictionTask?.cancel()
        interpolationTask?.cancel()
        stopsTask?.cancel()
        viewportTask = nil
        consumeTask = nil
        statusTask = nil
        evictionTask = nil
        interpolationTask = nil
        stopsTask = nil
        Task { await client.stop() }
    }

    // MARK: - Viewport

    /// Debounced entry point from the map's camera-change callback.
    func updateViewport(_ region: MKCoordinateRegion) {
        let box = BoundingBox(region: region).expanded(by: 0.15)
        viewportTask?.cancel()
        viewportTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await applyViewport(box)
        }
    }

    private func applyViewport(_ box: BoundingBox) async {
        if let current = currentBox, current.approximatelyEquals(box, tolerance: 0.0005) { return }
        currentBox = box
        pruneOutside(box)
        await client.setViewport(box, mode: subscriptionMode)
        merge(await client.snapshot(box: box, mode: subscriptionMode))
        refreshStops(for: box)
    }

    // MARK: - Stops

    func setShowStops(_ enabled: Bool) {
        showStops = enabled
        if let box = currentBox {
            refreshStops(for: box)
        }
    }

    /// Fetches stops for the box, but only when stops are enabled and we're zoomed in enough to keep
    /// them legible; otherwise clears them.
    private func refreshStops(for box: BoundingBox) {
        stopsTask?.cancel()
        guard showStops, box.latitudeSpan <= Self.stopsMaxSpan else {
            if !stops.isEmpty { stops = [] }
            return
        }
        stopsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let fetched = await journeyPlanner.stopPlaces(in: box)
            guard !Task.isCancelled else { return }
            stops = fetched
        }
    }

    // MARK: - Mode filter

    func setMode(_ mode: VehicleMode, enabled: Bool) {
        if enabled {
            enabledModes.insert(mode)
        } else {
            enabledModes.remove(mode)
        }
        let allowed = enabledModes
        targets = targets.filter { allowed.contains($0.value.mode ?? .bus) }
        vehicles = vehicles.filter { targets[$0.key] != nil }
        refreshLiveServiceJourneys()

        guard let box = currentBox else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await client.setViewport(box, mode: subscriptionMode)
            merge(await client.snapshot(box: box, mode: subscriptionMode))
        }
    }

    // MARK: - Merging / interpolation / eviction

    private func merge(_ batch: [Vehicle]) {
        guard !batch.isEmpty else { return }
        for vehicle in batch {
            targets[vehicle.id] = vehicle
            if vehicles[vehicle.id] == nil {
                vehicles[vehicle.id] = vehicle  // first sighting: place immediately
            }
        }
        lineColors.enrich(lineRefs: batch.compactMap(\.lineRef))
        refreshLiveServiceJourneys()
    }

    /// Recomputes `liveServiceJourneyIDs` from the mode-filtered target set, assigning only when the
    /// membership actually changes. Called from the membership-mutating paths (merge / prune / evict /
    /// mode change) — never from `stepInterpolation`, which only eases positions.
    private func refreshLiveServiceJourneys() {
        // Derive from `visibleVehicles` (the mode-filtered, on-screen set) so a row is only marked
        // live when its vehicle is actually tappable on the map.
        let ids = Set(visibleVehicles.lazy.compactMap(\.serviceJourneyId))
        if ids != liveServiceJourneyIDs { liveServiceJourneyIDs = ids }
    }

    /// One animation frame: ease each displayed vehicle toward its target position and bearing, and
    /// mirror any changed metadata. Publishes only when something actually moved/changed.
    private func stepInterpolation() {
        guard !targets.isEmpty else { return }
        var next = vehicles
        var changed = false

        for (id, target) in targets {
            guard let current = next[id] else {
                next[id] = target
                changed = true
                continue
            }

            // Start from the target (carries all metadata + final position), then override the
            // position/bearing with eased values while they're still far from the target.
            var shown = target

            let deltaLat = target.latitude - current.latitude
            let deltaLon = target.longitude - current.longitude
            if abs(deltaLat) > Self.positionEpsilon || abs(deltaLon) > Self.positionEpsilon {
                shown.latitude = current.latitude + deltaLat * Self.positionLerp
                shown.longitude = current.longitude + deltaLon * Self.positionLerp
            }

            if let targetBearing = target.bearing {
                let shownBearing = current.bearing ?? targetBearing
                let delta = Self.angularDelta(from: shownBearing, to: targetBearing)
                if abs(delta) > 0.5 {
                    shown.bearing = Self.normalizedAngle(shownBearing + delta * Self.bearingLerp)
                }
            }

            if shown != current {
                next[id] = shown
                changed = true
            }
        }

        if changed { vehicles = next }
    }

    private func pruneOutside(_ box: BoundingBox) {
        targets = targets.filter { box.contains(latitude: $0.value.latitude, longitude: $0.value.longitude) }
        vehicles = vehicles.filter { targets[$0.key] != nil }
        refreshLiveServiceJourneys()
    }

    private func evictStale() {
        let now = Date()
        targets = targets.filter { !$0.value.isExpired(asOf: now) }
        vehicles = vehicles.filter { targets[$0.key] != nil }
        refreshLiveServiceJourneys()
    }

    private var subscriptionMode: VehicleMode? {
        enabledModes.count == 1 ? enabledModes.first : nil
    }

    // MARK: - Angle helpers

    /// Shortest signed difference (degrees) from one heading to another, in `-180...180`.
    private static func angularDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

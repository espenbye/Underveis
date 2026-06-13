import MapKit
import SwiftUI

/// App root: a `TabView` (sidebar on Mac/iPad, floating tab bar on iPhone) over three destinations —
/// the live map ("Kart"), nearby stops ("Nær meg"), and the user's saved stops/lines ("Lagret").
/// The map tab owns the camera, selection, and detail inspector/sheet; the browse tabs hand a chosen
/// stop/line back here, which opens it and switches to the Kart tab.
struct RootView: View {
    let model: VehiclesModel

    /// Top-level tabs.
    private enum AppTab: Hashable { case map, nearby, saved }

    @State private var location = LocationProvider()
    @State private var departures = DeparturesModel()
    @State private var journey = JourneyModel()
    @State private var nearby = NearbyModel()
    @State private var cameraPosition: MapCameraPosition = .region(.underveisDefault)
    @State private var currentCamera: MapCamera?
    @State private var selectedVehicleID: String?
    @State private var selectedStopID: String?
    /// The resolved stop behind `selectedStopID` (from the map or a saved/recent snapshot). Held so
    /// the favourite toggle has the full stop (`DeparturesModel` only carries its name/symbol).
    @State private var selectedStop: Stop?
    /// Full stop the host is about to open (set by `openStop`), used to resolve `selectedStopID` for a
    /// fresh stop — e.g. a nearby result — that isn't on the map or in favourites/recents yet.
    @State private var primedStop: Stop?
    @State private var isFollowing = false
    @State private var showFilters = false
    /// Which top-level tab is showing. Browse tabs switch this back to `.map` after a selection.
    @State private var selectedTab: AppTab = .map
    @State private var hasCentered = false
    @AppStorage("mapStyle") private var mapStyleRaw = MapStyleOption.standard.rawValue

    private var mapStyle: MapStyleOption {
        MapStyleOption(rawValue: mapStyleRaw) ?? .standard
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Kart", systemImage: "map", value: AppTab.map) {
                mapTab
            }
            Tab("Nær meg", systemImage: "location.magnifyingglass", value: AppTab.nearby) {
                NearbyView(
                    model: nearby,
                    location: location,
                    liveServiceJourneyIDs: model.liveServiceJourneyIDs,
                    isFavorite: { model.personalization.isFavorite(stopID: $0) },
                    onToggleFavorite: { model.personalization.toggleFavorite($0) },
                    onSelectStop: { openStop($0); selectedTab = .map }
                )
            }
            Tab("Lagret", systemImage: "star", value: AppTab.saved) {
                SavedView(
                    model: model,
                    onSelectStop: { openStop($0); selectedTab = .map },
                    onSelectLine: { openLine($0); selectedTab = .map }
                )
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            location.requestAndStart()
            model.start()
            model.updateViewport(.underveisDefault)
        }
        .onChange(of: location.fixCount) {
            if selectedTab == .nearby, let coordinate = location.coordinate { nearby.update(coordinate: coordinate) }
            guard !hasCentered, let coordinate = location.coordinate else { return }
            hasCentered = true
            withAnimation { cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: .city)) }
        }
        // The "Nær meg" tab drives a location-scoped fetch while it's the active tab; stop otherwise.
        .onChange(of: selectedTab) { _, tab in
            if tab == .nearby {
                nearby.start(near: location.coordinate)
            } else {
                nearby.stop()
            }
        }
        // Selecting a stop starts its departures poll and is mutually exclusive with a selected
        // vehicle (clearing the vehicle also drops follow mode). Deselecting stops the poll.
        .onChange(of: selectedStopID) { _, newID in
            guard let id = newID else {
                selectedStop = nil
                departures.deselect()
                return
            }
            // Resolve a primed stop (one the host just chose, e.g. a nearby result) first, then the
            // on-map stops, then a saved/recent snapshot — so a stop opens even when it's off-screen,
            // zoomed out, or not yet a favourite/recent.
            let primed = primedStop.flatMap { $0.id == id ? $0 : nil }
            primedStop = nil
            guard let stop = primed ?? model.stops.first(where: { $0.id == id }) ?? model.personalization.knownStop(id: id) else {
                selectedStopID = nil  // unknown id (scrolled out before we could resolve it)
                return
            }
            selectedStop = stop
            departures.select(stop: stop)
            model.personalization.recordStopView(stop)
            selectedVehicleID = nil
            isFollowing = false
            center(on: stop)
        }
        // The reverse direction: picking a vehicle clears any selected stop (whose .onChange then
        // tears down the poll) and starts loading that vehicle's journey (route + stops). A vehicle
        // without a service journey, or a deselection, tears the journey down.
        .onChange(of: selectedVehicleID) { _, newID in
            guard let id = newID else {
                journey.deselect()
                return
            }
            selectedStopID = nil
            let vehicle = model.vehicles[id]
            if let serviceJourneyID = vehicle?.serviceJourneyId {
                journey.select(serviceJourneyId: serviceJourneyID)
            } else {
                journey.deselect()
            }
            // Record the line (not the ephemeral vehicle) as "recently viewed".
            if let vehicle, let ref = vehicle.lineRef, !ref.isEmpty {
                model.personalization.recordLineView(
                    lineRef: ref,
                    publicCode: vehicle.publicCode,
                    name: vehicle.lineName,
                    mode: vehicle.mode,
                    destination: vehicle.destinationName
                )
            }
        }
        // Follow mode: recenter on the tracked vehicle whenever its position changes. `followKey` is
        // nil when not following, so this no-ops then. On the transition into following (old key was
        // nil) we zoom in close; afterwards we keep whatever zoom/heading/pitch the user has set.
        .onChange(of: followKey) { oldKey, _ in
            guard isFollowing, let coordinate = followedVehicle?.coordinate else { return }
            let engaging = oldKey == nil
            let distance =
                engaging
                ? min(currentCamera?.distance ?? Self.followZoomDistance, Self.followZoomDistance)
                : currentCamera?.distance ?? Self.followZoomDistance
            let camera = MapCamera(
                centerCoordinate: coordinate,
                distance: distance,
                heading: currentCamera?.heading ?? 0,
                pitch: currentCamera?.pitch ?? 0
            )
            if engaging {
                // Animate the initial zoom-in toward the vehicle.
                withAnimation(.easeInOut(duration: 0.45)) { cameraPosition = .camera(camera) }
            } else {
                // Track frame-by-frame: the marker is already eased, so move the camera instantly to
                // keep it centred (a long animation here would lag behind the smooth marker).
                cameraPosition = .camera(camera)
            }
        }
    }

    /// The "Kart" tab: the live map with its overlays, map-control toolbar, and the selected
    /// vehicle/stop detail (inspector on macOS, bottom sheet on iPhone).
    @ViewBuilder
    private var mapTab: some View {
        NavigationStack {
            BusMapView(
                model: model,
                mapStyle: mapStyle,
                cameraPosition: $cameraPosition,
                selectedVehicleID: $selectedVehicleID,
                selectedStopID: $selectedStopID,
                currentCamera: $currentCamera,
                isFollowing: $isFollowing,
                routeCoordinates: journey.routeCoordinates,
                routeColor: routeColor,
                journeyStops: journey.calls,
                nextStopID: journey.nextStopID(for: followedVehicle)
            )
            .overlay(alignment: .topLeading) {
                StatusPill(status: model.status, count: model.visibleVehicles.count)
                    .padding(12)
            }
            .overlay(alignment: .top) {
                followChip
                    .animation(.snappy, value: isFollowing)
                    .padding(.top, 12)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("Underveis")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            #if os(macOS)
                .inspector(isPresented: inspectorPresented) {
                    inspectorContent
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
            #else
                // On iPhone, show the detail as a bottom card that leaves the map visible and
                // interactive (so you can still see/pan the followed vehicle) instead of a full sheet.
                .sheet(isPresented: inspectorPresented) {
                    inspectorContent
                        .presentationDetents([.height(260), .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(260)))
                        .presentationDragIndicator(.visible)
                }
            #endif
        }
    }

    /// Camera distance (≈ metres) to zoom to when follow first engages — a close neighbourhood view.
    private static let followZoomDistance: CLLocationDistance = 1400

    private var followedVehicle: Vehicle? {
        guard let id = selectedVehicleID else { return nil }
        return model.vehicles[id]
    }

    /// Colour for the selected vehicle's route line — its line colour, or the mode-fallback tint.
    private var routeColor: Color {
        guard let vehicle = followedVehicle else { return .accentColor }
        return model.lineColors.colors(for: vehicle).tint
    }

    /// Changes whenever the followed vehicle moves — drives the recenter `onChange`.
    private var followKey: String? {
        guard isFollowing, let vehicle = followedVehicle else { return nil }
        return "\(vehicle.latitude),\(vehicle.longitude)"
    }

    @ViewBuilder
    private var followChip: some View {
        if isFollowing, let vehicle = followedVehicle {
            FollowChip(label: vehicle.shortLabel) {
                withAnimation(.snappy) { isFollowing = false }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showFilters.toggle()
            } label: {
                Label("Filtre", systemImage: "line.3.horizontal.decrease.circle")
            }
            .popover(isPresented: $showFilters) {
                List { ModeFilterView(model: model) }
                    .frame(minWidth: 260, minHeight: 320)
                    #if os(iOS)
                        .presentationDetents([.medium, .large])
                    #endif
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                toggleFollow()
            } label: {
                Label("Følg", systemImage: isFollowing ? "dot.scope" : "scope")
            }
            .disabled(selectedVehicleID == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Karttype", selection: $mapStyleRaw) {
                    ForEach(MapStyleOption.allCases) { option in
                        Label(option.title, systemImage: option.symbolName)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Karttype", systemImage: "map")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                recenter()
            } label: {
                Label("Min posisjon", systemImage: "location")
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let id = selectedVehicleID, let vehicle = model.vehicles[id] {
            VehicleDetailView(
                vehicle: vehicle,
                colors: model.lineColors.colors(for: vehicle),
                journey: journey,
                isWatched: model.personalization.isWatched(lineRef: vehicle.lineRef ?? ""),
                onToggleWatch: { model.toggleWatched(for: vehicle) }
            )
        } else if selectedStopID != nil {
            StopDetailView(
                model: departures,
                liveServiceJourneyIDs: model.liveServiceJourneyIDs,
                isFavorite: selectedStop.map { model.personalization.isFavorite(stopID: $0.id) } ?? false,
                onToggleFavorite: { if let stop = selectedStop { model.personalization.toggleFavorite(stop) } },
                onSelectDeparture: selectDeparture
            )
        } else {
            ContentUnavailableView(
                "Ingenting valgt",
                systemImage: "bus.fill",
                description: Text("Trykk på et kjøretøy eller en holdeplass på kartet for detaljer.")
            )
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedVehicleID != nil || selectedStopID != nil },
            set: {
                if !$0 {
                    selectedVehicleID = nil
                    selectedStopID = nil
                    isFollowing = false
                }
            }
        )
    }

    private func toggleFollow() {
        guard selectedVehicleID != nil else { return }
        withAnimation(.snappy) { isFollowing.toggle() }
    }

    /// Opens a stop's departures board. Priming `primedStop` lets the stop `.onChange` resolve a
    /// fresh stop (e.g. a nearby result) that isn't on the map or saved yet; setting the id then
    /// starts the poll, records the view, and centres the map. Callers on the browse tabs switch to
    /// the Kart tab to reveal the board.
    private func openStop(_ stop: Stop) {
        primedStop = stop
        selectedStopID = stop.id
    }

    /// Watches a saved line (so it's shown + emphasized on the map). Callers switch to the Kart tab.
    private func openLine(_ line: SavedLine) {
        if !model.personalization.isWatched(lineRef: line.lineRef) {
            model.toggleWatched(line)
        }
    }

    private func recenter() {
        isFollowing = false  // recentering on the user releases vehicle follow
        if let coordinate = location.coordinate {
            withAnimation { cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: .city)) }
        } else {
            location.requestAndStart()
            withAnimation { cameraPosition = .userLocation(fallback: .region(.underveisDefault)) }
        }
    }

    /// Locates the live vehicle running a tapped departure's trip and selects + follows it. The
    /// vehicle-selection `.onChange` clears the stop, so the panel switches to the vehicle detail.
    /// No-ops when the trip has no vehicle currently on the map (`onSelectDeparture` is only wired to
    /// rows already marked live, so this guard is belt-and-braces).
    private func selectDeparture(_ departure: Departure) {
        guard let vehicle = model.visibleVehicles.first(where: {
            $0.serviceJourneyId == departure.serviceJourneyId
        }) else { return }
        selectedVehicleID = vehicle.id
        isFollowing = true
    }

    private func center(on stop: Stop) {
        guard let currentCamera else {
            withAnimation { cameraPosition = .region(MKCoordinateRegion(center: stop.coordinate, span: .city)) }
            return
        }

        let camera = MapCamera(
            centerCoordinate: stop.coordinate,
            distance: currentCamera.distance,
            heading: currentCamera.heading,
            pitch: currentCamera.pitch
        )
        withAnimation(.easeInOut(duration: 0.35)) { cameraPosition = .camera(camera) }
    }
}

/// Floating "following" indicator with a stop button.
private struct FollowChip: View {
    let label: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "location.north.line.fill").font(.caption2)
            Text("Følger \(label)").font(.caption.weight(.semibold)).lineLimit(1)
            Button(action: onStop) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

/// Floating connection-status indicator.
private struct StatusPill: View {
    let status: ConnectionStatus
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.caption.weight(.semibold))
            if count > 0 {
                Text("· \(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    private var color: Color {
        switch status {
        case .idle: .gray
        case .connecting, .reconnecting: .orange
        case .live: .green
        }
    }

    private var text: String {
        switch status {
        case .idle: "Frakoblet"
        case .connecting: "Kobler til…"
        case .reconnecting: "Kobler til…"
        case .live: "Direkte"
        }
    }
}

extension MKCoordinateRegion {
    /// Central Oslo — the launch view before a location fix arrives.
    static var underveisDefault: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 59.9113, longitude: 10.7510),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    }
}

extension MKCoordinateSpan {
    static var city: MKCoordinateSpan {
        MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    }
}

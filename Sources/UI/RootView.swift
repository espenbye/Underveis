import MapKit
import SwiftUI

/// Map-first root. The map fills the window on every platform; filters live in a toolbar
/// popover/sheet, the selected vehicle in an inspector, and connection status in a floating pill.
struct RootView: View {
    let model: VehiclesModel

    @State private var location = LocationProvider()
    @State private var departures = DeparturesModel()
    @State private var cameraPosition: MapCameraPosition = .region(.bussradarDefault)
    @State private var currentCamera: MapCamera?
    @State private var selectedVehicleID: String?
    @State private var selectedStopID: String?
    @State private var isFollowing = false
    @State private var showFilters = false
    @State private var hasCentered = false

    var body: some View {
        NavigationStack {
            BusMapView(
                model: model,
                cameraPosition: $cameraPosition,
                selectedVehicleID: $selectedVehicleID,
                selectedStopID: $selectedStopID,
                currentCamera: $currentCamera,
                isFollowing: $isFollowing
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
            .navigationTitle("Bussradar")
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
        .task {
            location.requestAndStart()
            model.start()
            model.updateViewport(.bussradarDefault)
        }
        .onChange(of: location.fixCount) {
            guard !hasCentered, let coordinate = location.coordinate else { return }
            hasCentered = true
            withAnimation { cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: .city)) }
        }
        // Selecting a stop starts its departures poll and is mutually exclusive with a selected
        // vehicle (clearing the vehicle also drops follow mode). Deselecting stops the poll.
        .onChange(of: selectedStopID) { _, newID in
            guard let id = newID else {
                departures.deselect()
                return
            }
            guard let stop = model.stops.first(where: { $0.id == id }) else {
                selectedStopID = nil  // stop scrolled out of the set before we could resolve it
                return
            }
            departures.select(stop: stop)
            selectedVehicleID = nil
            isFollowing = false
            center(on: stop)
        }
        // The reverse direction: picking a vehicle clears any selected stop (whose .onChange then
        // tears down the poll).
        .onChange(of: selectedVehicleID) { _, newID in
            if newID != nil { selectedStopID = nil }
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

    /// Camera distance (≈ metres) to zoom to when follow first engages — a close neighbourhood view.
    private static let followZoomDistance: CLLocationDistance = 1400

    private var followedVehicle: Vehicle? {
        guard let id = selectedVehicleID else { return nil }
        return model.vehicles[id]
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
            VehicleDetailView(vehicle: vehicle, colors: model.lineColors.colors(for: vehicle))
        } else if selectedStopID != nil {
            StopDetailView(
                model: departures,
                liveServiceJourneyIDs: model.liveServiceJourneyIDs,
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

    private func recenter() {
        isFollowing = false  // recentering on the user releases vehicle follow
        if let coordinate = location.coordinate {
            withAnimation { cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: .city)) }
        } else {
            location.requestAndStart()
            withAnimation { cameraPosition = .userLocation(fallback: .region(.bussradarDefault)) }
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
    static var bussradarDefault: MKCoordinateRegion {
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

import MapKit
import SwiftUI

/// Details for the selected vehicle, shown in the inspector panel. Thin composer: each section is
/// its own `View` with narrow inputs, so the per-second `journey.tickID` bump re-evaluates only the
/// live status card and the journey list — not the header, facts, or Look Around preview.
struct VehicleDetailView: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors
    /// The vehicle's journey (route + stop calls), owned by `RootView` and shared with the map.
    let journey: JourneyModel
    /// Whether this vehicle's line is watched, and a toggle for it (the star in the header). The
    /// toggle is shown only when the vehicle has a line to watch.
    let isWatched: Bool
    let onToggleWatch: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VehicleHeader(
                    shortLabel: vehicle.shortLabel,
                    title: vehicle.lineName ?? vehicle.mode?.title ?? "Avgang",
                    destination: vehicle.destinationName,
                    colors: colors,
                    watchState: vehicle.lineRef == nil ? nil : isWatched,
                    onToggleWatch: onToggleWatch
                )
                LiveStatusCard(vehicle: vehicle, journey: journey)
                Divider()
                RideAlongSection(
                    vehicleID: vehicle.id,
                    latitude: vehicle.latitude,
                    longitude: vehicle.longitude,
                    bearing: vehicle.bearing,
                    label: vehicle.lineName ?? vehicle.shortLabel
                )
                Divider()
                VehicleFacts(
                    originName: vehicle.originName,
                    destinationName: vehicle.destinationName,
                    mode: vehicle.mode,
                    delay: vehicle.delay,
                    speed: vehicle.speed,
                    lastUpdated: vehicle.lastUpdated
                )
                if vehicle.serviceJourneyId != nil {
                    Divider()
                    JourneySection(vehicle: vehicle, journey: journey, tint: colors.tint)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Line badge, line name, destination, and the optional watch star.
private struct VehicleHeader: View {
    let shortLabel: String
    let title: String
    let destination: String?
    let colors: LineColorStore.ResolvedColors
    /// `nil` hides the star (no line to watch); otherwise whether the line is watched.
    let watchState: Bool?
    let onToggleWatch: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.tint)
                .frame(width: 52, height: 52)
                .overlay {
                    Text(shortLabel)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(colors.label)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let destination {
                    Text(destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let isWatched = watchState {
                Spacer(minLength: 8)

                Button(action: onToggleWatch) {
                    Image(systemName: isWatched ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(isWatched ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isWatched ? "Slutt å følge linjen" : "Følg linjen")
            }
        }
    }
}

/// An at-a-glance "live status" strip: deviation from timetable, the next stop with a live ETA,
/// onboard crowding, and a traffic-congestion flag — whichever the feed currently provides. Hidden
/// entirely when none are known. Reading `journey.tickID` keeps the next-stop ETA counting down
/// between polls; that dependency is confined to this view.
private struct LiveStatusCard: View {
    let vehicle: Vehicle
    let journey: JourneyModel

    var body: some View {
        let _ = journey.tickID
        let nextCall = vehicle.serviceJourneyId != nil ? journey.nextCall(for: vehicle) : nil
        let inCongestion = vehicle.inCongestion == true
        let showDelay = vehicle.delay != nil
        let showNext = nextCall != nil
        let showOccupancy = vehicle.occupancy != nil
        if showDelay || showNext || showOccupancy || inCongestion {
            HStack(spacing: 0) {
                if let delay = vehicle.delay {
                    StatTile(icon: "clock", value: delayTileValue(delay), caption: "Avvik", tint: delayTint(delay))
                }
                if let nextCall {
                    if showDelay { tileDivider }
                    StatTile(
                        icon: "signpost.right.fill",
                        value: etaText(for: nextCall),
                        caption: nextCall.quayName,
                        tint: .primary
                    )
                }
                if let occupancy = vehicle.occupancy {
                    if showDelay || showNext { tileDivider }
                    StatTile(icon: occupancy.symbolName, value: occupancy.title, caption: "Ombord", tint: occupancyTint(occupancy))
                }
                if inCongestion {
                    if showDelay || showNext || showOccupancy { tileDivider }
                    StatTile(icon: "exclamationmark.triangle.fill", value: "I kø", caption: "Trafikk", tint: .orange)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var tileDivider: some View {
        Divider().frame(height: 40)
    }

    /// "I rute" / "+N min" / "−N min" — a compact deviation label for the status tile.
    private func delayTileValue(_ delay: Double) -> String {
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 { return "I rute" }
        return minutes > 0 ? "+\(minutes) min" : "−\(-minutes) min"
    }

    private func delayTint(_ delay: Double) -> Color {
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 { return .green }
        return minutes > 0 ? .orange : .blue
    }

    /// Live ETA to a call: "Nå" / "N min" / a clock time for stops more than an hour out.
    private func etaText(for call: JourneyCall) -> String {
        guard let time = call.effectiveArrival ?? call.effectiveDeparture else { return "—" }
        let remaining = time.timeIntervalSince(Date())
        if remaining < 60 { return "Nå" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "kl. " + time.formatted(date: .omitted, time: .shortened)
    }

    private func occupancyTint(_ occupancy: Occupancy) -> Color {
        switch occupancy.severity {
        case 0: .green
        case 1: .yellow
        case 2: .orange
        default: .red
        }
    }
}

/// Street-level Look Around preview at the vehicle's live position — the "ride along" view. Owns the
/// `RideAlongModel` and refetches as the vehicle moves; takes only the position fields so it is
/// untouched by the journey tick and by unrelated vehicle field changes.
private struct RideAlongSection: View {
    let vehicleID: String
    let latitude: Double
    let longitude: Double
    let bearing: Double?
    /// Title shown in the full-screen viewer.
    let label: String

    /// Drives the Look Around "ride along" preview, refetching as the vehicle moves.
    @State private var rideAlong = RideAlongModel()

    #if os(iOS)
        /// The scene shown in the full-screen ride-along viewer (nil when closed). Holding the scene
        /// that was current at tap time lets the viewer construct with a non-nil scene; it then keeps
        /// following via the `$rideAlong.scene` binding.
        @State private var rideAlongFullScreen: RideAlongScene?
    #endif

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Se deg omkring", systemImage: "binoculars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                switch rideAlong.availability {
                case .available where rideAlong.scene != nil:
                    preview
                case .unavailable:
                    placeholder("Ingen gatebilde her", systemImage: "eye.slash")
                default:
                    placeholder(nil, systemImage: nil)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        // Fetch on first appearance and reset + refetch when the selection switches vehicles.
        .task(id: vehicleID) {
            rideAlong.reset()
            rideAlong.update(to: coordinate, bearing: bearing)
        }
        // Track the vehicle as it moves (throttled inside the model, which derives the view direction
        // from movement). `CLLocationCoordinate2D` isn't `Equatable`, so key the change on a
        // lightweight position string like `RootView.followKey` does.
        .onChange(of: "\(latitude),\(longitude)") {
            rideAlong.update(to: coordinate, bearing: bearing)
        }
        #if os(iOS)
            // Our own full-screen viewer, so it keeps following the vehicle (the built-in
            // `LookAroundPreview` viewer can't be driven once it's open).
            .fullScreenCover(item: $rideAlongFullScreen) { item in
                RideAlongFullScreenView(
                    initialScene: item.scene,
                    scene: $rideAlong.scene,
                    label: label
                )
            }
        #endif
    }

    /// The inline thumbnail. On iOS it opens our own tracking full-screen viewer; on macOS the
    /// system viewer isn't available, so it's a plain preview.
    @ViewBuilder
    private var preview: some View {
        #if os(iOS)
            Button {
                if let scene = rideAlong.scene { rideAlongFullScreen = RideAlongScene(scene: scene) }
            } label: {
                LookAroundPreview(scene: $rideAlong.scene, allowsNavigation: false, badgePosition: .bottomTrailing)
                    // Suppress the preview's own tap-to-fullscreen so our button owns the tap.
                    .allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
        #else
            LookAroundPreview(scene: $rideAlong.scene, badgePosition: .bottomTrailing)
        #endif
    }

    /// Same-sized fill for the preview slot: a centred message, or a spinner while loading.
    private func placeholder(_ text: String?, systemImage: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let text, let systemImage {
                Label(text, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }
}

/// Static-ish facts about the vehicle: route, type, deviation, speed, last update.
private struct VehicleFacts: View {
    let originName: String?
    let destinationName: String?
    let mode: VehicleMode?
    let delay: Double?
    let speed: Double?
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let originName, let destinationName {
                fact("Rute", "\(originName) → \(destinationName)", systemImage: "arrow.right")
            }
            if let mode {
                fact("Type", mode.title, systemImage: mode.symbolName)
            }
            if let delay {
                fact("Avvik", delayText(delay), systemImage: "clock")
            }
            if let speed {
                fact("Fart", String(format: "%.0f km/t", speed * 3.6), systemImage: "speedometer")
            }
            if let lastUpdated {
                fact("Oppdatert", lastUpdated.formatted(date: .omitted, time: .standard), systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

    private func fact(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func delayText(_ delay: Double) -> String {
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 { return "I rute" }
        return minutes > 0 ? "\(minutes) min forsinket" : "\(-minutes) min før rute"
    }
}

/// The stop-by-stop list for the journey: passed stops dim, the next stop is highlighted, and the
/// rest show their expected arrival. `journey.tickID` keeps the countdowns live between polls.
private struct JourneySection: View {
    let vehicle: Vehicle
    let journey: JourneyModel
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stopp på ruten", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch journey.loadState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(minHeight: 80)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        case .loaded:
            if journey.calls.isEmpty {
                Label("Ingen stoppinformasjon", systemImage: "mappin.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let calls = journey.calls
                let statuses = journey.statuses(for: vehicle)
                VStack(spacing: 0) {
                    ForEach(calls.enumerated(), id: \.element.id) { index, call in
                        JourneyCallRow(
                            call: call,
                            status: statuses[call.id] ?? .upcoming,
                            tint: tint,
                            tickID: journey.tickID,
                            isFirst: index == 0,
                            isLast: index == calls.count - 1
                        )
                    }
                }
            }
        }
    }
}

/// One column of the live status card: a tinted glyph over a headline value and a muted caption.
private struct StatTile: View {
    let icon: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }
}

/// One stop on the journey: a timeline rail with a dot, the stop name, and its time. The dot/line and
/// the trailing time restyle by `status` (passed → dimmed, next → highlighted, upcoming → normal).
/// `tickID` is passed only to force a per-second re-render so the live ETA stays current.
private struct JourneyCallRow: View {
    let call: JourneyCall
    let status: JourneyModel.CallStatus
    let tint: Color
    let tickID: Int
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            rail
            VStack(alignment: .leading, spacing: 2) {
                Text(call.quayName)
                    .font(.callout.weight(status == .next ? .semibold : .regular))
                    .strikethrough(call.isCancelled)
                    .foregroundStyle(status == .passed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if let quay = call.publicCode {
                    Text("Spor \(quay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 6)
        .frame(minHeight: 34)
    }

    /// A continuous vertical rail (trimmed at the first/last stop) with the stop's dot on it.
    private var rail: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? AnyShapeStyle(.clear) : AnyShapeStyle(railColor))
                Rectangle().fill(isLast ? AnyShapeStyle(.clear) : AnyShapeStyle(railColor))
            }
            .frame(width: 2)

            Circle()
                .fill(status == .passed ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .frame(width: status == .next ? 13 : 9, height: status == .next ? 13 : 9)
                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
        }
        .frame(width: 18)
    }

    private var railColor: Color { tint.opacity(0.35) }

    @ViewBuilder
    private var trailing: some View {
        // Reading Date() here (re-run whenever `tickID` changes) is what makes the countdown live.
        let now = Date()
        if call.isCancelled {
            Text("Innstilt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if status == .passed {
            if let time = stopTime {
                Text(clock(time))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(headline(now: now))
                    .font(.callout.weight(status == .next ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(headlineColor)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(isDelayed ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    /// When the vehicle is expected at this stop (arrival, falling back to departure).
    private var stopTime: Date? { call.effectiveArrival ?? call.effectiveDeparture }

    /// Big line for an upcoming stop: "Nå" / "N min" / clock time for distant stops.
    private func headline(now: Date) -> String {
        guard let time = stopTime else { return "" }
        let remaining = time.timeIntervalSince(now)
        if remaining < 60 { return "Nå" }
        let minutes = Int(remaining / 60)
        let prefix = call.predictionInaccurate && call.isRealtime ? "~" : ""
        if minutes < 60 { return "\(prefix)\(minutes) min" }
        return clock(time)
    }

    /// Secondary line: the clock time, with a "forsinket" note when running late.
    private var caption: String? {
        guard let time = stopTime else { return nil }
        return isDelayed ? "\(clock(time)) · forsinket" : clock(time)
    }

    private var headlineColor: AnyShapeStyle {
        if isDelayed { return AnyShapeStyle(Color.orange) }
        return status == .next ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// At least a minute behind timetable, measured on whichever pair (arrival/departure) is available.
    private var isDelayed: Bool {
        if let expected = call.expectedArrival, let aimed = call.aimedArrival {
            return expected.timeIntervalSince(aimed) >= 60
        }
        if let expected = call.expectedDeparture, let aimed = call.aimedDeparture {
            return expected.timeIntervalSince(aimed) >= 60
        }
        return false
    }

    private func clock(_ date: Date) -> String {
        "kl. " + date.formatted(date: .omitted, time: .shortened)
    }
}

#if os(iOS)
    /// Identifiable wrapper so a non-nil scene can drive `fullScreenCover(item:)`.
    private struct RideAlongScene: Identifiable {
        let id = UUID()
        let scene: MKLookAroundScene
    }

    /// Full-screen Look Around viewer that keeps following the vehicle: the underlying detail view
    /// stays alive behind the cover and keeps refetching, updating `scene` here in place.
    private struct RideAlongFullScreenView: View {
        let initialScene: MKLookAroundScene
        @Binding var scene: MKLookAroundScene?
        let label: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            LookAroundViewer(initialScene: initialScene, scene: $scene)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .padding()
                    }
                    .accessibilityLabel("Lukk")
                }
                .overlay(alignment: .topLeading) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                }
        }
    }

    /// Wraps `MKLookAroundViewController` so the full-screen scene can update live. Only non-nil scene
    /// changes are applied, so a transient no-coverage fetch keeps the last good imagery on screen.
    private struct LookAroundViewer: UIViewControllerRepresentable {
        let initialScene: MKLookAroundScene
        @Binding var scene: MKLookAroundScene?

        func makeUIViewController(context: Context) -> MKLookAroundViewController {
            MKLookAroundViewController(scene: initialScene)
        }

        func updateUIViewController(_ controller: MKLookAroundViewController, context: Context) {
            if let scene, scene !== controller.scene {
                controller.scene = scene
            }
        }
    }
#endif

import MapKit
import SwiftUI

/// Details for the selected vehicle, shown in the inspector panel.
struct VehicleDetailView: View {
    let vehicle: Vehicle
    let colors: LineColorStore.ResolvedColors
    /// The vehicle's journey (route + stop calls), owned by `RootView` and shared with the map.
    let journey: JourneyModel
    /// Whether this vehicle's line is watched, and a toggle for it (the star in the header). The
    /// toggle is shown only when the vehicle has a line to watch.
    let isWatched: Bool
    let onToggleWatch: () -> Void

    /// Drives the Look Around "ride along" preview, refetching as the vehicle moves.
    @State private var rideAlong = RideAlongModel()

    #if os(iOS)
        /// The scene shown in the full-screen ride-along viewer (nil when closed). Holding the scene
        /// that was current at tap time lets the viewer construct with a non-nil scene; it then keeps
        /// following via the `$rideAlong.scene` binding.
        @State private var rideAlongFullScreen: RideAlongScene?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                rideAlongSection
                Divider()
                facts
                if vehicle.serviceJourneyId != nil {
                    Divider()
                    journeySection
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Fetch on first appearance and reset + refetch when the selection switches vehicles.
        .task(id: vehicle.id) {
            rideAlong.reset()
            rideAlong.update(to: vehicle.coordinate, bearing: vehicle.bearing)
        }
        // Track the vehicle as it moves (throttled inside the model, which derives the view direction
        // from movement). `CLLocationCoordinate2D` isn't `Equatable`, so key the change on a
        // lightweight position string like `RootView.followKey` does.
        .onChange(of: "\(vehicle.latitude),\(vehicle.longitude)") {
            rideAlong.update(to: vehicle.coordinate, bearing: vehicle.bearing)
        }
        #if os(iOS)
            // Our own full-screen viewer, so it keeps following the vehicle (the built-in
            // `LookAroundPreview` viewer can't be driven once it's open).
            .fullScreenCover(item: $rideAlongFullScreen) { item in
                RideAlongFullScreenView(
                    initialScene: item.scene,
                    scene: $rideAlong.scene,
                    label: vehicle.lineName ?? vehicle.shortLabel
                )
            }
        #endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.tint)
                .frame(width: 52, height: 52)
                .overlay {
                    Text(vehicle.shortLabel)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(colors.label)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.lineName ?? vehicle.mode?.title ?? "Avgang")
                    .font(.title3.weight(.semibold))
                if let destination = vehicle.destinationName {
                    Text(destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if vehicle.lineRef != nil {
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

    /// Street-level Look Around preview at the vehicle's live position — the "ride along" view.
    @ViewBuilder
    private var rideAlongSection: some View {
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

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let origin = vehicle.originName, let destination = vehicle.destinationName {
                fact("Rute", "\(origin) → \(destination)", systemImage: "arrow.right")
            }
            if let mode = vehicle.mode {
                fact("Type", mode.title, systemImage: mode.symbolName)
            }
            if let delay = vehicle.delay {
                fact("Avvik", delayText(delay), systemImage: "clock")
            }
            if let speed = vehicle.speed {
                fact("Fart", String(format: "%.0f km/t", speed * 3.6), systemImage: "speedometer")
            }
            if let updated = vehicle.lastUpdated {
                fact("Oppdatert", updated.formatted(date: .omitted, time: .standard), systemImage: "dot.radiowaves.left.and.right")
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

    /// The stop-by-stop list for the journey: passed stops dim, the next stop is highlighted, and the
    /// rest show their expected arrival. `journey.tickID` keeps the countdowns live between polls.
    @ViewBuilder
    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stopp på ruten", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            journeyContent
        }
    }

    @ViewBuilder
    private var journeyContent: some View {
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
                    ForEach(Array(calls.enumerated()), id: \.element.id) { index, call in
                        JourneyCallRow(
                            call: call,
                            status: statuses[call.id] ?? .upcoming,
                            tint: colors.tint,
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

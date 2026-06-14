import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Live departure board for the selected stop, shown in the inspector / bottom sheet. Mirrors
/// `VehicleDetailView`'s layout; `DeparturesModel` drives the data, polling every 30 s while a
/// per-second tick keeps the countdowns moving in between.
struct StopDetailView: View {
    let model: DeparturesModel
    /// Service-journey ids with a live vehicle on the map; those rows become tappable.
    let liveServiceJourneyIDs: Set<String>
    /// Schedules/tracks per-departure reminders behind the bell on each row.
    let reminders: ReminderStore
    /// Whether this stop is a favourite, and a toggle for it (the star in the header).
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    /// Whether a departure has a running Live Activity, and a toggle for it (iOS only).
    let isLiveActivityActive: (Departure) -> Bool
    let onToggleLiveActivity: (Departure) -> Void
    /// Invoked when a live row is tapped — locates and highlights its vehicle.
    let onSelectDeparture: (Departure) -> Void

    /// Raised when a reminder tap finds notifications switched off, prompting the user to enable them.
    @State private var showPermissionAlert = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                content
                footer
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Varsler er av", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) {}
            #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Åpne Innstillinger") { openURL(url) }
                }
            #endif
        } message: {
            Text("Slå på varsler for Underveis for å få påminnelser om avganger.")
        }
    }

    /// Toggles a reminder, then surfaces the permission alert if notifications turned out to be off.
    private func toggleReminder(for departure: Departure) {
        Task {
            await reminders.toggle(departure, stopName: model.stopName)
            if reminders.permissionDenied { showPermissionAlert = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.tint)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: model.stopSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.stopName.isEmpty ? "Holdeplass" : model.stopName)
                    .font(.title3.weight(.semibold))
                Text("Avganger")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Fjern fra favoritter" : "Legg til i favoritter")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle:
            EmptyView()
        case .loading:
            HStack {
                Spacer()
                ProgressView("Henter avganger…")
                Spacer()
            }
            .frame(minHeight: 160)
        case .failed(let message):
            ContentUnavailableView(
                "Noe gikk galt",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .frame(minHeight: 160)
        case .loaded:
            if model.departures.isEmpty {
                ContentUnavailableView(
                    "Ingen avganger",
                    systemImage: "clock",
                    description: Text("Ingen avganger de neste to timene.")
                )
                .frame(minHeight: 160)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.departures) { departure in
                        DepartureRow(
                            departure: departure,
                            tickID: model.tickID,
                            isLive: liveServiceJourneyIDs.contains(departure.serviceJourneyId),
                            hasReminder: reminders.isReminderSet(for: departure),
                            hasLiveActivity: isLiveActivityActive(departure),
                            onTap: { onSelectDeparture(departure) },
                            onToggleReminder: { toggleReminder(for: departure) },
                            onToggleLiveActivity: { onToggleLiveActivity(departure) }
                        )
                        if departure.id != model.departures.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .loaded = model.loadState, !model.departures.isEmpty {
            Text("Oppdateres om \(model.nextRefreshIn) s")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// One row of the departure board: line badge, destination + platform, a live countdown over the
/// clock time, and a reminder bell. `tickID` is passed only to force a re-render each second so the
/// countdown stays current.
private struct DepartureRow: View {
    let departure: Departure
    let tickID: Int
    /// Whether a vehicle for this trip is on the map right now; live rows are tappable.
    let isLive: Bool
    /// Whether a departure reminder is currently scheduled (fills the bell).
    let hasReminder: Bool
    /// Whether a Live Activity is running for this departure (fills the timer toggle, iOS only).
    let hasLiveActivity: Bool
    let onTap: () -> Void
    let onToggleReminder: () -> Void
    let onToggleLiveActivity: () -> Void

    var body: some View {
        // The toggles are siblings of the (optionally tappable) content so they never nest as buttons.
        HStack(spacing: 8) {
            tappableContent
            liveActivityButton
            reminderButton
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tappableContent: some View {
        if isLive {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
                .accessibilityHint("Vis kjøretøyet på kartet")
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            lineBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(departure.displayDestination)
                    .font(.callout.weight(.medium))
                    .strikethrough(departure.isCancelled)
                    .lineLimit(1)
                if let quay = departure.quayPublicCode {
                    Text("Spor \(quay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isLive {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Live")
            }

            trailing
        }
        .contentShape(Rectangle())
    }

    /// Live Activity toggle (iOS only). Like the reminder bell, it's hidden once a trip has departed
    /// or been cancelled — there's nothing left to count down to.
    @ViewBuilder
    private var liveActivityButton: some View {
        #if os(iOS)
            if departure.actualDeparture == nil && !departure.isCancelled {
                Button(action: onToggleLiveActivity) {
                    Image(systemName: hasLiveActivity ? "timer.circle.fill" : "timer.circle")
                        .font(.callout)
                        .foregroundStyle(hasLiveActivity ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasLiveActivity ? "Stopp nedtelling på låseskjerm" : "Vis nedtelling på låseskjerm")
            }
        #endif
    }

    /// Reminder toggle. Hidden once a trip has departed or been cancelled — there's nothing to remind
    /// about — so the column simply collapses for those rows.
    @ViewBuilder
    private var reminderButton: some View {
        if departure.actualDeparture == nil && !departure.isCancelled {
            Button(action: onToggleReminder) {
                Image(systemName: hasReminder ? "bell.fill" : "bell")
                    .font(.callout)
                    .foregroundStyle(hasReminder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasReminder ? "Fjern påminnelse" : "Påminn meg om avgang")
        }
    }

    private var lineBadge: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(enturHex: departure.colourHex) ?? .accentColor)
            .frame(width: 40, height: 30)
            .overlay {
                Text(departure.linePublicCode)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(enturHex: departure.textColourHex) ?? .white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
            }
    }

    @ViewBuilder
    private var trailing: some View {
        // Reading Date() here (re-run whenever `tickID` changes) is what makes the countdown live.
        let now = Date()
        VStack(alignment: .trailing, spacing: 2) {
            Text(departure.countdownLabel(now: now))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(departure.countdownTint)
            if let caption = caption(now: now) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(departure.status == .cancelled ? AnyShapeStyle(.secondary) : captionColor)
            }
        }
    }

    /// Secondary line: the clock time, with a "forsinket" note when running late.
    private func caption(now: Date) -> String? {
        if departure.isCancelled { return nil }
        let time = clock(departure.actualDeparture ?? departure.expectedDeparture)
        if case .delayed = departure.status { return "\(time) · forsinket" }
        return time
    }

    private var captionColor: AnyShapeStyle {
        if case .delayed = departure.status { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(.secondary)
    }

    private func clock(_ date: Date) -> String {
        "kl. " + date.formatted(date: .omitted, time: .shortened)
    }
}

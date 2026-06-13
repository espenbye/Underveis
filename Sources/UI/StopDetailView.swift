import SwiftUI

/// Live departure board for the selected stop, shown in the inspector / bottom sheet. Mirrors
/// `VehicleDetailView`'s layout; `DeparturesModel` drives the data, polling every 30 s while a
/// per-second tick keeps the countdowns moving in between.
struct StopDetailView: View {
    let model: DeparturesModel
    /// Service-journey ids with a live vehicle on the map; those rows become tappable.
    let liveServiceJourneyIDs: Set<String>
    /// Whether this stop is a favourite, and a toggle for it (the star in the header).
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    /// Invoked when a live row is tapped — locates and highlights its vehicle.
    let onSelectDeparture: (Departure) -> Void

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
                            onTap: { onSelectDeparture(departure) }
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

/// One row of the departure board: line badge, destination + platform, and a live countdown over the
/// clock time. `tickID` is passed only to force a re-render each second so the countdown stays current.
private struct DepartureRow: View {
    let departure: Departure
    let tickID: Int
    /// Whether a vehicle for this trip is on the map right now; live rows are tappable.
    let isLive: Bool
    let onTap: () -> Void

    var body: some View {
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
                Text(destination)
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
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
            Text(headline(now: now))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(headlineColor)
            if let caption = caption(now: now) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(departure.status == .cancelled ? AnyShapeStyle(.secondary) : captionColor)
            }
        }
    }

    private var destination: String {
        if !departure.destinationFrontText.isEmpty { return departure.destinationFrontText }
        return departure.lineName ?? "Avgang"
    }

    /// Big right-hand line: "Avreist" / "Innstilt" / "Nå" / "N min" / clock time for distant calls.
    private func headline(now: Date) -> String {
        if departure.actualDeparture != nil { return "Avreist" }
        if departure.isCancelled { return "Innstilt" }
        let remaining = departure.expectedDeparture.timeIntervalSince(now)
        if remaining < 60 { return "Nå" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "\(minutes) min" }
        return clock(departure.expectedDeparture)
    }

    /// Secondary line: the clock time, with a "forsinket" note when running late.
    private func caption(now: Date) -> String? {
        if departure.isCancelled { return nil }
        let time = clock(departure.actualDeparture ?? departure.expectedDeparture)
        if case .delayed = departure.status { return "\(time) · forsinket" }
        return time
    }

    private var headlineColor: AnyShapeStyle {
        if departure.actualDeparture != nil { return AnyShapeStyle(.secondary) }
        switch departure.status {
        case .cancelled: return AnyShapeStyle(Color.red)
        case .delayed: return AnyShapeStyle(Color.orange)
        case .onTime, .early: return AnyShapeStyle(Color.green)
        }
    }

    private var captionColor: AnyShapeStyle {
        if case .delayed = departure.status { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(.secondary)
    }

    private func clock(_ date: Date) -> String {
        "kl. " + date.formatted(date: .omitted, time: .shortened)
    }
}

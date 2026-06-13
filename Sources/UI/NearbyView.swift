import CoreLocation
import SwiftUI

/// The "Nær meg" sheet: transit stops around the user, nearest first, each previewing its next few
/// departures. Reads the list from `NearbyModel`; tapping a stop defers selection to the host (like
/// `SavedView`) so the sheet dismisses before the departures board opens. Location gating lives here
/// since the view holds the `LocationProvider`.
struct NearbyView: View {
    let model: NearbyModel
    let location: LocationProvider
    /// Service-journey ids with a live vehicle on the map; their inline previews get a live marker.
    let liveServiceJourneyIDs: Set<String>
    let isFavorite: (String) -> Bool
    let onToggleFavorite: (Stop) -> Void
    /// Open a stop's departures board — the host switches to the Kart tab to show it.
    let onSelectStop: (Stop) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Nær meg")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
            ContentUnavailableView {
                Label("Posisjon av", systemImage: "location.slash")
            } description: {
                Text("Slå på posisjonstilgang for å se holdeplasser i nærheten av deg.")
            } actions: {
                Button("Be om tilgang") { location.requestAndStart() }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if location.coordinate == nil {
            loading("Finner posisjonen din…")
        } else {
            switch model.loadState {
            case .idle, .loading:
                loading("Henter holdeplasser…")
            case .loaded:
                if model.nearby.isEmpty {
                    ContentUnavailableView(
                        "Ingen holdeplasser i nærheten",
                        systemImage: "mappin.slash",
                        description: Text("Fant ingen holdeplasser i nærheten av deg.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    list
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(model.nearby) { item in
                NearbyStopRow(
                    item: item,
                    tickID: model.tickID,
                    liveServiceJourneyIDs: liveServiceJourneyIDs,
                    isFavorite: isFavorite(item.id),
                    onToggleFavorite: { onToggleFavorite(item.stop) },
                    onTap: { onSelectStop(item.stop) }
                )
                if item.id != model.nearby.last?.id { Divider() }
            }
        }
    }

    private func loading(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

/// One nearby stop: a header (mode glyph, name, distance, favourite star) over up to three inline
/// departure previews. Tapping anywhere opens the full departures board; the star toggles favourite
/// in place without triggering the row tap (same precedent as `SavedStopRow`). `tickID` forces a
/// re-render each second so the countdowns stay current.
private struct NearbyStopRow: View {
    let item: NearbyStop
    let tickID: Int
    let liveServiceJourneyIDs: Set<String>
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onTap: () -> Void

    /// At most this many inline departures previewed per stop.
    private static let previewCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            departures
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityHint("Vis alle avganger")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: item.stop.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.stop.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(distanceText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Fjern fra favoritter" : "Legg til i favoritter")
        }
    }

    @ViewBuilder
    private var departures: some View {
        if item.departures.isEmpty {
            Text("Ingen avganger de neste to timene")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 42)
        } else {
            // Reading Date() here (re-run whenever `tickID` changes) is what keeps the countdowns live.
            let now = Date()
            VStack(spacing: 5) {
                ForEach(item.departures.prefix(Self.previewCount)) { departure in
                    NearbyDepartureRow(
                        departure: departure,
                        now: now,
                        isLive: liveServiceJourneyIDs.contains(departure.serviceJourneyId)
                    )
                }
            }
            .padding(.leading, 42)
        }
    }

    private var distanceText: String {
        Measurement(value: item.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// A compact one-line departure preview shown inside a nearby stop card.
private struct NearbyDepartureRow: View {
    let departure: Departure
    let now: Date
    /// Whether a vehicle for this trip is on the map right now.
    let isLive: Bool

    var body: some View {
        HStack(spacing: 8) {
            lineBadge

            Text(departure.displayDestination)
                .font(.caption)
                .strikethrough(departure.isCancelled)
                .lineLimit(1)

            if isLive {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Live")
            }

            Spacer(minLength: 6)

            Text(departure.countdownLabel(now: now))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(departure.countdownTint)
        }
    }

    private var lineBadge: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(enturHex: departure.colourHex) ?? .accentColor)
            .frame(width: 30, height: 22)
            .overlay {
                Text(departure.linePublicCode)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(enturHex: departure.textColourHex) ?? .white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
    }
}

import SwiftUI

/// The "Lagret" tab: the user's favourite stops, recents (recent stops + recent lines), and watched
/// lines, behind a segmented control. Reads its lists live from `model.personalization`; mutations
/// (favourite/watch) go straight to the store / model so the lists update in place. Navigation that
/// changes the map selection is handed to the host via `onSelectStop` / `onSelectLine`, which switches
/// to the Kart tab to show it.
struct SavedView: View {
    let model: VehiclesModel
    /// Open a saved stop's departures board (host switches to the Kart tab).
    let onSelectStop: (Stop) -> Void
    /// Watch + reveal a line on the map (host switches to the Kart tab).
    let onSelectLine: (SavedLine) -> Void

    @State private var tab: Tab = .favorites

    private enum Tab: Hashable { case favorites, recent, lines }

    private var personalization: PersonalizationStore { model.personalization }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Favoritter").tag(Tab.favorites)
                    Text("Nylig").tag(Tab.recent)
                    Text("Linjer").tag(Tab.lines)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                Divider()

                ScrollView {
                    content
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Lagret")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .favorites: favorites
        case .recent: recent
        case .lines: lines
        }
    }

    // MARK: - Favoritter

    @ViewBuilder
    private var favorites: some View {
        if personalization.favoriteStops.isEmpty {
            empty(
                "Ingen favoritter",
                systemImage: "star",
                description: "Trykk stjernen i en holdeplass for å lagre den her."
            )
        } else {
            rows(personalization.favoriteStops) { stop in
                stopRow(stop)
            }
        }
    }

    // MARK: - Nylig

    @ViewBuilder
    private var recent: some View {
        if personalization.recentStops.isEmpty && personalization.recentLines.isEmpty {
            empty(
                "Ingenting nylig",
                systemImage: "clock.arrow.circlepath",
                description: "Holdeplasser og linjer du åpner dukker opp her."
            )
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if !personalization.recentStops.isEmpty {
                    section("Holdeplasser") {
                        rows(personalization.recentStops) { stop in stopRow(stop) }
                    }
                }
                if !personalization.recentLines.isEmpty {
                    section("Linjer") {
                        rows(personalization.recentLines) { line in lineRow(line) }
                    }
                }
            }
        }
    }

    // MARK: - Linjer (watched)

    @ViewBuilder
    private var lines: some View {
        if personalization.watchedLines.isEmpty {
            empty(
                "Ingen fulgte linjer",
                systemImage: "star",
                description: "Trykk stjernen på et kjøretøy for å følge linjen – den vises da alltid, uansett filter."
            )
        } else {
            rows(personalization.watchedLines) { line in lineRow(line) }
        }
    }

    // MARK: - Rows

    private func stopRow(_ stop: SavedStop) -> some View {
        SavedStopRow(
            stop: stop,
            isFavorite: personalization.isFavorite(stopID: stop.id),
            onTap: { onSelectStop(stop.stop) },
            onToggleFavorite: { personalization.toggleFavorite(stop.stop) }
        )
    }

    private func lineRow(_ line: SavedLine) -> some View {
        SavedLineRow(
            line: line,
            isWatched: personalization.isWatched(lineRef: line.lineRef),
            onTap: { onSelectLine(line) },
            onToggleWatch: { model.toggleWatched(line) }
        )
    }

    // MARK: - Layout helpers

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Stacks rows with hairline dividers between them, matching the detail views' look.
    private func rows<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id { Divider() }
            }
        }
    }

    private func empty(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}

/// One saved/recent stop row: mode glyph, name + modes, and a favourite star. Tapping the row opens
/// the stop; the star toggles favourite in place.
private struct SavedStopRow: View {
    let stop: SavedStop
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stop.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let subtitle = modesSubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            star(isOn: isFavorite, action: onToggleFavorite, label: isFavorite ? "Fjern fra favoritter" : "Legg til i favoritter")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var modesSubtitle: String? {
        let labels = stop.transportModes.map(modeLabel)
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }
}

/// One saved/recent/watched line row: a coloured line badge, name + last destination, and a watch
/// star. Tapping watches + reveals the line on the map; the star toggles watch in place.
private struct SavedLineRow: View {
    let line: SavedLine
    let isWatched: Bool
    let onTap: () -> Void
    let onToggleWatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(line.mode.fallbackColor)
                .frame(width: 40, height: 30)
                .overlay {
                    Text(line.shortLabel)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(line.name ?? line.mode?.title ?? "Linje")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let destination = line.lastDestination {
                    Text(destination)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            star(isOn: isWatched, action: onToggleWatch, label: isWatched ? "Slutt å følge linjen" : "Følg linjen")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Shared favourite/watch star button used by the saved rows.
private func star(isOn: Bool, action: @escaping () -> Void, label: String) -> some View {
    Button(action: action) {
        Image(systemName: isOn ? "star.fill" : "star")
            .font(.body)
            .foregroundStyle(isOn ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(label)
}

/// Norwegian label for a Journey Planner transport-mode string (as stored in `Stop.transportModes`).
private func modeLabel(_ raw: String) -> String {
    switch raw {
    case "bus": "Buss"
    case "coach": "Ekspressbuss"
    case "tram": "Trikk"
    case "metro": "T-bane"
    case "rail": "Tog"
    case "water": "Ferge"
    case "air": "Fly"
    case "cableway", "funicular": "Bane"
    case "trolleybus": "Trollebuss"
    default: raw.capitalized
    }
}

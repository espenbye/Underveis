import SwiftUI
import WidgetKit

/// Renders the next-departure widget across the families it supports. The countdown uses SwiftUI's
/// self-advancing `Text(timerInterval:)` so it ticks without timeline reloads; the provider only
/// refreshes the underlying predictions periodically.
struct NextDepartureView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextDepartureEntry

    var body: some View {
        if !entry.isConfigured {
            unconfigured
        } else if entry.departures.isEmpty {
            empty
        } else {
            switch family {
            #if os(iOS)
                case .accessoryInline: inlineAccessory
                case .accessoryRectangular: rectangularAccessory
            #endif
            case .systemMedium: medium
            default: small
            }
        }
    }

    // MARK: - System families

    private var small: some View {
        let departure = entry.departures[0]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                badge(departure)
                Spacer()
                Image(systemName: "bus.fill").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            countdown(departure).font(.title.weight(.bold))
            Text(departure.displayDestination)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let name = entry.stopName {
                Text(name).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.stopName {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            ForEach(entry.departures.prefix(3)) { departure in
                HStack(spacing: 10) {
                    badge(departure)
                    Text(departure.displayDestination).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    countdown(departure).font(.callout.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Lock Screen accessories (iOS only)

    #if os(iOS)
        private var rectangularAccessory: some View {
            let departure = entry.departures[0]
            return VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(departure.linePublicCode).font(.caption.weight(.bold))
                    Text(departure.displayDestination).font(.caption).lineLimit(1)
                }
                countdown(departure).font(.headline)
            }
        }

        private var inlineAccessory: some View {
            let departure = entry.departures[0]
            // Inline accessories only render text/an image, so this shows a static label (no live tick).
            return Label(
                "\(departure.linePublicCode) · \(departure.countdownLabel(now: entry.date))",
                systemImage: "bus.fill"
            )
        }
    #endif

    // MARK: - States & pieces

    private var unconfigured: some View {
        VStack(spacing: 6) {
            Image(systemName: "star").font(.title2).foregroundStyle(.secondary)
            Text("Velg en favorittholdeplass")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock").font(.title2).foregroundStyle(.secondary)
            Text(entry.stopName ?? "Holdeplass").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("Ingen avganger nå").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func countdown(_ departure: Departure) -> some View {
        if departure.expectedDeparture > .now {
            Text(timerInterval: Date.now...departure.expectedDeparture, countsDown: true)
                .monospacedDigit()
        } else {
            Text("Nå")
        }
    }

    private func badge(_ departure: Departure) -> some View {
        Text(departure.linePublicCode)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(enturHex: departure.textColourHex) ?? .white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Color(enturHex: departure.colourHex) ?? .accentColor,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

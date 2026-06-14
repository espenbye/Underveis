import WidgetKit

/// One timeline snapshot for the next-departure widget: the chosen stop's upcoming departures at
/// `date`. The visible countdown advances continuously in the view via `Text(timerInterval:)`, so the
/// timeline only needs occasional reloads to refresh the underlying real-time predictions.
struct NextDepartureEntry: TimelineEntry {
    let date: Date
    /// Nil only before any stop is configured.
    let stopName: String?
    let departures: [Departure]
    /// False until the user picks a favourite stop in the widget's configuration.
    let isConfigured: Bool
}

/// Drives the configurable widget: reads the selected stop from the intent, fetches its live
/// departures (`DeparturesProvider`), and reloads every couple of minutes.
struct NextDepartureProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextDepartureEntry {
        NextDepartureEntry(date: Date(), stopName: "Holdeplass", departures: [], isConfigured: true)
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> NextDepartureEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<NextDepartureEntry> {
        let entry = await entry(for: configuration)
        // Refresh the real-time predictions every ~2 minutes; the countdown itself ticks locally.
        let next = Date().addingTimeInterval(120)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SelectStopIntent) async -> NextDepartureEntry {
        guard let stop = configuration.stop else {
            return NextDepartureEntry(date: Date(), stopName: nil, departures: [], isConfigured: false)
        }
        let departures = await DeparturesProvider.departures(stopPlaceID: stop.id)
        return NextDepartureEntry(
            date: Date(),
            stopName: stop.name,
            departures: departures,
            isConfigured: true
        )
    }
}

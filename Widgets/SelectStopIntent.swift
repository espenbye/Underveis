import AppIntents
import WidgetKit

/// Configuration for the "Neste avgang" widget: which stop to show. The stop is chosen entirely from
/// the widget's own configuration UI — a live search over every Norwegian stop (Entur Geocoder) — so
/// nothing has to be set up in the app first.
struct SelectStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Velg holdeplass"
    static let description = IntentDescription("Søk og vis neste avganger fra en holdeplass.")

    @Parameter(title: "Holdeplass")
    var stop: StopEntity?
}

/// An App Intents entity wrapping a stop place, so it can be searched for and selected in the widget
/// configuration. `id` is the NSR stop-place id (e.g. `NSR:StopPlace:58366`).
struct StopEntity: AppEntity {
    let id: String
    let name: String
    let symbolName: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Holdeplass")
    static let defaultQuery = StopQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }

    init(id: String, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }
}

/// Backs the configuration picker: `entities(matching:)` powers the search field (Entur Geocoder),
/// while `entities(for:)` rehydrates a stored selection by its id (Journey Planner). Being an
/// `EntityStringQuery` is what makes WidgetKit show a search bar instead of a fixed list.
struct StopQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [StopEntity] {
        await StopSearch.search(text: string)
    }

    func entities(for identifiers: [StopEntity.ID]) async throws -> [StopEntity] {
        await StopSearch.resolve(ids: identifiers)
    }

    func suggestedEntities() async throws -> [StopEntity] {
        // Seed the picker with major hubs so it's never empty; the user can search for any other stop.
        StopSearch.suggested
    }
}

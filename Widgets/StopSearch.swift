import Foundation

/// Stop-place lookup for the widget's configuration picker. Two paths, both against Entur's open APIs
/// (same `ET-Client-Name` as the rest of the app, no key):
///
/// - `search(text:)` — autocomplete by name via the **Geocoder** (`/geocoder/v1/autocomplete`,
///   `layers=venue`), powering the configuration search field.
/// - `resolve(ids:)` — turn a stored stop id back into a labelled entity via **Journey Planner**
///   (`stopPlace(id:)`), so a saved widget configuration rehydrates with the right name + symbol.
enum StopSearch {
    private static let clientName = "espenbye-underveis"

    /// A handful of major hubs shown in the configuration picker before the user searches, so the
    /// list is never empty (and works offline). Ids verified against the National Stop Register.
    static let suggested: [StopEntity] = [
        StopEntity(id: "NSR:StopPlace:59872", name: "Oslo S", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:58404", name: "Nationaltheatret", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:58211", name: "Oslo lufthavn", symbolName: "airplane"),
        StopEntity(id: "NSR:StopPlace:59952", name: "Drammen stasjon", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:59983", name: "Bergen stasjon", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:61291", name: "Stavanger stasjon", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:61608", name: "Kristiansand stasjon", symbolName: "train.side.front.car"),
        StopEntity(id: "NSR:StopPlace:59977", name: "Trondheim S", symbolName: "train.side.front.car"),
    ]

    // MARK: - Search

    static func search(text: String, size: Int = 12) async -> [StopEntity] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.entur.io/geocoder/v1/autocomplete")!
        components.queryItems = [
            URLQueryItem(name: "text", value: trimmed),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "lang", value: "no"),
            URLQueryItem(name: "layers", value: "venue"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let response = try? JSONDecoder().decode(GeocoderResponse.self, from: data)
        else { return [] }

        return response.features.compactMap { $0.toEntity() }
    }

    // MARK: - Resolve stored ids

    static func resolve(ids: [String]) async -> [StopEntity] {
        var result: [StopEntity] = []
        for id in ids {
            if let entity = await resolveOne(id: id) { result.append(entity) }
        }
        return result
    }

    private static func resolveOne(id: String) async -> StopEntity? {
        let url = URL(string: "https://api.entur.io/journey-planner/v3/graphql")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        let query = "query Stop($id: String!) { stopPlace(id: $id) { id name transportMode } }"
        let body = StopBody(query: query, variables: ["id": id])
        guard let httpBody = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let response = try? JSONDecoder().decode(StopLookupResponse.self, from: data),
            let place = response.data?.stopPlace, let name = place.name
        else { return nil }

        return StopEntity(id: place.id ?? id, name: name, symbolName: symbol(forModes: place.transportMode))
    }

    // MARK: - Symbol mapping

    /// SF Symbol for a stop's primary mode. Mirrors `Stop.symbolName`, but works from either the
    /// Geocoder's `category` strings (e.g. `onstreetBus`, `railStation`) or Journey Planner's
    /// `transportMode` values (e.g. `bus`, `rail`).
    static func symbol(forHints hints: [String]?) -> String {
        let joined = (hints ?? []).joined(separator: " ").lowercased()
        if joined.contains("rail") || joined.contains("train") { return "train.side.front.car" }
        if joined.contains("metro") || joined.contains("subway") { return "tram.tunnel.fill" }
        if joined.contains("tram") { return "tram.fill" }
        if joined.contains("ferry") || joined.contains("water") || joined.contains("boat") { return "ferry.fill" }
        if joined.contains("air") { return "airplane" }
        if joined.contains("cable") || joined.contains("funicular") { return "cablecar.fill" }
        return "bus.fill"  // bus, coach, trolleybus, or unspecified
    }

    static func symbol(forModes modes: [String]?) -> String { symbol(forHints: modes) }

    private struct StopBody: Encodable {
        let query: String
        let variables: [String: String]
    }
}

private struct GeocoderResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Properties

        struct Properties: Decodable {
            let id: String?
            let label: String?
            let name: String?
            let category: [String]?
        }

        /// Maps a geocoder feature to an entity, keeping only stop places (not addresses/streets).
        func toEntity() -> StopEntity? {
            guard let id = properties.id, id.contains("StopPlace") else { return nil }
            let name = properties.label ?? properties.name ?? id
            return StopEntity(id: id, name: name, symbolName: StopSearch.symbol(forHints: properties.category))
        }
    }
}

private struct StopLookupResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let stopPlace: StopPlace?
    }

    struct StopPlace: Decodable {
        let id: String?
        let name: String?
        let transportMode: [String]?
    }
}

import Foundation

/// Looks up line presentation (colour) from Entur's Journey Planner v3 API. The vehicles API
/// exposes only `lineRef/lineName/publicCode`; real colours live here. A vehicle's `lineRef`
/// (e.g. `RUT:Line:1`) is exactly the Journey Planner line `id`, so they join directly.
actor JourneyPlannerClient {
    struct LinePresentation: Sendable, Equatable {
        let lineRef: String
        let publicCode: String?
        let name: String?
        let transportMode: String?
        let colourHex: String?
        let textColourHex: String?
    }

    private let url = URL(string: "https://api.entur.io/journey-planner/v3/graphql")!
    private let clientName: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // `ISO8601DateFormatter` is a non-`Sendable` class, so it lives actor-isolated here (like
    // `encoder`/`decoder`) rather than as a shared static. Entur sometimes includes fractional
    // seconds and sometimes doesn't, so we keep one of each and try the fractional one first.
    private let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(clientName: String = "espenbye-underveis", session: URLSession = .shared) {
        self.clientName = clientName
        self.session = session
    }

    /// Batch-resolves presentation for the given line ids. Unknown ids are simply omitted.
    func lines(ids: [String]) async -> [LinePresentation] {
        let uniqueIDs = Array(Set(ids.filter { !$0.isEmpty }))
        guard !uniqueIDs.isEmpty else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        let operation = GraphQLOperation(
            query: Self.query,
            variables: LinesVariables(ids: uniqueIDs),
            operationName: "Lines"
        )
        guard let body = try? encoder.encode(operation) else { return [] }
        request.httpBody = body

        guard let (data, _) = try? await session.data(for: request),
            let response = try? decoder.decode(LinesResponse.self, from: data)
        else { return [] }

        return (response.data?.lines ?? []).compactMap { $0?.toPresentation() }
    }

    /// Transit stops within a bounding box (National Stop Register), filtered to those in use.
    func stopPlaces(in box: BoundingBox) async -> [Stop] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        let operation = GraphQLOperation(
            query: Self.stopsQuery,
            variables: StopsVariables(box: box),
            operationName: "Stops"
        )
        guard let body = try? encoder.encode(operation) else { return [] }
        request.httpBody = body

        guard let (data, _) = try? await session.data(for: request),
            let response = try? decoder.decode(StopsResponse.self, from: data)
        else { return [] }

        return (response.data?.stopPlacesByBbox ?? []).compactMap { $0?.toStop() }
    }

    /// Real-time departures for a single stop place (NSR id). Returns `nil` on a network/decode
    /// failure so callers can distinguish "couldn't load" from "no departures" (an empty list).
    func departures(stopPlaceID: String) async -> DeparturesResult? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        let operation = GraphQLOperation(
            query: Self.departuresQuery,
            variables: DeparturesVariables(id: stopPlaceID),
            operationName: "Departures"
        )
        guard let body = try? encoder.encode(operation) else { return nil }
        request.httpBody = body

        guard let (data, _) = try? await session.data(for: request),
            let response = try? decoder.decode(DeparturesResponse.self, from: data),
            let stopPlace = response.data?.stopPlace
        else { return nil }

        let departures = (stopPlace.estimatedCalls ?? []).compactMap { $0?.toDeparture(using: parseISO) }
        return DeparturesResult(stopName: stopPlace.name ?? "", departures: departures)
    }

    /// Parses Entur's ISO-8601 timestamps (`2026-06-13T12:22:38+02:00`, with or without fractional
    /// seconds). Fractional first since that variant is stricter.
    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatterWithFractional.date(from: string) ?? isoFormatter.date(from: string)
    }

    private static let query = """
        query Lines($ids: [ID]) {
          lines(ids: $ids) {
            id
            publicCode
            name
            transportMode
            presentation { colour textColour }
          }
        }
        """

    private static let stopsQuery = """
        query Stops($minLat: Float!, $minLon: Float!, $maxLat: Float!, $maxLon: Float!) {
          stopPlacesByBbox(
            minimumLatitude: $minLat
            minimumLongitude: $minLon
            maximumLatitude: $maxLat
            maximumLongitude: $maxLon
            filterByInUse: true
          ) {
            id
            name
            latitude
            longitude
            transportMode
          }
        }
        """

    private static let departuresQuery = """
        query Departures($id: String!) {
          stopPlace(id: $id) {
            id
            name
            estimatedCalls(numberOfDepartures: 20, timeRange: 7200) {
              realtime
              cancellation
              aimedDepartureTime
              expectedDepartureTime
              actualDepartureTime
              destinationDisplay { frontText }
              quay { id publicCode name }
              serviceJourney {
                id
                line { id publicCode name transportMode presentation { colour textColour } }
              }
            }
          }
        }
        """
}

/// A stop's name paired with its current departures — one `Sendable` value crossing back to the
/// main actor, so the model never has to look the name up separately.
struct DeparturesResult: Sendable, Equatable {
    let stopName: String
    let departures: [Departure]
}

private struct StopsVariables: Encodable, Sendable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    init(box: BoundingBox) {
        minLat = box.minLat
        minLon = box.minLon
        maxLat = box.maxLat
        maxLon = box.maxLon
    }
}

private struct StopsResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let stopPlacesByBbox: [StopDTO?]?
    }

    struct StopDTO: Decodable {
        let id: String?
        let name: String?
        let latitude: Double?
        let longitude: Double?
        let transportMode: [String]?

        func toStop() -> Stop? {
            guard let id, let name, let latitude, let longitude else { return nil }
            return Stop(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                transportModes: transportMode ?? []
            )
        }
    }
}

private struct LinesVariables: Encodable, Sendable {
    let ids: [String]
}

private struct LinesResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let lines: [LineDTO?]?
    }

    struct LineDTO: Decodable {
        let id: String?
        let publicCode: String?
        let name: String?
        let transportMode: String?
        let presentation: PresentationDTO?

        func toPresentation() -> JourneyPlannerClient.LinePresentation? {
            guard let id else { return nil }
            return JourneyPlannerClient.LinePresentation(
                lineRef: id,
                publicCode: publicCode,
                name: name,
                transportMode: transportMode,
                colourHex: presentation?.colour,
                textColourHex: presentation?.textColour
            )
        }
    }

    struct PresentationDTO: Decodable {
        let colour: String?
        let textColour: String?
    }
}

private struct DeparturesVariables: Encodable, Sendable {
    let id: String
}

private struct DeparturesResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let stopPlace: StopPlaceDTO?
    }

    struct StopPlaceDTO: Decodable {
        let id: String?
        let name: String?
        let estimatedCalls: [EstimatedCallDTO?]?
    }

    struct EstimatedCallDTO: Decodable {
        let realtime: Bool?
        let cancellation: Bool?
        let aimedDepartureTime: String?
        let expectedDepartureTime: String?
        let actualDepartureTime: String?
        let destinationDisplay: DestinationDisplayDTO?
        let quay: QuayDTO?
        let serviceJourney: ServiceJourneyDTO?

        /// Maps one estimated call to a `Departure`, dropping any call missing a stable identity,
        /// line number, or aimed time. `parse` is the actor's ISO-8601 parser, passed in to keep
        /// the mapping pure.
        func toDeparture(using parse: (String?) -> Date?) -> Departure? {
            guard let serviceJourneyID = serviceJourney?.id,
                let aimedString = aimedDepartureTime,
                let linePublicCode = serviceJourney?.line?.publicCode,
                let aimedDate = parse(aimedString)
            else { return nil }

            let line = serviceJourney?.line
            return Departure(
                id: "\(serviceJourneyID)|\(aimedString)",
                serviceJourneyId: serviceJourneyID,
                quayPublicCode: quay?.publicCode,
                linePublicCode: linePublicCode,
                lineName: line?.name,
                transportMode: line?.transportMode,
                destinationFrontText: destinationDisplay?.frontText ?? "",
                aimedDeparture: aimedDate,
                expectedDeparture: parse(expectedDepartureTime) ?? aimedDate,
                actualDeparture: parse(actualDepartureTime),
                isRealtime: realtime ?? false,
                isCancelled: cancellation ?? false,
                colourHex: line?.presentation?.colour,
                textColourHex: line?.presentation?.textColour
            )
        }
    }

    struct DestinationDisplayDTO: Decodable {
        let frontText: String?
    }

    struct QuayDTO: Decodable {
        let id: String?
        let publicCode: String?
        let name: String?
    }

    struct ServiceJourneyDTO: Decodable {
        let id: String?
        let line: LineDepartureDTO?
    }

    struct LineDepartureDTO: Decodable {
        let id: String?
        let publicCode: String?
        let name: String?
        let transportMode: String?
        let presentation: PresentationDTO?
    }

    struct PresentationDTO: Decodable {
        let colour: String?
        let textColour: String?
    }
}

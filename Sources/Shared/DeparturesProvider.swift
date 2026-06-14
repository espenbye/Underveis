import Foundation

/// A self-contained Entur Journey Planner departures fetcher used by the widget extension (and
/// reusable anywhere). Deliberately independent of `JourneyPlannerClient` / the WebSocket transport
/// (`GraphQLTransportWS`) so the widget target doesn't pull in the streaming layer — it only needs
/// this one HTTP query.
///
/// The query and decoding mirror `JourneyPlannerClient.departuresQuery` and its DTOs; keep the two in
/// sync if the departures shape ever changes.
enum DeparturesProvider {
    private static let endpoint = URL(string: "https://api.entur.io/journey-planner/v3/graphql")!
    private static let clientName = "espenbye-underveis"

    /// Real-time departures for one stop place (NSR id), in arrival order. Returns an empty array on
    /// any network/decode failure — the widget renders an "empty" state either way.
    static func departures(stopPlaceID: String, limit: Int = 6) async -> [Departure] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientName, forHTTPHeaderField: "ET-Client-Name")

        let body = RequestBody(query: Self.query, variables: ["id": stopPlaceID])
        guard let httpBody = try? JSONEncoder().encode(body) else { return [] }
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let response = try? JSONDecoder().decode(DeparturesResponse.self, from: data),
            let calls = response.data?.stopPlace?.estimatedCalls
        else { return [] }

        let parse = Self.makeParser()
        let departures = calls.compactMap { $0?.toDeparture(using: parse) }
        return Array(departures.prefix(limit))
    }

    /// Two ISO-8601 parsers (fractional first), matching `JourneyPlannerClient`. Returned as a closure
    /// so the per-call mapping stays pure and the formatters aren't recreated for every call.
    private static func makeParser() -> (String?) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return { string in
            guard let string else { return nil }
            return withFractional.date(from: string) ?? plain.date(from: string)
        }
    }

    private struct RequestBody: Encodable {
        let query: String
        let variables: [String: String]
    }

    private static let query = """
        query Departures($id: String!) {
          stopPlace(id: $id) {
            id
            name
            estimatedCalls(numberOfDepartures: 12, timeRange: 7200) {
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

private struct DeparturesResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let stopPlace: StopPlace?
    }

    struct StopPlace: Decodable {
        let id: String?
        let name: String?
        let estimatedCalls: [EstimatedCall?]?
    }

    struct EstimatedCall: Decodable {
        let realtime: Bool?
        let cancellation: Bool?
        let aimedDepartureTime: String?
        let expectedDepartureTime: String?
        let actualDepartureTime: String?
        let destinationDisplay: DestinationDisplay?
        let quay: Quay?
        let serviceJourney: ServiceJourney?

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

    struct DestinationDisplay: Decodable {
        let frontText: String?
    }

    struct Quay: Decodable {
        let id: String?
        let publicCode: String?
        let name: String?
    }

    struct ServiceJourney: Decodable {
        let id: String?
        let line: Line?
    }

    struct Line: Decodable {
        let id: String?
        let publicCode: String?
        let name: String?
        let transportMode: String?
        let presentation: Presentation?
    }

    struct Presentation: Decodable {
        let colour: String?
        let textColour: String?
    }
}

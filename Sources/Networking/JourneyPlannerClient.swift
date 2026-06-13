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

    init(clientName: String = "espenbye-bussradar", session: URLSession = .shared) {
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

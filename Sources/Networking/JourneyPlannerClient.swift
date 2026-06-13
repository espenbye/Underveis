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

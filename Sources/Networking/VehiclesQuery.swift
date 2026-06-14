import Foundation

/// GraphQL documents, variables, and response DTOs for Entur's realtime vehicles API
/// (`https://api.entur.io/realtime/v2/vehicles`). Field names and arguments here were confirmed
/// by live schema introspection.
enum VehiclesQuery {

    /// Shared field selection. `*EpochSecond` fields are used in preference to the ISO `DateTime`
    /// variants so no string date parsing is needed on the hot path.
    private static let fields = """
          vehicleId
          mode
          bearing
          speed
          delay
          occupancyStatus
          inCongestion
          lastUpdatedEpochSecond
          expirationEpochSecond
          line { lineRef lineName publicCode }
          serviceJourney { id }
          originName
          destinationName
          location { latitude longitude }
        """

    /// Live subscription. `monitored: true` keeps it to vehicles actively reporting;
    /// `bufferSize`/`bufferTime` let the server batch updates; `maxDataAge` drops stale vehicles.
    static let subscription = """
        subscription Vehicles($boundingBox: BoundingBox!, $mode: VehicleModeEnumeration) {
          vehicles(
            boundingBox: $boundingBox
            mode: $mode
            monitored: true
            bufferSize: 20
            bufferTime: 250
            maxDataAge: "PT5M"
          ) {
        \(fields)
          }
        }
        """

    /// One-shot query used to populate the map instantly before the subscription warms up.
    static let snapshot = """
        query Vehicles($boundingBox: BoundingBox!, $mode: VehicleModeEnumeration) {
          vehicles(boundingBox: $boundingBox, mode: $mode, monitored: true, maxDataAge: "PT5M") {
        \(fields)
          }
        }
        """
}

/// Variables for both the subscription and the snapshot query. `mode` is omitted from the encoded
/// JSON when `nil` (synthesised `encodeIfPresent`), which the server treats as "all modes".
struct VehiclesVariables: Encodable, Sendable {
    let boundingBox: BoundingBox
    let mode: String?
}

// MARK: - Response decoding

/// `{ data: { vehicles: [...] } }` — the shape of both the HTTP response body and the inner
/// `payload` of a WebSocket `next` message.
struct VehiclesResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let vehicles: [VehicleUpdateDTO]?
    }
}

/// `next` message: `{ type: "next", id, payload: { data: { vehicles } } }`.
struct VehiclesNextMessage: Decodable {
    let payload: VehiclesResponse
}

/// Decodes one element of the `vehicles` array and maps it to the app's `Vehicle` value type.
struct VehicleUpdateDTO: Decodable, Sendable {
    let vehicleId: String?
    let mode: String?
    let bearing: Double?
    let speed: Double?
    let delay: Double?
    let occupancyStatus: String?
    let inCongestion: Bool?
    let lastUpdatedEpochSecond: Double?
    let expirationEpochSecond: Double?
    let line: LineDTO?
    let serviceJourney: ServiceJourneyDTO?
    let originName: String?
    let destinationName: String?
    let location: LocationDTO?

    struct LineDTO: Decodable, Sendable {
        let lineRef: String?
        let lineName: String?
        let publicCode: String?
    }

    struct ServiceJourneyDTO: Decodable, Sendable {
        let id: String?
    }

    struct LocationDTO: Decodable, Sendable {
        let latitude: Double?
        let longitude: Double?
    }

    /// Returns `nil` when there's no usable identity or position to place on the map.
    func toVehicle() -> Vehicle? {
        guard let vehicleId,
            let latitude = location?.latitude,
            let longitude = location?.longitude
        else { return nil }

        return Vehicle(
            id: vehicleId,
            latitude: latitude,
            longitude: longitude,
            bearing: bearing,
            speed: speed,
            delay: delay,
            occupancy: occupancyStatus.flatMap(Occupancy.init(rawValue:)),
            inCongestion: inCongestion,
            mode: mode.flatMap(VehicleMode.init(rawValue:)),
            serviceJourneyId: serviceJourney?.id,
            lineRef: line?.lineRef,
            lineName: line?.lineName,
            publicCode: line?.publicCode,
            originName: originName,
            destinationName: destinationName,
            lastUpdated: lastUpdatedEpochSecond.map { Date(timeIntervalSince1970: $0) },
            expiration: expirationEpochSecond.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

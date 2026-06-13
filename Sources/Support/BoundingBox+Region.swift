import MapKit

/// Geographic rectangle matching Entur's `BoundingBox` GraphQL input
/// (`{ minLat, minLon, maxLat, maxLon }`, all required).
struct BoundingBox: Sendable, Equatable, Encodable {
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double
}

extension BoundingBox {
    /// Derives a bounding box from a MapKit region, clamped to valid lat/lon ranges.
    init(region: MKCoordinateRegion) {
        let halfLat = max(region.span.latitudeDelta, 0) / 2
        let halfLon = max(region.span.longitudeDelta, 0) / 2
        minLat = (region.center.latitude - halfLat).clamped(to: -90...90)
        maxLat = (region.center.latitude + halfLat).clamped(to: -90...90)
        minLon = (region.center.longitude - halfLon).clamped(to: -180...180)
        maxLon = (region.center.longitude + halfLon).clamped(to: -180...180)
    }

    /// Grows the box outward by a fraction of its size so vehicles just off-screen are pre-loaded
    /// and don't pop in abruptly while panning.
    func expanded(by fraction: Double) -> BoundingBox {
        let latPad = (maxLat - minLat) * fraction
        let lonPad = (maxLon - minLon) * fraction
        return BoundingBox(
            minLat: (minLat - latPad).clamped(to: -90...90),
            minLon: (minLon - lonPad).clamped(to: -180...180),
            maxLat: (maxLat + latPad).clamped(to: -90...90),
            maxLon: (maxLon + lonPad).clamped(to: -180...180)
        )
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLat && latitude <= maxLat && longitude >= minLon && longitude <= maxLon
    }

    /// North–south extent in degrees — a proxy for zoom level.
    var latitudeSpan: Double { maxLat - minLat }

    /// Rough degrees of diagonal extent — used to decide whether a camera move is big enough to
    /// warrant re-subscribing.
    func approximatelyEquals(_ other: BoundingBox, tolerance: Double) -> Bool {
        abs(minLat - other.minLat) < tolerance && abs(minLon - other.minLon) < tolerance
            && abs(maxLat - other.maxLat) < tolerance && abs(maxLon - other.maxLon) < tolerance
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

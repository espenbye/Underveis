import Foundation

/// Decoder for Google's Encoded Polyline Algorithm Format (precision 1e5), the encoding Entur uses
/// for a service journey's `pointsOnLink.points`. Pure and dependency-free.
enum Polyline {
    /// Decodes an encoded polyline string into ordered coordinates (origin → destination).
    ///
    /// Tolerant by design: an empty or malformed string yields whatever decoded cleanly (possibly
    /// `[]`), never a crash. There are no force-unwraps and nothing throws, so a truncated payload
    /// just drops its trailing partial coordinate.
    static func decode(_ encoded: String) -> [Coordinate] {
        let scalars = Array(encoded.unicodeScalars)
        var coordinates: [Coordinate] = []
        coordinates.reserveCapacity(scalars.count / 4)

        var index = 0
        var lat = 0
        var lon = 0

        while index < scalars.count {
            guard let dLat = nextValue(scalars, &index) else { break }
            guard let dLon = nextValue(scalars, &index) else { break }
            lat += dLat
            lon += dLon
            coordinates.append(
                Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            )
        }

        return coordinates
    }

    /// Reads one zig-zag-encoded signed integer starting at `index`, advancing it past the value.
    /// Returns `nil` when the stream ends mid-value (the caller then stops decoding).
    private static func nextValue(_ scalars: [Unicode.Scalar], _ index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < scalars.count {
            let byte = Int(scalars[index].value) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20 {
                // Zig-zag decode: even → positive, odd → negative.
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        return nil
    }
}

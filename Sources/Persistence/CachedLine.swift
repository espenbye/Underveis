import Foundation
import SwiftData

/// Persisted line-colour entry. Keyed uniquely by `lineRef` so colours survive relaunch and the
/// Journey Planner API isn't re-queried for lines we've already seen.
@Model
final class CachedLine {
    @Attribute(.unique) var lineRef: String
    var publicCode: String?
    var name: String?
    var transportMode: String?
    var colourHex: String?
    var textColourHex: String?
    var fetchedAt: Date

    init(
        lineRef: String,
        publicCode: String?,
        name: String?,
        transportMode: String?,
        colourHex: String?,
        textColourHex: String?,
        fetchedAt: Date
    ) {
        self.lineRef = lineRef
        self.publicCode = publicCode
        self.name = name
        self.transportMode = transportMode
        self.colourHex = colourHex
        self.textColourHex = textColourHex
        self.fetchedAt = fetchedAt
    }
}

import Foundation
import SwiftData

/// SwiftData persistence for the personalization features (favourite stops, watched lines, and
/// recents). These mirror `CachedLine`'s conventions: a single `@Attribute(.unique)` natural key,
/// plain stored properties, and a full memberwise `init`. The `@MainActor`-isolated
/// `PersonalizationStore` keeps Sendable value snapshots of these for the UI; all writes go through
/// the background `PersonalizationWriter` actor, so SwiftUI never reads or writes these models
/// directly.
///
/// `transportModes` / `mode` are stored as plain strings (a comma-joined list, and a
/// `VehicleMode.rawValue`) rather than richer types, so the models stay free of any non-trivial
/// SwiftData attribute handling — the store does the splitting/joining at the boundary.

/// A stop the user has pinned. Keyed by its NSR id so a stop is favourited at most once and
/// re-pinning is idempotent.
@Model
final class FavoriteStop {
    @Attribute(.unique) var stopID: String
    var name: String
    var latitude: Double
    var longitude: Double
    /// Comma-joined `Stop.transportModes` (e.g. `"tram,bus"`), so the row can rebuild a full `Stop`.
    var transportModesRaw: String
    var pinnedAt: Date

    init(
        stopID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        transportModesRaw: String,
        pinnedAt: Date
    ) {
        self.stopID = stopID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.transportModesRaw = transportModesRaw
        self.pinnedAt = pinnedAt
    }
}

/// A line the user is watching. Watched lines are always shown and emphasized on the map regardless
/// of the mode filter. Keyed by `lineRef` (the Journey Planner / vehicles line id, e.g. `RUT:Line:1`).
@Model
final class WatchedLine {
    @Attribute(.unique) var lineRef: String
    var publicCode: String?
    var name: String?
    /// A `VehicleMode.rawValue` (e.g. `"TRAM"`) when known, used to broaden the live subscription so
    /// a watched line's mode is fetched even when the user filtered it out.
    var modeRaw: String?
    var watchedAt: Date

    init(lineRef: String, publicCode: String?, name: String?, modeRaw: String?, watchedAt: Date) {
        self.lineRef = lineRef
        self.publicCode = publicCode
        self.name = name
        self.modeRaw = modeRaw
        self.watchedAt = watchedAt
    }
}

/// A recently viewed stop. Same shape as `FavoriteStop`; the unique `stopID` means re-viewing a stop
/// updates `viewedAt` in place rather than creating a duplicate row.
@Model
final class RecentStop {
    @Attribute(.unique) var stopID: String
    var name: String
    var latitude: Double
    var longitude: Double
    var transportModesRaw: String
    var viewedAt: Date

    init(
        stopID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        transportModesRaw: String,
        viewedAt: Date
    ) {
        self.stopID = stopID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.transportModesRaw = transportModesRaw
        self.viewedAt = viewedAt
    }
}

/// A recently viewed line, recorded when a vehicle is selected. Lines outlive the individual
/// vehicles running them, so this — not the ephemeral vehicle — is what "recently viewed vehicle"
/// resolves to. Unique by `lineRef`; `lastDestination` is the front text of the last vehicle seen.
@Model
final class RecentLine {
    @Attribute(.unique) var lineRef: String
    var publicCode: String?
    var name: String?
    var modeRaw: String?
    var lastDestination: String?
    var viewedAt: Date

    init(
        lineRef: String,
        publicCode: String?,
        name: String?,
        modeRaw: String?,
        lastDestination: String?,
        viewedAt: Date
    ) {
        self.lineRef = lineRef
        self.publicCode = publicCode
        self.name = name
        self.modeRaw = modeRaw
        self.lastDestination = lastDestination
        self.viewedAt = viewedAt
    }
}

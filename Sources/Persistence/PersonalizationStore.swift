import Foundation
import SwiftData

/// Owns the user's personalization: favourite stops, watched lines, and recents (recent stops +
/// recent lines). Modelled exactly on `LineColorStore` — the UI reads in-memory `Sendable` value
/// snapshots (the source of truth for rendering), hydrated once from disk on launch, and every
/// mutation updates those snapshots immediately and then persists through the background
/// `PersonalizationWriter` actor so the main thread never writes SwiftData.
@MainActor
@Observable
final class PersonalizationStore {

    /// Newest-first. Favourites the user has pinned.
    private(set) var favoriteStops: [SavedStop] = []
    /// Newest-first. Stops the user recently opened (capped at `recentsCap`).
    private(set) var recentStops: [SavedStop] = []
    /// Newest-first. Lines the user is watching.
    private(set) var watchedLines: [SavedLine] = []
    /// Newest-first. Lines whose vehicles the user recently viewed (capped at `recentsCap`).
    private(set) var recentLines: [SavedLine] = []

    /// Cached so the hot filtering path (`VehiclesModel.visibleVehicles`) doesn't rebuild a set each
    /// call. Kept in sync with `watchedLines` via `rebuildWatchedDerived()`.
    private(set) var watchedLineRefs: Set<String> = []
    /// The modes of the watched lines, used by `VehiclesModel` to widen the live subscription so a
    /// watched line is fetched even when its mode is filtered out.
    private(set) var watchedModes: Set<VehicleMode> = []

    /// How many recents of each kind to keep.
    private static let recentsCap = 15

    private let writer: PersonalizationWriter

    init(container: ModelContainer) {
        self.writer = PersonalizationWriter(modelContainer: container)
        hydrate(from: container.mainContext)
    }

    // MARK: - Reads (pure; safe to call from view bodies)

    func isFavorite(stopID: String) -> Bool { favoriteStops.contains { $0.id == stopID } }
    func isWatched(lineRef: String) -> Bool { watchedLineRefs.contains(lineRef) }

    /// Resolves a stop id we may not currently have on the map — a favourite or recent — back to a
    /// full `Stop`, so tapping a saved stop can open its departures board even when it's off-screen.
    func knownStop(id: String) -> Stop? {
        (favoriteStops.first { $0.id == id } ?? recentStops.first { $0.id == id })?.stop
    }

    // MARK: - Favourites

    func toggleFavorite(_ stop: Stop) {
        if let index = favoriteStops.firstIndex(where: { $0.id == stop.id }) {
            favoriteStops.remove(at: index)
            let id = stop.id
            Task { [writer] in await writer.deleteFavorite(stopID: id) }
        } else {
            let saved = SavedStop(stop: stop, date: Date())
            favoriteStops.insert(saved, at: 0)
            Task { [writer] in await writer.upsertFavorite(saved) }
        }
    }

    // MARK: - Watched lines

    func setWatched(
        _ on: Bool,
        lineRef: String,
        publicCode: String?,
        name: String?,
        mode: VehicleMode?
    ) {
        guard !lineRef.isEmpty else { return }
        if on {
            if !watchedLineRefs.contains(lineRef) {
                let line = SavedLine(
                    lineRef: lineRef,
                    publicCode: publicCode,
                    name: name,
                    mode: mode,
                    lastDestination: nil,
                    date: Date()
                )
                watchedLines.insert(line, at: 0)
                rebuildWatchedDerived()
                Task { [writer] in await writer.upsertWatched(line) }
            }
        } else {
            watchedLines.removeAll { $0.lineRef == lineRef }
            rebuildWatchedDerived()
            let ref = lineRef
            Task { [writer] in await writer.deleteWatched(lineRef: ref) }
        }
    }

    // MARK: - Recents

    func recordStopView(_ stop: Stop) {
        let saved = SavedStop(stop: stop, date: Date())
        recentStops.removeAll { $0.id == stop.id }
        recentStops.insert(saved, at: 0)
        if recentStops.count > Self.recentsCap { recentStops.removeLast(recentStops.count - Self.recentsCap) }
        let cap = Self.recentsCap
        Task { [writer] in await writer.recordRecentStop(saved, cap: cap) }
    }

    func recordLineView(
        lineRef: String,
        publicCode: String?,
        name: String?,
        mode: VehicleMode?,
        destination: String?
    ) {
        guard !lineRef.isEmpty else { return }
        let saved = SavedLine(
            lineRef: lineRef,
            publicCode: publicCode,
            name: name,
            mode: mode,
            lastDestination: destination,
            date: Date()
        )
        recentLines.removeAll { $0.lineRef == lineRef }
        recentLines.insert(saved, at: 0)
        if recentLines.count > Self.recentsCap { recentLines.removeLast(recentLines.count - Self.recentsCap) }
        let cap = Self.recentsCap
        Task { [writer] in await writer.recordRecentLine(saved, cap: cap) }
    }

    // MARK: - Reset

    /// Wipes all personalization — favourites, recents, and watched lines — both in memory and on
    /// disk. Callers that depend on watched lines for the live feed (`VehiclesModel`) must re-scope
    /// afterwards, since this clears `watchedLineRefs`/`watchedModes`.
    func clearAll() {
        favoriteStops = []
        recentStops = []
        watchedLines = []
        recentLines = []
        rebuildWatchedDerived()
        Task { [writer] in await writer.deleteAll() }
    }

    // MARK: - Internals

    private func rebuildWatchedDerived() {
        watchedLineRefs = Set(watchedLines.map(\.lineRef))
        watchedModes = Set(watchedLines.compactMap(\.mode))
    }

    private func hydrate(from context: ModelContext) {
        if let rows = try? context.fetch(
            FetchDescriptor<FavoriteStop>(sortBy: [SortDescriptor(\.pinnedAt, order: .reverse)])
        ) {
            favoriteStops = rows.map { SavedStop(row: $0) }
        }
        if let rows = try? context.fetch(
            FetchDescriptor<RecentStop>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        ) {
            recentStops = rows.map { SavedStop(row: $0) }
        }
        if let rows = try? context.fetch(
            FetchDescriptor<WatchedLine>(sortBy: [SortDescriptor(\.watchedAt, order: .reverse)])
        ) {
            watchedLines = rows.map { SavedLine(row: $0) }
        }
        if let rows = try? context.fetch(
            FetchDescriptor<RecentLine>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        ) {
            recentLines = rows.map { SavedLine(row: $0) }
        }
        rebuildWatchedDerived()
    }
}

// MARK: - Value snapshots

/// A `Sendable` snapshot of a saved/recent stop — the UI's source of truth and the value persisted
/// by the writer. `date` is the pin time for favourites and the view time for recents.
struct SavedStop: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let transportModes: [String]
    let date: Date

    /// Rebuilds a full `Stop` so a saved stop can be selected/opened like a live one.
    var stop: Stop {
        Stop(id: id, name: name, latitude: latitude, longitude: longitude, transportModes: transportModes)
    }

    /// SF Symbol for the stop's primary mode (same mapping `Stop` uses).
    var symbolName: String { stop.symbolName }

    init(stop: Stop, date: Date) {
        self.id = stop.id
        self.name = stop.name
        self.latitude = stop.latitude
        self.longitude = stop.longitude
        self.transportModes = stop.transportModes
        self.date = date
    }

    init(row: FavoriteStop) {
        self.id = row.stopID
        self.name = row.name
        self.latitude = row.latitude
        self.longitude = row.longitude
        self.transportModes = SavedStop.split(row.transportModesRaw)
        self.date = row.pinnedAt
    }

    init(row: RecentStop) {
        self.id = row.stopID
        self.name = row.name
        self.latitude = row.latitude
        self.longitude = row.longitude
        self.transportModes = SavedStop.split(row.transportModesRaw)
        self.date = row.viewedAt
    }

    /// Comma-joined form persisted in `transportModesRaw`.
    var transportModesRaw: String { transportModes.joined(separator: ",") }

    static func split(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init)
    }
}

/// A `Sendable` snapshot of a saved/recent line. `id` is `lineRef`, so SwiftUI keeps row identity.
struct SavedLine: Identifiable, Sendable, Equatable {
    var id: String { lineRef }
    let lineRef: String
    let publicCode: String?
    let name: String?
    let mode: VehicleMode?
    let lastDestination: String?
    let date: Date

    /// Short badge label — the public line number when known.
    var shortLabel: String { publicCode ?? name ?? "?" }

    init(
        lineRef: String,
        publicCode: String?,
        name: String?,
        mode: VehicleMode?,
        lastDestination: String?,
        date: Date
    ) {
        self.lineRef = lineRef
        self.publicCode = publicCode
        self.name = name
        self.mode = mode
        self.lastDestination = lastDestination
        self.date = date
    }

    init(row: WatchedLine) {
        self.lineRef = row.lineRef
        self.publicCode = row.publicCode
        self.name = row.name
        self.mode = row.modeRaw.flatMap(VehicleMode.init(rawValue:))
        self.lastDestination = nil
        self.date = row.watchedAt
    }

    init(row: RecentLine) {
        self.lineRef = row.lineRef
        self.publicCode = row.publicCode
        self.name = row.name
        self.mode = row.modeRaw.flatMap(VehicleMode.init(rawValue:))
        self.lastDestination = row.lastDestination
        self.date = row.viewedAt
    }
}

// MARK: - Background writer

/// Background SwiftData writer for personalization. Runs off the main actor with its own
/// `ModelContext` (mirrors `LineCacheWriter`), so user actions never block UI on disk writes.
@ModelActor
actor PersonalizationWriter {

    func upsertFavorite(_ stop: SavedStop) {
        let id = stop.id
        let descriptor = FetchDescriptor<FavoriteStop>(predicate: #Predicate { $0.stopID == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = stop.name
            existing.latitude = stop.latitude
            existing.longitude = stop.longitude
            existing.transportModesRaw = stop.transportModesRaw
            existing.pinnedAt = stop.date
        } else {
            modelContext.insert(
                FavoriteStop(
                    stopID: stop.id,
                    name: stop.name,
                    latitude: stop.latitude,
                    longitude: stop.longitude,
                    transportModesRaw: stop.transportModesRaw,
                    pinnedAt: stop.date
                )
            )
        }
        try? modelContext.save()
    }

    func deleteFavorite(stopID id: String) {
        try? modelContext.delete(model: FavoriteStop.self, where: #Predicate { $0.stopID == id })
        try? modelContext.save()
    }

    func upsertWatched(_ line: SavedLine) {
        let ref = line.lineRef
        let descriptor = FetchDescriptor<WatchedLine>(predicate: #Predicate { $0.lineRef == ref })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.publicCode = line.publicCode
            existing.name = line.name
            existing.modeRaw = line.mode?.rawValue
            existing.watchedAt = line.date
        } else {
            modelContext.insert(
                WatchedLine(
                    lineRef: line.lineRef,
                    publicCode: line.publicCode,
                    name: line.name,
                    modeRaw: line.mode?.rawValue,
                    watchedAt: line.date
                )
            )
        }
        try? modelContext.save()
    }

    func deleteWatched(lineRef ref: String) {
        try? modelContext.delete(model: WatchedLine.self, where: #Predicate { $0.lineRef == ref })
        try? modelContext.save()
    }

    func recordRecentStop(_ stop: SavedStop, cap: Int) {
        let id = stop.id
        let descriptor = FetchDescriptor<RecentStop>(predicate: #Predicate { $0.stopID == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = stop.name
            existing.latitude = stop.latitude
            existing.longitude = stop.longitude
            existing.transportModesRaw = stop.transportModesRaw
            existing.viewedAt = stop.date
        } else {
            modelContext.insert(
                RecentStop(
                    stopID: stop.id,
                    name: stop.name,
                    latitude: stop.latitude,
                    longitude: stop.longitude,
                    transportModesRaw: stop.transportModesRaw,
                    viewedAt: stop.date
                )
            )
        }
        try? modelContext.save()
        prune(RecentStop.self, sortBy: SortDescriptor(\.viewedAt, order: .reverse), cap: cap)
    }

    func recordRecentLine(_ line: SavedLine, cap: Int) {
        let ref = line.lineRef
        let descriptor = FetchDescriptor<RecentLine>(predicate: #Predicate { $0.lineRef == ref })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.publicCode = line.publicCode
            existing.name = line.name
            existing.modeRaw = line.mode?.rawValue
            existing.lastDestination = line.lastDestination
            existing.viewedAt = line.date
        } else {
            modelContext.insert(
                RecentLine(
                    lineRef: line.lineRef,
                    publicCode: line.publicCode,
                    name: line.name,
                    modeRaw: line.mode?.rawValue,
                    lastDestination: line.lastDestination,
                    viewedAt: line.date
                )
            )
        }
        try? modelContext.save()
        prune(RecentLine.self, sortBy: SortDescriptor(\.viewedAt, order: .reverse), cap: cap)
    }

    /// Deletes every persisted personalization row across all four models. Backs
    /// `PersonalizationStore.clearAll()` (the "Nullstill appen" reset).
    func deleteAll() {
        try? modelContext.delete(model: FavoriteStop.self)
        try? modelContext.delete(model: RecentStop.self)
        try? modelContext.delete(model: WatchedLine.self)
        try? modelContext.delete(model: RecentLine.self)
        try? modelContext.save()
    }

    /// Deletes the oldest rows beyond `cap`, keeping the most recent `cap` by `sortBy`.
    private func prune<T: PersistentModel>(_ type: T.Type, sortBy: SortDescriptor<T>, cap: Int) {
        let descriptor = FetchDescriptor<T>(sortBy: [sortBy])
        guard let all = try? modelContext.fetch(descriptor), all.count > cap else { return }
        for row in all[cap...] { modelContext.delete(row) }
        try? modelContext.save()
    }
}

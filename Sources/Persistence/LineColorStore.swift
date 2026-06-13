import SwiftData
import SwiftUI

/// Resolves a vehicle's line to its real presentation colours, backed by a SwiftData cache.
///
/// Rendering reads colours from an in-memory dictionary (the hot path — hundreds of markers,
/// many times a second). Misses are enriched out-of-band: `enrich(_:)` batches unknown line ids,
/// queries Journey Planner, updates the in-memory map, and persists via a background `@ModelActor`
/// writer so the main thread never touches disk for writes.
@MainActor
@Observable
final class LineColorStore {

    /// Colours to paint a marker with.
    struct ResolvedColors: Equatable {
        var tint: Color
        var label: Color
    }

    private struct Entry {
        var tint: Color?  // nil → line has no presentation colour; fall back to mode tint
        var label: Color?
        var fetchedAt: Date
    }

    /// Re-enrich entries older than this (line colours change essentially never, but allow drift).
    private static let ttl: TimeInterval = 60 * 60 * 24 * 14

    private var resolved: [String: Entry] = [:]
    private var pending: Set<String> = []
    private var requested: Set<String> = []
    private var flushTask: Task<Void, Never>?

    private let container: ModelContainer
    private let journeyPlanner: JourneyPlannerClient
    private let writer: LineCacheWriter

    init(container: ModelContainer, journeyPlanner: JourneyPlannerClient = JourneyPlannerClient()) {
        self.container = container
        self.journeyPlanner = journeyPlanner
        self.writer = LineCacheWriter(modelContainer: container)
        hydrateFromDisk()
    }

    // MARK: - Reads (pure; safe to call from view bodies)

    func colors(for vehicle: Vehicle) -> ResolvedColors {
        if let ref = vehicle.lineRef, let entry = resolved[ref], let tint = entry.tint {
            return ResolvedColors(tint: tint, label: entry.label ?? .white)
        }
        return ResolvedColors(tint: vehicle.mode.fallbackColor, label: .white)
    }

    // MARK: - Enrichment

    /// Queues unknown / stale line ids for colour lookup. Debounced so a burst of vehicle updates
    /// produces a single batched request.
    func enrich(lineRefs: some Sequence<String>) {
        let now = Date()
        var added = false
        for ref in lineRefs where !ref.isEmpty && !pending.contains(ref) {
            if let entry = resolved[ref], now.timeIntervalSince(entry.fetchedAt) < Self.ttl { continue }
            requested.insert(ref)
            added = true
        }
        guard added else { return }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        let batch = requested
        requested.removeAll()
        guard !batch.isEmpty else { return }
        pending.formUnion(batch)

        let results = await journeyPlanner.lines(ids: Array(batch))

        let now = Date()
        for line in results {
            resolved[line.lineRef] = Entry(
                tint: Color(enturHex: line.colourHex),
                label: Color(enturHex: line.textColourHex),
                fetchedAt: now
            )
        }
        // Mark ids that returned nothing as "known, colourless" so we don't keep refetching them.
        for ref in batch where resolved[ref] == nil {
            resolved[ref] = Entry(tint: nil, label: nil, fetchedAt: now)
        }
        pending.subtract(batch)

        await writer.upsert(results)
    }

    private func hydrateFromDisk() {
        let descriptor = FetchDescriptor<CachedLine>()
        guard let lines = try? container.mainContext.fetch(descriptor) else { return }
        for line in lines {
            resolved[line.lineRef] = Entry(
                tint: Color(enturHex: line.colourHex),
                label: Color(enturHex: line.textColourHex),
                fetchedAt: line.fetchedAt
            )
        }
    }
}

/// Background SwiftData writer. Runs off the main actor with its own `ModelContext`, so colour
/// upserts never block UI.
@ModelActor
actor LineCacheWriter {
    func upsert(_ lines: [JourneyPlannerClient.LinePresentation]) {
        guard !lines.isEmpty else { return }
        let now = Date()
        for line in lines {
            let ref = line.lineRef
            let descriptor = FetchDescriptor<CachedLine>(predicate: #Predicate { $0.lineRef == ref })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.publicCode = line.publicCode
                existing.name = line.name
                existing.transportMode = line.transportMode
                existing.colourHex = line.colourHex
                existing.textColourHex = line.textColourHex
                existing.fetchedAt = now
            } else {
                modelContext.insert(
                    CachedLine(
                        lineRef: ref,
                        publicCode: line.publicCode,
                        name: line.name,
                        transportMode: line.transportMode,
                        colourHex: line.colourHex,
                        textColourHex: line.textColourHex,
                        fetchedAt: now
                    )
                )
            }
        }
        try? modelContext.save()
    }
}

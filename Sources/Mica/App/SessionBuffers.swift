import Foundation
import MicaCore

struct BoundedLogBuffer: Equatable, Sendable {
    static let maximumEntryCount = 2_000
    static let maximumUTF8Bytes = 8 * 1_024 * 1_024

    struct Mutation: Equatable, Sendable {
        var droppedEntryIDs: [String] = []
        var appendedEntries: [ControllerLogEntry] = []
        var reset = false

        var isEmpty: Bool {
            droppedEntryIDs.isEmpty && appendedEntries.isEmpty && !reset
        }
    }

    private struct Slot: Equatable, Sendable {
        var entry: ControllerLogEntry
        var utf8ByteCount: Int
    }

    private var storage: [Slot?]
    private var headIndex = 0
    private(set) var count = 0
    private(set) var utf8ByteCount = 0
    private(set) var rawRevision: UInt64 = 0

    var entries: [ControllerLogEntry] {
        guard count > 0 else { return [] }

        var result: [ControllerLogEntry] = []
        result.reserveCapacity(count)
        for offset in 0..<count {
            if let slot = storage[index(forOffset: offset)] {
                result.append(slot.entry)
            }
        }
        return result
    }

    var isEmpty: Bool {
        count == 0
    }

    init(entries: [ControllerLogEntry] = []) {
        storage = Array(repeating: nil, count: Self.maximumEntryCount)
        setContents(entries)
    }

    @discardableResult
    mutating func append(_ entry: ControllerLogEntry) -> Mutation {
        let mutation = append(
            Slot(
                entry: entry,
                utf8ByteCount: Self.byteCount(for: entry)
            )
        )
        rawRevision &+= 1
        return mutation
    }

    mutating func replace(with entries: [ControllerLogEntry]) {
        let replacement = BoundedLogBuffer(entries: entries)
        guard self != replacement else { return }

        storage = replacement.storage
        headIndex = replacement.headIndex
        count = replacement.count
        utf8ByteCount = replacement.utf8ByteCount
        rawRevision &+= 1
    }

    @discardableResult
    mutating func removeAll() -> Mutation {
        guard !isEmpty else { return Mutation() }

        let droppedEntryIDs = entries.map(\.id)

        for offset in 0..<count {
            let storageIndex = index(forOffset: offset)
            storage[storageIndex] = nil
        }
        headIndex = 0
        count = 0
        utf8ByteCount = 0
        rawRevision &+= 1
        return Mutation(droppedEntryIDs: droppedEntryIDs, reset: true)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count,
              lhs.utf8ByteCount == rhs.utf8ByteCount else {
            return false
        }

        for offset in 0..<lhs.count {
            guard lhs.storage[lhs.index(forOffset: offset)]?.entry
                == rhs.storage[rhs.index(forOffset: offset)]?.entry else {
                return false
            }
        }
        return true
    }

    private mutating func setContents(_ entries: [ControllerLogEntry]) {
        for entry in entries {
            _ = append(
                Slot(
                    entry: entry,
                    utf8ByteCount: Self.byteCount(for: entry)
                )
            )
        }
    }

    private mutating func append(_ slot: Slot) -> Mutation {
        var droppedEntryIDs: [String] = []
        if count == Self.maximumEntryCount {
            if let removed = removeOldest() {
                droppedEntryIDs.append(removed.entry.id)
            }
        }

        let insertionIndex = index(forOffset: count)
        storage[insertionIndex] = slot
        count += 1
        utf8ByteCount += slot.utf8ByteCount

        while utf8ByteCount > Self.maximumUTF8Bytes {
            if let removed = removeOldest() {
                droppedEntryIDs.append(removed.entry.id)
            }
        }

        let appendedEntries = count > 0 ? [slot.entry] : []
        return Mutation(
            droppedEntryIDs: droppedEntryIDs,
            appendedEntries: appendedEntries
        )
    }

    private mutating func removeOldest() -> Slot? {
        guard count > 0, let oldest = storage[headIndex] else { return nil }

        storage[headIndex] = nil
        headIndex = (headIndex + 1) % Self.maximumEntryCount
        count -= 1
        utf8ByteCount -= oldest.utf8ByteCount

        if count == 0 {
            headIndex = 0
        }
        return oldest
    }

    private func index(forOffset offset: Int) -> Int {
        (headIndex + offset) % Self.maximumEntryCount
    }

    private static func byteCount(for entry: ControllerLogEntry) -> Int {
        entry.id.utf8.count
            + entry.message.type.utf8.count
            + entry.message.payload.utf8.count
            + (entry.message.time?.utf8.count ?? 0)
            + (entry.structuredFieldsText?.utf8.count ?? 0)
    }
}

struct ClosedConnectionRecord: Identifiable, Equatable, Sendable {
    var snapshot: ConnectionSnapshot
    var closedAt: Date

    var id: String {
        snapshot.id
    }
}

struct ClosedConnectionBuffer: Equatable {
    static let maximumEntryCount = 200
    static let maximumAge: TimeInterval = 30 * 60

    private var storedRecords: [ClosedConnectionRecord]
    private var now: () -> Date
    private(set) var revision: UInt64 = 0

    var entries: [ClosedConnectionRecord] {
        records
    }

    var records: [ClosedConnectionRecord] {
        Self.visibleRecords(from: storedRecords, at: now())
    }

    var snapshots: [ConnectionSnapshot] {
        records.map(\.snapshot)
    }

    var isEmpty: Bool {
        records.isEmpty
    }

    init(
        entries: [ConnectionSnapshot] = [],
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        let receiptTime = now()
        storedRecords = Self.normalizedRecords(
            existing: [],
            incoming: entries.map {
                ClosedConnectionRecord(snapshot: $0, closedAt: receiptTime)
            },
            at: receiptTime
        )
    }

    init(
        records: [ClosedConnectionRecord],
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        storedRecords = Self.normalizedRecords(
            existing: [],
            incoming: records,
            at: now()
        )
    }

    mutating func record(_ rows: [ConnectionSnapshot]) {
        let receiptTime = now()
        record(
            rows.map {
                ClosedConnectionRecord(snapshot: $0, closedAt: receiptTime)
            },
            at: receiptTime
        )
    }

    mutating func record(_ records: [ClosedConnectionRecord]) {
        record(records, at: now())
    }

    mutating func replace(with entries: [ConnectionSnapshot]) {
        let receiptTime = now()
        replace(
            with: entries.map {
                ClosedConnectionRecord(snapshot: $0, closedAt: receiptTime)
            },
            at: receiptTime
        )
    }

    mutating func replace(with records: [ClosedConnectionRecord]) {
        replace(with: records, at: now())
    }

    mutating func pruneExpired() {
        replace(with: storedRecords, at: now())
    }

    mutating func removeAll() {
        guard !storedRecords.isEmpty else { return }
        storedRecords.removeAll(keepingCapacity: true)
        revision &+= 1
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storedRecords == rhs.storedRecords
            && lhs.revision == rhs.revision
    }

    private mutating func record(
        _ records: [ClosedConnectionRecord],
        at currentTime: Date
    ) {
        let nextRecords = Self.normalizedRecords(
            existing: storedRecords,
            incoming: records,
            at: currentTime
        )
        updateStoredRecords(nextRecords)
    }

    private mutating func replace(
        with records: [ClosedConnectionRecord],
        at currentTime: Date
    ) {
        let nextRecords = Self.normalizedRecords(
            existing: [],
            incoming: records,
            at: currentTime
        )
        updateStoredRecords(nextRecords)
    }

    private mutating func updateStoredRecords(_ nextRecords: [ClosedConnectionRecord]) {
        guard nextRecords != storedRecords else { return }
        storedRecords = nextRecords
        revision &+= 1
    }

    private static func normalizedRecords(
        existing: [ClosedConnectionRecord],
        incoming: [ClosedConnectionRecord],
        at currentTime: Date
    ) -> [ClosedConnectionRecord] {
        let uniqueIncoming = latestIncomingRecords(incoming)
        let candidates = (uniqueIncoming + existing).enumerated().map {
            (record: $0.element, tieOrder: $0.offset)
        }.sorted { lhs, rhs in
            if lhs.record.closedAt != rhs.record.closedAt {
                return lhs.record.closedAt > rhs.record.closedAt
            }
            return lhs.tieOrder < rhs.tieOrder
        }
        let cutoff = currentTime.addingTimeInterval(-Self.maximumAge)
        var seenIDs = Set<String>()
        var result: [ClosedConnectionRecord] = []
        result.reserveCapacity(min(candidates.count, Self.maximumEntryCount))

        for candidate in candidates {
            let record = candidate.record
            guard record.closedAt >= cutoff,
                  !record.id.isEmpty,
                  seenIDs.insert(record.id).inserted else {
                continue
            }
            result.append(record)
            if result.count == Self.maximumEntryCount {
                break
            }
        }
        return result
    }

    private static func latestIncomingRecords(
        _ records: [ClosedConnectionRecord]
    ) -> [ClosedConnectionRecord] {
        var latestByID: [String: (record: ClosedConnectionRecord, sourceIndex: Int)] = [:]

        for (sourceIndex, record) in records.enumerated() where !record.id.isEmpty {
            guard let current = latestByID[record.id] else {
                latestByID[record.id] = (record, sourceIndex)
                continue
            }

            if record.closedAt > current.record.closedAt
                || (record.closedAt == current.record.closedAt
                    && sourceIndex > current.sourceIndex) {
                latestByID[record.id] = (record, sourceIndex)
            }
        }

        return latestByID.values.sorted { lhs, rhs in
            if lhs.record.closedAt != rhs.record.closedAt {
                return lhs.record.closedAt > rhs.record.closedAt
            }
            return lhs.sourceIndex < rhs.sourceIndex
        }.map(\.record)
    }

    private static func visibleRecords(
        from records: [ClosedConnectionRecord],
        at currentTime: Date
    ) -> [ClosedConnectionRecord] {
        let cutoff = currentTime.addingTimeInterval(-Self.maximumAge)
        return records.filter { $0.closedAt >= cutoff }
    }
}

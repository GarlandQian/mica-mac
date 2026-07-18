import Foundation
import MicaCore

struct BoundedLogBuffer: Equatable {
    static let maximumEntryCount = 2_000
    static let maximumUTF8Bytes = 8 * 1_024 * 1_024

    private(set) var entries: [ControllerLogEntry] = []
    private(set) var utf8ByteCount = 0

    init(entries: [ControllerLogEntry] = []) {
        replace(with: entries)
    }

    mutating func append(_ entry: ControllerLogEntry) {
        entries.append(entry)
        utf8ByteCount += Self.byteCount(for: entry)
        trimToBudget()
    }

    mutating func replace(with entries: [ControllerLogEntry]) {
        self.entries = entries
        utf8ByteCount = entries.reduce(into: 0) { total, entry in
            total += Self.byteCount(for: entry)
        }
        trimToBudget()
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        utf8ByteCount = 0
    }

    private mutating func trimToBudget() {
        while entries.count > Self.maximumEntryCount || utf8ByteCount > Self.maximumUTF8Bytes {
            guard !entries.isEmpty else { break }
            let oldest = entries.removeFirst()
            utf8ByteCount -= Self.byteCount(for: oldest)
        }
    }

    private static func byteCount(for entry: ControllerLogEntry) -> Int {
        entry.id.utf8.count
            + entry.message.type.utf8.count
            + entry.message.payload.utf8.count
            + (entry.message.time?.utf8.count ?? 0)
            + (entry.structuredFieldsText?.utf8.count ?? 0)
    }
}

struct ClosedConnectionBuffer: Equatable {
    static let maximumEntryCount = 1_000
    static let maximumEstimatedBytes = 16 * 1_024 * 1_024

    private(set) var entries: [ConnectionSnapshot] = []
    private(set) var estimatedByteCount = 0

    init(entries: [ConnectionSnapshot] = []) {
        replace(with: entries)
    }

    mutating func record(_ rows: [ConnectionSnapshot]) {
        var seenIDs = Set<String>()
        let validRows = rows.reversed().filter { row in
            !row.id.isEmpty && seenIDs.insert(row.id).inserted
        }.reversed()
        guard !validRows.isEmpty else { return }

        let incomingIDs = Set(validRows.map(\.id))
        entries.removeAll { row in
            guard incomingIDs.contains(row.id) else { return false }
            estimatedByteCount -= Self.byteCount(for: row)
            return true
        }

        entries.insert(contentsOf: validRows, at: 0)
        estimatedByteCount += validRows.reduce(into: 0) { total, row in
            total += Self.byteCount(for: row)
        }
        trimToBudget()
    }

    mutating func replace(with entries: [ConnectionSnapshot]) {
        self.entries = []
        estimatedByteCount = 0
        record(entries)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        estimatedByteCount = 0
    }

    private mutating func trimToBudget() {
        while entries.count > Self.maximumEntryCount || estimatedByteCount > Self.maximumEstimatedBytes {
            guard let oldest = entries.popLast() else { break }
            estimatedByteCount -= Self.byteCount(for: oldest)
        }
    }

    private static func byteCount(for row: ConnectionSnapshot) -> Int {
        var total = row.id.utf8.count + 3 * MemoryLayout<Int>.size
        total += row.start?.utf8.count ?? 0
        total += row.rule?.utf8.count ?? 0
        total += row.rulePayload?.utf8.count ?? 0
        total += row.chains?.reduce(into: 0) { $0 += $1.utf8.count } ?? 0

        if let metadata = row.metadata {
            total += [
                metadata.host,
                metadata.network,
                metadata.type,
                metadata.sourceIP,
                metadata.destinationIP,
                metadata.sourcePort,
                metadata.destinationPort,
                metadata.process,
                metadata.processPath,
                metadata.inboundIP,
                metadata.inboundPort,
                metadata.inboundName,
                metadata.dnsMode,
                metadata.sniffHost,
            ].reduce(into: 0) { $0 += $1?.utf8.count ?? 0 }
            total += metadata.uid == nil ? 0 : MemoryLayout<Int>.size
        }

        return total
    }
}

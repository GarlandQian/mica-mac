import Foundation
import MicaCore

enum ConnectionsScope: String, CaseIterable, Identifiable, Sendable {
    case active
    case closed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .active: "traffic.connection_tab_active"
        case .closed: "traffic.connection_tab_closed"
        }
    }
}

struct ConnectionRowItem: Identifiable, Equatable, Sendable {
    let id: String
    let host: String
    let process: String
    let rule: String
    let chain: String
    let network: String
    let uploadBytes: Int
    let downloadBytes: Int
    let uploadRate: Int
    let downloadRate: Int
    let totalRate: Int
    let durationText: String
    let isActive: Bool
    let snapshot: ConnectionSnapshot
    let closedAt: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.isActive == rhs.isActive
            && lhs.uploadBytes == rhs.uploadBytes
            && lhs.downloadBytes == rhs.downloadBytes
            && lhs.uploadRate == rhs.uploadRate
            && lhs.downloadRate == rhs.downloadRate
            && lhs.host == rhs.host
            && lhs.chain == rhs.chain
            && lhs.rule == rhs.rule
    }
}

/// Lean store for Connections: diffs by catalog structure/metric revisions and sorts natively.
@MainActor
@Observable
final class ConnectionsStore {
    private(set) var rows: [ConnectionRowItem] = []
    private(set) var totalActiveCount = 0
    private(set) var totalClosedCount = 0

    var scope: ConnectionsScope = .active {
        didSet {
            guard oldValue != scope else { return }
            rebuildRows()
        }
    }

    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            rebuildRows()
        }
    }

    var sortOrder: [KeyPathComparator<ConnectionRowItem>] = [
        KeyPathComparator(\.downloadBytes, order: .reverse),
    ] {
        didSet {
            rebuildRows()
        }
    }

    @ObservationIgnored private var activeSnapshots: [ConnectionSnapshot] = []
    @ObservationIgnored private var closedRecords: [ClosedConnectionRecord] = []
    @ObservationIgnored private var lastStructureRevision: UInt64?
    @ObservationIgnored private var lastMetricsRevision: UInt64?
    @ObservationIgnored private var lastClosedRevision: UInt64?

    func sync(
        activeCatalog: ConnectionsCatalogSnapshot,
        closedRecords: [ClosedConnectionRecord],
        closedRevision: UInt64
    ) {
        let activeChanged = lastStructureRevision != activeCatalog.structureRevision
            || lastMetricsRevision != activeCatalog.metricsRevision
        let closedChanged = lastClosedRevision != closedRevision

        guard activeChanged || closedChanged else { return }

        if activeChanged {
            lastStructureRevision = activeCatalog.structureRevision
            lastMetricsRevision = activeCatalog.metricsRevision
            activeSnapshots = activeCatalog.connections
            totalActiveCount = activeSnapshots.count
        }
        if closedChanged {
            lastClosedRevision = closedRevision
            self.closedRecords = closedRecords
            totalClosedCount = closedRecords.count
        }
        rebuildRows()
    }

    func item(id: String) -> ConnectionRowItem? {
        rows.first { $0.id == id }
    }

    private func rebuildRows() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        var next: [ConnectionRowItem] = []

        switch scope {
        case .active:
            next.reserveCapacity(activeSnapshots.count)
            for conn in activeSnapshots {
                let item = Self.makeItem(from: conn, isActive: true, closedAt: nil, now: now)
                if Self.matches(item, query: query) {
                    next.append(item)
                }
            }
        case .closed:
            next.reserveCapacity(closedRecords.count)
            for record in closedRecords {
                let item = Self.makeItem(from: record.snapshot, isActive: false, closedAt: record.closedAt, now: now)
                if Self.matches(item, query: query) {
                    next.append(item)
                }
            }
        }

        next.sort(using: sortOrder)
        if next != rows {
            rows = next
        }
    }

    private static func makeItem(
        from conn: ConnectionSnapshot,
        isActive: Bool,
        closedAt: Date?,
        now: Date
    ) -> ConnectionRowItem {
        let meta = conn.metadata
        let hostText: String
        if let host = meta?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            hostText = host
        } else if let dest = meta?.destinationIP?.trimmingCharacters(in: .whitespacesAndNewlines), !dest.isEmpty {
            hostText = dest
        } else {
            hostText = conn.id
        }

        let processText = meta?.process?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "-"
        let ruleText: String = {
            let r = conn.rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let p = conn.rulePayload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if r.isEmpty && p.isEmpty { return "-" }
            if p.isEmpty { return r }
            if r.isEmpty { return p }
            return "\(r) (\(p))"
        }()
        let chainText = (conn.chains?.isEmpty == false ? conn.chains!.reversed().joined(separator: " → ") : nil) ?? "-"
        let networkText = [meta?.network?.uppercased(), meta?.type]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " · ")

        let upRate = conn.uploadSpeed ?? 0
        let downRate = conn.downloadSpeed ?? 0

        return ConnectionRowItem(
            id: conn.id,
            host: hostText,
            process: processText,
            rule: ruleText,
            chain: chainText,
            network: networkText.isEmpty ? "-" : networkText,
            uploadBytes: conn.upload ?? 0,
            downloadBytes: conn.download ?? 0,
            uploadRate: upRate,
            downloadRate: downRate,
            totalRate: upRate + downRate,
            durationText: MicaFormatters.formatDuration(from: conn.start, now: now),
            isActive: isActive,
            snapshot: conn,
            closedAt: closedAt
        )
    }

    private static func matches(_ item: ConnectionRowItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return item.host.lowercased().contains(query)
            || item.process.lowercased().contains(query)
            || item.chain.lowercased().contains(query)
            || item.rule.lowercased().contains(query)
            || item.network.lowercased().contains(query)
    }
}

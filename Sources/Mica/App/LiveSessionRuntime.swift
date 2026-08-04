import Foundation
import MicaCore

struct LiveSessionRuntimeIdentity: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
}

struct LiveSessionConnectionRevisions: Equatable, Sendable {
    private(set) var structure: UInt64 = 0
    private(set) var metrics: UInt64 = 0
    private(set) var traffic: UInt64 = 0

    mutating func record(structureChanged: Bool, metricsChanged: Bool, trafficChanged: Bool) {
        if structureChanged { structure &+= 1 }
        if metricsChanged { metrics &+= 1 }
        if trafficChanged { traffic &+= 1 }
    }
}

struct LiveSessionObservationDelta: Equatable, Sendable {
    var source: ControllerSessionLiveSource = .none
    var trafficSamples = 0
    var memorySamples = 0
    var connectionFrames = 0
    var logEvents = 0

    var totalEventCount: Int {
        trafficSamples + memorySamples + connectionFrames + logEvents
    }

    mutating func record(
        source: ControllerSessionLiveSource,
        trafficSamples: Int = 0,
        memorySamples: Int = 0,
        connectionFrames: Int = 0,
        logEvents: Int = 0
    ) {
        self.source = source
        self.trafficSamples += max(trafficSamples, 0)
        self.memorySamples += max(memorySamples, 0)
        self.connectionFrames += max(connectionFrames, 0)
        self.logEvents += max(logEvents, 0)
    }
}

struct LiveSessionLogsPublication: Equatable, Sendable {
    let sequence: UInt64
    let fullSnapshot: [ControllerLogEntry]?
    let droppedEntryIDs: [String]
    let appendedEntries: [ControllerLogEntry]
}

struct LiveSessionTrafficPublication: Equatable, Sendable {
    let timeline: TrafficTimeline
    let latestRate: TrafficSnapshot
    let singBoxStatus: SingBoxStatusSnapshot?
}

struct LiveSessionMemoryPublication: Equatable, Sendable {
    let timeline: MemoryTimeline
    let latestResponse: MemoryResponse?
    let runtime: ControllerSessionRuntimeState
}

enum LiveSessionConnectionsSource: Equatable, Sendable {
    case mihomo(ConnectionsResponse)
    case singBox([ConnectionSnapshot])
}

struct LiveSessionConnectionsPublication: Equatable, Sendable {
    let source: LiveSessionConnectionsSource
    let timeline: ConnectionCountTimeline
    let revisions: LiveSessionConnectionRevisions
    /// Changed metric row positions since the previous publication. `nil`
    /// requires a complete metric refresh because structure changed.
    let changedMetricIndices: [Int]?
    let closedRecords: [ClosedConnectionRecord]
    let clearsClosedRecords: Bool
}

enum LiveSessionRuntimePublicationPayload: Equatable, Sendable {
    case logs(LiveSessionLogsPublication)
    case traffic(LiveSessionTrafficPublication)
    case memory(LiveSessionMemoryPublication)
    case connections(LiveSessionConnectionsPublication)
}

struct LiveSessionRuntimePublication: Equatable, Sendable {
    let identity: LiveSessionRuntimeIdentity
    let domain: LiveSessionPublicationDomain
    let revision: UInt64
    let receivedAt: Date
    let observation: LiveSessionObservationDelta
    let payload: LiveSessionRuntimePublicationPayload
}

actor LiveSessionRuntime {
    private let identity: LiveSessionRuntimeIdentity
    private let controllerKind: ControllerKind

    private var isActive = true
    private var presentationDemand: LiveSessionPresentationDemand
    private var rawRevisions: [LiveSessionPublicationDomain: UInt64] = [:]
    private var publishedRevisions: [LiveSessionPublicationDomain: UInt64] = [:]
    private var scheduledDomains: Set<LiveSessionPublicationDomain> = []
    private var receivedAtByDomain: [LiveSessionPublicationDomain: Date] = [:]
    private var observationsByDomain: [LiveSessionPublicationDomain: LiveSessionObservationDelta] = [:]

    private var logBuffer = BoundedLogBuffer()
    private var logNeedsFullSnapshot = true
    private var pendingLogDroppedEntryIDs: [String] = []
    private var pendingLogAppendedEntries: [ControllerLogEntry] = []

    private var trafficTimeline = TrafficTimeline()
    private var memoryTimeline = MemoryTimeline()
    private var connectionCountTimeline = ConnectionCountTimeline()
    private var latestMemoryResponse: MemoryResponse?
    private var latestSingBoxStatus: SingBoxStatusSnapshot?
    private var runtimeState = ControllerSessionRuntimeState()

    private var connectionTransferRates = ConnectionTransferRateTracker()
    private var mihomoConnections: ConnectionsResponse?
    private var singBoxConnections = OrderedConnectionStore()
    private var connectionSource: ConnectionSource = .mihomo
    private var connectionRevisions = LiveSessionConnectionRevisions()
    private var connectionNeedsFullMetricRefresh = true
    private var pendingConnectionMetricIndices: Set<Int> = []
    private var pendingClosedRecords: [ClosedConnectionRecord] = []
    private var clearsClosedRecords = false

    init(
        controllerKind: ControllerKind,
        initialPresentationDemand: LiveSessionPresentationDemand
    ) {
        identity = initialPresentationDemand.identity
        self.controllerKind = controllerKind
        presentationDemand = initialPresentationDemand
    }

    func currentIdentity() -> LiveSessionRuntimeIdentity {
        identity
    }

    func currentPresentationDemand() -> LiveSessionPresentationDemand {
        presentationDemand
    }

    func setPresentationDemand(
        _ demand: LiveSessionPresentationDemand
    ) -> Set<LiveSessionPublicationDomain>? {
        guard isActive,
              demand.identity == identity,
              demand.revision > presentationDemand.revision else {
            return nil
        }
        presentationDemand = demand

        var result: Set<LiveSessionPublicationDomain> = []
        for domain in LiveSessionPublicationDomain.allCases where reserveScheduleIfNeeded(domain) {
            result.insert(domain)
        }
        return result
    }

    func ingestTraffic(
        _ event: LiveTrafficEvent,
        source: ControllerSessionLiveSource,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        trafficTimeline.append(
            upload: event.upload,
            download: event.download,
            receivedAt: receivedAt
        )
        recordObservation(.traffic, source: source, trafficSamples: 1)
        return markDirty(.traffic, receivedAt: receivedAt)
    }

    func ingestLog(
        _ message: LogMessage,
        source: ControllerSessionLiveSource,
        receivedAt: Date = Date(),
        id: String = UUID().uuidString
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        let entry = ControllerLogEntry(id: id, receivedAt: receivedAt, message: message)
        mergeLogMutation(logBuffer.append(entry))
        recordObservation(.logs, source: source, logEvents: 1)
        return markDirty(.logs, receivedAt: receivedAt)
    }

    func ingestLogs(
        _ messages: [LogMessage],
        reset: Bool,
        source: ControllerSessionLiveSource,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        if reset {
            _ = logBuffer.removeAll()
            logNeedsFullSnapshot = true
            pendingLogDroppedEntryIDs.removeAll(keepingCapacity: true)
            pendingLogAppendedEntries.removeAll(keepingCapacity: true)
        }
        for (index, message) in messages.enumerated() {
            let entry = ControllerLogEntry(
                id: "runtime:\(logBuffer.rawRevision):\(index)",
                receivedAt: receivedAt,
                message: message
            )
            mergeLogMutation(logBuffer.append(entry))
        }
        recordObservation(.logs, source: source, logEvents: messages.count)
        return markDirty(.logs, receivedAt: receivedAt)
    }

    func clearLogs(receivedAt: Date = Date()) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        _ = logBuffer.removeAll()
        logNeedsFullSnapshot = true
        pendingLogDroppedEntryIDs.removeAll(keepingCapacity: true)
        pendingLogAppendedEntries.removeAll(keepingCapacity: true)
        return markDirty(.logs, receivedAt: receivedAt)
    }

    func ingestMemory(
        _ response: MemoryResponse,
        source: ControllerSessionLiveSource,
        timelineSource: MemoryTimeline.Source = .memoryEndpoint,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        if let inUse = response.inuse {
            memoryTimeline.append(
                inUseBytes: inUse,
                source: timelineSource,
                receivedAt: receivedAt
            )
        }
        latestMemoryResponse = response
        runtimeState.recordMemory(response, receivedAt: receivedAt)
        recordObservation(.memory, source: source, memorySamples: 1)
        return markDirty(.memory, receivedAt: receivedAt)
    }

    func ingestMihomoConnections(
        _ response: ConnectionsResponse,
        source: ControllerSessionLiveSource = .mihomoWebSocket,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        connectionSource = .mihomo
        let enriched = connectionTransferRates.enriching(response, receivedAt: receivedAt)
        let previous = mihomoConnections
        let changes = Self.connectionChanges(previous: previous, next: enriched)
        recordPendingConnectionChanges(changes)
        connectionRevisions.record(
            structureChanged: changes.structure,
            metricsChanged: changes.metrics,
            trafficChanged: changes.traffic
        )
        recordClosedRecords(
            Self.closedRecords(
                previous: previous?.connections ?? [],
                next: enriched.connections,
                receivedAt: receivedAt
            ),
            receivedAt: receivedAt
        )
        mihomoConnections = enriched
        connectionCountTimeline.append(
            activeCount: enriched.connections.count,
            receivedAt: receivedAt
        )
        recordObservation(.connections, source: source, connectionFrames: 1)

        var domains = markDirty(.connections, receivedAt: receivedAt)
        if let memory = enriched.memory {
            domains.formUnion(
                ingestMemory(
                    MemoryResponse(inuse: memory),
                    source: source,
                    timelineSource: .connectionsFrame,
                    receivedAt: receivedAt
                )
            )
        }
        return domains
    }

    func ingestSingBoxStatus(
        _ status: SingBoxStatusSnapshot,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        trafficTimeline.append(
            upload: Int(clamping: status.uplinkBytesPerSecond),
            download: Int(clamping: status.downlinkBytesPerSecond),
            receivedAt: receivedAt
        )
        memoryTimeline.append(
            inUseBytes: Int(clamping: status.memoryBytes),
            source: .runtimeStatus,
            receivedAt: receivedAt
        )
        runtimeState.recordSingBoxStatus(status, receivedAt: receivedAt)
        latestSingBoxStatus = status
        latestMemoryResponse = MemoryResponse(inuse: Int(clamping: status.memoryBytes))
        recordObservation(.traffic, source: .singBoxGRPC, trafficSamples: 1)
        recordObservation(.memory, source: .singBoxGRPC, memorySamples: 1)
        var domains = markDirty(.traffic, receivedAt: receivedAt)
        domains.formUnion(markDirty(.memory, receivedAt: receivedAt))
        return domains
    }

    func ingestSingBoxConnections(
        _ batch: SingBoxConnectionEventBatch,
        receivedAt: Date = Date()
    ) -> Set<LiveSessionPublicationDomain> {
        guard isActive else { return [] }
        connectionSource = .singBox
        let previousConnections = singBoxConnections.values
        var closedRecords: [ClosedConnectionRecord] = []
        if batch.reset {
            singBoxConnections.removeAll()
            pendingClosedRecords.removeAll(keepingCapacity: true)
            clearsClosedRecords = true
        }

        for event in batch.events {
            switch event.type.rawValue {
            case SingBoxConnectionEventType.closed.rawValue:
                let existing = singBoxConnections.remove(id: event.id)
                if let connection = event.connection {
                    closedRecords.append(
                        ClosedConnectionRecord(
                            snapshot: ConnectionSnapshot(singBox: connection),
                            closedAt: receivedAt
                        )
                    )
                } else if let existing {
                    closedRecords.append(
                        ClosedConnectionRecord(snapshot: existing, closedAt: receivedAt)
                    )
                }

            default:
                guard let connection = event.connection else { continue }
                let row = ConnectionSnapshot(singBox: connection)
                _ = singBoxConnections.upsert(row)
            }
        }
        recordClosedRecords(closedRecords, receivedAt: receivedAt)
        let changes = Self.connectionChanges(
            previous: previousConnections,
            next: singBoxConnections.values,
            trafficChanged: false
        )
        recordPendingConnectionChanges(changes)

        connectionRevisions.record(
            structureChanged: changes.structure,
            metricsChanged: changes.metrics,
            trafficChanged: false
        )
        connectionCountTimeline.append(
            activeCount: singBoxConnections.values.count,
            receivedAt: receivedAt
        )
        recordObservation(.connections, source: .singBoxGRPC, connectionFrames: 1)
        return markDirty(.connections, receivedAt: receivedAt)
    }

    func publication(
        for domain: LiveSessionPublicationDomain,
        force: Bool = false,
        demandRevision: UInt64? = nil
    ) -> LiveSessionRuntimePublication? {
        guard isActive else {
            return nil
        }

        let demandIsCurrent = demandRevision.map {
            $0 == presentationDemand.revision
        } ?? true
        scheduledDomains.remove(domain)
        guard canPublish(
            domain,
            force: force && demandIsCurrent
        ) else {
            return nil
        }
        let revision = rawRevisions[domain] ?? 0
        guard revision != (publishedRevisions[domain] ?? 0),
              let receivedAt = receivedAtByDomain[domain],
              let payload = makePayload(for: domain) else {
            return nil
        }

        publishedRevisions[domain] = revision
        let observation = observationsByDomain.removeValue(forKey: domain)
            ?? LiveSessionObservationDelta()
        MicaPerformanceObservation.record(
            .rawFrameIngestion,
            metadata: MicaPerformanceMetadata(
                count: UInt64(clamping: observation.totalEventCount),
                revision: revision,
                controllerKind: controllerKind
            )
        )
        MicaPerformanceObservation.record(
            .sessionPublication,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: revision,
                controllerKind: controllerKind
            )
        )
        return LiveSessionRuntimePublication(
            identity: identity,
            domain: domain,
            revision: revision,
            receivedAt: receivedAt,
            observation: observation,
            payload: payload
        )
    }

    func cancelScheduledPublication(_ domain: LiveSessionPublicationDomain) {
        scheduledDomains.remove(domain)
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        scheduledDomains.removeAll()
        rawRevisions.removeAll()
        publishedRevisions.removeAll()
        receivedAtByDomain.removeAll()
        observationsByDomain.removeAll()
        _ = logBuffer.removeAll()
        pendingLogDroppedEntryIDs.removeAll()
        pendingLogAppendedEntries.removeAll()
        trafficTimeline.reset()
        memoryTimeline.reset()
        connectionCountTimeline.reset()
        latestMemoryResponse = nil
        latestSingBoxStatus = nil
        runtimeState.reset()
        connectionTransferRates.reset()
        mihomoConnections = nil
        singBoxConnections.removeAll()
        connectionNeedsFullMetricRefresh = true
        pendingConnectionMetricIndices.removeAll()
        pendingClosedRecords.removeAll()
        clearsClosedRecords = false
    }

    private func markDirty(
        _ domain: LiveSessionPublicationDomain,
        receivedAt: Date
    ) -> Set<LiveSessionPublicationDomain> {
        rawRevisions[domain, default: 0] &+= 1
        receivedAtByDomain[domain] = max(receivedAtByDomain[domain] ?? receivedAt, receivedAt)
        return reserveScheduleIfNeeded(domain) ? [domain] : []
    }

    private func reserveScheduleIfNeeded(_ domain: LiveSessionPublicationDomain) -> Bool {
        guard canPublish(domain, force: false),
              rawRevisions[domain, default: 0] != publishedRevisions[domain, default: 0],
              !scheduledDomains.contains(domain) else {
            return false
        }
        scheduledDomains.insert(domain)
        return true
    }

    private func canPublish(
        _ domain: LiveSessionPublicationDomain,
        force: Bool
    ) -> Bool {
        if presentationDemand.baselinePublicationRequired, domain != .logs {
            return true
        }
        guard !presentationDemand.presentationPaused else { return false }
        if domain == .logs, presentationDemand.logsPresentationPaused {
            return false
        }
        return force || presentationDemand.observes(domain)
    }

    private func recordObservation(
        _ domain: LiveSessionPublicationDomain,
        source: ControllerSessionLiveSource,
        trafficSamples: Int = 0,
        memorySamples: Int = 0,
        connectionFrames: Int = 0,
        logEvents: Int = 0
    ) {
        observationsByDomain[domain, default: LiveSessionObservationDelta()].record(
            source: source,
            trafficSamples: trafficSamples,
            memorySamples: memorySamples,
            connectionFrames: connectionFrames,
            logEvents: logEvents
        )
    }

    private func makePayload(
        for domain: LiveSessionPublicationDomain
    ) -> LiveSessionRuntimePublicationPayload? {
        switch domain {
        case .logs:
            let publication: LiveSessionLogsPublication
            if logNeedsFullSnapshot {
                publication = LiveSessionLogsPublication(
                    sequence: logBuffer.rawRevision,
                    fullSnapshot: logBuffer.entries,
                    droppedEntryIDs: [],
                    appendedEntries: []
                )
            } else {
                publication = LiveSessionLogsPublication(
                    sequence: logBuffer.rawRevision,
                    fullSnapshot: nil,
                    droppedEntryIDs: pendingLogDroppedEntryIDs,
                    appendedEntries: pendingLogAppendedEntries
                )
            }
            logNeedsFullSnapshot = false
            pendingLogDroppedEntryIDs.removeAll(keepingCapacity: true)
            pendingLogAppendedEntries.removeAll(keepingCapacity: true)
            return .logs(publication)

        case .traffic:
            let latest = trafficTimeline.samples.last
            return .traffic(
                LiveSessionTrafficPublication(
                    timeline: trafficTimeline,
                    latestRate: TrafficSnapshot(
                        upload: latest?.upload ?? 0,
                        download: latest?.download ?? 0
                    ),
                    singBoxStatus: latestSingBoxStatus
                )
            )

        case .memory:
            return .memory(
                LiveSessionMemoryPublication(
                    timeline: memoryTimeline,
                    latestResponse: latestMemoryResponse,
                    runtime: runtimeState
                )
            )

        case .connections:
            let source: LiveSessionConnectionsSource
            switch connectionSource {
            case .mihomo:
                guard let mihomoConnections else { return nil }
                source = .mihomo(mihomoConnections)
            case .singBox:
                source = .singBox(singBoxConnections.values)
            }
            let publication = LiveSessionConnectionsPublication(
                source: source,
                timeline: connectionCountTimeline,
                revisions: connectionRevisions,
                changedMetricIndices: connectionNeedsFullMetricRefresh
                    ? nil
                    : pendingConnectionMetricIndices.sorted(),
                closedRecords: pendingClosedRecords,
                clearsClosedRecords: clearsClosedRecords
            )
            connectionNeedsFullMetricRefresh = false
            pendingConnectionMetricIndices.removeAll(keepingCapacity: true)
            pendingClosedRecords.removeAll(keepingCapacity: true)
            clearsClosedRecords = false
            return .connections(publication)
        }
    }

    private func mergeLogMutation(_ mutation: BoundedLogBuffer.Mutation) {
        guard !logNeedsFullSnapshot else { return }
        pendingLogDroppedEntryIDs.append(contentsOf: mutation.droppedEntryIDs)
        pendingLogAppendedEntries.append(contentsOf: mutation.appendedEntries)
        if pendingLogDroppedEntryIDs.count + pendingLogAppendedEntries.count
            > BoundedLogBuffer.maximumEntryCount * 2 {
            logNeedsFullSnapshot = true
            pendingLogDroppedEntryIDs.removeAll(keepingCapacity: true)
            pendingLogAppendedEntries.removeAll(keepingCapacity: true)
        }
    }

    private func recordClosedRecords(
        _ records: [ClosedConnectionRecord],
        receivedAt: Date
    ) {
        guard !records.isEmpty else { return }
        let cutoff = receivedAt.addingTimeInterval(-ClosedConnectionBuffer.maximumAge)
        pendingClosedRecords.removeAll { $0.closedAt < cutoff }
        pendingClosedRecords.append(contentsOf: records)
        if pendingClosedRecords.count > ClosedConnectionBuffer.maximumEntryCount {
            pendingClosedRecords.removeFirst(
                pendingClosedRecords.count - ClosedConnectionBuffer.maximumEntryCount
            )
        }
    }

    private struct ConnectionChanges {
        let structure: Bool
        let metrics: Bool
        let traffic: Bool
        let changedMetricIndices: [Int]
    }

    private func recordPendingConnectionChanges(_ changes: ConnectionChanges) {
        if changes.structure {
            connectionNeedsFullMetricRefresh = true
            pendingConnectionMetricIndices.removeAll(keepingCapacity: true)
        } else if !connectionNeedsFullMetricRefresh {
            pendingConnectionMetricIndices.formUnion(changes.changedMetricIndices)
        }
    }

    private static func connectionChanges(
        previous: ConnectionsResponse?,
        next: ConnectionsResponse
    ) -> ConnectionChanges {
        let traffic = previous?.uploadTotal != next.uploadTotal
            || previous?.downloadTotal != next.downloadTotal
            || previous?.memory != next.memory
        return connectionChanges(
            previous: previous?.connections,
            next: next.connections,
            trafficChanged: traffic
        )
    }

    private static func connectionChanges(
        previous: [ConnectionSnapshot]?,
        next: [ConnectionSnapshot],
        trafficChanged: Bool
    ) -> ConnectionChanges {
        guard let previous else {
            return ConnectionChanges(
                structure: !next.isEmpty,
                metrics: !next.isEmpty,
                traffic: trafficChanged,
                changedMetricIndices: Array(next.indices)
            )
        }

        let structure = previous.count != next.count
            || !zip(previous, next).allSatisfy { pair in
                connectionStructureEquals(pair.0, pair.1)
            }
        if structure {
            return ConnectionChanges(
                structure: true,
                metrics: true,
                traffic: trafficChanged,
                changedMetricIndices: Array(next.indices)
            )
        }

        var changedMetricIndices: [Int] = []
        changedMetricIndices.reserveCapacity(min(next.count, 32))
        for index in next.indices
        where !connectionMetricsEquals(previous[index], next[index]) {
            changedMetricIndices.append(index)
        }
        return ConnectionChanges(
            structure: false,
            metrics: !changedMetricIndices.isEmpty,
            traffic: trafficChanged,
            changedMetricIndices: changedMetricIndices
        )
    }

    private static func connectionStructureEquals(
        _ lhs: ConnectionSnapshot,
        _ rhs: ConnectionSnapshot
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.start == rhs.start
            && lhs.chains == rhs.chains
            && lhs.providerChains == rhs.providerChains
            && lhs.rule == rhs.rule
            && lhs.rulePayload == rhs.rulePayload
            && lhs.metadata == rhs.metadata
            && lhs.fields == rhs.fields
    }

    private static func connectionMetricsEquals(
        _ lhs: ConnectionSnapshot,
        _ rhs: ConnectionSnapshot
    ) -> Bool {
        lhs.upload == rhs.upload
            && lhs.download == rhs.download
            && lhs.uploadSpeed == rhs.uploadSpeed
            && lhs.downloadSpeed == rhs.downloadSpeed
    }

    private static func closedRecords(
        previous: [ConnectionSnapshot],
        next: [ConnectionSnapshot],
        receivedAt: Date
    ) -> [ClosedConnectionRecord] {
        let nextIDs = Set(occurrenceIDList(for: next))
        return zip(previous, occurrenceIDList(for: previous)).compactMap { connection, occurrenceID in
            guard !nextIDs.contains(occurrenceID) else { return nil }
            return ClosedConnectionRecord(snapshot: connection, closedAt: receivedAt)
        }
    }

    private static func occurrenceIDList(
        for connections: [ConnectionSnapshot]
    ) -> [ConnectionOccurrenceID] {
        var counts: [String: Int] = [:]
        var result: [ConnectionOccurrenceID] = []
        result.reserveCapacity(connections.count)
        for connection in connections {
            let occurrence = counts[connection.id, default: 0]
            counts[connection.id] = occurrence + 1
            result.append(ConnectionOccurrenceID(id: connection.id, occurrence: occurrence))
        }
        return result
    }

    private enum ConnectionSource {
        case mihomo
        case singBox
    }

    private struct ConnectionOccurrenceID: Hashable {
        let id: String
        let occurrence: Int
    }

    private struct OrderedConnectionStore {
        struct UpsertResult {
            let structureChanged: Bool
            let metricsChanged: Bool
        }

        private var storage: [ConnectionSnapshot?] = []
        private var indexByID: [String: Int] = [:]
        private var tombstoneCount = 0

        var isEmpty: Bool { indexByID.isEmpty }

        var values: [ConnectionSnapshot] {
            storage.compactMap { $0 }
        }

        mutating func upsert(_ row: ConnectionSnapshot) -> UpsertResult {
            if let index = indexByID[row.id], let previous = storage[index] {
                storage[index] = row
                let structureChanged = !LiveSessionRuntime.connectionStructureEquals(previous, row)
                return UpsertResult(
                    structureChanged: structureChanged,
                    metricsChanged: structureChanged
                        || !LiveSessionRuntime.connectionMetricsEquals(previous, row)
                )
            }

            indexByID[row.id] = storage.count
            storage.append(row)
            return UpsertResult(structureChanged: true, metricsChanged: true)
        }

        mutating func remove(id: String) -> ConnectionSnapshot? {
            guard let index = indexByID.removeValue(forKey: id),
                  let previous = storage[index] else {
                return nil
            }
            storage[index] = nil
            tombstoneCount += 1
            compactIfNeeded()
            return previous
        }

        mutating func removeAll() {
            storage.removeAll(keepingCapacity: true)
            indexByID.removeAll(keepingCapacity: true)
            tombstoneCount = 0
        }

        private mutating func compactIfNeeded() {
            guard tombstoneCount >= 64,
                  tombstoneCount * 3 >= storage.count else {
                return
            }
            storage = storage.compactMap { $0 }.map(Optional.some)
            indexByID.removeAll(keepingCapacity: true)
            indexByID.reserveCapacity(storage.count)
            for (index, connection) in storage.enumerated() {
                guard let connection else { continue }
                indexByID[connection.id] = index
            }
            tombstoneCount = 0
        }
    }
}

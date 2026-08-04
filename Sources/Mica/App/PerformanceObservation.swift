import MicaCore
import OSLog
import Synchronization

enum MicaPerformanceCategory: CaseIterable, Sendable {
    case ingestion
    case publication
    case projection
    case topology
    case interaction
    case rendering
    case refresh
    case retry
    case transport
    case persistence
    case localization
}

enum MicaPerformanceOperation: Int, CaseIterable, Sendable {
    case rawFrameIngestion
    case sessionPublication
    case connectionProjection
    case ruleProjection
    case sourceProjection
    case logProjection
    case proxyProjection
    case fullPresentationProjection
    case incrementalPresentationProjection
    case topologyNormalization
    case topologyLayout
    case topologyHitIndex
    case topologyCanvasPresentation
    case topologyBasePresentation
    case topologyHighlightPresentation
    case topologyAccessibilityPresentation
    case scrollPhase
    case dataTableEvaluation
    case refreshFlight
    case retryBackoff
    case transportClientCreation
    case persistenceRead
    case persistenceWrite
    case workspaceEncoding
    case workspacePersistence
    case localizationLookup
    case localizationCacheMiss
    case formatterCacheMiss

    var category: MicaPerformanceCategory {
        switch self {
        case .rawFrameIngestion:
            .ingestion
        case .sessionPublication:
            .publication
        case .connectionProjection, .ruleProjection, .sourceProjection, .logProjection, .proxyProjection,
             .fullPresentationProjection, .incrementalPresentationProjection:
            .projection
        case .topologyNormalization, .topologyLayout, .topologyHitIndex, .topologyCanvasPresentation,
             .topologyBasePresentation, .topologyHighlightPresentation,
             .topologyAccessibilityPresentation:
            .topology
        case .scrollPhase:
            .interaction
        case .dataTableEvaluation:
            .rendering
        case .refreshFlight:
            .refresh
        case .retryBackoff:
            .retry
        case .transportClientCreation:
            .transport
        case .persistenceRead, .persistenceWrite, .workspaceEncoding, .workspacePersistence:
            .persistence
        case .localizationLookup, .localizationCacheMiss, .formatterCacheMiss:
            .localization
        }
    }

    fileprivate var signpostName: StaticString {
        switch self {
        case .rawFrameIngestion:
            "Raw Frame Ingestion"
        case .sessionPublication:
            "Session Publication"
        case .connectionProjection:
            "Connection Projection"
        case .ruleProjection:
            "Rule Projection"
        case .sourceProjection:
            "Source Projection"
        case .logProjection:
            "Log Projection"
        case .proxyProjection:
            "Proxy Projection"
        case .fullPresentationProjection:
            "Full Presentation Projection"
        case .incrementalPresentationProjection:
            "Incremental Presentation Projection"
        case .topologyNormalization:
            "Topology Normalization"
        case .topologyLayout:
            "Topology Layout"
        case .topologyHitIndex:
            "Topology Hit Index"
        case .topologyCanvasPresentation:
            "Topology Canvas Presentation"
        case .topologyBasePresentation:
            "Topology Base Presentation"
        case .topologyHighlightPresentation:
            "Topology Highlight Presentation"
        case .topologyAccessibilityPresentation:
            "Topology Accessibility Presentation"
        case .scrollPhase:
            "Scroll Phase"
        case .dataTableEvaluation:
            "Data Table Evaluation"
        case .refreshFlight:
            "Refresh Flight"
        case .retryBackoff:
            "Retry Backoff"
        case .transportClientCreation:
            "Transport Client Creation"
        case .persistenceRead:
            "Persistence Read"
        case .persistenceWrite:
            "Persistence Write"
        case .workspaceEncoding:
            "Workspace Encoding"
        case .workspacePersistence:
            "Workspace Persistence"
        case .localizationLookup:
            "Localization Lookup"
        case .localizationCacheMiss:
            "Localization Cache Miss"
        case .formatterCacheMiss:
            "Formatter Cache Miss"
        }
    }
}

enum MicaPerformanceControllerKind: CaseIterable, Sendable {
    case unspecified
    case autoDetect
    case mihomoCompatible
    case nikkiMihomoCompatible
    case openClashMihomoCompatible
    case surgeCompatible
    case singBoxCompatible
    case cmfaCompatible
    case stashCompatible
    case stashCmfaCompatible
    case unknown
    case unsupported

    init(_ controllerKind: ControllerKind) {
        switch controllerKind {
        case .autoDetect:
            self = .autoDetect
        case .mihomoCompatible:
            self = .mihomoCompatible
        case .nikkiMihomoCompatible:
            self = .nikkiMihomoCompatible
        case .openClashMihomoCompatible:
            self = .openClashMihomoCompatible
        case .surgeCompatible:
            self = .surgeCompatible
        case .singBoxCompatible:
            self = .singBoxCompatible
        case .cmfaCompatible:
            self = .cmfaCompatible
        case .stashCompatible:
            self = .stashCompatible
        case .stashCmfaCompatible:
            self = .stashCmfaCompatible
        case .unknown:
            self = .unknown
        case .unsupported:
            self = .unsupported
        }
    }

    fileprivate var signpostValue: StaticString {
        switch self {
        case .unspecified:
            "unspecified"
        case .autoDetect:
            "auto-detect"
        case .mihomoCompatible:
            "mihomo-compatible"
        case .nikkiMihomoCompatible:
            "nikki-mihomo-compatible"
        case .openClashMihomoCompatible:
            "openclash-mihomo-compatible"
        case .surgeCompatible:
            "surge-compatible"
        case .singBoxCompatible:
            "sing-box-compatible"
        case .cmfaCompatible:
            "cmfa-compatible"
        case .stashCompatible:
            "stash-compatible"
        case .stashCmfaCompatible:
            "stash-cmfa-compatible"
        case .unknown:
            "unknown"
        case .unsupported:
            "unsupported"
        }
    }
}

/// Fixed metadata boundary for signposts. Do not add controller business-value strings here.
struct MicaPerformanceMetadata: Equatable, Sendable {
    let count: UInt64
    let revision: UInt64
    let duration: Duration
    let controllerKind: MicaPerformanceControllerKind

    init(
        count: UInt64 = 0,
        revision: UInt64 = 0,
        duration: Duration = .zero,
        controllerKind: ControllerKind? = nil
    ) {
        self.count = count
        self.revision = revision
        self.duration = duration < .zero ? .zero : duration
        self.controllerKind = controllerKind.map(MicaPerformanceControllerKind.init) ?? .unspecified
    }
}

struct MicaPerformanceCounter: Equatable, Sendable {
    private(set) var eventCount: UInt64 = 0
    private(set) var intervalStartCount: UInt64 = 0
    private(set) var intervalEndCount: UInt64 = 0
    private(set) var reportedCount: UInt64 = 0
    private(set) var maximumRevision: UInt64 = 0
    private(set) var totalDuration: Duration = .zero

    var completedObservationCount: UInt64 {
        eventCount + intervalEndCount
    }

    fileprivate mutating func recordEvent(_ metadata: MicaPerformanceMetadata) {
        eventCount += 1
        absorb(metadata)
    }

    fileprivate mutating func recordIntervalStart() {
        intervalStartCount += 1
    }

    fileprivate mutating func recordIntervalEnd(_ metadata: MicaPerformanceMetadata) {
        intervalEndCount += 1
        absorb(metadata)
    }

    fileprivate mutating func merge(_ other: MicaPerformanceCounter) {
        eventCount += other.eventCount
        intervalStartCount += other.intervalStartCount
        intervalEndCount += other.intervalEndCount
        reportedCount += other.reportedCount
        maximumRevision = max(maximumRevision, other.maximumRevision)
        totalDuration += other.totalDuration
    }

    private mutating func absorb(_ metadata: MicaPerformanceMetadata) {
        reportedCount += metadata.count
        maximumRevision = max(maximumRevision, metadata.revision)
        totalDuration += metadata.duration
    }
}

struct MicaPerformanceCounterSnapshot: Equatable, Sendable {
    private let values: [MicaPerformanceCounter]

    fileprivate init(values: [MicaPerformanceCounter]) {
        self.values = values
    }

    subscript(operation: MicaPerformanceOperation) -> MicaPerformanceCounter {
        values[operation.rawValue]
    }

    func total(for category: MicaPerformanceCategory) -> MicaPerformanceCounter {
        var total = MicaPerformanceCounter()
        for operation in MicaPerformanceOperation.allCases where operation.category == category {
            total.merge(values[operation.rawValue])
        }
        return total
    }

    var isEmpty: Bool {
        values.allSatisfy { $0 == MicaPerformanceCounter() }
    }
}

final class MicaPerformanceCounterStore: Sendable {
    private let state: Mutex<[MicaPerformanceCounter]>

    init() {
        state = Mutex(Self.makeStorage())
    }

    func recordEvent(
        _ operation: MicaPerformanceOperation,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) {
        state.withLock { values in
            values[operation.rawValue].recordEvent(metadata)
        }
    }

    func recordIntervalStart(_ operation: MicaPerformanceOperation) {
        state.withLock { values in
            values[operation.rawValue].recordIntervalStart()
        }
    }

    func recordIntervalEnd(
        _ operation: MicaPerformanceOperation,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) {
        state.withLock { values in
            values[operation.rawValue].recordIntervalEnd(metadata)
        }
    }

    func snapshot() -> MicaPerformanceCounterSnapshot {
        state.withLock { values in
            MicaPerformanceCounterSnapshot(values: values)
        }
    }

    func reset() {
        state.withLock { values in
            values = Self.makeStorage()
        }
    }

    private static func makeStorage() -> [MicaPerformanceCounter] {
        Array(repeating: MicaPerformanceCounter(), count: MicaPerformanceOperation.allCases.count)
    }
}

struct MicaPerformanceInterval: Sendable {
    fileprivate let operation: MicaPerformanceOperation
    fileprivate let state: OSSignpostIntervalState?
}

enum MicaPerformanceObservation {
    private static let counterStore = MicaPerformanceCounterStore()

    static func record(
        _ operation: MicaPerformanceOperation,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) {
        counterStore.recordEvent(operation, metadata: metadata)

        let signposter = MicaPerformanceSignposters.signposter(for: operation.category)
        guard signposter.isEnabled else { return }
        let duration = metadata.duration.components
        signposter.emitEvent(
            operation.signpostName,
            "count=\(metadata.count, privacy: .public) revision=\(metadata.revision, privacy: .public) duration-seconds=\(duration.seconds, privacy: .public) duration-attoseconds=\(duration.attoseconds, privacy: .public) controller=\(metadata.controllerKind.signpostValue, privacy: .public)"
        )
    }

    static func recordDebug(
        _ operation: MicaPerformanceOperation,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) {
#if DEBUG
        record(operation, metadata: metadata)
#endif
    }

    static func beginInterval(
        _ operation: MicaPerformanceOperation,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) -> MicaPerformanceInterval {
        counterStore.recordIntervalStart(operation)

        let signposter = MicaPerformanceSignposters.signposter(for: operation.category)
        guard signposter.isEnabled else {
            return MicaPerformanceInterval(operation: operation, state: nil)
        }
        let duration = metadata.duration.components
        let state = signposter.beginInterval(
            operation.signpostName,
            "count=\(metadata.count, privacy: .public) revision=\(metadata.revision, privacy: .public) duration-seconds=\(duration.seconds, privacy: .public) duration-attoseconds=\(duration.attoseconds, privacy: .public) controller=\(metadata.controllerKind.signpostValue, privacy: .public)"
        )
        return MicaPerformanceInterval(operation: operation, state: state)
    }

    static func endInterval(
        _ interval: MicaPerformanceInterval,
        metadata: MicaPerformanceMetadata = MicaPerformanceMetadata()
    ) {
        counterStore.recordIntervalEnd(interval.operation, metadata: metadata)

        guard let state = interval.state else { return }
        let signposter = MicaPerformanceSignposters.signposter(for: interval.operation.category)
        let duration = metadata.duration.components
        signposter.endInterval(
            interval.operation.signpostName,
            state,
            "count=\(metadata.count, privacy: .public) revision=\(metadata.revision, privacy: .public) duration-seconds=\(duration.seconds, privacy: .public) duration-attoseconds=\(duration.attoseconds, privacy: .public) controller=\(metadata.controllerKind.signpostValue, privacy: .public)"
        )
    }

    static func counterSnapshot() -> MicaPerformanceCounterSnapshot {
        counterStore.snapshot()
    }

    static func resetCounters() {
        counterStore.reset()
    }
}

private enum MicaPerformanceSignposters {
    private static let subsystem = "dev.mica.mica"

    static let ingestion = OSSignposter(subsystem: subsystem, category: "performance.ingestion")
    static let publication = OSSignposter(subsystem: subsystem, category: "performance.publication")
    static let projection = OSSignposter(subsystem: subsystem, category: "performance.projection")
    static let topology = OSSignposter(subsystem: subsystem, category: "performance.topology")
    static let interaction = OSSignposter(subsystem: subsystem, category: "performance.interaction")
    static let rendering = OSSignposter(subsystem: subsystem, category: "performance.rendering")
    static let refresh = OSSignposter(subsystem: subsystem, category: "performance.refresh")
    static let retry = OSSignposter(subsystem: subsystem, category: "performance.retry")
    static let transport = OSSignposter(subsystem: subsystem, category: "performance.transport")
    static let persistence = OSSignposter(subsystem: subsystem, category: "performance.persistence")
    static let localization = OSSignposter(subsystem: subsystem, category: "performance.localization")

    static func signposter(for category: MicaPerformanceCategory) -> OSSignposter {
        switch category {
        case .ingestion:
            ingestion
        case .publication:
            publication
        case .projection:
            projection
        case .topology:
            topology
        case .interaction:
            interaction
        case .rendering:
            rendering
        case .refresh:
            refresh
        case .retry:
            retry
        case .transport:
            transport
        case .persistence:
            persistence
        case .localization:
            localization
        }
    }
}

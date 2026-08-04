import Foundation

/// Controller-received memory samples retained for at most five minutes.
/// This is session data, not a Workbench presentation type.
struct MemoryTimeline: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case memoryEndpoint
        case connectionsFrame
        case runtimeStatus
    }

    struct Sample: Identifiable, Equatable, Sendable {
        let id: Int
        let receivedAt: Date
        let inUseBytes: Int
        let source: Source
    }

    static let maximumSampleCount = 300
    static let retentionDuration: TimeInterval = 5 * 60

    private(set) var samples: [Sample] = []
    private var nextSampleID = 0
    private var latestReceivedAt: Date?
    let capacity: Int

    init(capacity: Int = Self.maximumSampleCount) {
        self.capacity = max(capacity, 1)
    }

    var isEmpty: Bool { samples.isEmpty }

    mutating func append(
        inUseBytes: Int,
        source: Source = .memoryEndpoint,
        receivedAt: Date = Date()
    ) {
        if let latest = samples.last,
           latest.inUseBytes == max(inUseBytes, 0),
           latest.source != source,
           abs(latest.receivedAt.timeIntervalSince(receivedAt)) < 0.25 {
            return
        }

        samples.append(
            Sample(
                id: nextSampleID,
                receivedAt: receivedAt,
                inUseBytes: max(inUseBytes, 0),
                source: source
            )
        )
        nextSampleID += 1
        trim(receivedAt: receivedAt)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        nextSampleID = 0
        latestReceivedAt = nil
    }

    private mutating func trim(receivedAt: Date) {
        latestReceivedAt = max(latestReceivedAt ?? receivedAt, receivedAt)
        if let latestReceivedAt {
            let cutoff = latestReceivedAt.addingTimeInterval(-Self.retentionDuration)
            samples.removeAll { $0.receivedAt < cutoff }
        }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

/// Controller-received active-connection counts retained for at most five minutes.
/// Samples are appended only when a real connection snapshot or event batch arrives.
struct ConnectionCountTimeline: Equatable, Sendable {
    struct Sample: Identifiable, Equatable, Sendable {
        let id: Int
        let receivedAt: Date
        let activeCount: Int
    }

    static let maximumSampleCount = 300
    static let retentionDuration: TimeInterval = 5 * 60

    private(set) var samples: [Sample] = []
    private var nextSampleID = 0
    private var latestReceivedAt: Date?
    let capacity: Int

    init(capacity: Int = Self.maximumSampleCount) {
        self.capacity = max(capacity, 1)
    }

    var isEmpty: Bool { samples.isEmpty }

    mutating func append(
        activeCount: Int,
        receivedAt: Date = Date()
    ) {
        samples.append(
            Sample(
                id: nextSampleID,
                receivedAt: receivedAt,
                activeCount: max(activeCount, 0)
            )
        )
        nextSampleID += 1
        trim(receivedAt: receivedAt)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        nextSampleID = 0
        latestReceivedAt = nil
    }

    private mutating func trim(receivedAt: Date) {
        latestReceivedAt = max(latestReceivedAt ?? receivedAt, receivedAt)
        if let latestReceivedAt {
            let cutoff = latestReceivedAt.addingTimeInterval(-Self.retentionDuration)
            samples.removeAll { $0.receivedAt < cutoff }
        }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

/// Controller-received transfer-rate samples retained for at most five minutes.
/// No timer, interpolation, or placeholder sample is introduced here.
struct TrafficTimeline: Equatable, Sendable {
    struct Sample: Identifiable, Equatable, Sendable {
        let id: Int
        let receivedAt: Date
        let upload: Int
        let download: Int
    }

    static let maximumSampleCount = 300
    static let retentionDuration: TimeInterval = 5 * 60

    private(set) var samples: [Sample] = []
    private var nextSampleID = 0
    private var latestReceivedAt: Date?
    let capacity: Int

    init(capacity: Int = Self.maximumSampleCount) {
        self.capacity = max(capacity, 1)
    }

    var isEmpty: Bool { samples.isEmpty }

    mutating func append(
        upload: Int,
        download: Int,
        receivedAt: Date = Date()
    ) {
        samples.append(
            Sample(
                id: nextSampleID,
                receivedAt: receivedAt,
                upload: max(upload, 0),
                download: max(download, 0)
            )
        )
        nextSampleID += 1
        trim(receivedAt: receivedAt)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        nextSampleID = 0
        latestReceivedAt = nil
    }

    private mutating func trim(receivedAt: Date) {
        latestReceivedAt = max(latestReceivedAt ?? receivedAt, receivedAt)
        if let latestReceivedAt {
            let cutoff = latestReceivedAt.addingTimeInterval(-Self.retentionDuration)
            samples.removeAll { $0.receivedAt < cutoff }
        }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

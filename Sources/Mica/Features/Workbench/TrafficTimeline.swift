import Foundation

/// A bounded presentation history of rates that actually arrived from a live controller.
/// It deliberately has no timer, interpolation, or placeholder samples.
struct TrafficTimeline: Equatable {
    struct Sample: Identifiable, Equatable {
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

    var isEmpty: Bool {
        samples.isEmpty
    }

    mutating func append(upload: Int, download: Int, receivedAt: Date = Date()) {
        samples.append(
            Sample(
                id: nextSampleID,
                receivedAt: receivedAt,
                upload: max(upload, 0),
                download: max(download, 0)
            )
        )
        nextSampleID += 1
        latestReceivedAt = max(latestReceivedAt ?? receivedAt, receivedAt)

        if let latestReceivedAt {
            let cutoff = latestReceivedAt.addingTimeInterval(-Self.retentionDuration)
            samples.removeAll { $0.receivedAt < cutoff }
        }

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        nextSampleID = 0
        latestReceivedAt = nil
    }
}

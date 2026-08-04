import Foundation

enum SessionRefreshRequestSource: Equatable, Sendable {
    case periodic
    case manual

    func merged(with other: SessionRefreshRequestSource) -> SessionRefreshRequestSource {
        self == .manual || other == .manual ? .manual : .periodic
    }
}

enum SessionRefreshRetryDecision: Equatable, Sendable {
    case retry
    case stop
    case cancel
}

enum SessionRefreshCoordinatorError: Error, Equatable, Sendable {
    case generationInvalidated
}

enum SessionRefreshFlightPhase: Equatable, Sendable {
    case initial
    case followUp
}

struct SessionRefreshLaneStatus: Equatable, Sendable {
    var phase: SessionRefreshFlightPhase?
    var hasPendingFollowUp: Bool

    static let idle = SessionRefreshLaneStatus(
        phase: nil,
        hasPendingFollowUp: false
    )

    var isInFlight: Bool {
        phase != nil
    }
}

struct SessionRefreshFlight: Sendable {
    let id: UUID
    let generation: UUID
    fileprivate let task: Task<Void, Error>

    func wait() async throws {
        try await task.value
    }
}

actor SessionRefreshCoordinator {
    typealias Operation = @Sendable (
        _ lane: SessionRefreshLane,
        _ generation: UUID,
        _ source: SessionRefreshRequestSource
    ) async throws -> Void
    typealias RetryDecision = @Sendable (
        _ error: any Error,
        _ retryCount: Int
    ) -> SessionRefreshRetryDecision
    typealias Backoff = @Sendable (_ retryCount: Int) -> Duration
    typealias Sleep = @Sendable (_ duration: Duration) async throws -> Void

    private struct PendingRequest {
        var source: SessionRefreshRequestSource
        var operation: Operation
    }

    private struct FlightState {
        let id: UUID
        var phase: SessionRefreshFlightPhase
        var pendingFollowUp: PendingRequest?
        let task: Task<Void, Error>
    }

    private(set) var generation: UUID?
    private var flights: [SessionRefreshLane: FlightState] = [:]
    private let retryDecision: RetryDecision
    private let backoff: Backoff
    private let sleep: Sleep

    init(
        generation: UUID,
        retryDecision: @escaping RetryDecision = { error, retryCount in
            switch RouterTrialFailureCategory(error: error).retryDisposition {
            case .transient:
                return .retry
            case .retryOnce:
                return retryCount == 0 ? .retry : .stop
            case .terminal:
                return .stop
            case .cancelled:
                return .cancel
            }
        },
        backoff: @escaping Backoff = { retryCount in
            SessionRetryPolicy.delay(forAttempt: retryCount)
        },
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.generation = generation
        self.retryDecision = retryDecision
        self.backoff = backoff
        self.sleep = sleep
    }

    func enqueue(
        _ lane: SessionRefreshLane,
        source: SessionRefreshRequestSource,
        generation: UUID,
        operation: @escaping Operation
    ) throws -> SessionRefreshFlight {
        try ensureGeneration(generation)

        if var flight = flights[lane] {
            if flight.phase == .initial {
                if var pending = flight.pendingFollowUp {
                    pending.source = pending.source.merged(with: source)
                    pending.operation = operation
                    flight.pendingFollowUp = pending
                } else {
                    flight.pendingFollowUp = PendingRequest(
                        source: source,
                        operation: operation
                    )
                }
                flights[lane] = flight
            }

            return SessionRefreshFlight(
                id: flight.id,
                generation: generation,
                task: flight.task
            )
        }

        let flightID = UUID()
        let task = Task { [weak self] in
            guard let self else {
                throw SessionRefreshCoordinatorError.generationInvalidated
            }
            try await self.runFlight(
                lane: lane,
                generation: generation,
                flightID: flightID,
                initialSource: source,
                initialOperation: operation
            )
        }
        flights[lane] = FlightState(
            id: flightID,
            phase: .initial,
            pendingFollowUp: nil,
            task: task
        )

        return SessionRefreshFlight(
            id: flightID,
            generation: generation,
            task: task
        )
    }

    func request(
        _ lane: SessionRefreshLane,
        source: SessionRefreshRequestSource,
        generation: UUID,
        operation: @escaping Operation
    ) async throws {
        let flight = try enqueue(
            lane,
            source: source,
            generation: generation,
            operation: operation
        )
        try await flight.wait()
    }

    func status(
        for lane: SessionRefreshLane,
        generation: UUID
    ) -> SessionRefreshLaneStatus {
        guard self.generation == generation,
              let flight = flights[lane] else {
            return .idle
        }
        return SessionRefreshLaneStatus(
            phase: flight.phase,
            hasPendingFollowUp: flight.pendingFollowUp != nil
        )
    }

    func cancel(
        _ lane: SessionRefreshLane,
        generation: UUID
    ) {
        guard self.generation == generation,
              let flight = flights.removeValue(forKey: lane) else {
            return
        }
        flight.task.cancel()
    }

    func invalidate(generation: UUID) {
        guard self.generation == generation else { return }
        self.generation = nil
        cancelAllFlights()
    }

    func replaceGeneration(with generation: UUID) {
        guard self.generation != generation else { return }
        self.generation = generation
        cancelAllFlights()
    }

    private func runFlight(
        lane: SessionRefreshLane,
        generation: UUID,
        flightID: UUID,
        initialSource: SessionRefreshRequestSource,
        initialOperation: @escaping Operation
    ) async throws {
        let interval = MicaPerformanceObservation.beginInterval(
            .refreshFlight,
            metadata: MicaPerformanceMetadata(count: 1)
        )
        defer {
            finishFlight(lane: lane, flightID: flightID)
            MicaPerformanceObservation.endInterval(
                interval,
                metadata: MicaPerformanceMetadata(count: 1)
            )
        }

        var source = initialSource
        var operation = initialOperation
        var mayRunFollowUp = true

        while true {
            try await runAttempts(
                lane: lane,
                generation: generation,
                flightID: flightID,
                source: source,
                operation: operation
            )

            guard mayRunFollowUp,
                  let followUp = takeFollowUp(
                    lane: lane,
                    generation: generation,
                    flightID: flightID
                  ) else {
                return
            }

            mayRunFollowUp = false
            source = followUp.source
            operation = followUp.operation
        }
    }

    private func runAttempts(
        lane: SessionRefreshLane,
        generation: UUID,
        flightID: UUID,
        source: SessionRefreshRequestSource,
        operation: Operation
    ) async throws {
        var retryCount = 0

        while true {
            try ensureCurrentFlight(
                lane: lane,
                generation: generation,
                flightID: flightID
            )

            do {
                try await operation(lane, generation, source)
                try ensureCurrentFlight(
                    lane: lane,
                    generation: generation,
                    flightID: flightID
                )
                return
            } catch is CancellationError {
                try ensureCurrentFlight(
                    lane: lane,
                    generation: generation,
                    flightID: flightID
                )
                throw CancellationError()
            } catch let error as SessionRefreshCoordinatorError {
                throw error
            } catch {
                try ensureCurrentFlight(
                    lane: lane,
                    generation: generation,
                    flightID: flightID
                )

                switch retryDecision(error, retryCount) {
                case .stop:
                    throw error
                case .cancel:
                    throw CancellationError()
                case .retry:
                    let delay = backoff(retryCount)
                    MicaPerformanceObservation.record(
                        .retryBackoff,
                        metadata: MicaPerformanceMetadata(
                            count: 1,
                            revision: UInt64(clamping: retryCount),
                            duration: delay
                        )
                    )
                    retryCount += 1
                    do {
                        try await sleep(delay)
                    } catch is CancellationError {
                        try ensureCurrentFlight(
                            lane: lane,
                            generation: generation,
                            flightID: flightID
                        )
                        throw CancellationError()
                    }
                }
            }
        }
    }

    private func takeFollowUp(
        lane: SessionRefreshLane,
        generation: UUID,
        flightID: UUID
    ) -> PendingRequest? {
        guard self.generation == generation,
              var flight = flights[lane],
              flight.id == flightID,
              flight.phase == .initial,
              let followUp = flight.pendingFollowUp else {
            return nil
        }

        flight.phase = .followUp
        flight.pendingFollowUp = nil
        flights[lane] = flight
        return followUp
    }

    private func finishFlight(
        lane: SessionRefreshLane,
        flightID: UUID
    ) {
        guard flights[lane]?.id == flightID else { return }
        flights[lane] = nil
    }

    private func ensureGeneration(_ generation: UUID) throws {
        guard self.generation == generation else {
            throw SessionRefreshCoordinatorError.generationInvalidated
        }
    }

    private func ensureCurrentFlight(
        lane: SessionRefreshLane,
        generation: UUID,
        flightID: UUID
    ) throws {
        try ensureGeneration(generation)
        guard flights[lane]?.id == flightID else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func cancelAllFlights() {
        let tasks = flights.values.map(\.task)
        flights.removeAll(keepingCapacity: true)
        for task in tasks {
            task.cancel()
        }
    }
}

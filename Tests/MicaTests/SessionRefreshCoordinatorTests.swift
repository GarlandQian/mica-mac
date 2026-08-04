import Foundation
import Testing
@testable import Mica

private enum SessionRefreshTestError: Error, Equatable, Sendable {
    case transient
    case terminal
}

private struct ControlledRefreshSnapshot: Equatable, Sendable {
    var callCount: Int
    var maximumActiveCount: Int
    var sources: [SessionRefreshRequestSource]
}

private actor ControlledRefreshOperation {
    private var callCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var sources: [SessionRefreshRequestSource] = []
    private var blockedCalls: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func perform(
        lane: SessionRefreshLane,
        generation: UUID,
        source: SessionRefreshRequestSource
    ) async {
        _ = lane
        _ = generation
        callCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        sources.append(source)
        resumeCallWaiters()

        await withCheckedContinuation { continuation in
            blockedCalls.append(continuation)
        }
        activeCount -= 1
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expectedCount, continuation))
        }
    }

    func releaseNext() {
        guard !blockedCalls.isEmpty else { return }
        blockedCalls.removeFirst().resume()
    }

    func snapshot() -> ControlledRefreshSnapshot {
        ControlledRefreshSnapshot(
            callCount: callCount,
            maximumActiveCount: maximumActiveCount,
            sources: sources
        )
    }

    private func resumeCallWaiters() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in callWaiters {
            if callCount >= waiter.0 {
                waiter.1.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }
}

private struct RetryOperationSnapshot: Equatable, Sendable {
    var attemptCount: Int
    var maximumActiveCount: Int
}

private actor ScriptedRetryOperation {
    private let transientFailureCount: Int
    private let terminalFailure: Bool
    private var attemptCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0

    init(transientFailureCount: Int = 0, terminalFailure: Bool = false) {
        self.transientFailureCount = transientFailureCount
        self.terminalFailure = terminalFailure
    }

    func perform() throws {
        attemptCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }

        if terminalFailure {
            throw SessionRefreshTestError.terminal
        }
        if attemptCount <= transientFailureCount {
            throw SessionRefreshTestError.transient
        }
    }

    func snapshot() -> RetryOperationSnapshot {
        RetryOperationSnapshot(
            attemptCount: attemptCount,
            maximumActiveCount: maximumActiveCount
        )
    }
}

private actor BackoffRecorder {
    private var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

private actor CancellableBackoff {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async throws {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
        try await Task.sleep(for: .seconds(60))
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private actor CompletionRecorder {
    private var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }

    func count() -> Int {
        values.count
    }

    func recordedValues() -> [String] {
        values
    }
}

struct SessionRefreshCoordinatorTests {
    @Test func duplicateManualAndPeriodicRequestsUseOneBoundedFollowUp() async throws {
        let generation = UUID()
        let operation = ControlledRefreshOperation()
        let completions = CompletionRecorder()
        let coordinator = SessionRefreshCoordinator(
            generation: generation,
            retryDecision: { _, _ in .stop },
            backoff: { _ in .zero },
            sleep: { _ in }
        )
        let perform: SessionRefreshCoordinator.Operation = { lane, generation, source in
            await operation.perform(
                lane: lane,
                generation: generation,
                source: source
            )
        }

        let first = try await coordinator.enqueue(
            .medium,
            source: .periodic,
            generation: generation,
            operation: perform
        )
        await operation.waitForCallCount(1)

        let second = try await coordinator.enqueue(
            .medium,
            source: .manual,
            generation: generation,
            operation: perform
        )
        let third = try await coordinator.enqueue(
            .medium,
            source: .periodic,
            generation: generation,
            operation: perform
        )

        #expect(first.id == second.id)
        #expect(first.id == third.id)
        #expect(
            await coordinator.status(for: .medium, generation: generation)
                == SessionRefreshLaneStatus(phase: .initial, hasPendingFollowUp: true)
        )

        let initialWaiters = [first, second, third].map { flight in
            Task {
                try await flight.wait()
                await completions.record("joined")
            }
        }

        await operation.releaseNext()
        await operation.waitForCallCount(2)
        #expect(await completions.count() == 0)

        let fourth = try await coordinator.enqueue(
            .medium,
            source: .manual,
            generation: generation,
            operation: perform
        )
        #expect(fourth.id == first.id)
        #expect(
            await coordinator.status(for: .medium, generation: generation)
                == SessionRefreshLaneStatus(phase: .followUp, hasPendingFollowUp: false)
        )
        let fourthWaiter = Task {
            try await fourth.wait()
            await completions.record("joined")
        }

        await operation.releaseNext()
        for waiter in initialWaiters {
            try await waiter.value
        }
        try await fourthWaiter.value

        let snapshot = await operation.snapshot()
        #expect(snapshot.callCount == 2)
        #expect(snapshot.maximumActiveCount == 1)
        #expect(snapshot.sources == [.periodic, .manual])
        #expect(await completions.count() == 4)
        #expect(
            await coordinator.status(for: .medium, generation: generation) == .idle
        )
    }

    @Test func transientFailuresRetryIterativelyUntilSuccess() async throws {
        let generation = UUID()
        let transientFailureCount = 512
        let operation = ScriptedRetryOperation(
            transientFailureCount: transientFailureCount
        )
        let backoffRecorder = BackoffRecorder()
        let coordinator = SessionRefreshCoordinator(
            generation: generation,
            retryDecision: { error, _ in
                error as? SessionRefreshTestError == .transient ? .retry : .stop
            },
            backoff: { retryCount in
                .milliseconds(Int64(retryCount + 1))
            },
            sleep: { duration in
                await backoffRecorder.record(duration)
            }
        )

        try await coordinator.request(
            .slow,
            source: .periodic,
            generation: generation
        ) { _, _, _ in
            try await operation.perform()
        }

        let snapshot = await operation.snapshot()
        let backoffs = await backoffRecorder.recordedDurations()
        #expect(snapshot.attemptCount == transientFailureCount + 1)
        #expect(snapshot.maximumActiveCount == 1)
        #expect(backoffs.count == transientFailureCount)
        #expect(backoffs.first == .milliseconds(1))
        #expect(backoffs.last == .milliseconds(Int64(transientFailureCount)))
    }

    @Test func terminalFailureDoesNotRetryOrRunBackoff() async throws {
        let generation = UUID()
        let operation = ScriptedRetryOperation(terminalFailure: true)
        let backoffRecorder = BackoffRecorder()
        let coordinator = SessionRefreshCoordinator(
            generation: generation,
            retryDecision: { _, _ in .stop },
            backoff: { _ in .seconds(30) },
            sleep: { duration in
                await backoffRecorder.record(duration)
            }
        )

        do {
            try await coordinator.request(
                .fast,
                source: .manual,
                generation: generation
            ) { _, _, _ in
                try await operation.perform()
            }
            Issue.record("Expected terminal refresh failure")
        } catch let error as SessionRefreshTestError {
            #expect(error == .terminal)
        }

        let snapshot = await operation.snapshot()
        #expect(snapshot.attemptCount == 1)
        #expect(await backoffRecorder.recordedDurations().isEmpty)
        #expect(
            await coordinator.status(for: .fast, generation: generation) == .idle
        )
    }

    @Test func cancellingLaneDuringBackoffStopsTheFlight() async throws {
        let generation = UUID()
        let operation = ScriptedRetryOperation(transientFailureCount: .max)
        let backoff = CancellableBackoff()
        let coordinator = SessionRefreshCoordinator(
            generation: generation,
            retryDecision: { _, _ in .retry },
            backoff: { _ in .seconds(60) },
            sleep: { _ in
                try await backoff.sleep()
            }
        )
        let flight = try await coordinator.enqueue(
            .medium,
            source: .periodic,
            generation: generation
        ) { _, _, _ in
            try await operation.perform()
        }

        await backoff.waitUntilStarted()
        await coordinator.cancel(.medium, generation: generation)

        do {
            try await flight.wait()
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        #expect((await operation.snapshot()).attemptCount == 1)
        #expect(
            await coordinator.status(for: .medium, generation: generation) == .idle
        )
    }

    @Test func generationReplacementRejectsOldCompletionWithoutClearingNewFlight() async throws {
        let oldGeneration = UUID()
        let newGeneration = UUID()
        let oldOperation = ControlledRefreshOperation()
        let publications = CompletionRecorder()
        let coordinator = SessionRefreshCoordinator(
            generation: oldGeneration,
            retryDecision: { _, _ in .stop },
            backoff: { _ in .zero },
            sleep: { _ in }
        )
        let oldFlight = try await coordinator.enqueue(
            .slow,
            source: .periodic,
            generation: oldGeneration
        ) { lane, generation, source in
            await oldOperation.perform(
                lane: lane,
                generation: generation,
                source: source
            )
        }
        await oldOperation.waitForCallCount(1)

        let oldPublisher = Task { () -> Bool in
            do {
                try await oldFlight.wait()
                await publications.record("old")
                return false
            } catch let error as SessionRefreshCoordinatorError {
                return error == .generationInvalidated
            } catch {
                return false
            }
        }

        await coordinator.replaceGeneration(with: newGeneration)
        let newFlight = try await coordinator.enqueue(
            .slow,
            source: .manual,
            generation: newGeneration
        ) { _, _, _ in }
        try await newFlight.wait()
        await publications.record("new")

        await oldOperation.releaseNext()
        #expect(await oldPublisher.value)
        #expect(await publications.recordedValues() == ["new"])
        #expect(
            await coordinator.status(for: .slow, generation: newGeneration) == .idle
        )
    }
}

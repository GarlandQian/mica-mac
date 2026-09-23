import Foundation
import Testing
@testable import Mica

private actor SupervisedTaskGate {
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
struct LiveSessionTaskSupervisorTests {
    private func makeSupervisor() -> (LiveSessionTaskSupervisor, LiveSessionRuntimeIdentity) {
        let identity = LiveSessionRuntimeIdentity(controllerID: UUID(), generation: UUID())
        let supervisor = LiveSessionTaskSupervisor()
        supervisor.bind(to: identity)
        return (supervisor, identity)
    }

    private func startEverySlot(
        in supervisor: LiveSessionTaskSupervisor,
        identity: LiveSessionRuntimeIdentity
    ) throws -> [LiveSessionTaskSlot: Task<Void, Never>] {
        try Dictionary(uniqueKeysWithValues: LiveSessionTaskSlot.allCases.map { slot in
            let task = try #require(supervisor.start(slot, for: identity) { _ in
                try? await Task.sleep(for: .seconds(60))
            })
            return (slot, task)
        })
    }

    @Test func replacementCancelsOldTaskAndItsLateCompletionCannotClearSuccessor() async throws {
        let (supervisor, identity) = makeSupervisor()
        let oldGate = SupervisedTaskGate()
        let newGate = SupervisedTaskGate()
        let oldTask = try #require(supervisor.start(.logs, for: identity) { _ in
            await oldGate.suspend()
        })
        await oldGate.waitUntilStarted()

        let newTask = try #require(supervisor.start(.logs, for: identity) { _ in
            await newGate.suspend()
        })
        await newGate.waitUntilStarted()
        #expect(oldTask.isCancelled)
        #expect(!newTask.isCancelled)

        await oldGate.release()
        await oldTask.value
        #expect(supervisor.contains(.logs))
        #expect(!newTask.isCancelled)

        await newGate.release()
        await newTask.value
        #expect(!supervisor.contains(.logs))
    }

    @Test func newGenerationCancelsOldTasksAndRejectsOldStarts() async throws {
        let (supervisor, oldIdentity) = makeSupervisor()
        let oldGate = SupervisedTaskGate()
        let oldTask = try #require(supervisor.start(.baseline, for: oldIdentity) { _ in
            await oldGate.suspend()
        })
        await oldGate.waitUntilStarted()
        let newIdentity = LiveSessionRuntimeIdentity(
            controllerID: oldIdentity.controllerID,
            generation: UUID()
        )
        supervisor.bind(to: newIdentity)
        #expect(oldTask.isCancelled)
        #expect(supervisor.activeSlots.isEmpty)

        let newGate = SupervisedTaskGate()
        let newTask = try #require(supervisor.start(.baseline, for: newIdentity) { _ in
            await newGate.suspend()
        })
        await newGate.waitUntilStarted()
        var staleOperationRan = false
        let rejected = supervisor.start(.baseline, for: oldIdentity) { @MainActor _ in
            staleOperationRan = true
        }
        #expect(rejected == nil)
        #expect(!newTask.isCancelled)

        await oldGate.release()
        await oldTask.value
        #expect(supervisor.contains(.baseline))
        #expect(!staleOperationRan)

        await newGate.release()
        await newTask.value
        #expect(supervisor.activeSlots.isEmpty)
    }

    @Test func streamingCancellationLeavesRefreshAndProbeTasksRunning() async throws {
        let (supervisor, identity) = makeSupervisor()
        let tasks = try startEverySlot(in: supervisor, identity: identity)
        supervisor.cancel(group: .streaming)

        let survivors: Set<LiveSessionTaskSlot> = [
            .baseline, .fastRefresh, .mediumRefresh, .slowRefresh,
            .manualRefresh, .immediateRefresh, .probe,
        ]
        #expect(supervisor.activeSlots == survivors)
        for (slot, task) in tasks {
            #expect(task.isCancelled == !survivors.contains(slot))
        }
        supervisor.cancel(group: .all)
        for task in tasks.values { await task.value }
    }

    @Test func producerCancellationPreservesRetryAndProbeOwnership() async throws {
        let (supervisor, identity) = makeSupervisor()
        let tasks = try startEverySlot(in: supervisor, identity: identity)
        supervisor.cancel(group: .producers)

        #expect(supervisor.activeSlots == [.retry, .probe])
        #expect(tasks[.immediateRefresh]?.isCancelled == true)
        #expect(tasks[.singBox]?.isCancelled == true)
        #expect(tasks[.retry]?.isCancelled == false)
        #expect(tasks[.probe]?.isCancelled == false)
        supervisor.cancel(group: .all)
        for task in tasks.values { await task.value }
    }

    @Test func cancellingBeforeExecutionSkipsOperationAndRemovesOwnership() async throws {
        let (supervisor, identity) = makeSupervisor()
        var didRun = false
        let task = try #require(supervisor.start(.probe, for: identity) { @MainActor _ in
            didRun = true
        })
        task.cancel()
        await task.value

        #expect(!didRun)
        #expect(!supervisor.contains(.probe))
    }

    @Test func rebindingSameSessionPreservesTasksAndUnbindingCancelsAll() async throws {
        let (supervisor, identity) = makeSupervisor()
        let tasks = try startEverySlot(in: supervisor, identity: identity)
        supervisor.bind(to: identity)
        #expect(tasks.values.allSatisfy { !$0.isCancelled })

        supervisor.bind(to: nil)
        #expect(supervisor.identity == nil)
        #expect(supervisor.activeSlots.isEmpty)
        #expect(tasks.values.allSatisfy { $0.isCancelled })
        for task in tasks.values { await task.value }
    }

    @Test func changingControllerWithSameGenerationStillReplacesOwnership() async throws {
        let (supervisor, identity) = makeSupervisor()
        let task = try #require(supervisor.start(.traffic, for: identity) { _ in
            try? await Task.sleep(for: .seconds(60))
        })
        supervisor.bind(to: LiveSessionRuntimeIdentity(
            controllerID: UUID(),
            generation: identity.generation
        ))
        #expect(task.isCancelled)
        #expect(supervisor.activeSlots.isEmpty)
        await task.value
    }

    @Test func releasingSupervisorCancelsItsRemainingTasks() async throws {
        let identity = LiveSessionRuntimeIdentity(controllerID: UUID(), generation: UUID())
        var supervisor: LiveSessionTaskSupervisor? = LiveSessionTaskSupervisor()
        supervisor?.bind(to: identity)
        let task = try #require(supervisor?.start(.connections, for: identity) { _ in
            try? await Task.sleep(for: .seconds(60))
        })
        supervisor = nil
        #expect(task.isCancelled)
        await task.value
    }
}

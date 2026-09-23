import Foundation

enum LiveSessionTaskSlot: CaseIterable, Hashable, Sendable {
    case baseline
    case fastRefresh
    case mediumRefresh
    case slowRefresh
    case manualRefresh
    case immediateRefresh
    case traffic
    case logs
    case memory
    case connections
    case singBox
    case retry
    case probe

    fileprivate var isRefresh: Bool {
        switch self {
        case .baseline, .fastRefresh, .mediumRefresh, .slowRefresh,
             .manualRefresh, .immediateRefresh:
            true
        default:
            false
        }
    }

    fileprivate var isStream: Bool {
        switch self {
        case .traffic, .logs, .memory, .connections, .singBox:
            true
        default:
            false
        }
    }
}

enum LiveSessionTaskGroup {
    case refresh
    case streaming
    case producers
    case all

    fileprivate func contains(_ slot: LiveSessionTaskSlot) -> Bool {
        switch self {
        case .refresh: slot.isRefresh
        case .streaming: slot.isStream || slot == .retry
        case .producers: slot.isRefresh || slot.isStream
        case .all: true
        }
    }
}

struct LiveSessionTaskToken: Equatable, Sendable {
    let identity: LiveSessionRuntimeIdentity
    let slot: LiveSessionTaskSlot
    fileprivate let id: UUID
}

@MainActor
final class LiveSessionTaskSupervisor {
    private struct Entry: Sendable {
        let token: LiveSessionTaskToken
        let task: Task<Void, Never>
    }

    private(set) var identity: LiveSessionRuntimeIdentity?
    private var entries: [LiveSessionTaskSlot: Entry] = [:]

    deinit {
        for entry in entries.values {
            entry.task.cancel()
        }
    }

    var activeSlots: Set<LiveSessionTaskSlot> {
        Set(entries.keys)
    }

    func bind(to identity: LiveSessionRuntimeIdentity?) {
        guard self.identity != identity else { return }
        cancel(group: .all)
        self.identity = identity
    }

    @discardableResult
    func start(
        _ slot: LiveSessionTaskSlot,
        for identity: LiveSessionRuntimeIdentity,
        operation: @escaping @isolated(any) @Sendable (LiveSessionTaskToken) async -> Void
    ) -> Task<Void, Never>? {
        guard self.identity == identity else { return nil }
        cancel(slot)
        let token = LiveSessionTaskToken(identity: identity, slot: slot, id: UUID())
        let task = Task { [weak self] in
            defer { self?.complete(token) }
            guard !Task.isCancelled, self?.owns(token) == true else { return }
            await operation(token)
        }
        entries[slot] = Entry(token: token, task: task)
        return task
    }

    func contains(_ slot: LiveSessionTaskSlot) -> Bool {
        entries[slot] != nil
    }

    func task(for slot: LiveSessionTaskSlot) -> Task<Void, Never>? {
        entries[slot]?.task
    }

    func owns(_ token: LiveSessionTaskToken) -> Bool {
        identity == token.identity && entries[token.slot]?.token == token
    }

    @discardableResult
    func complete(_ token: LiveSessionTaskToken) -> Bool {
        guard owns(token) else { return false }
        entries[token.slot] = nil
        return true
    }

    func cancel(_ slot: LiveSessionTaskSlot) {
        entries.removeValue(forKey: slot)?.task.cancel()
    }

    func cancel(group: LiveSessionTaskGroup) {
        for slot in entries.keys.filter(group.contains) {
            cancel(slot)
        }
    }
}

import Foundation
import MicaCore
import Observation
import SwiftUI

struct ProxyCatalogRevision: Hashable, Sendable {
    let controllerID: RouterProfile.ID?
    let generation: UUID?
    let value: UInt64

    static let zero = ProxyCatalogRevision(
        controllerID: nil,
        generation: nil,
        value: 0
    )

    func isCurrent(
        controllerID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        self.controllerID == controllerID
            && self.generation == generation
    }

    func isCurrent(
        selectedControllerID: RouterProfile.ID?,
        sessionControllerID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        selectedControllerID == sessionControllerID
            && isCurrent(
                controllerID: sessionControllerID,
                generation: generation
            )
    }
}

struct ProxyCatalogUpdate: Equatable {
    let revision: ProxyCatalogRevision
    let catalog: PolicyGroupCatalogSnapshot
}

enum ProxyCatalogUpdatePriority: Equatable {
    case immediate
    case deferrable
}

enum ProxyCatalogUpdateClassifier {
    static func priority(
        previous: PolicyGroupCatalogSnapshot,
        next: PolicyGroupCatalogSnapshot
    ) -> ProxyCatalogUpdatePriority {
        guard previous.mode == next.mode,
              previous.groups.count == next.groups.count else {
            return .immediate
        }

        for (previousGroup, nextGroup) in zip(previous.groups, next.groups) {
            guard previousGroup.id == nextGroup.id,
                  previousGroup.type == nextGroup.type,
                  previousGroup.selected == nextGroup.selected,
                  previousGroup.options == nextGroup.options,
                  previousGroup.hidden == nextGroup.hidden,
                  previousGroup.selectable == nextGroup.selectable,
                  previousGroup.details?.fixed == nextGroup.details?.fixed else {
                return .immediate
            }
        }

        return .deferrable
    }
}

enum ProxyInteractionRegion: Hashable {
    case directory
    case nodes
    case inspector
}

struct WorkbenchProxyFilterObstructions: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let globalSearch = Self(rawValue: 1 << 0)
    static let groupFilter = Self(rawValue: 1 << 1)
    static let healthFilter = Self(rawValue: 1 << 2)
}

enum WorkbenchProxyRevealObstruction: Equatable, Sendable {
    case hiddenGlobal
    case filters(
        groupOccurrenceID: String,
        blockers: WorkbenchProxyFilterObstructions
    )

    var detailKey: String {
        switch self {
        case .hiddenGlobal:
            "routing.reveal_blocked_global_detail"
        case .filters(_, let blockers):
            if blockers == .globalSearch {
                "routing.reveal_blocked_search_detail"
            } else if blockers == .groupFilter {
                "routing.reveal_blocked_group_filter_detail"
            } else if blockers == .healthFilter {
                "routing.reveal_blocked_health_filter_detail"
            } else {
                "routing.reveal_blocked_multiple_filters_detail"
            }
        }
    }

    var actionTitleKey: String {
        switch self {
        case .hiddenGlobal: "routing.show_global_and_locate"
        case .filters: "routing.clear_filters_and_locate"
        }
    }
}

enum WorkbenchProxyUnresolvedReason: String, Equatable, Sendable {
    case emptyCatalog
    case missingGroup
    case ambiguousGroup
    case missingNode

    var detailKey: String {
        switch self {
        case .emptyCatalog: "routing.reveal_empty_catalog_detail"
        case .missingGroup: "routing.reveal_missing_group_detail"
        case .ambiguousGroup: "routing.reveal_ambiguous_group_detail"
        case .missingNode: "routing.reveal_missing_node_detail"
        }
    }
}

@MainActor
@Observable
final class ProxyCatalogPresentationCoordinator {
    private(set) var commitRevision: UInt64 = 0

    @ObservationIgnored private var scheduler = ProxyCatalogPresentationScheduler()
    @ObservationIgnored private var readyUpdate: ProxyCatalogUpdate?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func deferIfInteracting(
        _ update: ProxyCatalogUpdate,
        at now: Date
    ) -> Bool {
        guard scheduler.deferIfInteracting(update, at: now) else {
            return false
        }
        schedulePendingDeadlineIfNeeded(at: now)
        return true
    }

    func beginTransientInteraction(at now: Date) {
        scheduler.beginTransientInteraction(at: now)
    }

    func updateScrolling(
        _ isScrolling: Bool,
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        if isScrolling {
            scheduler.beginScrolling(in: region, at: now)
            return
        }

        scheduler.endScrolling(in: region, at: now)
        guard let update = scheduler.takePendingUpdateIfIdle(at: now) else {
            schedulePendingDeadlineIfNeeded(at: now)
            return
        }
        cancelPendingDeadline()
        publish(update)
    }

    func prioritizeUserOperationResult(at now: Date) -> ProxyCatalogUpdate? {
        scheduler.beginCriticalWindow(at: now)
        let update = scheduler.takePendingUpdate()
        cancelPendingDeadline()
        return update
    }

    func takeReadyUpdate() -> ProxyCatalogUpdate? {
        defer { readyUpdate = nil }
        return readyUpdate
    }

    func clearPendingUpdate() {
        scheduler.clearPendingUpdate()
        readyUpdate = nil
        cancelPendingDeadline()
    }

    func reset(preservingScrollState: Bool = false) {
        scheduler.reset(preservingScrollState: preservingScrollState)
        readyUpdate = nil
        cancelPendingDeadline()
    }

    private func schedulePendingDeadlineIfNeeded(at now: Date) {
        guard deadlineTask == nil,
              scheduler.scrollingRegions.isEmpty,
              let deadline = scheduler.pendingDeadline else {
            return
        }

        let remainingMilliseconds = Int64(
            ceil(max(0, deadline.timeIntervalSince(now) * 1_000))
        )
        deadlineTask = Task { @concurrent [weak self] in
            if remainingMilliseconds > 0 {
                do {
                    try await Task.sleep(
                        for: .milliseconds(remainingMilliseconds)
                    )
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self?.pendingDeadlineReached()
        }
    }

    private func pendingDeadlineReached() {
        deadlineTask = nil
        let now = Date()
        guard let update = scheduler.takePendingUpdateIfDue(at: now) else {
            schedulePendingDeadlineIfNeeded(at: now)
            return
        }
        publish(update)
    }

    private func publish(_ update: ProxyCatalogUpdate) {
        readyUpdate = update
        commitRevision &+= 1
    }

    private func cancelPendingDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }
}

@MainActor
final class ProxyScrollInteractionTracker {
    private(set) var isScrolling = false

    func update(
        _ phase: ScrollPhase,
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator,
        at now: Date = Date()
    ) {
        let nextIsScrolling: Bool
        switch phase {
        case .tracking, .interacting, .decelerating, .animating:
            nextIsScrolling = true
        case .idle:
            nextIsScrolling = false
        }

        guard nextIsScrolling != isScrolling else { return }
        isScrolling = nextIsScrolling
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: nextIsScrolling ? 1 : 2
            )
        )
        coordinator.updateScrolling(
            nextIsScrolling,
            in: region,
            at: now
        )
    }

    func end(
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator,
        at now: Date = Date()
    ) {
        guard isScrolling else { return }
        isScrolling = false
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(count: 1, revision: 2)
        )
        coordinator.updateScrolling(false, in: region, at: now)
    }
}

@MainActor
private struct ProxyScrollInteractionModifier: ViewModifier {
    let region: ProxyInteractionRegion
    let coordinator: ProxyCatalogPresentationCoordinator
    let tracker: ProxyScrollInteractionTracker

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                tracker.update(
                    phase,
                    in: region,
                    coordinator: coordinator
                )
            }
            .onDisappear {
                tracker.end(
                    in: region,
                    coordinator: coordinator
                )
            }
    }
}

extension View {
    func proxyScrollInteraction(
        in region: ProxyInteractionRegion,
        coordinator: ProxyCatalogPresentationCoordinator,
        tracker: ProxyScrollInteractionTracker
    ) -> some View {
        modifier(
            ProxyScrollInteractionModifier(
                region: region,
                coordinator: coordinator,
                tracker: tracker
            )
        )
    }
}

struct ProxyCatalogPresentationScheduler: Equatable {
    static let maximumDeferral: TimeInterval = 0.2
    static let transientInteractionDuration: TimeInterval = 0.18
    static let criticalResultDuration: TimeInterval = 0.75

    private(set) var scrollingRegions: Set<ProxyInteractionRegion> = []
    private(set) var transientInteractionUntil: Date?
    private(set) var criticalResultUntil: Date?
    private(set) var pendingUpdate: ProxyCatalogUpdate?
    private(set) var pendingDeadline: Date?

    mutating func beginScrolling(
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        expireWindows(at: now)
        scrollingRegions.insert(region)
    }

    mutating func endScrolling(
        in region: ProxyInteractionRegion,
        at now: Date
    ) {
        scrollingRegions.remove(region)
        expireWindows(at: now)
    }

    mutating func beginTransientInteraction(at now: Date) {
        expireWindows(at: now)
        guard transientInteractionUntil == nil else { return }
        transientInteractionUntil = now.addingTimeInterval(
            Self.transientInteractionDuration
        )
    }

    mutating func beginCriticalWindow(at now: Date) {
        expireWindows(at: now)
        let candidate = now.addingTimeInterval(Self.criticalResultDuration)
        if let criticalResultUntil {
            self.criticalResultUntil = max(criticalResultUntil, candidate)
        } else {
            criticalResultUntil = candidate
        }
    }

    mutating func deferIfInteracting(
        _ update: ProxyCatalogUpdate,
        at now: Date
    ) -> Bool {
        expireWindows(at: now)
        guard !isInCriticalWindow,
              isInteracting else { return false }

        pendingUpdate = update
        if pendingDeadline == nil {
            pendingDeadline = now.addingTimeInterval(Self.maximumDeferral)
        }
        return true
    }

    mutating func takePendingUpdateIfIdle(at now: Date) -> ProxyCatalogUpdate? {
        expireWindows(at: now)
        guard !isInteracting else { return nil }
        return takePendingUpdate()
    }

    mutating func takePendingUpdateIfDue(at now: Date) -> ProxyCatalogUpdate? {
        expireWindows(at: now)
        guard scrollingRegions.isEmpty,
              let pendingDeadline,
              pendingDeadline <= now else { return nil }
        return takePendingUpdate()
    }

    mutating func takePendingUpdate() -> ProxyCatalogUpdate? {
        defer {
            pendingUpdate = nil
            pendingDeadline = nil
        }
        return pendingUpdate
    }

    mutating func clearPendingUpdate() {
        pendingUpdate = nil
        pendingDeadline = nil
    }

    mutating func reset(preservingScrollState: Bool = false) {
        if !preservingScrollState {
            scrollingRegions.removeAll(keepingCapacity: false)
        }
        transientInteractionUntil = nil
        criticalResultUntil = nil
        clearPendingUpdate()
    }

    private var isInteracting: Bool {
        !scrollingRegions.isEmpty || transientInteractionUntil != nil
    }

    private var isInCriticalWindow: Bool {
        criticalResultUntil != nil
    }

    private mutating func expireWindows(at now: Date) {
        if let transientInteractionUntil,
           transientInteractionUntil <= now {
            self.transientInteractionUntil = nil
        }
        if let criticalResultUntil,
           criticalResultUntil <= now {
            self.criticalResultUntil = nil
        }
    }
}

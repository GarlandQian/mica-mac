import Foundation
import MicaCore
import Observation

@MainActor
@Observable
final class OverviewTelemetryRuntime {
    private(set) var timelineWindow: OverviewTimelineWindow
    private(set) var isPaused = false
    let interaction = OverviewTimelineInteractionState()

    @ObservationIgnored let projectionCache = OverviewTimelineProjectionCache()

    init(timelineWindow: OverviewTimelineWindow) {
        self.timelineWindow = timelineWindow
    }

    func setTimelineWindow(_ window: OverviewTimelineWindow) {
        guard timelineWindow != window else { return }
        timelineWindow = window
        returnToLive()
    }

    func synchronize(preferredWindow: OverviewTimelineWindow) {
        setTimelineWindow(preferredWindow)
    }

    func togglePause() {
        isPaused.toggle()
    }

    func returnToLive() {
        isPaused = false
        interaction.reset()
    }
}

@MainActor
@Observable
final class OverviewTopologyRuntime {
    var presentation: OverviewTopologyPresentation?
    var availableWidth = 520
    var isPaused = false
    var isExpanded = false
    let interaction = OverviewTopologyInteractionState()

    @ObservationIgnored let presentationCache = OverviewTopologyPresentationCache()
    @ObservationIgnored let policyInspectionCache = OverviewPolicyInspectionCache()
    @ObservationIgnored private var nodeStatusCache:
        (policyRevision: UInt64, topologyRevision: UInt64, map: [String: MicaTheme.Status])?

    func togglePause() {
        isPaused.toggle()
    }

    /// Controller-reported status per policy-hop node, memoized on the policy
    /// catalog + topology revisions (task 08-20 R5): telemetry ticks flip
    /// neither key, so they never re-resolve the catalog nor invalidate the
    /// band equality gate.
    func nodeStatuses(
        topology: ConnectionTopology,
        topologyRevision: UInt64,
        policyRevision: UInt64,
        catalog: PolicyGroupCatalogSnapshot
    ) -> [String: MicaTheme.Status] {
        if let cache = nodeStatusCache,
           cache.policyRevision == policyRevision,
           cache.topologyRevision == topologyRevision {
            return cache.map
        }
        let policyIndex = policyInspectionCache.resolve(
            revision: policyRevision,
            catalog: catalog
        )
        var statuses: [String: MicaTheme.Status] = [:]
        statuses.reserveCapacity(topology.nodes.count)
        for node in topology.nodes {
            guard case .policyHop = node.columnID else { continue }
            statuses[node.id] = OverviewTopologyNodeStatus.resolve(
                name: node.name,
                policyIndex: policyIndex
            )
        }
        nodeStatusCache = (policyRevision, topologyRevision, statuses)
        return statuses
    }
}

@MainActor
final class OverviewRuntimeRegistry {
    private struct SessionKey: Hashable {
        let controllerID: RouterProfile.ID
        let generation: UUID
    }

    private var activeSession: SessionKey?
    private var telemetryRuntimes: [SessionKey: OverviewTelemetryRuntime] = [:]
    private var topologyRuntimes: [SessionKey: OverviewTopologyRuntime] = [:]

    func prepare(controllerID: RouterProfile.ID, generation: UUID) {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        guard activeSession != key else { return }
        activeSession = key
        telemetryRuntimes = telemetryRuntimes.filter { $0.key == key }
        topologyRuntimes = topologyRuntimes.filter { $0.key == key }
    }

    func telemetryRuntime(
        controllerID: RouterProfile.ID,
        generation: UUID,
        preferredWindow: OverviewTimelineWindow
    ) -> OverviewTelemetryRuntime {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        prepare(controllerID: controllerID, generation: generation)
        if let runtime = telemetryRuntimes[key] {
            runtime.synchronize(preferredWindow: preferredWindow)
            return runtime
        }
        let runtime = OverviewTelemetryRuntime(timelineWindow: preferredWindow)
        telemetryRuntimes[key] = runtime
        return runtime
    }

    func existingTopologyRuntime(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) -> OverviewTopologyRuntime? {
        topologyRuntimes[SessionKey(controllerID: controllerID, generation: generation)]
    }

    func topologyRuntime(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) -> OverviewTopologyRuntime {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        prepare(controllerID: controllerID, generation: generation)
        if let runtime = topologyRuntimes[key] {
            return runtime
        }
        let runtime = OverviewTopologyRuntime()
        topologyRuntimes[key] = runtime
        return runtime
    }

    func clear() {
        activeSession = nil
        telemetryRuntimes.removeAll(keepingCapacity: false)
        topologyRuntimes.removeAll(keepingCapacity: false)
    }
}

@MainActor
@Observable
final class OverviewWindowRuntime {
    var showsPreferences = false

    @ObservationIgnored let liveSessionWindowDemandID: LiveSessionWindowDemandID
    @ObservationIgnored let registry = OverviewRuntimeRegistry()

    init(liveSessionWindowDemandID: LiveSessionWindowDemandID = LiveSessionWindowDemandID()) {
        self.liveSessionWindowDemandID = liveSessionWindowDemandID
    }

    func togglePreferences() {
        showsPreferences.toggle()
    }
}

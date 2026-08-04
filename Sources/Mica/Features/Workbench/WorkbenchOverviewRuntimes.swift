import CoreGraphics
import Foundation
import MicaCore
import Observation

@MainActor
@Observable
final class OverviewTelemetryModuleRuntime {
    var timelineWindow: OverviewTimelineWindow
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

    func togglePause() {
        isPaused.toggle()
    }

    func returnToLive() {
        isPaused = false
        interaction.reset()
    }

    func synchronize(
        preferredWindow: OverviewDashboardTimelineWindow
    ) {
        let next = preferredWindow.projectionWindow
        guard timelineWindow != next else { return }
        timelineWindow = next
        returnToLive()
    }
}

@MainActor
@Observable
final class OverviewTopologyModuleRuntime {
    var presentation: OverviewTopologyPresentation?
    var availableWidth = 520
    var isPaused = false
    var isExpanded = false
    let interaction = OverviewTopologyInteractionState()

    @ObservationIgnored let presentationCache = OverviewTopologyPresentationCache()

    func togglePause() {
        isPaused.toggle()
    }
}

@MainActor
final class OverviewDashboardModuleRuntimeRegistry {
    private struct SessionKey: Hashable {
        let controllerID: RouterProfile.ID
        let generation: UUID
    }

    private var activeSession: SessionKey?
    private var telemetryRuntimes: [SessionKey: OverviewTelemetryModuleRuntime] = [:]
    private var topologyRuntimes: [SessionKey: OverviewTopologyModuleRuntime] = [:]

    func prepare(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        guard activeSession != key else { return }
        activeSession = key
        telemetryRuntimes = telemetryRuntimes.filter { $0.key == key }
        topologyRuntimes = topologyRuntimes.filter { $0.key == key }
    }

    func telemetryRuntime(
        controllerID: RouterProfile.ID,
        generation: UUID,
        preferredWindow: OverviewDashboardTimelineWindow
    ) -> OverviewTelemetryModuleRuntime {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        prepare(controllerID: controllerID, generation: generation)
        if let runtime = telemetryRuntimes[key] {
            return runtime
        }
        let runtime = OverviewTelemetryModuleRuntime(
            timelineWindow: preferredWindow.projectionWindow
        )
        telemetryRuntimes[key] = runtime
        return runtime
    }

    func topologyRuntime(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) -> OverviewTopologyModuleRuntime {
        let key = SessionKey(controllerID: controllerID, generation: generation)
        prepare(controllerID: controllerID, generation: generation)
        if let runtime = topologyRuntimes[key] {
            return runtime
        }
        let runtime = OverviewTopologyModuleRuntime()
        topologyRuntimes[key] = runtime
        return runtime
    }

    func clear() {
        activeSession = nil
        telemetryRuntimes.removeAll(keepingCapacity: false)
        topologyRuntimes.removeAll(keepingCapacity: false)
    }
}

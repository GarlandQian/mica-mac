import Foundation
import MicaCore
import Observation

struct OperationState: Equatable {
    enum Kind: Equatable {
        case working
        case success
        case partial
        case error
    }

    enum Event: String, Equatable {
        case diagnosticsReportCopied
    }

    var kind: Kind
    var message: String
    var action: String?
    var target: String?
    var nextStep: String?
    var event: Event?

    static func working(_ message: String, action: String? = nil, target: String? = nil, nextStep: String? = nil, event: Event? = nil) -> OperationState {
        OperationState(kind: .working, message: message, action: action, target: target, nextStep: nextStep, event: event)
    }

    static func success(_ message: String, action: String? = nil, target: String? = nil, nextStep: String? = nil, event: Event? = nil) -> OperationState {
        OperationState(kind: .success, message: message, action: action, target: target, nextStep: nextStep, event: event)
    }

    static func partial(_ message: String, action: String? = nil, target: String? = nil, nextStep: String? = nil, event: Event? = nil) -> OperationState {
        OperationState(kind: .partial, message: message, action: action, target: target, nextStep: nextStep, event: event)
    }

    static func error(_ message: String, action: String? = nil, target: String? = nil, nextStep: String? = nil, event: Event? = nil) -> OperationState {
        OperationState(kind: .error, message: message, action: action, target: target, nextStep: nextStep, event: event)
    }
}

enum TrialCommandAction: String, CaseIterable, Equatable {
    case test
    case refresh
    case reloadRules
    case setRuleState
    case reloadProviders
    case testDelay
    case providerUpdate
    case providerUpdateAll
    case providerHealthCheck
    case closeConnection
    case closeConnectionGroup
    case closeAll
    case switchNode
    case clearFixedSelection
    case setMode
    case setConfig
    case configurationReload
    case geoDataUpdate
    case surgeOutboundMode
    case surgePolicySelect
    case surgePolicyTest
    case surgeRequestKill
    case surgeProfileReload
    case surgeLogLevel
    case memoryCheck
    case dnsFlush
    case fakeIPFlush
    case coreRestart
    case coreUpgrade
    case singBoxClearLogs
    case singBoxTailscaleExitNode
    case singBoxTailscaleLogout
    case saveRouter
    case diagnosticsCopy

    var title: String {
        title(language: MicaStrings.appLanguage)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .test:
            MicaStrings.localized("action.test", language: language)
        case .refresh:
            MicaStrings.localized("action.refresh", language: language)
        case .reloadRules:
            MicaStrings.localized("action.reload_rules", language: language)
        case .setRuleState:
            MicaStrings.localized("action.set_rule_state", language: language)
        case .reloadProviders:
            MicaStrings.localized("action.reload_providers", language: language)
        case .testDelay:
            MicaStrings.localized("action.test_delay", language: language)
        case .providerUpdate:
            MicaStrings.localized("action.provider_update", language: language)
        case .providerUpdateAll:
            MicaStrings.localized("action.provider_update_all", language: language)
        case .providerHealthCheck:
            MicaStrings.localized("action.provider_health_check", language: language)
        case .closeConnection:
            MicaStrings.localized("action.close_connection", language: language)
        case .closeConnectionGroup:
            MicaStrings.localized("action.close_connection_group", language: language)
        case .closeAll:
            MicaStrings.localized("action.close_all", language: language)
        case .switchNode:
            MicaStrings.localized("action.switch_route", language: language)
        case .clearFixedSelection:
            MicaStrings.localized("action.clear_fixed_selection", language: language)
        case .setMode:
            MicaStrings.localized("action.set_mode", language: language)
        case .setConfig:
            MicaStrings.localized("action.set_config", language: language)
        case .configurationReload:
            MicaStrings.localized("action.reload_configuration", language: language)
        case .geoDataUpdate:
            MicaStrings.localized("action.update_geo_data", language: language)
        case .surgeOutboundMode:
            MicaStrings.localized("action.surge_outbound", language: language)
        case .surgePolicySelect:
            MicaStrings.localized("action.surge_policy_select", language: language)
        case .surgePolicyTest:
            MicaStrings.localized("action.surge_policy_test", language: language)
        case .surgeRequestKill:
            MicaStrings.localized("action.surge_kill_request", language: language)
        case .surgeProfileReload:
            MicaStrings.localized("action.surge_reload_profile", language: language)
        case .surgeLogLevel:
            MicaStrings.localized("action.set_log_level", language: language)
        case .memoryCheck:
            MicaStrings.localized("action.memory_check", language: language)
        case .dnsFlush:
            MicaStrings.localized("action.dns_flush", language: language)
        case .fakeIPFlush:
            MicaStrings.localized("action.fakeip_flush", language: language)
        case .coreRestart:
            MicaStrings.localized("action.core_restart", language: language)
        case .coreUpgrade:
            MicaStrings.localized("action.core_upgrade", language: language)
        case .singBoxClearLogs:
            MicaStrings.localized("traffic.clear_logs", language: language)
        case .singBoxTailscaleExitNode, .singBoxTailscaleLogout:
            MicaStrings.localized("diagnostics.operation_tailscale", language: language)
        case .saveRouter:
            MicaStrings.localized("action.save_controller", language: language)
        case .diagnosticsCopy:
            MicaStrings.localized("action.diagnostics_copy", language: language)
        }
    }
}

enum CommandLifecycle: String, CaseIterable, Equatable {
    case queued
    case working
    case success
    case partial
    case failed

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .queued:
            MicaStrings.localized("lifecycle.queued", language: language)
        case .working:
            MicaStrings.localized("lifecycle.working", language: language)
        case .success:
            MicaStrings.localized("lifecycle.success", language: language)
        case .partial:
            MicaStrings.localized("lifecycle.partial", language: language)
        case .failed:
            MicaStrings.localized("lifecycle.failed", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }

    var isTerminal: Bool {
        switch self {
        case .success, .partial, .failed:
            true
        case .queued, .working:
            false
        }
    }
}

struct CommandLogEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var action: TrialCommandAction
    var status: CommandLifecycle
    var timestamp: Date
    var safeTarget: String
    var safeSummary: String
}

struct TrialSessionSnapshot: Equatable {
    var routerName: String
    var lastTestedAt: Date?
    var lastRefreshedAt: Date?
    var lastSuccessfulBaseSnapshotAt: Date?
    var lastPartialSnapshotAt: Date?
    var lastCommandAction: TrialCommandAction?
    var lastCommandStatus: CommandLifecycle?
    var lastCommandSummary: String?
    var commandLog: [CommandLogEntry]

    static func empty(routerName: String) -> TrialSessionSnapshot {
        TrialSessionSnapshot(
            routerName: routerName,
            lastTestedAt: nil,
            lastRefreshedAt: nil,
            lastSuccessfulBaseSnapshotAt: nil,
            lastPartialSnapshotAt: nil,
            lastCommandAction: nil,
            lastCommandStatus: nil,
            lastCommandSummary: nil,
            commandLog: []
        )
    }

    var isFirstRun: Bool {
        lastSuccessfulBaseSnapshotAt == nil && commandLog.isEmpty
    }

    var lastCommandResult: String {
        lastCommandResult(language: MicaStrings.appLanguage)
    }

    func lastCommandResult(language: AppLanguage) -> String {
        guard let action = lastCommandAction,
              let status = lastCommandStatus else {
            return MicaStrings.localized("trial.no_command_yet", language: language)
        }

        return "\(action.title(language: language)) \(status.label(language: language))"
    }

    var sessionHealth: TrialSessionHealth {
        if lastCommandStatus == .failed {
            return .failed
        }

        if lastCommandStatus == .partial {
            return .partial
        }

        if let lastSuccessfulBaseSnapshotAt {
            return Date().timeIntervalSince(lastSuccessfulBaseSnapshotAt) > 900 ? .stale : .fresh
        }

        return .idle
    }

    var readinessLabel: String {
        readinessLabel(language: MicaStrings.appLanguage)
    }

    func readinessLabel(language: AppLanguage) -> String {
        switch sessionHealth {
        case .idle:
            return MicaStrings.localized("trial.readiness_first_run", language: language)
        case .fresh:
            return MicaStrings.localized("trial.readiness_ready", language: language)
        case .stale:
            return MicaStrings.localized("trial.readiness_stale", language: language)
        case .partial:
            return MicaStrings.localized("trial.readiness_partial", language: language)
        case .failed:
            return MicaStrings.localized("trial.readiness_failed", language: language)
        }
    }

    var readinessDiagnosticsLabel: String {
        sessionHealth.diagnosticsLabel
    }

    var commandCountDiagnostics: String {
        let counts = Dictionary(grouping: commandLog) { $0.status }
            .mapValues { $0.count }

        return CommandLifecycle.allCases
            .map { "\($0.diagnosticsLabel)=\(counts[$0] ?? 0)" }
            .joined(separator: ", ")
    }

    var diagnosticsSummary: String {
        [
            "session=\(sessionHealth.diagnosticsLabel)",
            "readiness=\(readinessDiagnosticsLabel)",
            "last-command=\(lastCommandStatus?.diagnosticsLabel ?? "none")",
            "commands=\(commandCountDiagnostics)",
        ].joined(separator: "; ")
    }

    mutating func record(_ entry: CommandLogEntry) {
        commandLog.insert(entry, at: 0)
        commandLog = Array(commandLog.prefix(20))
        lastCommandAction = entry.action
        lastCommandStatus = entry.status
        lastCommandSummary = entry.safeSummary
    }

    mutating func update(
        _ commandID: UUID,
        status: CommandLifecycle,
        summary: String,
        timestamp: Date
    ) {
        guard let index = commandLog.firstIndex(where: { $0.id == commandID }) else {
            return
        }

        commandLog[index].status = status
        commandLog[index].timestamp = timestamp
        commandLog[index].safeSummary = summary

        let action = commandLog[index].action
        lastCommandAction = action
        lastCommandStatus = status
        lastCommandSummary = summary

        guard status.isTerminal else {
            return
        }

        switch action {
        case .test:
            lastTestedAt = timestamp
            if status == .success {
                lastSuccessfulBaseSnapshotAt = timestamp
            }
        case .refresh:
            lastRefreshedAt = timestamp
            if status == .success || status == .partial {
                lastSuccessfulBaseSnapshotAt = timestamp
            }
            if status == .partial {
                lastPartialSnapshotAt = timestamp
            }
        case .reloadRules, .reloadProviders:
            if status == .partial {
                lastPartialSnapshotAt = timestamp
            }
        case .testDelay, .providerUpdate, .providerUpdateAll, .providerHealthCheck, .closeConnection, .closeConnectionGroup, .closeAll, .switchNode, .clearFixedSelection, .setRuleState, .setMode, .setConfig, .configurationReload, .geoDataUpdate, .surgeOutboundMode, .surgePolicySelect, .surgePolicyTest, .surgeRequestKill, .surgeProfileReload, .surgeLogLevel, .memoryCheck, .dnsFlush, .fakeIPFlush, .coreRestart, .coreUpgrade, .singBoxClearLogs, .singBoxTailscaleExitNode, .singBoxTailscaleLogout, .saveRouter, .diagnosticsCopy:
            break
        }
    }
}

enum TrialSessionHealth: String, Equatable {
    case idle
    case fresh
    case stale
    case partial
    case failed

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("trial.readiness_first_run", language: language)
        case .fresh:
            MicaStrings.localized("trial.readiness_ready", language: language)
        case .stale:
            MicaStrings.localized("trial.readiness_stale", language: language)
        case .partial:
            MicaStrings.localized("trial.readiness_partial", language: language)
        case .failed:
            MicaStrings.localized("trial.readiness_failed", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }
}

enum EnhancedSnapshotState: Equatable {
    case idle
    case loading
    case available
    case unavailable(String)

    var isUnavailable: Bool {
        if case .unavailable = self {
            return true
        }

        return false
    }

    var isLoading: Bool {
        self == .loading
    }

    var diagnosticsLabel: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .available:
            "available"
        case .unavailable:
            "unavailable"
        }
    }

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("snapshot.idle", language: language)
        case .loading:
            MicaStrings.localized("snapshot.loading", language: language)
        case .available:
            MicaStrings.localized("matrix.ready", language: language)
        case .unavailable:
            MicaStrings.localized("snapshot.unavailable", language: language)
        }
    }

    var message: String? {
        if case .unavailable(let message) = self {
            return message
        }

        return nil
    }

    func summaryValue(count: Int) -> String {
        summaryValue(count: count, language: MicaStrings.appLanguage)
    }

    func summaryValue(count: Int, language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("snapshot.idle", language: language)
        case .loading:
            MicaStrings.localized("snapshot.loading", language: language)
        case .available:
            "\(count)"
        case .unavailable:
            count > 0
                ? MicaStrings.localized("data.stale_count \(count)", language: language)
                : MicaStrings.localized("snapshot.unavailable", language: language)
        }
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(version: String)
    case failed(String)

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .disconnected:
            MicaStrings.localized("connection.disconnected", language: language)
        case .connecting:
            MicaStrings.localized("connection.connecting", language: language)
        case .connected(let version):
            MicaStrings.localized("connection.connected_version \(version)", language: language)
        case .failed(_):
            MicaStrings.localized("connection.failed", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .disconnected:
            "disconnected"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        case .failed:
            "failed"
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ConnectionTransferRateTracker: Equatable, Sendable {
    private struct OccurrenceIdentity: Hashable, Sendable {
        var reportedID: String
        var occurrence: Int
    }

    private struct Counters: Equatable, Sendable {
        var upload: Int?
        var download: Int?
    }

    private var previousSampleAt: Date?
    private var countersByOccurrence: [OccurrenceIdentity: Counters] = [:]
    private var occurrenceCountsByReportedID: [String: Int] = [:]

    mutating func enriching(
        _ response: ConnectionsResponse,
        receivedAt: Date
    ) -> ConnectionsResponse {
        guard previousSampleAt != nil else {
            recordInitialCounters(from: response.connections)
            previousSampleAt = receivedAt
            return response
        }

        let elapsed = previousSampleAt.map { receivedAt.timeIntervalSince($0) }
        let currentCounts = response.connections.reduce(into: [String: Int]()) { counts, connection in
            counts[connection.id, default: 0] += 1
        }
        var occurrences: [String: Int] = [:]
        var nextCounters: [OccurrenceIdentity: Counters] = [:]
        nextCounters.reserveCapacity(response.connections.count)
        var connections: [ConnectionSnapshot] = []
        connections.reserveCapacity(response.connections.count)

        for connection in response.connections {
            let occurrence = occurrences[connection.id, default: 0]
            occurrences[connection.id] = occurrence + 1
            let identity = OccurrenceIdentity(
                reportedID: connection.id,
                occurrence: occurrence
            )
            var projected = connection
            if occurrenceCountsByReportedID[connection.id] == currentCounts[connection.id],
               let previous = countersByOccurrence[identity],
               let elapsed,
               elapsed > 0 {
                projected.uploadSpeed = connection.uploadSpeed
                    ?? Self.bytesPerSecond(current: connection.upload, previous: previous.upload, elapsed: elapsed)
                projected.downloadSpeed = connection.downloadSpeed
                    ?? Self.bytesPerSecond(current: connection.download, previous: previous.download, elapsed: elapsed)
            }
            connections.append(projected)
            nextCounters[identity] = Counters(
                upload: connection.upload,
                download: connection.download
            )
        }

        previousSampleAt = receivedAt
        countersByOccurrence = nextCounters
        occurrenceCountsByReportedID = currentCounts

        return ConnectionsResponse(
            uploadTotal: response.uploadTotal,
            downloadTotal: response.downloadTotal,
            memory: response.memory,
            connections: connections
        )
    }

    private mutating func recordInitialCounters(from connections: [ConnectionSnapshot]) {
        var occurrenceCounts: [String: Int] = [:]
        occurrenceCounts.reserveCapacity(connections.count)
        var counters: [OccurrenceIdentity: Counters] = [:]
        counters.reserveCapacity(connections.count)

        for connection in connections {
            let occurrence = occurrenceCounts[connection.id, default: 0]
            occurrenceCounts[connection.id] = occurrence + 1
            counters[
                OccurrenceIdentity(reportedID: connection.id, occurrence: occurrence)
            ] = Counters(upload: connection.upload, download: connection.download)
        }

        countersByOccurrence = counters
        occurrenceCountsByReportedID = occurrenceCounts
    }

    mutating func reset() {
        previousSampleAt = nil
        countersByOccurrence.removeAll(keepingCapacity: false)
        occurrenceCountsByReportedID.removeAll(keepingCapacity: false)
    }

    private static func bytesPerSecond(current: Int?, previous: Int?, elapsed: TimeInterval) -> Int? {
        guard let current, let previous, current >= previous, previous >= 0 else { return nil }
        let delta = current - previous
        let value = (Double(delta) / elapsed).rounded()
        guard value.isFinite else { return nil }
        return Int(min(value, Double(Int.max)))
    }
}

struct PendingMemorySample: Equatable, Sendable {
    var response: MemoryResponse
    var receivedAt: Date
}

/// Field-granular controller session state consumed by SwiftUI.
///
/// `ControllerSession` also owns high-frequency timelines and stream buffers.
/// Keeping this as a nested observable reference lets a view observe `state`
/// without being invalidated when only `runtime` or `controls` changes.
@MainActor
@Observable
final class ControllerSessionPresentationState {
    var controls = DashboardSessionControls()
    var generation = UUID()
    var controllerID: RouterProfile.ID?
    var state: LiveSessionState = .idle
    var lastSuccessAt: Date?
    var endReason: LiveSessionEndReason?
    var runtime = ControllerSessionRuntimeState()

    func synchronizeLifecycle(with session: ControllerSession) {
        if controls != session.controls {
            controls = session.controls
        }
        if generation != session.generation {
            generation = session.generation
        }
        if controllerID != session.controllerID {
            controllerID = session.controllerID
        }
        if state != session.state {
            state = session.state
        }
        if lastSuccessAt != session.lastSuccessAt {
            lastSuccessAt = session.lastSuccessAt
        }
        if endReason != session.endReason {
            endReason = session.endReason
        }
    }

    func publishRuntime(_ nextRuntime: ControllerSessionRuntimeState) {
        if runtime != nextRuntime {
            runtime = nextRuntime
        }
    }

    func synchronize(with session: ControllerSession) {
        synchronizeLifecycle(with: session)
        if runtime != session.runtime {
            runtime = session.runtime
        }
    }
}

struct ControllerSession: Equatable {
    var controls = DashboardSessionControls()
    var generation = UUID()
    var controllerID: RouterProfile.ID?
    var state: LiveSessionState = .idle
    var lastSuccessAt: Date?
    var latestReceivedAt: Date?
    var endReason: LiveSessionEndReason?
    var hasCommittedBaseline = false
    var baselineTransaction = LiveSessionBaselineTransaction()
    var refreshLanes = Dictionary(
        uniqueKeysWithValues: SessionRefreshLane.allCases.map { ($0, SessionRefreshLaneState()) }
    )
    var endpointCache = SessionEndpointCache()
    var pendingPresentation = PendingSessionPresentation()
    var pendingMemorySample: PendingMemorySample?
    var trafficTimeline = TrafficTimeline()
    var memoryTimeline = MemoryTimeline()
    var connectionCountTimeline = ConnectionCountTimeline()
    var connectionTransferRates = ConnectionTransferRateTracker()
    var logBuffer = BoundedLogBuffer()
    var singBoxVersion: SingBoxVersion?
    var singBoxStatus: SingBoxStatusSnapshot?
    var singBoxGroups: SingBoxPolicyCatalog?
    var singBoxMode: SingBoxClashModeStatus?
    var singBoxActiveConnections: [ConnectionSnapshot] = []
    var surgeRawSnapshot = SurgeControlSnapshot.empty
    var surgeConnectionRatesReceivedAt: Date?
    var singBoxTailscaleStatus: SingBoxTailscaleStatus?
    var singBoxTailscaleError: String?
    var liveObservation = ControllerSessionLiveObservation()
    var runtime = ControllerSessionRuntimeState()

    mutating func begin(controllerID: RouterProfile.ID) {
        generation = UUID()
        self.controllerID = controllerID
        state = .connecting
        lastSuccessAt = nil
        latestReceivedAt = nil
        endReason = nil
        hasCommittedBaseline = false
        baselineTransaction.begin(generation: generation, phase: .initial)
        refreshLanes = Dictionary(
            uniqueKeysWithValues: SessionRefreshLane.allCases.map { ($0, SessionRefreshLaneState()) }
        )
        endpointCache.reset()
        resetPendingPresentation()
        trafficTimeline.reset()
        memoryTimeline.reset()
        connectionCountTimeline.reset()
        connectionTransferRates.reset()
        logBuffer.removeAll()
        singBoxVersion = nil
        singBoxStatus = nil
        singBoxGroups = nil
        singBoxMode = nil
        singBoxActiveConnections = []
        surgeRawSnapshot = .empty
        surgeConnectionRatesReceivedAt = nil
        singBoxTailscaleStatus = nil
        singBoxTailscaleError = nil
        liveObservation.reset()
        runtime.reset()
        controls.resetForControllerSwitch()
    }

    mutating func invalidate(reason: LiveSessionEndReason = .sessionEnd) {
        generation = UUID()
        controllerID = nil
        state = .stopped
        lastSuccessAt = nil
        latestReceivedAt = nil
        endReason = reason
        hasCommittedBaseline = false
        baselineTransaction.finish()
        refreshLanes = Dictionary(
            uniqueKeysWithValues: SessionRefreshLane.allCases.map { ($0, SessionRefreshLaneState()) }
        )
        endpointCache.reset()
        resetPendingPresentation()
        trafficTimeline.reset()
        memoryTimeline.reset()
        connectionCountTimeline.reset()
        connectionTransferRates.reset()
        logBuffer.removeAll()
        singBoxVersion = nil
        singBoxStatus = nil
        singBoxGroups = nil
        singBoxMode = nil
        singBoxActiveConnections = []
        surgeRawSnapshot = .empty
        surgeConnectionRatesReceivedAt = nil
        singBoxTailscaleStatus = nil
        singBoxTailscaleError = nil
        liveObservation.stop()
        runtime.reset()
        controls.resetForControllerSwitch()
    }

    mutating func resetForControllerSwitch() {
        invalidate(reason: .controllerSwitch)
    }

    mutating func beginReconnect(message: String) {
        guard hasCommittedBaseline, !baselineTransaction.isReconnect else { return }

        state = .staleReconnecting(message)
        baselineTransaction.begin(
            generation: generation,
            phase: .reconnect,
            receivedAt: lastSuccessAt
        )
        latestReceivedAt = nil
        endpointCache.reset()
        resetPendingPresentation()
        trafficTimeline.reset()
        memoryTimeline.reset()
        connectionCountTimeline.reset()
        connectionTransferRates.reset()
        logBuffer.removeAll()
        singBoxVersion = nil
        singBoxStatus = nil
        singBoxGroups = nil
        singBoxMode = nil
        singBoxActiveConnections = []
        surgeRawSnapshot = .empty
        surgeConnectionRatesReceivedAt = nil
    }

    mutating func recordReceived(at date: Date) {
        latestReceivedAt = max(latestReceivedAt ?? date, date)
        if baselineTransaction.isActive {
            baselineTransaction.recordReceived(at: date)
        }
    }

    mutating func recordSingBoxConnectionsReceived(at date: Date) {
        recordReceived(at: date)
        baselineTransaction.recordSingBoxConnections(at: date)
    }

    mutating func commitBaseline(at date: Date) {
        latestReceivedAt = max(latestReceivedAt ?? date, date)
        lastSuccessAt = latestReceivedAt
        hasCommittedBaseline = true
        baselineTransaction.finish()
        endReason = nil
    }

    mutating func recordPendingMemory(_ response: MemoryResponse, receivedAt: Date) {
        pendingPresentation.memory = response
        pendingMemorySample = PendingMemorySample(response: response, receivedAt: receivedAt)
    }

    mutating func resetPendingPresentation() {
        pendingPresentation.reset()
        pendingMemorySample = nil
    }

    var diagnosticsSummary: String {
        [
            "generation=\(generation.uuidString.prefix(8))",
            "controller=\(controllerID?.uuidString ?? "none")",
            "state=\(state.diagnosticsLabel)",
            "closed=\(controls.closedConnections.count)",
            "paused=\(controls.dashboardUpdatesPaused)",
            "group-visibility=all",
            "member-order=controller",
            "last-success=\(lastSuccessAt == nil ? "never" : "set")",
            "latest-received=\(latestReceivedAt == nil ? "never" : "set")",
            "baseline=\(hasCommittedBaseline ? "committed" : (baselineTransaction.isActive ? "staging" : "none"))",
            "refresh-fast=\(refreshLanes[.fast]?.lastSuccessAt == nil ? "waiting" : "ready")",
            "refresh-medium=\(refreshLanes[.medium]?.lastSuccessAt == nil ? "waiting" : "ready")",
            "refresh-slow=\(refreshLanes[.slow]?.lastSuccessAt == nil ? "waiting" : "ready")",
            "pending-presentation=\(!pendingPresentation.isEmpty)",
            "traffic-samples=\(trafficTimeline.samples.count)",
            "memory-samples=\(memoryTimeline.samples.count)",
            "connection-count-samples=\(connectionCountTimeline.samples.count)",
            "logs=\(logBuffer.entries.count)",
            "live=[\(liveObservation.diagnosticsSummary)]",
            "runtime=[\(runtime.diagnosticsSummary)]",
        ].joined(separator: "; ")
    }
}

struct ControllerSessionRuntimeState: Equatable, Sendable {
    // Mihomo reports memory values in bytes. Keep the upstream values unchanged
    // so presentation can apply the unit conversion exactly once.
    var memoryInUseBytes: Int?
    var memoryLimitBytes: Int?
    var memoryUpdatedAt: Date?
    var configurationReloadCount = 0
    var geoDataUpdateCount = 0
    var dnsFlushCount = 0
    var fakeIPFlushCount = 0
    var coreRestartCount = 0
    var coreUpgradeCount = 0
    var goroutineCount: Int?
    var connectionsIn: Int?
    var connectionsOut: Int?
    var lastRuntimeOperationAt: Date?

    mutating func reset() {
        memoryInUseBytes = nil
        memoryLimitBytes = nil
        memoryUpdatedAt = nil
        configurationReloadCount = 0
        geoDataUpdateCount = 0
        dnsFlushCount = 0
        fakeIPFlushCount = 0
        coreRestartCount = 0
        coreUpgradeCount = 0
        goroutineCount = nil
        connectionsIn = nil
        connectionsOut = nil
        lastRuntimeOperationAt = nil
    }

    mutating func recordMemory(_ memory: MemoryResponse, receivedAt: Date = Date()) {
        memoryInUseBytes = memory.inuse
        memoryLimitBytes = memory.oslimit
        memoryUpdatedAt = receivedAt
        lastRuntimeOperationAt = memoryUpdatedAt
    }

    mutating func recordSingBoxStatus(_ status: SingBoxStatusSnapshot, receivedAt: Date = Date()) {
        memoryInUseBytes = Int(clamping: status.memoryBytes)
        memoryUpdatedAt = receivedAt
        goroutineCount = Int(status.goroutines)
        connectionsIn = Int(status.connectionsIn)
        connectionsOut = Int(status.connectionsOut)
        lastRuntimeOperationAt = memoryUpdatedAt
    }

    mutating func recordDNSFlush() {
        dnsFlushCount += 1
        lastRuntimeOperationAt = Date()
    }

    mutating func recordConfigurationReload() {
        configurationReloadCount += 1
        lastRuntimeOperationAt = Date()
    }

    mutating func recordGeoDataUpdate() {
        geoDataUpdateCount += 1
        lastRuntimeOperationAt = Date()
    }

    mutating func recordFakeIPFlush() {
        fakeIPFlushCount += 1
        lastRuntimeOperationAt = Date()
    }

    mutating func recordCoreRestart() {
        coreRestartCount += 1
        lastRuntimeOperationAt = Date()
    }

    mutating func recordCoreUpgrade() {
        coreUpgradeCount += 1
        lastRuntimeOperationAt = Date()
    }

    var diagnosticsSummary: String {
        [
            "memory-inuse-bytes=\(memoryInUseBytes.map(String.init) ?? "unknown")",
            "memory-limit-bytes=\(memoryLimitBytes.map(String.init) ?? "unknown")",
            "memory-updated=\(memoryUpdatedAt == nil ? "never" : "set")",
            "goroutines=\(goroutineCount.map(String.init) ?? "unknown")",
            "connections-in=\(connectionsIn.map(String.init) ?? "unknown")",
            "connections-out=\(connectionsOut.map(String.init) ?? "unknown")",
            "configuration-reloads=\(configurationReloadCount)",
            "geo-data-updates=\(geoDataUpdateCount)",
            "dns-flushes=\(dnsFlushCount)",
            "fakeip-flushes=\(fakeIPFlushCount)",
            "core-restarts=\(coreRestartCount)",
            "core-upgrades=\(coreUpgradeCount)",
            "runtime-updated=\(lastRuntimeOperationAt == nil ? "never" : "set")",
            "boundary=remote-controller-api-only",
        ].joined(separator: "; ")
    }
}

struct ControllerSessionLiveObservation: Equatable, Sendable {
    var state: ControllerSessionLiveObservationState = .idle
    var source: ControllerSessionLiveSource = .none
    var trafficSampleCount = 0
    var memorySampleCount = 0
    var connectionFrameCount = 0
    var logEventCount = 0
    var nearLiveEventCount = 0
    var activeRequestCount = 0
    var recentRequestCount = 0
    var lastUpdatedAt: Date?

    var displayEventCount: Int {
        logEventCount + nearLiveEventCount
    }

    mutating func reset() {
        state = .idle
        source = .none
        trafficSampleCount = 0
        memorySampleCount = 0
        connectionFrameCount = 0
        logEventCount = 0
        nearLiveEventCount = 0
        activeRequestCount = 0
        recentRequestCount = 0
        lastUpdatedAt = nil
    }

    mutating func start(source: ControllerSessionLiveSource) {
        self.source = source
        state = .connecting
    }

    mutating func recordTrafficSample(source: ControllerSessionLiveSource) {
        self.source = source
        trafficSampleCount += 1
        lastUpdatedAt = Date()
        if state != .nearLive {
            state = .observing
        }
    }

    mutating func recordMemorySample(source: ControllerSessionLiveSource) {
        self.source = source
        memorySampleCount += 1
        lastUpdatedAt = Date()
        if state != .nearLive {
            state = .observing
        }
    }

    mutating func recordConnectionFrame(source: ControllerSessionLiveSource) {
        self.source = source
        connectionFrameCount += 1
        lastUpdatedAt = Date()
        if state != .nearLive {
            state = .observing
        }
    }

    mutating func recordLogEvent(source: ControllerSessionLiveSource) {
        self.source = source
        logEventCount += 1
        lastUpdatedAt = Date()
        state = .observing
    }

    mutating func record(
        _ delta: LiveSessionObservationDelta,
        receivedAt: Date
    ) {
        guard delta.totalEventCount > 0 else { return }
        source = delta.source
        trafficSampleCount += delta.trafficSamples
        memorySampleCount += delta.memorySamples
        connectionFrameCount += delta.connectionFrames
        logEventCount += delta.logEvents
        lastUpdatedAt = max(lastUpdatedAt ?? receivedAt, receivedAt)
        state = .observing
    }

    mutating func recordSurgeNearLive(eventCount: Int, activeRequestCount: Int, recentRequestCount: Int) {
        source = .surgeNearLive
        trafficSampleCount += 1
        nearLiveEventCount = max(eventCount, 0)
        self.activeRequestCount = max(activeRequestCount, 0)
        self.recentRequestCount = max(recentRequestCount, 0)
        lastUpdatedAt = Date()
        state = .nearLive
    }

    mutating func markFailure(partial: Bool) {
        state = partial ? .partial : .failed
    }

    mutating func markUnavailable(source: ControllerSessionLiveSource) {
        self.source = source
        state = .unavailable
    }

    mutating func stop() {
        state = .stopped
    }

    var diagnosticsSummary: String {
        [
            "state=\(state.diagnosticsLabel)",
            "source=\(source.diagnosticsLabel)",
            "traffic-samples=\(trafficSampleCount)",
            "memory-samples=\(memorySampleCount)",
            "connection-frames=\(connectionFrameCount)",
            "log-events=\(logEventCount)",
            "near-live-events=\(nearLiveEventCount)",
            "active-requests=\(activeRequestCount)",
            "recent-requests=\(recentRequestCount)",
            "updated=\(lastUpdatedAt == nil ? "never" : "set")",
            "visibility=full-controller-data",
        ].joined(separator: "; ")
    }
}

enum ControllerSessionLiveObservationState: Equatable, Sendable {
    case idle
    case connecting
    case observing
    case nearLive
    case partial
    case failed
    case unavailable
    case stopped

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("session.live_state_idle", language: language)
        case .connecting:
            MicaStrings.localized("session.live_state_connecting", language: language)
        case .observing:
            MicaStrings.localized("session.live_state_observing", language: language)
        case .nearLive:
            MicaStrings.localized("session.live_state_near_live", language: language)
        case .partial:
            MicaStrings.localized("session.live_state_partial", language: language)
        case .failed:
            MicaStrings.localized("session.live_state_failed", language: language)
        case .unavailable:
            MicaStrings.localized("session.live_state_unavailable", language: language)
        case .stopped:
            MicaStrings.localized("session.live_state_stopped", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .idle:
            "idle"
        case .connecting:
            "connecting"
        case .observing:
            "observing"
        case .nearLive:
            "near-live"
        case .partial:
            "partial"
        case .failed:
            "failed"
        case .unavailable:
            "unavailable"
        case .stopped:
            "stopped"
        }
    }
}

enum ControllerSessionLiveSource: Equatable, Sendable {
    case none
    case mihomoWebSocket
    case surgeNearLive
    case singBoxGRPC

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .none:
            MicaStrings.localized("session.live_source_none", language: language)
        case .mihomoWebSocket:
            MicaStrings.localized("session.live_source_mihomo_ws", language: language)
        case .surgeNearLive:
            MicaStrings.localized("session.live_source_surge_near_live", language: language)
        case .singBoxGRPC:
            MicaStrings.localized("session.live_source_sing_box_grpc", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .none:
            "none"
        case .mihomoWebSocket:
            "mihomo-websocket"
        case .surgeNearLive:
            "surge-near-live-http"
        case .singBoxGRPC:
            "sing-box-grpc"
        }
    }
}

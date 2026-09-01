import Foundation
import MicaCore

// MARK: - Controller target presentation

enum WorkbenchControllerTargetScope: Equatable, Sendable {
    case thisMac
    case networkHost
    case unconfigured

    init(host: String) {
        let candidate = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !candidate.contains(where: { $0.isWhitespace }),
              !candidate.contains("/"),
              !candidate.contains("\\") else {
            self = .unconfigured
            return
        }

        let normalized = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        if Self.isLoopback(normalized) {
            self = .thisMac
        } else {
            self = .networkHost
        }
    }

    var titleKey: String {
        switch self {
        case .thisMac: "target.scope_this_mac"
        case .networkHost: "target.scope_network_host"
        case .unconfigured: "target.scope_unconfigured"
        }
    }

    var detailKey: String {
        switch self {
        case .thisMac: "target.scope_this_mac_detail"
        case .networkHost: "target.scope_network_host_detail"
        case .unconfigured: "target.scope_unconfigured_detail"
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        if host == "localhost" || host == "localhost." || host == "::1"
            || host == "0:0:0:0:0:0:0:1" {
            return true
        }

        if host.hasPrefix("::ffff:127.") {
            return true
        }

        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.allSatisfy({ component in
                  guard let octet = Int(component) else { return false }
                  return (0 ... 255).contains(octet)
              }) else {
            return false
        }
        return components.first == "127"
    }
}

extension RouterProfile {
    var workbenchTargetScope: WorkbenchControllerTargetScope {
        WorkbenchControllerTargetScope(host: host)
    }

    var permitsThisMacTarget: Bool {
        controllerKind == .surgeCompatible && surgePlatform == .macLocal
    }

    var expectsNetworkControllerTarget: Bool {
        switch controllerKind {
        case .nikkiMihomoCompatible, .openClashMihomoCompatible:
            true
        case .surgeCompatible:
            surgePlatform != .macLocal
        case .autoDetect, .mihomoCompatible, .singBoxCompatible,
             .cmfaCompatible, .stashCompatible, .stashCmfaCompatible,
             .unknown, .unsupported:
            false
        }
    }
}

// MARK: - Actions projection

enum WorkbenchActionsAvailability: Equatable, Sendable {
    case checking
    case recovery
    case ready
    case partial
    case unsupported
}

enum WorkbenchActionsIntent: Equatable, Sendable {
    case testConnection
    case refresh
    case direct(UnifiedControllerAction)
    case runtimeOperation(String)
    case editController
    case openDiagnostics
    case navigate(WorkbenchDestination)
}

enum WorkbenchActionRisk: Equatable, Sendable {
    case standard
    case destructive
}

enum WorkbenchActionGroup: String, CaseIterable, Identifiable, Sendable {
    case connection
    case snapshot
    case maintenance
    case lifecycle

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .connection: "actions.group_connection"
        case .snapshot: "actions.group_data"
        case .maintenance: "actions.group_maintenance"
        case .lifecycle: "diagnostics.operation_core_lifecycle"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "antenna.radiowaves.left.and.right"
        case .snapshot: "externaldrive.connected.to.line.below"
        case .maintenance: "wrench.and.screwdriver"
        case .lifecycle: "powerplug"
        }
    }
}

struct WorkbenchActionCommand: Identifiable, Equatable, Sendable {
    let id: String
    let group: WorkbenchActionGroup
    let titleKey: String
    let detailKey: String
    let systemImage: String
    let intent: WorkbenchActionsIntent
    let risk: WorkbenchActionRisk
    let isEnabled: Bool
    let requiresConfirmation: Bool
    let confirmationMessageKey: String?
}

struct WorkbenchActionCommandGroup: Identifiable, Equatable, Sendable {
    var id: WorkbenchActionGroup { group }
    let group: WorkbenchActionGroup
    let commands: [WorkbenchActionCommand]
}

struct WorkbenchActionsRecovery: Equatable, Sendable {
    let titleKey: String
    let detailKey: String
    let message: String?
    let primaryIntent: WorkbenchActionsIntent?
}

struct WorkbenchActionsInput: Equatable {
    let router: RouterProfile
    let generation: UUID
    let controllerType: UnifiedControllerType
    let sessionState: LiveSessionState
    let capabilities: ControllerCapabilities
    let runtimeRows: [DiagnosticsRuntimeOperationRow]
    let canTest: Bool
    let canRefresh: Bool
    let isBusy: Bool
}

struct WorkbenchActionsSnapshot: Equatable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let availability: WorkbenchActionsAvailability
    let targetScope: WorkbenchControllerTargetScope
    let showsTargetCorrection: Bool
    let commandCount: Int
    let executableCount: Int
    let groups: [WorkbenchActionCommandGroup]
    let relatedDestinations: [WorkbenchDestination]
    let recovery: WorkbenchActionsRecovery?

    var visibleOperationIDs: [String] {
        groups.flatMap(\.commands).map(\.id)
    }
}

struct WorkbenchActionsLayoutDecision: Equatable, Sendable {
    static let compactMaximumWidth: CGFloat = 780
    static let denseMaximumWidth: CGFloat = 1_080
    static let twoColumnThreshold: CGFloat = 900

    let maximumContentWidth: CGFloat
    let usesTwoColumns: Bool

    static func resolve(
        commandCount: Int,
        availableWidth: CGFloat
    ) -> WorkbenchActionsLayoutDecision {
        let isSparse = commandCount <= 2
        return WorkbenchActionsLayoutDecision(
            maximumContentWidth: isSparse
                ? compactMaximumWidth
                : denseMaximumWidth,
            usesTwoColumns: !isSparse && availableWidth >= twoColumnThreshold
        )
    }
}

enum WorkbenchActionsProjection {
    static func snapshot(_ input: WorkbenchActionsInput) -> WorkbenchActionsSnapshot {
        let rawAvailability = availability(for: input)
        let groups = commandGroups(for: input, availability: rawAvailability)
        let effectiveAvailability = groups.isEmpty && rawAvailability.isCommandState
            ? WorkbenchActionsAvailability.unsupported
            : rawAvailability
        let commands = groups.flatMap(\.commands)
        let showsRelatedDestinations = effectiveAvailability == .unsupported
            || effectiveAvailability.isCommandState && commands.count <= 2
        let targetScope = input.router.workbenchTargetScope
        let showsTargetCorrection = targetScope == .thisMac
            && !input.router.permitsThisMacTarget
            && (
                input.router.expectsNetworkControllerTarget
                    || effectiveAvailability == .recovery
            )

        return WorkbenchActionsSnapshot(
            controllerID: input.router.id,
            generation: input.generation,
            availability: effectiveAvailability,
            targetScope: targetScope,
            showsTargetCorrection: showsTargetCorrection,
            commandCount: commands.count,
            executableCount: commands.reduce(into: 0) { count, command in
                if command.isEnabled { count += 1 }
            },
            groups: groups,
            relatedDestinations: showsRelatedDestinations
                ? relatedDestinations(for: input.capabilities)
                : [],
            recovery: recovery(for: input, availability: effectiveAvailability)
        )
    }

    private static func availability(
        for input: WorkbenchActionsInput
    ) -> WorkbenchActionsAvailability {
        switch input.sessionState {
        case .connecting:
            .checking
        case .live:
            input.controllerType.isResolvedActionsController ? .ready : .unsupported
        case .partial:
            input.controllerType.isResolvedActionsController ? .partial : .unsupported
        case .idle, .staleReconnecting, .failedBeforeFirstSnapshot, .failed, .stopped:
            .recovery
        }
    }

    private static func recovery(
        for input: WorkbenchActionsInput,
        availability: WorkbenchActionsAvailability
    ) -> WorkbenchActionsRecovery? {
        switch availability {
        case .checking:
            return WorkbenchActionsRecovery(
                titleKey: "actions.checking_title",
                detailKey: "actions.checking_detail",
                message: input.sessionState.failureDetail,
                primaryIntent: nil
            )
        case .recovery:
            return WorkbenchActionsRecovery(
                titleKey: "actions.recovery_title",
                detailKey: "actions.recovery_detail",
                message: input.sessionState.failureDetail,
                primaryIntent: input.canTest ? .testConnection : nil
            )
        case .unsupported:
            return WorkbenchActionsRecovery(
                titleKey: "actions.unsupported_title",
                detailKey: "actions.unsupported_detail",
                message: input.sessionState.failureDetail,
                primaryIntent: input.canTest ? .testConnection : nil
            )
        case .ready, .partial:
            return nil
        }
    }

    private static func commandGroups(
        for input: WorkbenchActionsInput,
        availability: WorkbenchActionsAvailability
    ) -> [WorkbenchActionCommandGroup] {
        guard availability.isCommandState else { return [] }

        let permitsLiveCommands = input.sessionState.allowsLiveCommands
        let ordinaryCommandEnabled = permitsLiveCommands && !input.isBusy
        var commands: [WorkbenchActionCommand] = []

        if input.capabilities.snapshot {
            commands.append(
                WorkbenchActionCommand(
                    id: "refresh",
                    group: .connection,
                    titleKey: "action.refresh",
                    detailKey: "command.action_refresh_detail",
                    systemImage: MicaSymbols.Operation.refreshData,
                    intent: .refresh,
                    risk: .standard,
                    isEnabled: input.canRefresh && !input.isBusy,
                    requiresConfirmation: false,
                    confirmationMessageKey: nil
                )
            )
        }

        appendDirectAction(
            .reloadRules,
            id: "reload-rules",
            titleKey: "action.reload_rules",
            detailKey: "diagnostics.operation_rules_detail",
            systemImage: MicaSymbols.Data.rules,
            group: .snapshot,
            input: input,
            isEnabled: ordinaryCommandEnabled,
            commands: &commands
        )
        appendDirectAction(
            .reloadProviders,
            id: "reload-providers",
            titleKey: "action.reload_providers",
            detailKey: "diagnostics.operation_external_resources_detail",
            systemImage: MicaSymbols.Data.providers,
            group: .snapshot,
            input: input,
            isEnabled: ordinaryCommandEnabled,
            commands: &commands
        )
        appendDirectAction(
            .reloadProfile,
            id: "reload-profile",
            titleKey: "action.surge_reload_profile",
            detailKey: "action.help_surge_reload_profile",
            systemImage: "doc.badge.arrow.up",
            group: .snapshot,
            input: input,
            isEnabled: ordinaryCommandEnabled,
            commands: &commands
        )

        for operationID in [
            "configuration-reload", "geo-resources", "memory", "dns-flush", "cache-flush",
            "core-restart", "core-upgrade",
        ] {
            guard let row = input.runtimeRows.first(where: { $0.id == operationID }),
                  row.status == .supported,
                  row.actionButtonKey != nil,
                  supportsRuntimeDispatcher(operationID, controllerType: input.controllerType) else {
                continue
            }

            let group: WorkbenchActionGroup = row.isDestructive ? .lifecycle : .maintenance
            commands.append(
                WorkbenchActionCommand(
                    id: row.id,
                    group: group,
                    titleKey: row.titleKey,
                    detailKey: row.detailKey,
                    systemImage: row.systemImage,
                    intent: .runtimeOperation(row.id),
                    risk: row.isDestructive ? .destructive : .standard,
                    isEnabled: ordinaryCommandEnabled,
                    requiresConfirmation: row.requiresConfirmation,
                    confirmationMessageKey: row.confirmationMessageKey
                )
            )
        }

        return WorkbenchActionGroup.allCases.compactMap { group in
            let groupCommands = commands.filter { $0.group == group }
            guard !groupCommands.isEmpty else { return nil }
            return WorkbenchActionCommandGroup(group: group, commands: groupCommands)
        }
    }

    private static func appendDirectAction(
        _ action: UnifiedControllerAction,
        id: String,
        titleKey: String,
        detailKey: String,
        systemImage: String,
        group: WorkbenchActionGroup,
        input: WorkbenchActionsInput,
        isEnabled: Bool,
        commands: inout [WorkbenchActionCommand]
    ) {
        guard input.capabilities.supports(action),
              supportsDirectDispatcher(action, controllerType: input.controllerType) else {
            return
        }

        commands.append(
            WorkbenchActionCommand(
                id: id,
                group: group,
                titleKey: titleKey,
                detailKey: detailKey,
                systemImage: systemImage,
                intent: .direct(action),
                risk: .standard,
                isEnabled: isEnabled,
                requiresConfirmation: false,
                confirmationMessageKey: nil
            )
        )
    }

    private static func supportsDirectDispatcher(
        _ action: UnifiedControllerAction,
        controllerType: UnifiedControllerType
    ) -> Bool {
        switch action {
        case .reloadRules:
            return controllerType.isMihomoHTTPFamily || controllerType == .surgeHTTPAPI
        case .reloadProviders:
            return controllerType.isMihomoHTTPFamily
        case .reloadProfile:
            return controllerType == .surgeHTTPAPI
        default:
            return false
        }
    }

    private static func supportsRuntimeDispatcher(
        _ operationID: String,
        controllerType: UnifiedControllerType
    ) -> Bool {
        switch operationID {
        case "configuration-reload", "geo-resources":
            return controllerType == .mihomoCompatible
                || controllerType == .nikkiMihomoCompatible
                || controllerType == .openClashMihomoCompatible
        case "cache-flush":
            return controllerType == .mihomoCompatible
                || controllerType == .nikkiMihomoCompatible
                || controllerType == .openClashMihomoCompatible
                || controllerType == .cmfaCompatible
        case "memory":
            return controllerType == .mihomoCompatible
                || controllerType == .nikkiMihomoCompatible
                || controllerType == .openClashMihomoCompatible
                || controllerType == .cmfaCompatible
        case "dns-flush":
            return controllerType == .mihomoCompatible
                || controllerType == .nikkiMihomoCompatible
                || controllerType == .openClashMihomoCompatible
                || controllerType == .cmfaCompatible
                || controllerType == .surgeHTTPAPI
        case "core-restart", "core-upgrade":
            return controllerType == .mihomoCompatible
                || controllerType == .nikkiMihomoCompatible
                || controllerType == .openClashMihomoCompatible
        default:
            return false
        }
    }

    private static func relatedDestinations(
        for capabilities: ControllerCapabilities
    ) -> [WorkbenchDestination] {
        var destinations: [WorkbenchDestination] = []
        if capabilities.policyGroups { destinations.append(.proxies) }
        if capabilities.connections || capabilities.activeRequests { destinations.append(.connections) }
        if capabilities.rules { destinations.append(.rules) }
        if capabilities.providers { destinations.append(.sources) }
        if capabilities.snapshot { destinations.append(.configuration) }
        return destinations
    }
}

private extension WorkbenchActionsAvailability {
    var isCommandState: Bool {
        self == .ready || self == .partial
    }
}

extension UnifiedControllerType {
    var hasWorkbenchRuntimeOperations: Bool {
        switch self {
        case .mihomoCompatible, .openClashMihomoCompatible,
             .nikkiMihomoCompatible, .cmfaCompatible:
            true
        case .surgeHTTPAPI, .singBoxCompatible, .stashCompatible,
             .stashCmfaCompatible, .smartProbe, .unknown, .unsupported:
            false
        }
    }
}

private extension UnifiedControllerType {
    var isResolvedActionsController: Bool {
        switch self {
        case .mihomoCompatible, .surgeHTTPAPI, .openClashMihomoCompatible,
             .nikkiMihomoCompatible, .singBoxCompatible, .cmfaCompatible,
             .stashCompatible:
            true
        case .stashCmfaCompatible, .smartProbe, .unknown, .unsupported:
            false
        }
    }

    var isMihomoHTTPFamily: Bool {
        switch self {
        case .mihomoCompatible, .openClashMihomoCompatible,
             .nikkiMihomoCompatible, .cmfaCompatible, .stashCompatible:
            true
        case .surgeHTTPAPI, .singBoxCompatible, .stashCmfaCompatible,
             .smartProbe, .unknown, .unsupported:
            false
        }
    }
}

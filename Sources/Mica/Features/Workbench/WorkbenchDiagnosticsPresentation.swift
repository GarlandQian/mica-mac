import Foundation
import MicaCore

// MARK: - Diagnostics presentation

enum WorkbenchDiagnosticsOverallState: Equatable, Sendable {
    case checking
    case ready
    case needsAttention
    case blocked
}

enum WorkbenchDiagnosticsFreshness: Equatable, Sendable {
    case checking
    case live(Date?)
    case retained(Date?)
    case paused(Date?)
    case unavailable
}

enum WorkbenchDiagnosticsIssueSeverity: Equatable, Sendable {
    case critical
    case warning
}

enum WorkbenchDiagnosticsAction: Equatable, Sendable {
    case refresh
    case resumePresentation
    case editController
    case navigate(WorkbenchDestination)

    var titleKey: String {
        switch self {
        case .refresh: "diagnostics.recheck_now"
        case .resumePresentation: "live.resume_updates"
        case .editController: "action.edit_router"
        case .navigate(let destination): destination.titleKey
        }
    }

    var systemImage: String {
        switch self {
        case .refresh: MicaSymbols.Operation.refreshData
        case .resumePresentation: "play.fill"
        case .editController: "pencil"
        case .navigate(let destination): destination.symbolName
        }
    }
}

struct WorkbenchDiagnosticsActionAvailability: Equatable, Sendable {
    let canRefresh: Bool
    let canTest: Bool
    let canTogglePresentationPause: Bool
    let isPresentationPaused: Bool
    let hasSelectedController: Bool
    let isBusy: Bool

    func isEnabled(_ action: WorkbenchDiagnosticsAction) -> Bool {
        switch action {
        case .refresh:
            canRefresh || canTest
        case .resumePresentation:
            canTogglePresentationPause && isPresentationPaused
        case .editController:
            hasSelectedController && !isBusy
        case .navigate:
            true
        }
    }
}

struct WorkbenchDiagnosticsEvidence: Identifiable, Equatable, Sendable {
    let id: String
    let titleKey: String
    let value: String
    let monospaced: Bool
}

struct WorkbenchDiagnosticsIssue: Identifiable, Equatable, Sendable {
    let id: String
    let severity: WorkbenchDiagnosticsIssueSeverity
    let title: String
    let detail: String
    let affectedDestinations: [WorkbenchDestination]
    let evidence: [WorkbenchDiagnosticsEvidence]
    let primaryAction: WorkbenchDiagnosticsAction?
}

struct WorkbenchDiagnosticsArea: Identifiable, Equatable, Sendable {
    var id: WorkbenchDestination { destination }
    let destination: WorkbenchDestination
    let titleKey: String
    let systemImage: String
}

struct WorkbenchDiagnosticsTechnicalItem: Identifiable, Equatable, Sendable {
    let id: String
    let titleKey: String
    let value: String
    let monospaced: Bool
}

struct WorkbenchDiagnosticsTechnicalGroup: Identifiable, Equatable, Sendable {
    let id: String
    let titleKey: String
    let items: [WorkbenchDiagnosticsTechnicalItem]
}

struct WorkbenchDiagnosticsInput: Equatable {
    let router: RouterProfile
    let generation: UUID
    let detectedKind: ControllerKind
    let controllerType: UnifiedControllerType
    let sessionState: LiveSessionState
    let lastSuccessAt: Date?
    let isPresentationPaused: Bool
    let presentationPausedAt: Date?
    let health: ControllerHealthSnapshot
    let capabilities: ControllerCapabilities
    let rulesState: EnhancedSnapshotState
    let providersState: EnhancedSnapshotState
    let liveStreamState: LiveStreamState
    let metadata: ControllerMetadataSnapshot
    let language: AppLanguage
}

struct WorkbenchDiagnosticsSnapshot: Equatable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let controllerName: String
    let visibleTarget: String
    let targetScope: WorkbenchControllerTargetScope
    let overallState: WorkbenchDiagnosticsOverallState
    let freshness: WorkbenchDiagnosticsFreshness
    let issues: [WorkbenchDiagnosticsIssue]
    let availableAreas: [WorkbenchDiagnosticsArea]
    let technicalGroups: [WorkbenchDiagnosticsTechnicalGroup]
    let checkedAt: Date?
}

enum WorkbenchDiagnosticsProjection {
    static func snapshot(_ input: WorkbenchDiagnosticsInput) -> WorkbenchDiagnosticsSnapshot {
        let isChecking = input.sessionState == .connecting
            || input.health.summary == .checking && input.lastSuccessAt == nil
        let controllerAccessIssue = isChecking ? nil : controllerAccessIssue(input)
        let suppressDomainIssues = controllerAccessIssue != nil

        var issues: [WorkbenchDiagnosticsIssue] = []
        if !isChecking {
            if let controllerAccessIssue {
                issues.append(controllerAccessIssue)
            } else if let adapterIssue = adapterIssue(input) {
                issues.append(adapterIssue)
            }

            if let issue = staleIssue(input) {
                issues.append(issue)
            }
            if input.isPresentationPaused {
                issues.append(pausedIssue(input))
            }

            if !suppressDomainIssues && !input.isPresentationPaused {
                issues.append(contentsOf: endpointIssues(input))
                appendSnapshotIssues(input, to: &issues)
                if let liveIssue = liveTelemetryIssue(input) {
                    issues.append(liveIssue)
                }
            }

            if case .partial(let message) = input.sessionState,
               !issues.contains(where: {
                   $0.id.hasPrefix("endpoint-") || $0.id == "live-telemetry"
               }) {
                issues.append(
                    issue(
                        id: "session-partial",
                        severity: .warning,
                        titleKey: "diagnostics.issue_partial_title",
                        detailKey: "diagnostics.issue_partial_detail",
                        affected: [.overview],
                        evidence: evidence(
                            id: "session-partial-message",
                            titleKey: "diagnostics.evidence_reason",
                            value: message,
                            language: input.language
                        ),
                        action: .refresh,
                        language: input.language
                    )
                )
            }
        }

        issues = deduplicatedAndSorted(issues)
        let overallState: WorkbenchDiagnosticsOverallState
        if isChecking {
            overallState = .checking
        } else if issues.contains(where: { $0.id == "controller-access" || $0.id == "adapter" })
            && input.lastSuccessAt == nil {
            overallState = .blocked
        } else if issues.isEmpty {
            overallState = .ready
        } else {
            overallState = .needsAttention
        }

        let availableAreas = availableAreas(input, issues: issues)
        return WorkbenchDiagnosticsSnapshot(
            controllerID: input.router.id,
            generation: input.generation,
            controllerName: input.router.displayName,
            visibleTarget: input.router.endpointURL,
            targetScope: input.router.workbenchTargetScope,
            overallState: overallState,
            freshness: freshness(input),
            issues: issues,
            availableAreas: availableAreas,
            technicalGroups: technicalGroups(input, availableAreas: availableAreas),
            checkedAt: input.health.checkedAt
        )
    }

    static func reconciledSelection(
        currentID: String?,
        issues: [WorkbenchDiagnosticsIssue]
    ) -> String? {
        if let currentID, issues.contains(where: { $0.id == currentID }) {
            return currentID
        }
        return issues.first?.id
    }

    static func displayableText(_ value: String) -> String? {
        guard let value = value.managementNonEmpty,
              !containsMachineAssignment(value),
              !containsAPIPath(value) else {
            return nil
        }
        return value
    }

    private static func controllerAccessIssue(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsIssue? {
        let summary = input.health.summary
        let stateIsFailure: Bool
        switch input.sessionState {
        case .idle, .failedBeforeFirstSnapshot, .failed, .stopped:
            stateIsFailure = true
        case .connecting, .live, .staleReconnecting, .partial:
            stateIsFailure = false
        }

        guard stateIsFailure
                || summary == .authFailed
                || summary == .wrongTarget
                || summary == .offline else {
            return nil
        }

        let titleKey: String
        let detailKey: String
        let action: WorkbenchDiagnosticsAction
        switch summary {
        case .authFailed:
            titleKey = "failure.auth_failed_headline"
            detailKey = "failure.auth_failed_message"
            action = .editController
        case .wrongTarget:
            titleKey = "failure.wrong_target_headline"
            detailKey = "failure.wrong_target_message"
            action = .editController
        case .unknown, .checking, .ready, .partial, .offline:
            titleKey = "failure.network_failed_headline"
            detailKey = "failure.network_failed_message"
            action = .refresh
        }

        let scope = input.router.workbenchTargetScope
        let detail = scope == .thisMac && !input.router.permitsThisMacTarget
            ? MicaStrings.localized("target.loopback_recovery_detail", language: input.language)
            : MicaStrings.localizedKey(detailKey, language: input.language)
        let message = input.sessionState.failureDetail
            ?? input.health.failureMessage
            ?? MicaStrings.localizedKey(detailKey, language: input.language)

        return WorkbenchDiagnosticsIssue(
            id: "controller-access",
            severity: .critical,
            title: MicaStrings.localizedKey(titleKey, language: input.language),
            detail: detail,
            affectedDestinations: WorkbenchDestination.workbenchTabCases,
            evidence: [
                WorkbenchDiagnosticsEvidence(
                    id: "controller-target",
                    titleKey: "settings.controller_endpoint",
                    value: input.router.endpointURL,
                    monospaced: true
                ),
                WorkbenchDiagnosticsEvidence(
                    id: "controller-failure",
                    titleKey: "diagnostics.evidence_reason",
                    value: displayableText(message)
                        ?? MicaStrings.localized("diagnostics.evidence_unavailable", language: input.language),
                    monospaced: false
                ),
            ],
            primaryAction: action
        )
    }

    private static func adapterIssue(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsIssue? {
        switch input.controllerType {
        case .smartProbe, .unknown, .unsupported, .stashCmfaCompatible:
            return issue(
                id: "adapter",
                severity: .critical,
                titleKey: "diagnostics.issue_adapter_title",
                detailKey: "diagnostics.issue_adapter_detail",
                affected: WorkbenchDestination.workbenchTabCases,
                evidence: WorkbenchDiagnosticsEvidence(
                    id: "adapter-kind",
                    titleKey: "settings.controller_type",
                    value: input.detectedKind.micaLabel(language: input.language),
                    monospaced: false
                ),
                action: .editController,
                language: input.language
            )
        case .mihomoCompatible, .surgeHTTPAPI, .openClashMihomoCompatible,
             .nikkiMihomoCompatible, .singBoxCompatible, .cmfaCompatible,
             .stashCompatible:
            return nil
        }
    }

    private static func staleIssue(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsIssue? {
        guard case .staleReconnecting(let message) = input.sessionState else { return nil }
        return issue(
            id: "session-stale",
            severity: .warning,
            titleKey: "diagnostics.issue_stale_title",
            detailKey: "diagnostics.issue_stale_detail",
            affected: WorkbenchDestination.workbenchTabCases,
            evidence: evidence(
                id: "session-stale-message",
                titleKey: "diagnostics.evidence_reason",
                value: message,
                language: input.language
            ),
            action: .refresh,
            language: input.language
        )
    }

    private static func pausedIssue(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsIssue {
        issue(
            id: "presentation-paused",
            severity: .warning,
            titleKey: "diagnostics.issue_paused_title",
            detailKey: "diagnostics.issue_paused_detail",
            affected: WorkbenchDestination.workbenchTabCases,
            evidence: WorkbenchDiagnosticsEvidence(
                id: "presentation-paused-at",
                titleKey: "diagnostics.evidence_paused_at",
                value: formatted(input.presentationPausedAt, language: input.language),
                monospaced: true
            ),
            action: .resumePresentation,
            language: input.language
        )
    }

    private static func endpointIssues(
        _ input: WorkbenchDiagnosticsInput
    ) -> [WorkbenchDiagnosticsIssue] {
        input.health.endpoints.compactMap { endpoint in
            guard case .failed(let message) = endpoint.status,
                  endpointIsExpected(endpoint.endpoint, capabilities: input.capabilities) else {
                return nil
            }

            let destination = destination(for: endpoint.endpoint)
            let severity: WorkbenchDiagnosticsIssueSeverity = endpoint.endpoint == .version
                && input.lastSuccessAt == nil ? .critical : .warning
            let endpointTitle = MicaStrings.localizedKey(
                endpoint.endpoint.displayTitleKey,
                language: input.language
            )
            let title = MicaStrings.localized(
                "diagnostics.issue_endpoint_title \(endpointTitle)",
                language: input.language
            )
            let action: WorkbenchDiagnosticsAction = endpoint.endpoint == .version
                ? .editController
                : .navigate(destination)

            return WorkbenchDiagnosticsIssue(
                id: "endpoint-\(endpoint.endpoint.shortName)",
                severity: severity,
                title: title,
                detail: MicaStrings.localized(
                    "diagnostics.issue_endpoint_detail",
                    language: input.language
                ),
                affectedDestinations: affectedDestinations(for: endpoint.endpoint),
                evidence: [
                    WorkbenchDiagnosticsEvidence(
                        id: "endpoint-status-\(endpoint.endpoint.shortName)",
                        titleKey: "diagnostics.evidence_result",
                        value: displayableText(message)
                            ?? endpoint.status.label(language: input.language),
                        monospaced: false
                    ),
                ],
                primaryAction: action
            )
        }
    }

    private static func appendSnapshotIssues(
        _ input: WorkbenchDiagnosticsInput,
        to issues: inout [WorkbenchDiagnosticsIssue]
    ) {
        let issueIDs = Set(issues.map(\.id))
        if input.capabilities.rules,
           !issueIDs.contains("endpoint-rules"),
           case .unavailable(let message) = input.rulesState {
            issues.append(
                issue(
                    id: "rules-data",
                    severity: .warning,
                    titleKey: "diagnostics.issue_rules_title",
                    detailKey: "diagnostics.issue_rules_detail",
                    affected: [.overview, .rules],
                    evidence: evidence(
                        id: "rules-data-message",
                        titleKey: "diagnostics.evidence_reason",
                        value: message,
                        language: input.language
                    ),
                    action: .navigate(.rules),
                    language: input.language
                )
            )
        }

        if input.capabilities.providers,
           !issueIDs.contains("endpoint-providers"),
           case .unavailable(let message) = input.providersState {
            issues.append(
                issue(
                    id: "sources-data",
                    severity: .warning,
                    titleKey: "diagnostics.issue_sources_title",
                    detailKey: "diagnostics.issue_sources_detail",
                    affected: [.overview, .sources],
                    evidence: evidence(
                        id: "sources-data-message",
                        titleKey: "diagnostics.evidence_reason",
                        value: message,
                        language: input.language
                    ),
                    action: .navigate(.sources),
                    language: input.language
                )
            )
        }
    }

    private static func liveTelemetryIssue(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsIssue? {
        guard input.capabilities.traffic || input.capabilities.logs else { return nil }
        let message: String
        switch input.liveStreamState {
        case .partial(let detail), .failed(let detail):
            message = detail
        case .idle, .connecting, .live, .nearLive, .unavailable, .stopped:
            return nil
        }

        var affected: [WorkbenchDestination] = [.overview]
        if input.capabilities.traffic { affected.append(.connections) }
        if input.capabilities.logs { affected.append(.logs) }
        return issue(
            id: "live-telemetry",
            severity: .warning,
            titleKey: "diagnostics.issue_telemetry_title",
            detailKey: "diagnostics.issue_telemetry_detail",
            affected: affected,
            evidence: evidence(
                id: "live-telemetry-message",
                titleKey: "diagnostics.evidence_reason",
                value: message,
                language: input.language
            ),
            action: .navigate(.overview),
            language: input.language
        )
    }

    private static func freshness(
        _ input: WorkbenchDiagnosticsInput
    ) -> WorkbenchDiagnosticsFreshness {
        if input.isPresentationPaused {
            return .paused(input.presentationPausedAt)
        }
        switch input.sessionState {
        case .connecting:
            return .checking
        case .live, .partial:
            return .live(input.lastSuccessAt)
        case .staleReconnecting where input.lastSuccessAt != nil:
            return .retained(input.lastSuccessAt)
        case .failed where input.lastSuccessAt != nil:
            return .retained(input.lastSuccessAt)
        case .idle, .staleReconnecting, .failedBeforeFirstSnapshot, .failed, .stopped:
            return .unavailable
        }
    }

    private static func availableAreas(
        _ input: WorkbenchDiagnosticsInput,
        issues: [WorkbenchDiagnosticsIssue]
    ) -> [WorkbenchDiagnosticsArea] {
        guard input.lastSuccessAt != nil else { return [] }

        let issueIDs = Set(issues.map(\.id))
        var areas: [WorkbenchDiagnosticsArea] = []
        func append(
            _ destination: WorkbenchDestination,
            when condition: Bool,
            excluding excludedIssueIDs: Set<String>
        ) {
            guard condition, issueIDs.isDisjoint(with: excludedIssueIDs) else { return }
            areas.append(
                WorkbenchDiagnosticsArea(
                    destination: destination,
                    titleKey: destination.titleKey,
                    systemImage: destination.symbolName
                )
            )
        }

        append(.proxies, when: input.capabilities.policyGroups, excluding: ["endpoint-proxies"])
        append(
            .connections,
            when: input.capabilities.connections || input.capabilities.activeRequests,
            excluding: ["endpoint-connections"]
        )
        append(.rules, when: input.capabilities.rules, excluding: ["endpoint-rules", "rules-data"])
        append(.sources, when: input.capabilities.providers, excluding: ["endpoint-providers", "sources-data"])
        append(
            .overview,
            when: input.capabilities.traffic || input.capabilities.logs,
            excluding: ["live-telemetry"]
        )
        append(.configuration, when: input.capabilities.snapshot, excluding: ["endpoint-configs"])
        return areas
    }

    private static func technicalGroups(
        _ input: WorkbenchDiagnosticsInput,
        availableAreas: [WorkbenchDiagnosticsArea]
    ) -> [WorkbenchDiagnosticsTechnicalGroup] {
        let controllerItems = [
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-name",
                titleKey: "diagnostics.active_controller",
                value: input.router.displayName,
                monospaced: false
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-requested-kind",
                titleKey: "diagnostics.technical_requested_type",
                value: input.router.controllerKind.micaLabel(language: input.language),
                monospaced: false
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-detected-kind",
                titleKey: "diagnostics.technical_detected_type",
                value: input.detectedKind.micaLabel(language: input.language),
                monospaced: false
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-target",
                titleKey: "settings.controller_endpoint",
                value: input.router.endpointURL,
                monospaced: true
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-target-scope",
                titleKey: "diagnostics.technical_target_scope",
                value: MicaStrings.localizedKey(input.router.workbenchTargetScope.titleKey, language: input.language),
                monospaced: false
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-version",
                titleKey: "diagnostics.version",
                value: input.metadata.versionLabel,
                monospaced: true
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "controller-mode",
                titleKey: "diagnostics.mode",
                value: MicaStrings.displayMode(input.metadata.mode, language: input.language),
                monospaced: false
            ),
        ].filter { $0.value.managementNonEmpty != nil && $0.value != "-" }

        let sessionItems = [
            WorkbenchDiagnosticsTechnicalItem(
                id: "session-state",
                titleKey: "diagnostics.technical_session_state",
                value: input.sessionState.label(language: input.language),
                monospaced: false
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "session-last-success",
                titleKey: "diagnostics.technical_last_success",
                value: formatted(input.lastSuccessAt, language: input.language),
                monospaced: true
            ),
            WorkbenchDiagnosticsTechnicalItem(
                id: "session-last-check",
                titleKey: "diagnostics.check_latest",
                value: formatted(input.health.checkedAt, language: input.language),
                monospaced: true
            ),
        ]

        var evidenceItems: [WorkbenchDiagnosticsTechnicalItem] = input.health.endpoints.compactMap { endpoint in
            guard endpointIsExpected(endpoint.endpoint, capabilities: input.capabilities),
                  endpoint.status != .idle else {
                return nil
            }
            let detail = displayableText(endpoint.status.detail(language: input.language))
            let label = endpoint.status.label(language: input.language)
            let value = detail == nil || detail == label ? label : "\(label) · \(detail!)"
            return WorkbenchDiagnosticsTechnicalItem(
                id: "evidence-\(endpoint.endpoint.shortName)",
                titleKey: endpoint.endpoint.displayTitleKey,
                value: value,
                monospaced: false
            )
        }
        if !availableAreas.isEmpty {
            let labels = availableAreas.map {
                MicaStrings.localizedKey($0.titleKey, language: input.language)
            }
            evidenceItems.append(
                WorkbenchDiagnosticsTechnicalItem(
                    id: "evidence-available-areas",
                    titleKey: "diagnostics.available_now",
                    value: labels.formatted(
                        .list(type: .and, width: .standard)
                            .locale(input.language.resolvedLocale)
                    ),
                    monospaced: false
                )
            )
        }

        return [
            WorkbenchDiagnosticsTechnicalGroup(
                id: "controller",
                titleKey: "diagnostics.technical_controller",
                items: controllerItems
            ),
            WorkbenchDiagnosticsTechnicalGroup(
                id: "session",
                titleKey: "diagnostics.technical_session",
                items: sessionItems
            ),
            WorkbenchDiagnosticsTechnicalGroup(
                id: "evidence",
                titleKey: "diagnostics.technical_evidence",
                items: evidenceItems
            ),
        ].filter { !$0.items.isEmpty }
    }

    private static func endpointIsExpected(
        _ endpoint: ControllerEndpointKind,
        capabilities: ControllerCapabilities
    ) -> Bool {
        switch endpoint {
        case .version: true
        case .configs: capabilities.snapshot
        case .proxies: capabilities.policyGroups
        case .connections: capabilities.connections || capabilities.activeRequests
        case .rules: capabilities.rules
        case .providers: capabilities.providers
        }
    }

    private static func destination(
        for endpoint: ControllerEndpointKind
    ) -> WorkbenchDestination {
        switch endpoint {
        case .version: .controllers
        case .configs: .configuration
        case .proxies: .proxies
        case .connections: .connections
        case .rules: .rules
        case .providers: .sources
        }
    }

    private static func affectedDestinations(
        for endpoint: ControllerEndpointKind
    ) -> [WorkbenchDestination] {
        switch endpoint {
        case .version: WorkbenchDestination.workbenchTabCases
        case .configs: [.overview, .configuration]
        case .proxies: [.overview, .proxies]
        case .connections: [.overview, .connections]
        case .rules: [.overview, .rules]
        case .providers: [.overview, .sources]
        }
    }

    private static func issue(
        id: String,
        severity: WorkbenchDiagnosticsIssueSeverity,
        titleKey: String,
        detailKey: String,
        affected: [WorkbenchDestination],
        evidence: WorkbenchDiagnosticsEvidence,
        action: WorkbenchDiagnosticsAction?,
        language: AppLanguage
    ) -> WorkbenchDiagnosticsIssue {
        WorkbenchDiagnosticsIssue(
            id: id,
            severity: severity,
            title: MicaStrings.localizedKey(titleKey, language: language),
            detail: MicaStrings.localizedKey(detailKey, language: language),
            affectedDestinations: affected,
            evidence: [evidence],
            primaryAction: action
        )
    }

    private static func evidence(
        id: String,
        titleKey: String,
        value: String,
        language: AppLanguage
    ) -> WorkbenchDiagnosticsEvidence {
        WorkbenchDiagnosticsEvidence(
            id: id,
            titleKey: titleKey,
            value: displayableText(value)
                ?? MicaStrings.localizedKey(
                    "diagnostics.evidence_unavailable",
                    language: language
                ),
            monospaced: false
        )
    }

    private static func deduplicatedAndSorted(
        _ issues: [WorkbenchDiagnosticsIssue]
    ) -> [WorkbenchDiagnosticsIssue] {
        var seen: Set<String> = []
        return issues
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let left = issueSortKey(lhs)
                let right = issueSortKey(rhs)
                return left == right ? lhs.id < rhs.id : left < right
            }
    }

    private static func issueSortKey(
        _ issue: WorkbenchDiagnosticsIssue
    ) -> Int {
        let severityRank = issue.severity == .critical ? 0 : 100
        let domainRank: Int = switch issue.id {
        case "controller-access": 0
        case "adapter": 1
        case "session-stale": 2
        case "presentation-paused": 3
        case "endpoint-version": 10
        case "endpoint-configs": 11
        case "endpoint-proxies": 12
        case "endpoint-connections": 13
        case "endpoint-rules", "rules-data": 14
        case "endpoint-providers", "sources-data": 15
        case "live-telemetry": 16
        case "session-partial": 20
        default: 90
        }
        return severityRank + domainRank
    }

    private static func formatted(
        _ date: Date?,
        language: AppLanguage
    ) -> String {
        guard let date = workbenchDisplayableDate(date) else {
            return MicaStrings.localized("diagnostics.never", language: language)
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    private static func containsMachineAssignment(_ value: String) -> Bool {
        value.split { character in
            character.isWhitespace || character == ";" || character == ","
        }.contains { fragment in
            guard let separator = fragment.firstIndex(of: "=") else { return false }
            let key = fragment[..<separator]
            let rawValue = fragment[fragment.index(after: separator)...]
            return !key.isEmpty
                && !rawValue.isEmpty
                && key.allSatisfy {
                    $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "."
                }
        }
    }

    private static func containsAPIPath(_ value: String) -> Bool {
        let uppercased = value.uppercased()
        let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
        if methods.contains(where: { uppercased.contains("\($0) /") }) {
            return true
        }

        let punctuation = CharacterSet(charactersIn: ".,;:!?()[]{}<>\"'")
        return value.split(whereSeparator: \.isWhitespace).contains { fragment in
            let token = String(fragment).trimmingCharacters(in: punctuation)
            if token.hasPrefix("/"), token.count > 1 { return true }
            guard let components = URLComponents(string: token),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host != nil else {
                return false
            }
            return !components.path.isEmpty && components.path != "/"
        }
    }
}

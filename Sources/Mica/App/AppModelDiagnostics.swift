import AppKit
import Foundation

extension AppModel {
    func copyDiagnosticsReport() {
        copyDiagnosticsExport(.diagnosticsReport)
    }

    func copyEndpointResults() {
        copyDiagnosticsExport(.endpointResults)
    }

    func copyCheckResults() {
        copyDiagnosticsExport(.checkResults)
    }

    func copyDiagnosticsExport(_ target: DiagnosticsExportTarget) {
        pendingDiagnosticsCopyTarget = target
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsExportPayload(for: target), forType: .string)
        pendingDiagnosticsCopyTarget = nil
        lastDiagnosticsCopyTarget = target
        diagnosticsTransientState = "copy-target=\(target.id); export=credentials-and-raw-bodies-excluded"

        if let router = selectedRouter {
            let targetTitle = target.title(language: presentationLanguage)
            let commandID = beginCommand(.diagnosticsCopy, router: router, summary: localized("operation.copying_export \(targetTitle)"))
            finishCommand(commandID, routerID: router.id, status: .success, summary: localized("operation.export_copied_summary \(targetTitle)"))
        }

        let targetTitle = target.title(language: presentationLanguage)
        operationState = .success(
            localized("operation.copied \(targetTitle)"),
            action: TrialCommandAction.diagnosticsCopy.title(language: presentationLanguage),
            target: selectedRouter?.displayName,
            nextStep: localized("action.paste_issue"),
            event: .diagnosticsReportCopied
        )
    }

    func performEndpointCheckAction(_ action: EndpointCheckAction) {
        switch action {
        case .retryTest:
            testSelectedRouter()
        case .refresh:
            refreshSelectedRouter()
        case .reloadRules:
            reloadRules()
        case .reloadProviders:
            reloadProviders()
        case .copyDiagnostics:
            copyDiagnosticsReport()
        }
    }

    func diagnosticsExportPayload(for target: DiagnosticsExportTarget) -> String {
        switch target {
        case .endpointResults:
            return [
                localized("diagnostics.endpoint_results_title"),
                endpointResultsExport,
                localized("diagnostics.report_policy"),
            ].joined(separator: "\n")
        case .checkResults:
            return [
                localized("diagnostics.check_results_title"),
                checkResultsExport,
                localized("diagnostics.report_policy"),
            ].joined(separator: "\n")
        case .diagnosticsReport:
            return diagnosticsReport
        }
    }

    func controllerDiagnosticsReport() -> String {
        let router = selectedRouter
        let controller = router?.endpointURL ?? localized("diagnostics.none")
        let lastConnected = router?.lastConnectedAt.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? localized("diagnostics.never")
        let activeController = router?.displayName ?? localized("diagnostics.none")

        return [
            localized("diagnostics.title"),
            localized("diagnostics.active_controller \(activeController)"),
            localized("diagnostics.controller \(controller)"),
            localized("diagnostics.connection \(connectionState.label(language: presentationLanguage))"),
            localized("diagnostics.version \(dashboard.versionLabel)"),
            localized("diagnostics.mode \(MicaStrings.displayMode(dashboard.mode, language: presentationLanguage))"),
            localized("diagnostics.policy_groups \(dashboard.groups.count)"),
            localized("diagnostics.connections \(dashboard.connections.count)"),
            localized("diagnostics.rules \(dashboard.rules.count)"),
            localized("diagnostics.proxy_providers \(dashboard.providers.count)"),
            localized("diagnostics.rules_snapshot \(rulesSnapshotState.diagnosticsLabel)"),
            localized("diagnostics.provider_snapshot \(providersSnapshotState.diagnosticsLabel)"),
            localized("diagnostics.controller_health \(controllerHealth.summary.diagnosticsLabel)"),
            localized("diagnostics.unified_controller \(unifiedControllerDiagnostics)"),
            localized("diagnostics.core_compatibility \(coreCompatibilitySummary.diagnosticsLabel)"),
            localized("diagnostics.capability_matrix \(capabilityMatrixDiagnostics)"),
            localized("diagnostics.capability_operations \(capabilityDrivenOperationDiagnostics)"),
            localized("diagnostics.controller_adapter \(controllerAdapterDiagnostics)"),
            localized("diagnostics.surge_snapshot \(surgeSnapshotDiagnostics)"),
            localized("diagnostics.observability \(observabilityReadinessDiagnostics)"),
            localized("diagnostics.base_endpoints \(controllerHealth.baseDiagnosticsLabel)"),
            localized("diagnostics.enhanced_endpoints \(controllerHealth.enhancedDiagnosticsLabel)"),
            localized("diagnostics.insight \(dashboard.insight.diagnosticsStats)"),
            localized("diagnostics.trial_session \(selectedTrialSession.diagnosticsSummary)"),
            localized("diagnostics.qa_summary \(diagnosticsQASummary)"),
            localized("diagnostics.smoke_checks \(realControllerSmokeSummary)"),
            localized("diagnostics.qa_sections"),
            diagnosticsReportSections.map { "- \($0.title): \($0.value)" }.joined(separator: "\n"),
            localized("diagnostics.section_endpoint_results"),
            endpointResultsExport,
            localized("diagnostics.section_check_results"),
            checkResultsExport,
            localized("diagnostics.last_connected \(lastConnected)"),
            localized("diagnostics.report_policy"),
        ].joined(separator: "\n")
    }

    func diagnosticsMachineReportPreview() -> String {
        let router = selectedRouter
        let activeController = router?.displayName ?? localized("diagnostics.none")

        return [
            localized("diagnostics.title"),
            localized("diagnostics.active_controller \(activeController)"),
            localized("diagnostics.connection \(connectionState.label(language: presentationLanguage))"),
            localized("diagnostics.version \(dashboard.versionLabel)"),
            localized("diagnostics.mode \(MicaStrings.displayMode(dashboard.mode, language: presentationLanguage))"),
            localized("diagnostics.policy_groups \(dashboard.groups.count)"),
            localized("diagnostics.connections \(dashboard.connections.count)"),
            localized("diagnostics.rules \(dashboard.rules.count)"),
            localized("diagnostics.proxy_providers \(dashboard.providers.count)"),
            localized("diagnostics.rules_snapshot \(rulesSnapshotState.diagnosticsLabel)"),
            localized("diagnostics.provider_snapshot \(providersSnapshotState.diagnosticsLabel)"),
            localized("diagnostics.controller_health \(controllerHealth.summary.diagnosticsLabel)"),
            localized("diagnostics.base_endpoints \(controllerHealth.baseDiagnosticsLabel)"),
            localized("diagnostics.enhanced_endpoints \(controllerHealth.enhancedDiagnosticsLabel)"),
            localized("diagnostics.insight \(dashboard.insight.diagnosticsStats)"),
            localized("diagnostics.trial_session \(selectedTrialSession.diagnosticsSummary)"),
            localized("diagnostics.qa_summary \(diagnosticsQASummary)"),
            localized("diagnostics.report_policy"),
        ].joined(separator: "\n")
    }

    func diagnosticsReportDisplayPreview() -> String {
        let router = selectedRouter
        let activeController = router?.displayName ?? localized("diagnostics.none")
        let baseReady = controllerHealth.baseEndpoints.filter { $0.status.isReady }.count
        let enhancedReady = controllerHealth.enhancedEndpoints.filter { $0.status.isReady }.count

        return [
            localized("diagnostics.title"),
            localized("diagnostics.active_controller \(activeController)"),
            localized("diagnostics.connection \(connectionState.label(language: presentationLanguage))"),
            localized("diagnostics.controller_health \(controllerHealth.summary.label(language: presentationLanguage))"),
            localized("diagnostics.core_compatibility \(coreCompatibilitySummary.label(language: presentationLanguage))"),
            localized("diagnostics.policy_groups \(dashboard.groups.count)"),
            localized("diagnostics.connections \(dashboard.connections.count)"),
            localized("diagnostics.rules \(dashboard.rules.count)"),
            localized("diagnostics.proxy_providers \(dashboard.providers.count)"),
            localized("diagnostics.display_endpoint_summary \(baseReady) \(controllerHealth.baseEndpoints.count) \(enhancedReady) \(controllerHealth.enhancedEndpoints.count)"),
            localized("diagnostics.insight \(dashboard.insight.diagnosticsStatsSummary(language: presentationLanguage))"),
            localized("diagnostics.report_policy"),
        ].joined(separator: "\n")
    }

    var diagnosticsReport: String {
        [
            localized("diagnostics.full_report_title"),
            localized("diagnostics.section_endpoint_results"),
            endpointResultsExport,
            localized("diagnostics.section_check_results"),
            checkResultsExport,
            localized("diagnostics.section_report"),
            controllerDiagnosticsReport(),
            localized("diagnostics.report_policy"),
        ].joined(separator: "\n")
    }

    var diagnosticsQASummary: String {
        let profile = selectedRouter == nil ? "missing" : "ready"
        let base = controllerHealth.baseDiagnosticsLabel
        let enhanced = controllerHealth.enhancedDiagnosticsLabel
        let session = selectedTrialSession.readinessDiagnosticsLabel

        return [
            "profile=\(profile)",
            "trial-readiness=\(session)",
            "controller=\(controllerHealth.summary.diagnosticsLabel)",
            "compatibility=\(coreCompatibilitySummary.diagnosticsLabel)",
            "capabilities=[\(capabilityMatrixDiagnostics)]",
            "operations=[\(capabilityDrivenOperationDiagnostics)]",
            "adapter=[\(controllerAdapterDiagnostics)]",
            "unified=[\(unifiedControllerDiagnostics)]",
            "surge=[\(surgeSnapshotDiagnostics)]",
            "observability=[\(observabilityReadinessDiagnostics)]",
            "base=[\(base)]",
            "enhanced=[\(enhanced)]",
            "commands=[\(selectedTrialSession.commandCountDiagnostics)]",
            "diagnostics=full-visible-ui; copied-report=credentials-and-raw-bodies-excluded",
        ].joined(separator: "; ")
    }

    var realControllerSmokeSummary: String {
        let profile = selectedRouter == nil ? "missing" : "configured"
        let baseReady = controllerHealth.baseEndpoints.filter { $0.status.isReady }.count
        let enhancedReady = controllerHealth.enhancedEndpoints.filter { $0.status.isReady }.count

        return [
            "profile=\(profile)",
            "connection=\(connectionState.diagnosticsLabel)",
            "controller=\(controllerHealth.summary.diagnosticsLabel)",
            "base-ready=\(baseReady)/\(controllerHealth.baseEndpoints.count)",
            "enhanced-ready=\(enhancedReady)/\(controllerHealth.enhancedEndpoints.count)",
            "rules=\(rulesSnapshotState.diagnosticsLabel)",
            "providers=\(providersSnapshotState.diagnosticsLabel)",
            "commands=[\(selectedTrialSession.commandCountDiagnostics)]",
            "data-source=real-controller-only",
        ].joined(separator: "; ")
    }

    var diagnosticsReportSections: [DiagnosticsReportSection] {
        [
            DiagnosticsReportSection(
                id: "controller-health",
                title: localized("diagnostics.section_controller_health"),
                value: "summary=\(controllerHealth.summary.diagnosticsLabel); connection=\(connectionState.diagnosticsLabel)"
            ),
            DiagnosticsReportSection(
                id: "core-compatibility",
                title: localized("diagnostics.section_core_compatibility"),
                value: "summary=\(coreCompatibilitySummary.diagnosticsLabel); capabilities=[\(capabilityMatrixDiagnostics)]"
            ),
            DiagnosticsReportSection(
                id: "controller-adapter",
                title: localized("diagnostics.section_controller_adapter"),
                value: controllerAdapterDiagnostics
            ),
            DiagnosticsReportSection(
                id: "capability-driven-operations",
                title: localized("diagnostics.section_capability_operations"),
                value: capabilityDrivenOperationDiagnostics
            ),
            DiagnosticsReportSection(
                id: "unified-controller",
                title: localized("diagnostics.section_unified_controller"),
                value: unifiedControllerDiagnostics
            ),
            DiagnosticsReportSection(
                id: "surge-snapshot",
                title: localized("diagnostics.section_surge_snapshot"),
                value: surgeSnapshotDiagnostics
            ),
            DiagnosticsReportSection(
                id: "observability-readiness",
                title: localized("diagnostics.section_observability"),
                value: observabilityReadinessDiagnostics
            ),
            DiagnosticsReportSection(
                id: "trial-readiness",
                title: localized("diagnostics.section_trial_readiness"),
                value: "readiness=\(selectedTrialSession.readinessDiagnosticsLabel); session=\(selectedTrialSession.sessionHealth.diagnosticsLabel)"
            ),
            DiagnosticsReportSection(
                id: "endpoint-summary",
                title: localized("diagnostics.section_endpoint_summary"),
                value: "base=[\(controllerHealth.baseDiagnosticsLabel)]; enhanced=[\(controllerHealth.enhancedDiagnosticsLabel)]"
            ),
            DiagnosticsReportSection(
                id: "command-count",
                title: localized("diagnostics.section_command_count"),
                value: selectedTrialSession.commandCountDiagnostics
            ),
            DiagnosticsReportSection(
                id: "snapshot-stats",
                title: localized("diagnostics.section_snapshot_stats"),
                value: snapshotStatsDiagnostics
            ),
            DiagnosticsReportSection(
                id: "scenario-qa",
                title: localized("diagnostics.section_smoke_checks"),
                value: realControllerSmokeSummary
            ),
            DiagnosticsReportSection(
                id: "data-visibility",
                title: localized("diagnostics.section_data_visibility"),
                value: localized("diagnostics.report_policy_value")
            ),
        ]
    }

    var endpointResultsExport: String {
        diagnosticsExportPlanRows
            .map { "- \($0.title): \($0.value)" }
            .joined(separator: "\n")
    }

    var exportPlanRows: [DiagnosticsExportPlanRow] {
        diagnosticsExportPlanRows
    }

    var diagnosticsExportPlanRows: [DiagnosticsExportPlanRow] {
        [
            DiagnosticsExportPlanRow(
                id: "app-version",
                title: localized("evidence.app_version"),
                value: "app=Mica; version=<development>",
                boundary: localized("evidence.boundary_app_version")
            ),
            DiagnosticsExportPlanRow(
                id: "active-router",
                title: localized("evidence.active_controller"),
                value: selectedRouter
                    .map { "name=\($0.displayName); endpoint=\($0.endpointURL); kind=\($0.controllerKind.rawValue)" }
                    ?? localized("diagnostics.none"),
                boundary: localized("evidence.boundary_active_controller")
            ),
            DiagnosticsExportPlanRow(
                id: "connection-state",
                title: localized("evidence.connection_state"),
                value: connectionState.label(language: presentationLanguage),
                boundary: localized("evidence.boundary_connection_state")
            ),
            DiagnosticsExportPlanRow(
                id: "controller-health",
                title: localized("evidence.controller_health_summary"),
                value: controllerHealth.summary.diagnosticsLabel,
                boundary: localized("evidence.boundary_controller_health")
            ),
            DiagnosticsExportPlanRow(
                id: "core-compatibility",
                title: localized("evidence.core_compatibility_summary"),
                value: coreCompatibilitySummary.diagnosticsLabel,
                boundary: localized("evidence.boundary_core_compatibility")
            ),
            DiagnosticsExportPlanRow(
                id: "endpoint-summary",
                title: localized("evidence.endpoint_summary"),
                value: "base=[\(controllerHealth.baseDiagnosticsLabel)]; enhanced=[\(controllerHealth.enhancedDiagnosticsLabel)]",
                boundary: localized("evidence.boundary_endpoint_summary")
            ),
            DiagnosticsExportPlanRow(
                id: "capability-aggregate",
                title: localized("evidence.capability_aggregate"),
                value: capabilityMatrixDiagnostics,
                boundary: localized("evidence.boundary_capability_aggregate")
            ),
            DiagnosticsExportPlanRow(
                id: "controller-adapter",
                title: localized("evidence.controller_adapter_summary"),
                value: controllerAdapterDiagnostics,
                boundary: localized("evidence.boundary_controller_adapter")
            ),
            DiagnosticsExportPlanRow(
                id: "capability-driven-operations",
                title: localized("evidence.capability_driven_operations"),
                value: capabilityDrivenOperationDiagnostics,
                boundary: localized("evidence.boundary_capability_operations")
            ),
            DiagnosticsExportPlanRow(
                id: "unified-controller",
                title: localized("evidence.unified_controller_summary"),
                value: unifiedControllerDiagnostics,
                boundary: localized("evidence.boundary_unified_controller")
            ),
            DiagnosticsExportPlanRow(
                id: "surge-snapshot",
                title: localized("evidence.surge_snapshot_aggregate"),
                value: surgeSnapshotDiagnostics,
                boundary: localized("evidence.boundary_surge_snapshot")
            ),
            DiagnosticsExportPlanRow(
                id: "observability-readiness",
                title: localized("evidence.observability_readiness"),
                value: observabilityReadinessDiagnostics,
                boundary: localized("evidence.boundary_observability")
            ),
            DiagnosticsExportPlanRow(
                id: "trial-readiness",
                title: localized("evidence.trial_readiness"),
                value: selectedTrialSession.readinessDiagnosticsLabel,
                boundary: localized("evidence.boundary_trial_readiness")
            ),
            DiagnosticsExportPlanRow(
                id: "command-count",
                title: localized("evidence.command_count_aggregate"),
                value: selectedTrialSession.commandCountDiagnostics,
                boundary: localized("evidence.boundary_command_count")
            ),
            DiagnosticsExportPlanRow(
                id: "snapshot-stats",
                title: localized("evidence.snapshot_stats_aggregate"),
                value: snapshotStatsDiagnostics,
                boundary: localized("evidence.boundary_snapshot_stats")
            ),
            DiagnosticsExportPlanRow(
                id: "real-controller-smoke-checks",
                title: localized("evidence.real_controller_smoke_checks"),
                value: realControllerSmokeSummary,
                boundary: localized("evidence.boundary_smoke_checks")
            ),
            DiagnosticsExportPlanRow(
                id: "data-visibility",
                title: localized("evidence.data_visibility_marker"),
                value: "active-ui=full-controller-data; copied-report=credentials-auth-headers-subscription-urls-raw-bodies-excluded",
                boundary: localized("evidence.boundary_data_visibility")
            ),
        ]
    }
}

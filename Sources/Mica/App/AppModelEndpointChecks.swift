import Foundation

extension AppModel {
    var endpointCheckSteps: [EndpointCheckStep] {
        let session = selectedTrialSession
        let testStatus = latestCommandStatus(.test, in: session)
        let providerEntry = latestProviderCommandEntry(in: session)
        let providerStatus = providerEntry?.status
        let delayStatus = latestCommandStatus(.testDelay, in: session)
        let closeStatus = latestCommandStatus(.closeConnection, in: session) ?? latestCommandStatus(.closeAll, in: session)
        let hasRouter = selectedRouter != nil
        let isSurge = selectedRouter.map { runtimeControllerKind(for: $0) == .surgeCompatible } ?? false
        let hasBaseSnapshot = isSurge ? !surgeSnapshot.isEmpty : dashboard.hasBaseSnapshot
        let enhancedReady = isSurge ? !surgeSnapshot.isEmpty : (rulesSnapshotState == .available && providersSnapshotState == .available)
        let proxiesCapability = isSurge ? (!surgeSnapshot.policyGroups.isEmpty ? CapabilityStatus.supported : CapabilityStatus.untested) : capabilityStatus(for: .proxies)
        let connectionsCapability = isSurge ? (!surgeSnapshot.isEmpty ? CapabilityStatus.supported : CapabilityStatus.untested) : capabilityStatus(for: .connections)
        let providersCapability = isSurge ? CapabilityStatus.unavailable : capabilityStatus(for: .providers)

        return [
            EndpointCheckStep(
                id: "endpoint-profile",
                title: localized("trial.profile"),
                state: hasRouter ? .passed : .failed,
                detail: hasRouter ? localized("trial.profile_ready_detail") : localized("trial.profile_missing_detail"),
                nextAction: hasRouter ? localized("trial.continue_test_connection") : localized("trial.add_or_select_controller"),
                primaryAction: nil
            ),
            EndpointCheckStep(
                id: "endpoint-test-connection",
                title: localized("trial.test_connection"),
                state: hasRouter ? endpointState(for: testStatus, defaultState: .ready) : .skipped,
                detail: lastResultLabel(for: .test, in: session),
                nextAction: testStatus == .success ? localized("trial.run_base_snapshot") : localized("trial.retry_test_or_edit"),
                primaryAction: hasRouter ? .retryTest : nil
            ),
            EndpointCheckStep(
                id: "endpoint-base-snapshot",
                title: localized("trial.base_snapshot"),
                state: isRefreshingDashboard ? .running : (hasBaseSnapshot ? .passed : endpointState(for: controllerHealth.summary, defaultState: hasRouter ? .ready : .skipped)),
                detail: hasBaseSnapshot ? (isSurge ? localized("trial.surge_base_loaded") : localized("trial.base_loaded")) : localized("trial.base_not_loaded"),
                nextAction: hasBaseSnapshot ? localized("trial.continue_enhanced_snapshot") : localized("trial.refresh_or_retry_test"),
                primaryAction: hasRouter ? .refresh : nil
            ),
            EndpointCheckStep(
                id: "endpoint-enhanced-snapshot",
                title: localized("trial.enhanced_snapshot"),
                state: reloadingRules || reloadingProviders ? .running : (enhancedReady ? .passed : (hasBaseSnapshot ? .partial : .skipped)),
                detail: isSurge ? surgeEnhancedSnapshotDisplaySummary : enhancedSnapshotDisplaySummary,
                nextAction: enhancedReady ? (isSurge ? localized("trial.use_surge_operations") : localized("trial.continue_provider_update")) : localized("trial.reload_rules_or_providers"),
                primaryAction: isSurge ? nil : (hasBaseSnapshot ? .reloadProviders : nil)
            ),
            EndpointCheckStep(
                id: "endpoint-provider-update",
                title: localized("trial.provider_update"),
                state: updatingProviderName == nil ? endpointState(for: providerStatus, defaultState: providersCapability == .supported ? .ready : .skipped) : .running,
                detail: isSurge ? localized("trial.surge_provider_not_included") : (providersCapability == .supported ? lastResultLabel(for: providerEntry) : localized("trial.provider_unavailable")),
                nextAction: providerStatus == .failed ? localized("trial.retry_provider_update") : (providersCapability == .supported ? localized("trial.use_provider_confirmation") : (isSurge ? localized("trial.use_surge_policy_controls") : localized("trial.reload_providers_or_refresh"))),
                primaryAction: nil
            ),
            EndpointCheckStep(
                id: "endpoint-delay-test",
                title: localized("trial.delay_test"),
                state: measuringDelayGroupID == nil ? endpointState(for: delayStatus, defaultState: proxiesCapability == .supported ? .ready : .skipped) : .running,
                detail: isSurge ? localized("trial.use_surge_policy_test") : (proxiesCapability == .supported ? lastResultLabel(for: .testDelay, in: session) : localized("trial.proxy_group_unavailable")),
                nextAction: delayStatus == .failed ? localized("trial.retry_test_delay") : (proxiesCapability == .supported ? (isSurge ? localized("trial.use_surge_policy_test") : localized("trial.use_route_delay")) : localized("trial.refresh_or_retry_test")),
                primaryAction: nil
            ),
            EndpointCheckStep(
                id: "endpoint-connection-close",
                title: localized("trial.connection_close"),
                state: closingConnectionID == nil && !closingAllConnections ? endpointState(for: closeStatus, defaultState: connectionsCapability == .supported ? .ready : .skipped) : .running,
                detail: isSurge ? localized("trial.use_surge_kill_request") : (connectionsCapability == .supported ? lastResultLabel(for: closeStatus == latestCommandStatus(.closeAll, in: session) ? .closeAll : .closeConnection, in: session) : localized("trial.connections_unavailable")),
                nextAction: closeStatus == .failed ? localized("trial.refresh_then_retry_close") : (connectionsCapability == .supported ? (isSurge ? localized("trial.use_surge_request_confirmation") : localized("trial.use_connection_confirmation")) : localized("trial.refresh_or_retry_test")),
                primaryAction: nil
            ),
            EndpointCheckStep(
                id: "endpoint-diagnostics-copy",
                title: localized("trial.diagnostics_copy"),
                state: lastDiagnosticsCopyTarget == nil ? (hasRouter ? .ready : .skipped) : .passed,
                detail: lastDiagnosticsCopyTarget.map { localized("trial.last_copied \($0.title(language: presentationLanguage))") } ?? localized("trial.copy_report_when_ready"),
                nextAction: localized("trial.copy_diagnostics"),
                primaryAction: hasRouter ? .copyDiagnostics : nil
            ),
        ]
    }

    var checkResultRows: [CheckResultRow] {
        let session = selectedTrialSession
        let testStatus = latestCommandStatus(.test, in: session)
        let providerEntry = latestProviderCommandEntry(in: session)
        let providerStatus = providerEntry?.status
        let closeStatus = latestCommandStatus(.closeConnection, in: session)
        let closeAllStatus = latestCommandStatus(.closeAll, in: session)
        let delayStatus = latestCommandStatus(.testDelay, in: session)
        let diagnosticsStatus = latestCommandStatus(.diagnosticsCopy, in: session)
        let isSurge = selectedRouter.map { runtimeControllerKind(for: $0) == .surgeCompatible } ?? false
        let hasBaseSnapshot = isSurge ? !surgeSnapshot.isEmpty : dashboard.hasBaseSnapshot
        let enhancedReady = isSurge ? !surgeSnapshot.isEmpty : (rulesSnapshotState == .available && providersSnapshotState == .available)
        let diagnosticsCopied = diagnosticsStatus == .success || lastDiagnosticsCopyTarget != nil

        return [
            CheckResultRow(
                id: "profile",
                title: localized("trial.profile"),
                state: selectedRouter == nil ? .attention : .ready,
                currentState: selectedRouter == nil ? localized("matrix.missing") : localized("matrix.ready"),
                latestResult: selectedRouter == nil ? localized("matrix.no_profile_selected") : localized("matrix.display_name_available"),
                lastChecked: safeTimeLabel(selectedRouter?.lastConnectedAt),
                nextAction: selectedRouter == nil ? localized("matrix.add_controller") : localized("matrix.edit_if_endpoint_changed"),
                retryAction: selectedRouter == nil ? localized("matrix.add_controller") : localized("matrix.edit_controller"),
                reportPolicy: localized("matrix.evidence_profile")
            ),
            CheckResultRow(
                id: "test-connection",
                title: localized("trial.test_connection"),
                state: checkResultState(for: testStatus),
                currentState: testStatus?.label(language: presentationLanguage) ?? localized("matrix.not_checked"),
                latestResult: lastResultLabel(for: .test, in: session),
                lastChecked: lastCheckedLabel(for: .test, in: session),
                nextAction: testStatus == .success ? localized("matrix.refresh") : localized("trial.retry_test_or_edit"),
                retryAction: testStatus == .failed ? localized("matrix.retry_test") : localized("matrix.retry_if_stale"),
                reportPolicy: localized("matrix.evidence_test")
            ),
            CheckResultRow(
                id: "base-snapshot",
                title: localized("trial.base_snapshot"),
                state: hasBaseSnapshot ? .ready : checkResultState(for: controllerHealth.summary),
                currentState: hasBaseSnapshot ? localized("matrix.ready") : controllerHealth.summary.label(language: presentationLanguage),
                latestResult: hasBaseSnapshot ? (isSurge ? localized("matrix.surge_snapshot_loaded") : localized("matrix.base_snapshot_loaded")) : localized("matrix.no_current_base_snapshot"),
                lastChecked: safeTimeLabel(session.lastSuccessfulBaseSnapshotAt),
                nextAction: hasBaseSnapshot ? localized("matrix.continue_trial") : localized("matrix.retry_test_or_refresh"),
                retryAction: hasBaseSnapshot ? localized("matrix.refresh") : localized("matrix.retry_test"),
                reportPolicy: isSurge ? localized("matrix.evidence_base_surge") : localized("matrix.evidence_base_mihomo")
            ),
            CheckResultRow(
                id: "enhanced-snapshot",
                title: localized("trial.enhanced_snapshot"),
                state: enhancedReady ? .ready : .partial,
                currentState: enhancedReady ? localized("matrix.ready") : localized("matrix.partial_or_not_loaded"),
                latestResult: isSurge ? surgeEnhancedSnapshotDisplaySummary : enhancedSnapshotDisplaySummary,
                lastChecked: safeTimeLabel(session.lastPartialSnapshotAt ?? session.lastRefreshedAt),
                nextAction: enhancedReady ? localized("matrix.continue_trial") : (isSurge ? localized("matrix.refresh_surge") : localized("trial.reload_rules_or_providers")),
                retryAction: enhancedReady ? localized("matrix.reload_if_stale") : (isSurge ? localized("matrix.refresh_surge") : localized("matrix.reload_rules_or_providers_short")),
                reportPolicy: isSurge ? localized("matrix.evidence_enhanced_surge") : localized("matrix.evidence_enhanced_mihomo")
            ),
            CheckResultRow(
                id: "provider-update",
                title: localized("trial.provider_update"),
                state: checkResultState(for: providerStatus),
                currentState: updatingProviderName == nil ? (providerStatus?.label(language: presentationLanguage) ?? localized("matrix.not_checked")) : localized("matrix.working"),
                latestResult: lastResultLabel(for: providerEntry),
                lastChecked: lastCheckedLabel(for: providerEntry),
                nextAction: isSurge ? localized("trial.use_surge_policy_controls") : (providerStatus == .failed ? localized("matrix.retry_failed_provider_update") : localized("matrix.update_provider_with_confirmation")),
                retryAction: isSurge ? localized("matrix.refresh_surge") : (providerStatus == .failed ? localized("trial.retry_provider_update") : localized("matrix.use_row_confirmation")),
                reportPolicy: isSurge ? localized("matrix.evidence_provider_surge") : localized("matrix.evidence_provider_mihomo")
            ),
            CheckResultRow(
                id: "close-connection",
                title: localized("trial.connection_close"),
                state: checkResultState(for: closeStatus),
                currentState: closingConnectionID == nil ? (closeStatus?.label(language: presentationLanguage) ?? localized("matrix.not_checked")) : localized("matrix.working"),
                latestResult: lastResultLabel(for: .closeConnection, in: session),
                lastChecked: lastCheckedLabel(for: .closeConnection, in: session),
                nextAction: closeStatus == .failed ? localized("trial.refresh_then_retry_close") : localized("matrix.close_selected_with_confirmation"),
                retryAction: closeStatus == .failed ? localized("matrix.refresh_then_retry") : localized("matrix.use_row_confirmation"),
                reportPolicy: localized("matrix.evidence_close_connection")
            ),
            CheckResultRow(
                id: "close-all-connections",
                title: localized("trial.close_all_connections"),
                state: checkResultState(for: closeAllStatus),
                currentState: closingAllConnections ? localized("matrix.working") : (closeAllStatus?.label(language: presentationLanguage) ?? localized("matrix.not_checked")),
                latestResult: lastResultLabel(for: .closeAll, in: session),
                lastChecked: lastCheckedLabel(for: .closeAll, in: session),
                nextAction: closeAllStatus == .failed ? localized("matrix.refresh_then_retry_close_all") : localized("matrix.close_all_with_confirmation"),
                retryAction: closeAllStatus == .failed ? localized("matrix.refresh_then_retry") : localized("matrix.use_close_all_confirmation"),
                reportPolicy: localized("matrix.evidence_close_all")
            ),
            CheckResultRow(
                id: "delay-test",
                title: localized("trial.delay_test"),
                state: checkResultState(for: delayStatus),
                currentState: measuringDelayGroupID == nil ? (delayStatus?.label(language: presentationLanguage) ?? localized("matrix.not_checked")) : localized("matrix.working"),
                latestResult: lastResultLabel(for: .testDelay, in: session),
                lastChecked: lastCheckedLabel(for: .testDelay, in: session),
                nextAction: delayStatus == .failed ? localized("trial.retry_test_delay") : localized("matrix.run_test_delay_from_module"),
                retryAction: delayStatus == .failed ? localized("trial.retry_test_delay") : localized("matrix.run_test_delay"),
                reportPolicy: localized("matrix.evidence_delay")
            ),
            CheckResultRow(
                id: "diagnostics-copy",
                title: localized("trial.diagnostics_copy"),
                state: diagnosticsCopied ? .ready : .notChecked,
                currentState: diagnosticsCopied ? localized("matrix.copied") : localized("matrix.ready"),
                latestResult: diagnosticsCopied ? localized("matrix.diagnostics_report_copied") : localized("matrix.no_copy_current_state"),
                lastChecked: lastCheckedLabel(for: .diagnosticsCopy, in: session),
                nextAction: localized("matrix.copy_diagnostics"),
                retryAction: localized("matrix.copy_full_report"),
                reportPolicy: localized("matrix.evidence_diagnostics")
            ),
        ]
    }

    var checkResultsExport: String {
        checkResultRows
            .map { row in
                "- \(row.title): state=\(row.state.label(language: presentationLanguage)); current=\(row.currentState); last=\(row.latestResult); checked=\(row.lastChecked); next=\(row.nextAction); retry=\(row.retryAction); evidence=\(row.reportPolicy)"
            }
            .joined(separator: "\n")
    }

    private func latestCommandStatus(_ action: TrialCommandAction, in session: TrialSessionSnapshot) -> CommandLifecycle? {
        latestCommandEntry(action, in: session)?.status
    }

    private func latestProviderCommandEntry(in session: TrialSessionSnapshot) -> CommandLogEntry? {
        var latestEntry: CommandLogEntry?

        for entry in session.commandLog
        where entry.action == .providerUpdate || entry.action == .providerUpdateAll {
            guard let currentLatest = latestEntry else {
                latestEntry = entry
                continue
            }

            if entry.timestamp > currentLatest.timestamp {
                latestEntry = entry
            }
        }

        return latestEntry
    }

    private func latestCommandEntry(_ action: TrialCommandAction, in session: TrialSessionSnapshot) -> CommandLogEntry? {
        session.commandLog.first { $0.action == action }
    }

    private func lastResultLabel(for action: TrialCommandAction, in session: TrialSessionSnapshot) -> String {
        lastResultLabel(for: latestCommandEntry(action, in: session))
    }

    private func lastResultLabel(for entry: CommandLogEntry?) -> String {
        guard let entry else {
            return localized("check.no_result")
        }

        return "\(entry.action.title(language: presentationLanguage)) \(entry.status.label(language: presentationLanguage))"
    }

    private func lastCheckedLabel(for action: TrialCommandAction, in session: TrialSessionSnapshot) -> String {
        lastCheckedLabel(for: latestCommandEntry(action, in: session))
    }

    private func lastCheckedLabel(for entry: CommandLogEntry?) -> String {
        safeTimeLabel(entry?.timestamp)
    }

    private func safeTimeLabel(_ date: Date?) -> String {
        guard let date else {
            return localized("matrix.not_recorded")
        }

        return ISO8601DateFormatter().string(from: date)
    }

    private func endpointState(
        for status: CommandLifecycle?,
        defaultState: EndpointCheckState
    ) -> EndpointCheckState {
        switch status {
        case .queued, .working:
            return .running
        case .success:
            return .passed
        case .partial:
            return .partial
        case .failed:
            return .failed
        case nil:
            return defaultState
        }
    }

    private func endpointState(
        for summary: ControllerHealthSummary,
        defaultState: EndpointCheckState
    ) -> EndpointCheckState {
        switch summary {
        case .ready:
            return .passed
        case .partial, .checking:
            return .partial
        case .authFailed, .wrongTarget, .offline:
            return .failed
        case .unknown:
            return defaultState
        }
    }

    private func checkResultState(for status: CommandLifecycle?) -> CheckResultState {
        switch status {
        case .success:
            return .ready
        case .partial, .queued, .working:
            return .partial
        case .failed:
            return .attention
        case nil:
            return .notChecked
        }
    }

    private func checkResultState(for summary: ControllerHealthSummary) -> CheckResultState {
        switch summary {
        case .ready:
            return .ready
        case .partial, .checking:
            return .partial
        case .authFailed, .wrongTarget, .offline:
            return .attention
        case .unknown:
            return .notChecked
        }
    }
}

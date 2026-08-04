import Foundation
import MicaCore

extension AppModel {
    var diagnosticsRuntimeOperationRows: [DiagnosticsRuntimeOperationRow] {
        let rowsByID = Dictionary(uniqueKeysWithValues: capabilityMatrixRows.map { ($0.id, $0) })

        return [
            diagnosticsRuntimeOperationRow(
                id: "core-config",
                titleKey: "workbench.configuration",
                detailKey: "diagnostics.operation_core_config_detail",
                sourceKey: "diagnostics.operation_source_configs",
                sourceRowID: "configs-mode",
                action: .changeMode,
                systemImage: MicaSymbols.Data.config,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "configuration-reload",
                titleKey: "action.reload_configuration",
                detailKey: "action.help_reload_configuration",
                sourceKey: "diagnostics.operation_source_configs",
                sourceRowID: "configuration-reload",
                action: .reloadConfiguration,
                systemImage: "arrow.triangle.2.circlepath",
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "external-resources",
                titleKey: "diagnostics.operation_external_resources",
                detailKey: "diagnostics.operation_external_resources_detail",
                sourceKey: "diagnostics.operation_source_providers",
                sourceRowID: "providers",
                action: .reloadProviders,
                systemImage: MicaSymbols.Data.providers,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "provider-update",
                titleKey: "diagnostics.operation_provider_update",
                detailKey: "diagnostics.operation_provider_update_detail",
                sourceKey: "diagnostics.operation_source_provider_update",
                sourceRowID: "provider-update",
                action: .updateProvider,
                systemImage: MicaSymbols.Operation.refreshData,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "rules",
                titleKey: "diagnostics.operation_rules",
                detailKey: "diagnostics.operation_rules_detail",
                sourceKey: "diagnostics.operation_source_rules",
                sourceRowID: "rules",
                action: .reloadRules,
                systemImage: MicaSymbols.Data.rules,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "traffic-logs",
                titleKey: "diagnostics.operation_logs",
                detailKey: "diagnostics.operation_logs_detail",
                sourceKey: "diagnostics.operation_source_live_logs",
                sourceRowID: "traffic-logs",
                action: nil,
                systemImage: MicaSymbols.Operation.liveTelemetry,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "connection-management",
                titleKey: "diagnostics.operation_connections",
                detailKey: "diagnostics.operation_connections_detail",
                sourceKey: "diagnostics.operation_source_connections",
                sourceRowID: "connections",
                action: .closeConnection,
                systemImage: MicaSymbols.Data.connection,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "dns-flush",
                titleKey: "diagnostics.operation_dns_flush",
                detailKey: "diagnostics.operation_dns_flush_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "dns-flush",
                action: .dnsFlush,
                systemImage: MicaSymbols.Data.dnsCache,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "cache-flush",
                titleKey: "diagnostics.operation_cache_flush",
                detailKey: "diagnostics.operation_cache_flush_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "cache-flush",
                action: .flushFakeIP,
                systemImage: MicaSymbols.Data.providers,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "geo-resources",
                titleKey: "diagnostics.operation_geo_resources",
                detailKey: "diagnostics.operation_geo_resources_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "geo-resources",
                action: .updateGeoData,
                systemImage: MicaSymbols.Data.dnsCache,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "memory",
                titleKey: "diagnostics.operation_memory",
                detailKey: "diagnostics.operation_memory_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "memory",
                action: nil,
                systemImage: MicaSymbols.Data.memory,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "runtime-status",
                titleKey: "diagnostics.operation_runtime_status",
                detailKey: "diagnostics.operation_runtime_status_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "runtime-status",
                action: nil,
                systemImage: MicaSymbols.Data.processor,
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "core-lifecycle",
                titleKey: "diagnostics.operation_core_lifecycle",
                detailKey: "diagnostics.operation_core_lifecycle_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "core-actions",
                action: nil,
                systemImage: "powerplug",
                rowsByID: rowsByID
            ),
            diagnosticsRuntimeOperationRow(
                id: "core-restart",
                titleKey: "diagnostics.operation_core_restart",
                detailKey: "diagnostics.operation_core_restart_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "core-actions",
                action: nil,
                systemImage: "restart.circle",
                rowsByID: rowsByID,
                requiresConfirmation: true,
                confirmationMessageKey: "diagnostics.confirm_core_restart_message",
                isDestructive: true
            ),
            diagnosticsRuntimeOperationRow(
                id: "core-upgrade",
                titleKey: "diagnostics.operation_core_upgrade",
                detailKey: "diagnostics.operation_core_upgrade_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "core-actions",
                action: nil,
                systemImage: MicaSymbols.Data.upload,
                rowsByID: rowsByID,
                requiresConfirmation: true,
                confirmationMessageKey: "diagnostics.confirm_core_upgrade_message",
                isDestructive: true
            ),
            diagnosticsRuntimeOperationRow(
                id: "tailscale",
                titleKey: "diagnostics.operation_tailscale",
                detailKey: "diagnostics.operation_tailscale_detail",
                sourceKey: "diagnostics.operation_source_backend_boundary",
                sourceRowID: "tailscale",
                action: nil,
                systemImage: MicaSymbols.Data.connection,
                rowsByID: rowsByID
            ),
        ]
    }

    private func diagnosticsRuntimeOperationRow(
        id: String,
        titleKey: String,
        detailKey: String,
        sourceKey: String,
        sourceRowID: String,
        action: UnifiedControllerAction?,
        systemImage: String,
        rowsByID: [String: CapabilityMatrixRow],
        requiresConfirmation: Bool = false,
        confirmationMessageKey: String? = nil,
        isDestructive: Bool = false
    ) -> DiagnosticsRuntimeOperationRow {
        let sourceStatus = rowsByID[sourceRowID]?.status ?? .unavailable
        let status = diagnosticsRuntimeOperationStatus(sourceStatus: sourceStatus, action: action)

        return DiagnosticsRuntimeOperationRow(
            id: id,
            titleKey: titleKey,
            detailKey: detailKey,
            sourceKey: sourceKey,
            sourceRowID: sourceRowID,
            systemImage: systemImage,
            status: status,
            nextStepKey: diagnosticsRuntimeNextStepKey(for: status),
            actionButtonKey: diagnosticsRuntimeActionButtonKey(id: id, status: status),
            requiresConfirmation: requiresConfirmation,
            confirmationMessageKey: confirmationMessageKey,
            isDestructive: isDestructive,
            evidence: diagnosticsRuntimeOperationEvidence(id: id, sourceKey: sourceKey, status: status)
        )
    }

    private func diagnosticsRuntimeActionButtonKey(id: String, status: CapabilityStatus) -> String? {
        guard status == .supported else {
            return nil
        }

        switch id {
        case "configuration-reload":
            return "diagnostics.run_configuration_reload"
        case "geo-resources":
            return "diagnostics.run_geo_update"
        case "memory":
            return "diagnostics.run_memory_check"
        case "dns-flush":
            return "diagnostics.run_dns_flush"
        case "cache-flush":
            return "diagnostics.run_cache_flush"
        case "core-restart":
            return "diagnostics.run_core_restart"
        case "core-upgrade":
            return "diagnostics.run_core_upgrade"
        default:
            return nil
        }
    }

    private func diagnosticsRuntimeOperationEvidence(
        id: String,
        sourceKey: String,
        status: CapabilityStatus
    ) -> String {
        switch id {
        case "configuration-reload":
            if controllerSession.runtime.configurationReloadCount > 0 {
                return localized("diagnostics.operation_configuration_reload_evidence \(controllerSession.runtime.configurationReloadCount)")
            }
        case "geo-resources":
            if controllerSession.runtime.geoDataUpdateCount > 0 {
                return localized("diagnostics.operation_geo_update_evidence \(controllerSession.runtime.geoDataUpdateCount)")
            }
        case "memory":
            if controllerSession.runtime.memoryInUseBytes != nil || controllerSession.runtime.memoryLimitBytes != nil {
                return localized(
                    "diagnostics.operation_memory_evidence \(formatRuntimeMemoryBytes(controllerSession.runtime.memoryInUseBytes)) \(formatRuntimeMemoryBytes(controllerSession.runtime.memoryLimitBytes))"
                )
            }
        case "dns-flush":
            if controllerSession.runtime.dnsFlushCount > 0 {
                return localized("diagnostics.operation_dns_flush_evidence \(controllerSession.runtime.dnsFlushCount)")
            }
        case "cache-flush":
            if controllerSession.runtime.fakeIPFlushCount > 0 {
                return localized("diagnostics.operation_fakeip_flush_evidence \(controllerSession.runtime.fakeIPFlushCount)")
            }
        case "core-lifecycle":
            if controllerSession.runtime.coreRestartCount > 0 || controllerSession.runtime.coreUpgradeCount > 0 {
                return localized("diagnostics.operation_core_lifecycle_evidence \(controllerSession.runtime.coreRestartCount) \(controllerSession.runtime.coreUpgradeCount)")
            }
        case "core-restart":
            if controllerSession.runtime.coreRestartCount > 0 {
                return localized("diagnostics.operation_core_restart_evidence \(controllerSession.runtime.coreRestartCount)")
            }
        case "core-upgrade":
            if controllerSession.runtime.coreUpgradeCount > 0 {
                return localized("diagnostics.operation_core_upgrade_evidence \(controllerSession.runtime.coreUpgradeCount)")
            }
        default:
            break
        }

        return localized("diagnostics.operation_evidence_summary \(MicaStrings.localizedKey(sourceKey, language: presentationLanguage)) \(status.label(language: presentationLanguage))")
    }

    private func formatRuntimeMemoryBytes(_ bytes: Int?) -> String {
        guard let bytes else {
            return localized("diagnostics.none")
        }

        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func diagnosticsRuntimeOperationStatus(
        sourceStatus: CapabilityStatus,
        action: UnifiedControllerAction?
    ) -> CapabilityStatus {
        guard let action else {
            return sourceStatus
        }

        if supportsUnifiedAction(action) {
            return sourceStatus == .supported ? .supported : sourceStatus
        }

        switch sourceStatus {
        case .supported:
            return .partial
        case .partial, .untested, .failed, .unavailable:
            return sourceStatus
        }
    }

    private func diagnosticsRuntimeNextStepKey(for status: CapabilityStatus) -> String {
        switch status {
        case .supported:
            return "diagnostics.operation_next_supported"
        case .partial:
            return "diagnostics.operation_next_partial"
        case .untested:
            return "diagnostics.operation_next_test_refresh"
        case .unavailable:
            return "diagnostics.operation_next_unavailable"
        case .failed:
            return "diagnostics.operation_next_failed"
        }
    }
}

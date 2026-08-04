import Foundation
import MicaCore

extension AppModel {
    private func capabilityTitle(for id: String) -> String {
        switch id {
        case "active-requests":
            localized("capability.active_requests")
        case "recent-requests":
            localized("capability.recent_requests")
        case "adapter-source":
            localized("capability.adapter_source")
        case "cache-flush":
            localized("diagnostics.operation_cache_flush")
        case "close-all":
            localized("capability.close_all")
        case "close-connection":
            localized("capability.close_connection")
        case "configs-mode":
            localized("capability.configs_mode")
        case "configuration-reload":
            localized("action.reload_configuration")
        case "connections":
            localized("endpoint.display_connections")
        case "controller-family":
            localized("editor.controller_family")
        case "core-actions":
            localized("diagnostics.operation_core_lifecycle")
        case "delay-test", "group-delay":
            localized("capability.delay_test")
        case "dns-flush":
            localized("diagnostics.operation_dns_flush")
        case "geo-resources":
            localized("diagnostics.operation_geo_resources")
        case "kill-request":
            localized("capability.kill_request")
        case "memory":
            localized("diagnostics.operation_memory")
        case "runtime-status":
            localized("diagnostics.operation_runtime_status")
        case "mode-change":
            localized("capability.mode_change")
        case "outbound-mode":
            localized("capability.outbound_mode")
        case "platform-scope":
            selectedRouter?.surgePlatform.micaLabel(language: presentationLanguage) ?? localized("capability.platform_scope")
        case "policy-groups":
            localized("capability.policy_groups")
        case "policy-select":
            localized("capability.policy_select")
        case "policy-test":
            localized("capability.policy_test")
        case "provider-update":
            localized("diagnostics.operation_provider_update")
        case "providers":
            localized("endpoint.display_providers")
        case "proxies-groups":
            localized("capability.proxies_groups")
        case "refresh-snapshot":
            localized("capability.refresh_snapshot")
        case "rules":
            localized("endpoint.display_rules")
        case "rules-providers":
            localized("capability.rules_providers")
        case "rules-traffic":
            localized("capability.rules_traffic")
        case "switch-policy":
            localized("capability.switch_policy")
        case "tailscale":
            localized("diagnostics.operation_tailscale")
        case "test-connection":
            localized("capability.test_connection")
        case "traffic-stream":
            localized("capability.traffic_stream")
        case "logs-stream":
            localized("capability.log_stream")
        case "traffic-logs":
            localized("capability.traffic_logs")
        case "version":
            localized("endpoint.display_version")
        default:
            id
        }
    }

    var coreCompatibilitySummary: CoreCompatibilitySummary {
        if let selectedRouter,
           [.surgeCompatible, .singBoxCompatible].contains(runtimeControllerKind(for: selectedRouter)) {
            return .unknownController
        }

        let versionStatus = controllerHealth.status(for: .version)
        let versionDetail = versionStatus.readyDetail?.lowercased() ?? dashboard.versionLabel.lowercased()
        let baseStatuses = controllerHealth.baseEndpoints.map(\.status)
        let enhancedStatuses = controllerHealth.enhancedEndpoints.map(\.status)
        let hasAnyProbe = controllerHealth.checkedAt != nil || baseStatuses.contains(where: { !$0.isIdle })

        guard hasAnyProbe else {
            return .unknownController
        }

        if controllerHealth.summary == .wrongTarget {
            return .unknownController
        }

        if controllerHealth.summary == .authFailed || controllerHealth.summary == .offline {
            return .unsupported
        }

        if baseStatuses.contains(where: { $0.isFailure }) {
            return .unsupported
        }

        let baseReady = baseStatuses.allSatisfy { $0.isReady }
        let enhancedFailed = enhancedStatuses.contains(where: { $0.isFailure })
        let enhancedUntested = enhancedStatuses.contains(where: { $0.isIdle || $0.isChecking })

        if versionDetail.contains("smart") {
            return baseReady && !enhancedFailed ? .smartCompatible : .partialCompatible
        }

        if baseReady && !enhancedFailed && !enhancedUntested {
            return .mihomoCompatible
        }

        if baseReady {
            return .partialCompatible
        }

        return .unknownController
    }

    var capabilityMatrixRows: [CapabilityMatrixRow] {
        let adapter = selectedControllerAdapter

        if let selectedRouter,
           runtimeControllerKind(for: selectedRouter) == .surgeCompatible {
            let surgeRows = adapter.capabilities.map { capability in
                CapabilityMatrixRow(
                    id: capability.id == "dns-flush" ? "dns-flush" : "surge-\(capability.id)",
                    title: capabilityTitle(for: capability.id),
                    status: capability.status,
                    evidence: capability.evidence,
                    operationImpact: localized("capability.impact_surge_separated")
                )
            }
            return surgeRows + backendUnavailableCapabilityRows(excluding: ["dns-flush"])
        }

        if let selectedRouter,
           runtimeControllerKind(for: selectedRouter) == .singBoxCompatible {
            return singBoxCapabilityMatrixRows(adapter: adapter)
        }

        if let selectedRouter,
           runtimeControllerKind(for: selectedRouter) == .stashCmfaCompatible {
            return futureBackendCapabilityRows(
                family: "Stash / CMFA",
                source: "stash-cmfa-api-unavailable",
                boundary: localized("capability.impact_future_stash_cmfa")
            )
        }

        let versionStatus = capabilityStatus(for: .version)
        let configsStatus = capabilityStatus(for: .configs)
        let proxiesStatus = capabilityStatus(for: .proxies)
        let connectionsStatus = capabilityStatus(for: .connections)
        let rulesStatus = capabilityStatus(for: .rules)
        let providersStatus = capabilityStatus(for: .providers)
        let ruleProvidersStatus = aggregateStatus([rulesStatus, providersStatus])
        let runtimeCapabilities = selectedRouter.map(effectiveUnifiedCapabilities(for:)) ?? .none
        let gatedStatus: (UnifiedControllerAction, CapabilityStatus) -> CapabilityStatus = { action, status in
            runtimeCapabilities.supports(action) ? status : .unavailable
        }
        let groupDelayStatus = gatedStatus(
            .testLatency,
            proxiesStatus == .supported ? .supported : proxiesStatus.fallbackStatus
        )
        let closeConnectionStatus = gatedStatus(
            .closeConnection,
            connectionsStatus == .supported ? .supported : connectionsStatus.fallbackStatus
        )
        let closeAllStatus = gatedStatus(
            .closeAllConnections,
            connectionsStatus == .supported ? .supported : connectionsStatus.fallbackStatus
        )
        let providerUpdateStatus = gatedStatus(
            .updateProvider,
            providersStatus == .supported ? .supported : providersStatus.fallbackStatus
        )
        let streamReadiness = optionalStreamReadinessState
        let runtimeUtilityStatus = versionStatus == .supported ? .supported : versionStatus.fallbackStatus
        let configurationReloadStatus = gatedStatus(.reloadConfiguration, configsStatus)
        let dnsFlushStatus = gatedStatus(.dnsFlush, runtimeUtilityStatus)
        let fakeIPFlushStatus = gatedStatus(.flushFakeIP, runtimeUtilityStatus)
        let geoDataStatus = gatedStatus(.updateGeoData, runtimeUtilityStatus)
        let memoryStatus = runtimeCapabilities.memory ? runtimeUtilityStatus : .unavailable
        let runtimeKind = selectedRouter.map(runtimeControllerKind(for:)) ?? .unknown
        let coreManagementStatus: CapabilityStatus = switch runtimeKind {
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible:
            runtimeUtilityStatus
        case .autoDetect, .surgeCompatible, .singBoxCompatible, .cmfaCompatible, .stashCompatible, .stashCmfaCompatible, .unknown, .unsupported:
            .unavailable
        }
        let configsImpact = runtimeCapabilities.modeChange
            ? localized("capability.impact_configs_supported")
            : localized("capability.impact_configs_read_only")

        return [
            CapabilityMatrixRow(id: "controller-family", title: capabilityTitle(for: "controller-family"), status: adapter.confidence.capabilityStatus, evidence: adapter.detectedKind.micaLabel(language: presentationLanguage), operationImpact: localized("capability.impact_adapter_source \(adapter.source.label(language: presentationLanguage)) \(adapter.nextSafeAction)")),
            CapabilityMatrixRow(id: "adapter-source", title: capabilityTitle(for: "adapter-source"), status: adapter.confidence.capabilityStatus, evidence: adapter.source.label(language: presentationLanguage), operationImpact: localized("capability.impact_adapter_counted")),
            CapabilityMatrixRow(id: "version", title: capabilityTitle(for: "version"), status: versionStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .version).detail, language: presentationLanguage), operationImpact: operationImpact(for: versionStatus, supported: localized("capability.impact_version_supported"))),
            CapabilityMatrixRow(id: "configs-mode", title: capabilityTitle(for: "configs-mode"), status: configsStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .configs).detail, language: presentationLanguage), operationImpact: operationImpact(for: configsStatus, supported: configsImpact)),
            CapabilityMatrixRow(id: "configuration-reload", title: capabilityTitle(for: "configuration-reload"), status: configurationReloadStatus, evidence: configurationReloadStatus == .supported ? localized("capability.evidence_api_path \("PUT /configs")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: configurationReloadStatus, supported: localized("capability.impact_configuration_reload_supported"))),
            CapabilityMatrixRow(id: "proxies-groups", title: capabilityTitle(for: "proxies-groups"), status: proxiesStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .proxies).detail, language: presentationLanguage), operationImpact: operationImpact(for: proxiesStatus, supported: localized("capability.impact_proxies_supported"))),
            CapabilityMatrixRow(id: "group-delay", title: capabilityTitle(for: "group-delay"), status: groupDelayStatus, evidence: proxiesStatus == .supported ? localized("capability.evidence_derived_proxy_group") : localized("capability.evidence_requires_proxy_groups"), operationImpact: operationImpact(for: groupDelayStatus, supported: localized("capability.impact_group_delay_supported"))),
            CapabilityMatrixRow(id: "connections", title: capabilityTitle(for: "connections"), status: connectionsStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .connections).detail, language: presentationLanguage), operationImpact: operationImpact(for: connectionsStatus, supported: localized("capability.impact_connections_supported"))),
            CapabilityMatrixRow(id: "close-connection", title: capabilityTitle(for: "close-connection"), status: closeConnectionStatus, evidence: closeConnectionStatus == .supported ? localized("capability.evidence_derived_connections") : localized("capability.evidence_requires_connections"), operationImpact: operationImpact(for: closeConnectionStatus, supported: localized("capability.impact_close_connection_supported"))),
            CapabilityMatrixRow(id: "close-all", title: capabilityTitle(for: "close-all"), status: closeAllStatus, evidence: closeAllStatus == .supported ? localized("capability.evidence_derived_connections") : localized("capability.evidence_requires_connections"), operationImpact: operationImpact(for: closeAllStatus, supported: localized("capability.impact_close_all_supported"))),
            CapabilityMatrixRow(id: "rules", title: capabilityTitle(for: "rules"), status: rulesStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .rules).detail, language: presentationLanguage), operationImpact: operationImpact(for: rulesStatus, supported: localized("capability.impact_rules_supported"))),
            CapabilityMatrixRow(id: "providers", title: capabilityTitle(for: "providers"), status: providersStatus, evidence: MicaStrings.displayEndpointDetail(controllerHealth.status(for: .providers).detail, language: presentationLanguage), operationImpact: operationImpact(for: providersStatus, supported: localized("capability.impact_providers_supported"))),
            CapabilityMatrixRow(id: "rules-providers", title: capabilityTitle(for: "rules-providers"), status: ruleProvidersStatus, evidence: ruleProvidersStatus == .supported ? localized("capability.evidence_api_paths \("GET /providers/proxies, GET /providers/rules")") : localized("capability.evidence_requires_providers"), operationImpact: operationImpact(for: ruleProvidersStatus, supported: localized("capability.impact_rules_providers_supported"))),
            CapabilityMatrixRow(id: "provider-update", title: capabilityTitle(for: "provider-update"), status: providerUpdateStatus, evidence: providerUpdateStatus == .supported ? localized("capability.evidence_derived_providers") : localized("capability.evidence_requires_providers"), operationImpact: operationImpact(for: providerUpdateStatus, supported: localized("capability.impact_provider_update_supported"))),
            CapabilityMatrixRow(id: "traffic-stream", title: capabilityTitle(for: "traffic-stream"), status: capabilityStatus(for: streamReadiness), evidence: streamReadiness == .ready ? localized("capability.evidence_api_path \("GET /traffic")") : optionalStreamReadinessDetail, operationImpact: streamReadiness == .ready ? localized("capability.impact_traffic_stream_ready") : localized("capability.impact_traffic_logs_unavailable")),
            CapabilityMatrixRow(id: "logs-stream", title: capabilityTitle(for: "logs-stream"), status: capabilityStatus(for: streamReadiness), evidence: streamReadiness == .ready ? localized("capability.evidence_api_path \("GET /logs")") : optionalStreamReadinessDetail, operationImpact: streamReadiness == .ready ? localized("capability.impact_log_stream_ready") : localized("capability.impact_traffic_logs_unavailable")),
            CapabilityMatrixRow(id: "traffic-logs", title: capabilityTitle(for: "traffic-logs"), status: capabilityStatus(for: streamReadiness), evidence: optionalStreamReadinessDetail, operationImpact: streamReadiness == .ready ? localized("capability.impact_traffic_logs_ready") : localized("capability.impact_traffic_logs_unavailable")),
            CapabilityMatrixRow(id: "dns-flush", title: capabilityTitle(for: "dns-flush"), status: dnsFlushStatus, evidence: dnsFlushStatus == .supported ? localized("capability.evidence_api_path \("POST /cache/dns/flush")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: dnsFlushStatus, supported: localized("capability.impact_dns_supported"))),
            CapabilityMatrixRow(id: "cache-flush", title: capabilityTitle(for: "cache-flush"), status: fakeIPFlushStatus, evidence: fakeIPFlushStatus == .supported ? localized("capability.evidence_api_path \("POST /cache/fakeip/flush")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: fakeIPFlushStatus, supported: localized("capability.impact_fakeip_supported"))),
            CapabilityMatrixRow(id: "geo-resources", title: capabilityTitle(for: "geo-resources"), status: geoDataStatus, evidence: geoDataStatus == .supported ? localized("capability.evidence_api_path \("POST /configs/geo")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: geoDataStatus, supported: localized("capability.impact_geo_update_supported"))),
            CapabilityMatrixRow(id: "memory", title: capabilityTitle(for: "memory"), status: memoryStatus, evidence: memoryStatus == .supported ? localized("capability.evidence_api_path \("GET /memory")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: memoryStatus, supported: localized("capability.impact_memory_supported"))),
            CapabilityMatrixRow(id: "runtime-status", title: capabilityTitle(for: "runtime-status"), status: .unavailable, evidence: localized("capability.evidence_runtime_status_unavailable"), operationImpact: localized("capability.impact_runtime_status_unavailable")),
            CapabilityMatrixRow(id: "core-actions", title: capabilityTitle(for: "core-actions"), status: coreManagementStatus, evidence: coreManagementStatus == .supported ? localized("capability.evidence_api_paths \("POST /restart, POST /upgrade")") : localized("capability.evidence_requires_ready_mihomo"), operationImpact: operationImpact(for: coreManagementStatus, supported: localized("capability.impact_core_actions_supported"))),
            CapabilityMatrixRow(id: "tailscale", title: capabilityTitle(for: "tailscale"), status: .unavailable, evidence: localized("capability.evidence_tailscale_unavailable"), operationImpact: localized("capability.impact_tailscale_unavailable")),
        ]
    }

    private func singBoxCapabilityMatrixRows(adapter: ControllerAdapter) -> [CapabilityMatrixRow] {
        let capabilities = ControllerCapabilities.singBoxCompatible
        let endpointStatus: (Bool, ControllerEndpointKind) -> CapabilityStatus = { supported, endpoint in
            supported ? self.capabilityStatus(for: endpoint) : .unavailable
        }
        let actionStatus: (UnifiedControllerAction, CapabilityStatus) -> CapabilityStatus = { action, status in
            capabilities.supports(action) ? status : .unavailable
        }
        let apiEvidence: (String) -> String = { rpc in
            self.localized("capability.evidence_api_path \(rpc)")
        }
        let apiEvidenceList: (String) -> String = { rpcs in
            self.localized("capability.evidence_api_paths \(rpcs)")
        }
        let unsupportedEvidence: (String) -> String = { capability in
            "\(SingBoxStartedServiceAdapter.sourceEvidence); \(capability)=false"
        }

        let versionStatus = endpointStatus(capabilities.snapshot, .version)
        let modeStatus = actionStatus(.changeMode, endpointStatus(capabilities.modeChange, .configs))
        let policyStatus = endpointStatus(capabilities.policyGroups, .proxies)
        let latencyStatus = actionStatus(.testLatency, policyStatus)
        let connectionStatus = endpointStatus(capabilities.connections, .connections)
        let closeConnectionStatus = actionStatus(.closeConnection, connectionStatus)
        let closeAllStatus = actionStatus(.closeAllConnections, connectionStatus)
        let rulesStatus = endpointStatus(capabilities.rules, .rules)
        let providersStatus = endpointStatus(capabilities.providers, .providers)
        let ruleProvidersStatus = aggregateStatus([rulesStatus, providersStatus])
        let providerUpdateStatus = actionStatus(.updateProvider, providersStatus)
        let trafficStatus = capabilities.traffic ? singBoxLiveCapabilityStatus : .unavailable
        let logsStatus = capabilities.logs ? singBoxLiveCapabilityStatus : .unavailable
        let trafficLogsStatus = aggregateStatus([trafficStatus, logsStatus])
        let memoryStatus = capabilities.memory ? singBoxRuntimeCapabilityStatus : .unavailable
        let runtimeStatus = capabilities.memory ? singBoxRuntimeCapabilityStatus : .unavailable
        let tailscaleStatus = singBoxTailscaleCapabilityStatus

        return [
            CapabilityMatrixRow(
                id: "controller-family",
                title: capabilityTitle(for: "controller-family"),
                status: adapter.confidence.capabilityStatus,
                evidence: adapter.detectedKind.micaLabel(language: presentationLanguage),
                operationImpact: localized(
                    "capability.impact_adapter_source \(adapter.source.label(language: presentationLanguage)) \(adapter.nextSafeAction)"
                )
            ),
            CapabilityMatrixRow(
                id: "adapter-source",
                title: capabilityTitle(for: "adapter-source"),
                status: adapter.confidence.capabilityStatus,
                evidence: SingBoxStartedServiceAdapter.sourceEvidence,
                operationImpact: localized("capability.impact_adapter_counted")
            ),
            CapabilityMatrixRow(
                id: "version",
                title: capabilityTitle(for: "version"),
                status: versionStatus,
                evidence: apiEvidence("StartedService/GetVersion"),
                operationImpact: operationImpact(
                    for: versionStatus,
                    supported: localized("capability.impact_version_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "configs-mode",
                title: capabilityTitle(for: "configs-mode"),
                status: modeStatus,
                evidence: apiEvidenceList(
                    "StartedService/GetClashModeStatus, StartedService/SubscribeClashMode, StartedService/SetClashMode"
                ),
                operationImpact: operationImpact(
                    for: modeStatus,
                    supported: localized("capability.impact_configs_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "configuration-reload",
                title: capabilityTitle(for: "configuration-reload"),
                status: actionStatus(.reloadConfiguration, modeStatus),
                evidence: unsupportedEvidence("capabilities.configurationReload"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "proxies-groups",
                title: capabilityTitle(for: "proxies-groups"),
                status: policyStatus,
                evidence: apiEvidenceList("StartedService/SubscribeGroups, StartedService/SelectOutbound"),
                operationImpact: operationImpact(
                    for: policyStatus,
                    supported: localized("capability.impact_proxies_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "group-delay",
                title: capabilityTitle(for: "group-delay"),
                status: latencyStatus,
                evidence: apiEvidence("StartedService/URLTest"),
                operationImpact: operationImpact(
                    for: latencyStatus,
                    supported: localized("capability.impact_group_delay_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "connections",
                title: capabilityTitle(for: "connections"),
                status: connectionStatus,
                evidence: apiEvidence("StartedService/SubscribeConnections"),
                operationImpact: operationImpact(
                    for: connectionStatus,
                    supported: localized("capability.impact_connections_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "close-connection",
                title: capabilityTitle(for: "close-connection"),
                status: closeConnectionStatus,
                evidence: apiEvidence("StartedService/CloseConnection"),
                operationImpact: operationImpact(
                    for: closeConnectionStatus,
                    supported: localized("capability.impact_close_connection_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "close-all",
                title: capabilityTitle(for: "close-all"),
                status: closeAllStatus,
                evidence: apiEvidence("StartedService/CloseAllConnections"),
                operationImpact: operationImpact(
                    for: closeAllStatus,
                    supported: localized("capability.impact_close_all_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "rules",
                title: capabilityTitle(for: "rules"),
                status: rulesStatus,
                evidence: unsupportedEvidence("capabilities.rules"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "providers",
                title: capabilityTitle(for: "providers"),
                status: providersStatus,
                evidence: unsupportedEvidence("capabilities.providers"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "rules-providers",
                title: capabilityTitle(for: "rules-providers"),
                status: ruleProvidersStatus,
                evidence: "\(unsupportedEvidence("capabilities.rules")); capabilities.providers=false",
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "provider-update",
                title: capabilityTitle(for: "provider-update"),
                status: providerUpdateStatus,
                evidence: unsupportedEvidence("capabilities.providerUpdate"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "traffic-stream",
                title: capabilityTitle(for: "traffic-stream"),
                status: trafficStatus,
                evidence: apiEvidence("StartedService/SubscribeStatus"),
                operationImpact: operationImpact(
                    for: trafficStatus,
                    supported: localized("capability.impact_traffic_stream_ready")
                )
            ),
            CapabilityMatrixRow(
                id: "logs-stream",
                title: capabilityTitle(for: "logs-stream"),
                status: logsStatus,
                evidence: apiEvidence("StartedService/SubscribeLog"),
                operationImpact: operationImpact(
                    for: logsStatus,
                    supported: localized("capability.impact_log_stream_ready")
                )
            ),
            CapabilityMatrixRow(
                id: "traffic-logs",
                title: capabilityTitle(for: "traffic-logs"),
                status: trafficLogsStatus,
                evidence: apiEvidenceList("StartedService/SubscribeStatus, StartedService/SubscribeLog"),
                operationImpact: operationImpact(
                    for: trafficLogsStatus,
                    supported: localized("capability.impact_traffic_logs_ready")
                )
            ),
            CapabilityMatrixRow(
                id: "dns-flush",
                title: capabilityTitle(for: "dns-flush"),
                status: actionStatus(.dnsFlush, runtimeStatus),
                evidence: unsupportedEvidence("capabilities.dnsFlush"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "cache-flush",
                title: capabilityTitle(for: "cache-flush"),
                status: actionStatus(.flushFakeIP, runtimeStatus),
                evidence: unsupportedEvidence("capabilities.fakeIPFlush"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "geo-resources",
                title: capabilityTitle(for: "geo-resources"),
                status: actionStatus(.updateGeoData, runtimeStatus),
                evidence: unsupportedEvidence("capabilities.geoDataUpdate"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "memory",
                title: capabilityTitle(for: "memory"),
                status: memoryStatus,
                evidence: apiEvidence("StartedService/SubscribeStatus"),
                operationImpact: operationImpact(
                    for: memoryStatus,
                    supported: localized("capability.impact_memory_supported")
                )
            ),
            CapabilityMatrixRow(
                id: "runtime-status",
                title: capabilityTitle(for: "runtime-status"),
                status: runtimeStatus,
                evidence: apiEvidence("StartedService/SubscribeStatus"),
                operationImpact: operationImpact(
                    for: runtimeStatus,
                    supported: localized("diagnostics.operation_runtime_status_detail")
                )
            ),
            CapabilityMatrixRow(
                id: "core-actions",
                title: capabilityTitle(for: "core-actions"),
                status: .unavailable,
                evidence: unsupportedEvidence("capabilities.coreManagement"),
                operationImpact: localized("capability.impact_unavailable")
            ),
            CapabilityMatrixRow(
                id: "tailscale",
                title: capabilityTitle(for: "tailscale"),
                status: tailscaleStatus,
                evidence: apiEvidenceList(
                    "StartedService/SubscribeTailscaleStatus, StartedService/SetTailscaleExitNode, StartedService/TailscaleLogout"
                ),
                operationImpact: operationImpact(
                    for: tailscaleStatus,
                    supported: localized("capability.impact_adapter_counted")
                )
            ),
        ]
    }

    private var backendUnavailableCapabilityRows: [CapabilityMatrixRow] {
        backendUnavailableCapabilityRows()
    }

    private func backendUnavailableCapabilityRows(excluding excludedIDs: Set<String> = []) -> [CapabilityMatrixRow] {
        [
            CapabilityMatrixRow(id: "configuration-reload", title: capabilityTitle(for: "configuration-reload"), status: .unavailable, evidence: localized("capability.evidence_requires_ready_mihomo"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "dns-flush", title: capabilityTitle(for: "dns-flush"), status: .unavailable, evidence: localized("capability.evidence_no_dns"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "cache-flush", title: capabilityTitle(for: "cache-flush"), status: .unavailable, evidence: localized("capability.evidence_cache_boundary"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "geo-resources", title: capabilityTitle(for: "geo-resources"), status: .unavailable, evidence: localized("capability.evidence_geo_no_contract"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "memory", title: capabilityTitle(for: "memory"), status: .unavailable, evidence: localized("capability.evidence_memory_no_contract"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "runtime-status", title: capabilityTitle(for: "runtime-status"), status: .unavailable, evidence: localized("capability.evidence_runtime_status_unavailable"), operationImpact: localized("capability.impact_runtime_status_unavailable")),
            CapabilityMatrixRow(id: "core-actions", title: capabilityTitle(for: "core-actions"), status: .unavailable, evidence: localized("capability.evidence_core_disabled"), operationImpact: localized("capability.impact_unavailable")),
            CapabilityMatrixRow(id: "tailscale", title: capabilityTitle(for: "tailscale"), status: .unavailable, evidence: localized("capability.evidence_tailscale_unavailable"), operationImpact: localized("capability.impact_tailscale_unavailable")),
        ].filter { !excludedIDs.contains($0.id) }
    }

    private func futureBackendCapabilityRows(
        family: String,
        source: String,
        boundary: String
    ) -> [CapabilityMatrixRow] {
        [
            CapabilityMatrixRow(id: "controller-family", title: capabilityTitle(for: "controller-family"), status: .unavailable, evidence: family, operationImpact: boundary),
            CapabilityMatrixRow(id: "adapter-source", title: capabilityTitle(for: "adapter-source"), status: .unavailable, evidence: source, operationImpact: localized("capability.impact_future_no_requests")),
            CapabilityMatrixRow(id: "rules", title: capabilityTitle(for: "rules"), status: .unavailable, evidence: localized("capability.evidence_future_rules \(family)"), operationImpact: localized("capability.impact_future_rules")),
            CapabilityMatrixRow(id: "providers", title: capabilityTitle(for: "providers"), status: .unavailable, evidence: localized("capability.evidence_future_providers \(family)"), operationImpact: localized("capability.impact_future_providers")),
            CapabilityMatrixRow(id: "policy-groups", title: capabilityTitle(for: "policy-groups"), status: .unavailable, evidence: localized("capability.evidence_future_policy_groups \(family)"), operationImpact: localized("capability.impact_future_policy_groups")),
            CapabilityMatrixRow(id: "connections", title: capabilityTitle(for: "connections"), status: .unavailable, evidence: localized("capability.evidence_future_connections \(family)"), operationImpact: localized("capability.impact_future_connections")),
            CapabilityMatrixRow(id: "traffic-logs", title: capabilityTitle(for: "traffic-logs"), status: .unavailable, evidence: localized("capability.evidence_future_live \(family)"), operationImpact: localized("capability.impact_future_live")),
            CapabilityMatrixRow(id: "runtime-status", title: capabilityTitle(for: "runtime-status"), status: .unavailable, evidence: localized("capability.evidence_future_runtime_status \(family)"), operationImpact: localized("capability.impact_runtime_status_unavailable")),
        ] + backendUnavailableCapabilityRows(excluding: ["runtime-status"])
    }

    private var singBoxLiveCapabilityStatus: CapabilityStatus {
        switch liveStreamState {
        case .live, .nearLive:
            return .supported
        case .partial:
            return .partial
        case .failed:
            return .failed
        case .unavailable:
            return .unavailable
        case .idle, .connecting, .stopped:
            return .untested
        }
    }

    private var singBoxRuntimeCapabilityStatus: CapabilityStatus {
        if controllerSession.singBoxStatus != nil {
            return .supported
        }

        switch singBoxLiveCapabilityStatus {
        case .partial, .failed, .unavailable:
            return singBoxLiveCapabilityStatus
        case .supported, .untested:
            return .untested
        }
    }

    private var singBoxTailscaleCapabilityStatus: CapabilityStatus {
        if controllerSession.singBoxTailscaleError != nil {
            return controllerSession.singBoxTailscaleStatus == nil ? .failed : .partial
        }

        if controllerSession.singBoxTailscaleStatus != nil {
            return .supported
        }

        switch singBoxLiveCapabilityStatus {
        case .partial, .failed, .unavailable:
            return singBoxLiveCapabilityStatus
        case .supported, .untested:
            return .untested
        }
    }

    var capabilityMatrixDiagnostics: String {
        let counts = Dictionary(grouping: capabilityMatrixRows) { $0.status }
            .mapValues { $0.count }

        return CapabilityStatus.allCases
            .map { "\($0.diagnosticsLabel)=\(counts[$0] ?? 0)" }
            .joined(separator: ", ")
    }

    var controllerDataCoverageRows: [CapabilityMatrixRow] {
        let rowsByID = Dictionary(uniqueKeysWithValues: capabilityMatrixRows.map { ($0.id, $0) })

        return [
            dataCoverageRow(
                id: "coverage-config",
                titleKey: "coverage.config_mode",
                detailKey: "coverage.detail_config_mode",
                sourceGroups: [
                    ["version", "surge-test-connection"],
                    ["configs-mode", "surge-outbound-mode", "surge-refresh-snapshot"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-proxy-nodes",
                titleKey: "coverage.proxy_groups_nodes",
                detailKey: "coverage.detail_proxy_groups_nodes",
                sourceGroups: [
                    ["proxies-groups", "surge-policy-groups", "surge-policy-select"],
                    ["group-delay", "surge-policy-test"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-connections",
                titleKey: "coverage.connections",
                detailKey: "coverage.detail_connections",
                sourceGroups: [
                    ["connections", "surge-active-requests", "surge-recent-requests"],
                    ["close-connection", "close-all", "surge-kill-request"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-rules",
                titleKey: "coverage.rules",
                detailKey: "coverage.detail_rules",
                sourceGroups: [["rules", "surge-rules-traffic"]],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-providers",
                titleKey: "coverage.providers",
                detailKey: "coverage.detail_providers",
                sourceGroups: [
                    ["providers", "rules-providers"],
                    ["provider-update"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-live",
                titleKey: "coverage.live_logs_traffic",
                detailKey: "coverage.detail_live_logs_traffic",
                sourceGroups: [
                    ["traffic-stream", "surge-rules-traffic", "surge-active-requests", "surge-recent-requests"],
                    ["logs-stream", "surge-rules-traffic"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-dns-cache-geo",
                titleKey: "coverage.dns_cache_geo",
                detailKey: "coverage.detail_dns_cache_geo",
                sourceGroups: [
                    ["dns-flush"],
                    ["cache-flush"],
                    ["geo-resources"],
                ],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-memory",
                titleKey: "coverage.memory_aggregates",
                detailKey: "coverage.detail_memory_aggregates",
                sourceGroups: [["memory"]],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-runtime-goroutine",
                titleKey: "coverage.runtime_goroutine",
                detailKey: "coverage.detail_runtime_goroutine",
                sourceGroups: [["runtime-status"]],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-core-lifecycle",
                titleKey: "coverage.core_lifecycle",
                detailKey: "coverage.detail_core_lifecycle",
                sourceGroups: [["core-actions"]],
                rowsByID: rowsByID
            ),
            dataCoverageRow(
                id: "coverage-tailscale",
                titleKey: "coverage.tailscale_status",
                detailKey: "coverage.detail_tailscale_status",
                sourceGroups: [["tailscale"]],
                rowsByID: rowsByID
            ),
        ]
    }

    private func dataCoverageRow(
        id: String,
        titleKey: String,
        detailKey: String,
        sourceGroups: [[String]],
        rowsByID: [String: CapabilityMatrixRow]
    ) -> CapabilityMatrixRow {
        let groupStatuses = sourceGroups.map { dataCoverageGroupStatus($0, rowsByID: rowsByID) }
        let sourceStatuses = groupStatuses.compactMap { $0.status }
        let status = dataCoverageStatus(sourceStatuses, hasMissingSource: groupStatuses.contains { $0.status == nil })
        let evidence = sourceGroups.map { sourceIDs in
            sourceIDs.map { sourceID in
                let sourceTitle = rowsByID[sourceID]?.title ?? localized("diagnostics.none")
                let sourceStatus = rowsByID[sourceID]?.status.label(language: presentationLanguage) ?? localized("matrix.missing")
                return localized("coverage.source_status \(sourceTitle) \(sourceStatus)")
            }.joined(separator: "|")
        }.joined(separator: "; ")

        return CapabilityMatrixRow(
            id: id,
            title: MicaStrings.localizedKey(titleKey, language: presentationLanguage),
            status: status,
            evidence: evidence,
            operationImpact: MicaStrings.localizedKey(detailKey, language: presentationLanguage)
        )
    }

    private func dataCoverageGroupStatus(
        _ sourceIDs: [String],
        rowsByID: [String: CapabilityMatrixRow]
    ) -> (status: CapabilityStatus?, hasSource: Bool) {
        let statuses = sourceIDs.compactMap { rowsByID[$0]?.status }

        guard !statuses.isEmpty else {
            return (nil, false)
        }

        if statuses.contains(.supported) {
            return (.supported, true)
        }

        if statuses.contains(.partial) {
            return (.partial, true)
        }

        if statuses.contains(.failed) {
            return (.failed, true)
        }

        if statuses.contains(.untested) {
            return (.untested, true)
        }

        return (.unavailable, true)
    }

    private func dataCoverageStatus(_ statuses: [CapabilityStatus], hasMissingSource: Bool) -> CapabilityStatus {
        guard !statuses.isEmpty else {
            return .unavailable
        }

        if statuses.allSatisfy({ $0 == .supported }) {
            return hasMissingSource ? .partial : .supported
        }

        if statuses.contains(.failed) {
            return .failed
        }

        if statuses.contains(where: { $0 == .supported || $0 == .partial }) {
            return .partial
        }

        if statuses.contains(.untested) {
            return .untested
        }

        return .unavailable
    }

    var observabilityReadinessRows: [ObservabilityReadinessRow] {
        let isSingBox = selectedRouter.map(runtimeControllerKind(for:)) == .singBoxCompatible
        let rulesState: ObservabilityReadinessState = isSingBox
            ? .unavailable
            : observabilityState(for: capabilityStatus(for: .rules))
        let providersState: ObservabilityReadinessState = isSingBox
            ? .unavailable
            : observabilityState(for: capabilityStatus(for: .providers))

        return [
            ObservabilityReadinessRow(
                id: "snapshot-connections",
                title: localized("observability.snapshot_connections_title"),
                category: localized("observability.category_snapshot"),
                state: observabilityState(for: capabilityStatus(for: .connections)),
                detail: localized("observability.snapshot_connections_detail"),
                boundary: localized("observability.snapshot_connections_boundary")
            ),
            ObservabilityReadinessRow(
                id: "snapshot-rules",
                title: localized("observability.snapshot_rules_title"),
                category: localized("observability.category_snapshot"),
                state: rulesState,
                detail: localized("observability.snapshot_rules_detail"),
                boundary: localized("observability.snapshot_rules_boundary")
            ),
            ObservabilityReadinessRow(
                id: "snapshot-providers",
                title: localized("observability.snapshot_providers_title"),
                category: localized("observability.category_snapshot"),
                state: providersState,
                detail: localized("observability.snapshot_providers_detail"),
                boundary: localized("observability.snapshot_providers_boundary")
            ),
            ObservabilityReadinessRow(
                id: "local-command-log",
                title: localized("observability.local_command_log_title"),
                category: localized("observability.category_local"),
                state: .ready,
                detail: localized("observability.local_command_log_detail"),
                boundary: localized("observability.local_command_log_boundary")
            ),
            ObservabilityReadinessRow(
                id: "diagnostics-report",
                title: localized("observability.diagnostics_report_title"),
                category: localized("observability.category_local"),
                state: .ready,
                detail: localized("observability.diagnostics_report_detail"),
                boundary: localized("observability.diagnostics_report_boundary")
            ),
            ObservabilityReadinessRow(
                id: "stream-ui-layer",
                title: localized("observability.stream_ui_layer_title"),
                category: localized("observability.category_live_stream"),
                state: optionalStreamReadinessState,
                detail: optionalStreamReadinessDetail,
                boundary: localized("observability.stream_ui_layer_boundary")
            ),
            ObservabilityReadinessRow(
                id: "optional-traffic-stream",
                title: localized("capability.traffic_stream"),
                category: localized("observability.category_live_stream"),
                state: optionalStreamReadinessState,
                detail: optionalStreamReadinessDetail,
                boundary: localized("observability.traffic_log_streams_boundary")
            ),
            ObservabilityReadinessRow(
                id: "optional-log-stream",
                title: localized("capability.log_stream"),
                category: localized("observability.category_live_stream"),
                state: optionalStreamReadinessState,
                detail: optionalStreamReadinessDetail,
                boundary: localized("observability.traffic_log_streams_boundary")
            ),
        ]
    }

    var observabilityReadinessDiagnostics: String {
        let counts = Dictionary(grouping: observabilityReadinessRows) { $0.state }
            .mapValues { $0.count }

        return ObservabilityReadinessState.allCases
            .map { "\($0.diagnosticsLabel)=\(counts[$0] ?? 0)" }
            .joined(separator: ", ")
    }

    var optionalStreamReadinessState: ObservabilityReadinessState {
        if selectedRouter.map(runtimeControllerKind(for:)) == .singBoxCompatible {
            return observabilityState(for: singBoxLiveCapabilityStatus)
        }

        switch coreCompatibilitySummary {
        case .mihomoCompatible:
            return .ready
        case .smartCompatible, .partialCompatible:
            return .controllerCapabilityUnknown
        case .unknownController:
            return .controllerCapabilityUnknown
        case .unsupported:
            return .unavailable
        }
    }

    var optionalStreamReadinessDetail: String {
        switch optionalStreamReadinessState {
        case .ready:
            return localized("capability.stream_ready")
        case .partial:
            return localized("capability.stream_partial")
        case .notImplementedInUI:
            return localized("capability.stream_disabled")
        case .controllerCapabilityUnknown:
            return localized("capability.stream_unknown")
        case .futureOptionalStream:
            return localized("capability.stream_future_optional")
        case .unavailable:
            return localized("capability.stream_unavailable")
        }
    }

    func capabilityStatus(for endpoint: ControllerEndpointKind) -> CapabilityStatus {
        switch controllerHealth.status(for: endpoint) {
        case .ready:
            return .supported
        case .failed:
            return endpoint.isBase ? .failed : .unavailable
        case .checking:
            return .untested
        case .idle:
            return .untested
        }
    }

    private func operationImpact(for status: CapabilityStatus, supported: String) -> String {
        switch status {
        case .supported:
            return supported
        case .unavailable:
            return localized("capability.impact_unavailable")
        case .partial:
            return localized("capability.impact_partial")
        case .untested:
            return localized("capability.impact_untested")
        case .failed:
            return localized("capability.impact_failed")
        }
    }

    func controllerAdapter(for router: RouterProfile?) -> ControllerAdapter {
        guard let router else {
            return ControllerAdapter(
                requestedKind: .unknown,
                detectedKind: .unknown,
                source: .unknown,
                confidence: .unknown,
                nextSafeAction: localized("adapter.next_add_controller"),
                capabilities: ControllerAdapterCapability.defaultRows(
                    status: .untested,
                    evidence: localized("capability.evidence_no_profile"),
                    language: presentationLanguage
                )
            )
        }

        let requestedKind = router.controllerKind
        let detectedKind = detectedControllerKind(for: router)
        let source = controllerAdapterSource(for: requestedKind, detected: detectedKind)
        let confidence = controllerAdapterConfidence(requested: requestedKind, detected: detectedKind)

        return ControllerAdapter(
            requestedKind: requestedKind,
            detectedKind: detectedKind,
            source: source,
            confidence: confidence,
            nextSafeAction: controllerAdapterNextSafeAction(kind: detectedKind, confidence: confidence),
            capabilities: controllerAdapterCapabilities(for: detectedKind, source: source)
        )
    }

    private func detectedControllerKind(for router: RouterProfile) -> ControllerKind {
        switch router.controllerKind {
        case .autoDetect:
            if controllerSession.controllerID == router.id {
                return activeSessionControllerKind ?? .unknown
            }
            switch coreCompatibilitySummary {
            case .mihomoCompatible:
                return .mihomoCompatible
            case .smartCompatible, .partialCompatible:
                return .unknown
            case .unknownController:
                return .unknown
            case .unsupported:
                return .unsupported
            }
        case .stashCmfaCompatible:
            if controllerSession.controllerID == router.id {
                return activeSessionControllerKind ?? .unknown
            }
            return .unknown
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible, .surgeCompatible, .singBoxCompatible, .cmfaCompatible, .stashCompatible, .unknown, .unsupported:
            return router.controllerKind
        }
    }

    private func controllerAdapterSource(for requested: ControllerKind, detected: ControllerKind) -> ControllerAdapterSource {
        let resolved = requested == .autoDetect || requested == .stashCmfaCompatible
            ? detected
            : requested
        switch resolved {
        case .autoDetect:
            return .autoProbe
        case .mihomoCompatible:
            return .mihomoExternalController
        case .nikkiMihomoCompatible:
            return .nikkiExternalController
        case .openClashMihomoCompatible:
            return .openClashExternalController
        case .surgeCompatible:
            return .surgeHTTPAPIAdapter
        case .cmfaCompatible:
            return .cmfaExternalController
        case .stashCompatible:
            return .stashExternalController
        case .singBoxCompatible:
            return .singBoxStartedServiceGRPC
        case .stashCmfaCompatible:
            return .stashCmfaAdapterUnavailable
        case .unknown:
            return requested == .autoDetect ? .autoProbe : .unknown
        case .unsupported:
            return .unknown
        }
    }

    private func controllerAdapterConfidence(requested: ControllerKind, detected: ControllerKind) -> ControllerAdapterConfidence {
        if detected == .unsupported {
            return .unsupported
        }

        if detected == .singBoxCompatible {
            switch (controllerHealth.summary, liveStreamState) {
            case (.authFailed, _), (.wrongTarget, _), (.offline, _),
                 (_, .partial), (_, .failed), (_, .unavailable):
                return .partial
            default:
                return requested == .autoDetect ? .detected : .configured
            }
        }

        if requested == .surgeCompatible {
            switch controllerHealth.summary {
            case .authFailed, .wrongTarget, .offline:
                return .partial
            case .ready:
                return .configured
            case .partial, .checking, .unknown:
                return surgeSnapshot.isEmpty ? .partial : .configured
            }
        }

        if requested == .autoDetect || requested == .stashCmfaCompatible {
            return detected == .unknown ? .unknown : .detected
        }

        if controllerHealth.summary == .partial || coreCompatibilitySummary == .partialCompatible {
            return .partial
        }

        return .configured
    }

    private func controllerAdapterCapabilities(
        for kind: ControllerKind,
        source: ControllerAdapterSource
    ) -> [ControllerAdapterCapability] {
        switch kind {
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible, .cmfaCompatible, .stashCompatible:
            let capabilities = unifiedCapabilities(for: kind)
            let gated: (UnifiedControllerAction, CapabilityStatus) -> CapabilityStatus = { action, status in
                capabilities.supports(action) ? status : .unavailable
            }
            return [
                ControllerAdapterCapability(id: "test-connection", title: capabilityTitle(for: "test-connection"), status: capabilityStatus(for: .version), evidence: localized("capability.evidence_mihomo_probe \(source.label(language: presentationLanguage))")),
                ControllerAdapterCapability(id: "refresh-snapshot", title: capabilityTitle(for: "refresh-snapshot"), status: aggregateStatus([capabilityStatus(for: .configs), capabilityStatus(for: .proxies), capabilityStatus(for: .connections)]), evidence: localized("capability.evidence_mihomo_base_snapshot")),
                ControllerAdapterCapability(id: "switch-policy", title: capabilityTitle(for: "switch-policy"), status: gated(.switchPolicy, capabilityStatus(for: .proxies)), evidence: localized("capability.evidence_mihomo_switch_policy")),
                ControllerAdapterCapability(id: "delay-test", title: capabilityTitle(for: "delay-test"), status: gated(.testLatency, capabilityStatus(for: .proxies)), evidence: localized("capability.evidence_mihomo_delay_test")),
                ControllerAdapterCapability(id: "mode-change", title: capabilityTitle(for: "mode-change"), status: gated(.changeMode, capabilityStatus(for: .configs)), evidence: localized("capability.evidence_mihomo_mode_change")),
                ControllerAdapterCapability(id: "close-connection", title: capabilityTitle(for: "close-connection"), status: gated(.closeConnection, capabilityStatus(for: .connections)), evidence: localized("capability.evidence_mihomo_close_connection")),
                ControllerAdapterCapability(id: "close-all", title: capabilityTitle(for: "close-all"), status: gated(.closeAllConnections, capabilityStatus(for: .connections)), evidence: localized("capability.evidence_mihomo_close_all")),
                ControllerAdapterCapability(id: "provider-update", title: capabilityTitle(for: "provider-update"), status: gated(.updateProvider, capabilityStatus(for: .providers)), evidence: localized("capability.evidence_mihomo_provider_update")),
                ControllerAdapterCapability(id: "rules-providers", title: capabilityTitle(for: "rules-providers"), status: aggregateStatus([capabilityStatus(for: .rules), capabilityStatus(for: .providers)]), evidence: localized("capability.evidence_mihomo_enhanced_optional")),
                ControllerAdapterCapability(id: "traffic-logs", title: capabilityTitle(for: "traffic-logs"), status: capabilities.traffic ? capabilityStatus(for: optionalStreamReadinessState) : .unavailable, evidence: optionalStreamReadinessDetail),
            ]
        case .surgeCompatible:
            return SurgeHTTPAPIAdapter.capabilities(
                snapshot: surgeSnapshot,
                health: controllerHealth,
                platform: selectedRouter?.surgePlatform ?? .remoteMac,
                language: presentationLanguage
            )
        case .singBoxCompatible:
            let capabilities = ControllerCapabilities.singBoxCompatible
            let versionStatus = capabilities.snapshot ? capabilityStatus(for: .version) : .unavailable
            let policyStatus = capabilities.policyGroups ? capabilityStatus(for: .proxies) : .unavailable
            let modeStatus = capabilities.supports(.changeMode) ? capabilityStatus(for: .configs) : .unavailable
            let connectionStatus = capabilities.connections ? capabilityStatus(for: .connections) : .unavailable
            let latencyStatus = capabilities.supports(.testLatency) ? policyStatus : .unavailable
            let closeConnectionStatus = capabilities.supports(.closeConnection) ? connectionStatus : .unavailable
            let closeAllStatus = capabilities.supports(.closeAllConnections) ? connectionStatus : .unavailable
            let liveStatus = capabilities.traffic ? singBoxLiveCapabilityStatus : .unavailable
            let snapshotStatus = aggregateStatus([
                versionStatus,
                singBoxRuntimeCapabilityStatus,
                policyStatus,
                modeStatus,
            ])

            return SingBoxStartedServiceAdapter.capabilities(
                versionStatus: versionStatus,
                snapshotStatus: snapshotStatus,
                policyStatus: policyStatus,
                latencyStatus: latencyStatus,
                modeStatus: modeStatus,
                closeConnectionStatus: closeConnectionStatus,
                closeAllStatus: closeAllStatus,
                liveStatus: liveStatus,
                language: presentationLanguage
            )
        case .stashCmfaCompatible:
            return ControllerAdapterCapability.defaultRows(status: .unavailable, evidence: localized("capability.evidence_stash_cmfa_unavailable"), language: presentationLanguage)
        case .autoDetect, .unknown:
            return ControllerAdapterCapability.defaultRows(status: .untested, evidence: localized("capability.evidence_detect_controller"), language: presentationLanguage)
        case .unsupported:
            return ControllerAdapterCapability.defaultRows(status: .unavailable, evidence: localized("capability.evidence_unsupported_target"), language: presentationLanguage)
        }
    }

    private func aggregateStatus(_ statuses: [CapabilityStatus]) -> CapabilityStatus {
        if statuses.contains(.failed) {
            return .failed
        }

        if statuses.allSatisfy({ $0 == .supported }) {
            return .supported
        }

        if statuses.contains(.supported) || statuses.contains(.partial) {
            return .partial
        }

        if statuses.contains(.unavailable) {
            return .unavailable
        }

        return .untested
    }

    private func controllerAdapterNextSafeAction(
        kind: ControllerKind,
        confidence: ControllerAdapterConfidence
    ) -> String {
        switch kind {
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible, .cmfaCompatible, .stashCompatible:
            return confidence == .configured || confidence == .detected ? localized("action.refresh") : localized("matrix.retry_test")
        case .surgeCompatible:
            return confidence == .configured || confidence == .detected ? localized("adapter.next_refresh_surge") : localized("matrix.retry_test")
        case .singBoxCompatible:
            return confidence == .configured || confidence == .detected ? localized("action.refresh") : localized("matrix.retry_test")
        case .stashCmfaCompatible:
            return localized("adapter.next_view_capability_matrix")
        case .autoDetect, .unknown:
            return localized("action.test")
        case .unsupported:
            return localized("matrix.edit_controller")
        }
    }

    func controllerSupports(
        _ unifiedAction: UnifiedControllerAction,
        router: RouterProfile,
        action: String
    ) -> Bool {
        let controllerType = effectiveUnifiedControllerType(for: router)
        let capabilities = effectiveUnifiedCapabilities(for: router)

        guard capabilities.supports(unifiedAction) else {
            operationState = controllerType == .unsupported ? .error(
                unsupportedOperationMessage(for: unifiedAction, controllerType: controllerType),
                action: action,
                target: router.displayName,
                nextStep: unsupportedOperationNextStep(for: controllerType)
            ) : .partial(
                unsupportedOperationMessage(for: unifiedAction, controllerType: controllerType),
                action: action,
                target: router.displayName,
                nextStep: unsupportedOperationNextStep(for: controllerType)
            )
            return false
        }

        return true
    }

    func effectiveUnifiedCapabilities(for router: RouterProfile) -> ControllerCapabilities {
        if selectedRouterID == router.id, unifiedSnapshot.checkedAt != nil {
            return unifiedSnapshot.capabilities
        }

        if selectedRouterID == router.id {
            if let activeSessionControllerKind {
                return unifiedCapabilities(for: activeSessionControllerKind)
            }
            return unifiedCapabilities(for: selectedControllerAdapter.detectedKind)
        }

        return unifiedCapabilities(for: router.controllerKind)
    }

    func effectiveUnifiedControllerType(for router: RouterProfile) -> UnifiedControllerType {
        if selectedRouterID == router.id, unifiedSnapshot.checkedAt != nil {
            return unifiedSnapshot.controllerType
        }

        if selectedRouterID == router.id {
            if let activeSessionControllerKind {
                return unifiedControllerType(for: activeSessionControllerKind, fallback: router.unifiedControllerType)
            }
            return unifiedControllerType(for: selectedControllerAdapter.detectedKind, fallback: router.unifiedControllerType)
        }

        return router.unifiedControllerType
    }

    func unifiedCapabilities(for kind: ControllerKind) -> ControllerCapabilities {
        switch kind {
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible:
            return .mihomoCompatible
        case .cmfaCompatible:
            return .cmfaCompatible
        case .stashCompatible:
            return .stashCompatible
        case .surgeCompatible:
            return .surgeHTTPAPI
        case .singBoxCompatible:
            return .singBoxCompatible
        case .stashCmfaCompatible:
            return .none
        case .autoDetect, .unknown:
            return .probeReadiness
        case .unsupported:
            return .none
        }
    }

    func unifiedControllerType(
        for kind: ControllerKind,
        fallback: UnifiedControllerType
    ) -> UnifiedControllerType {
        switch kind {
        case .mihomoCompatible:
            return .mihomoCompatible
        case .nikkiMihomoCompatible:
            return .nikkiMihomoCompatible
        case .openClashMihomoCompatible:
            return .openClashMihomoCompatible
        case .surgeCompatible:
            return .surgeHTTPAPI
        case .singBoxCompatible:
            return .singBoxCompatible
        case .cmfaCompatible:
            return .cmfaCompatible
        case .stashCompatible:
            return .stashCompatible
        case .stashCmfaCompatible:
            return .stashCmfaCompatible
        case .autoDetect:
            return fallback == .unknown ? .smartProbe : fallback
        case .unknown:
            return .unknown
        case .unsupported:
            return .unsupported
        }
    }

    private func unsupportedOperationMessage(
        for action: UnifiedControllerAction,
        controllerType: UnifiedControllerType
    ) -> String {
        switch controllerType {
        case .mihomoCompatible:
            return localized("capability.unsupported_mihomo \(action.micaLabel(language: presentationLanguage))")
        case .surgeHTTPAPI:
            return localized("capability.unsupported_surge \(action.micaLabel(language: presentationLanguage))")
        case .openClashMihomoCompatible:
            return localized("capability.unsupported_openclash \(action.micaLabel(language: presentationLanguage))")
        case .nikkiMihomoCompatible:
            return localized("capability.unsupported_nikki \(action.micaLabel(language: presentationLanguage))")
        case .singBoxCompatible:
            return "\(action.micaLabel(language: presentationLanguage)): \(localized("capability.impact_unavailable"))"
        case .cmfaCompatible, .stashCompatible:
            return localized("capability.unsupported_stash_cmfa \(action.micaLabel(language: presentationLanguage))")
        case .stashCmfaCompatible:
            return localized("capability.unsupported_stash_cmfa \(action.micaLabel(language: presentationLanguage))")
        case .smartProbe:
            return localized("capability.unsupported_smart \(action.micaLabel(language: presentationLanguage))")
        case .unknown:
            return localized("capability.unsupported_unknown \(action.micaLabel(language: presentationLanguage))")
        case .unsupported:
            return localized("capability.unsupported_profile \(action.micaLabel(language: presentationLanguage))")
        }
    }

    private func unsupportedOperationNextStep(for controllerType: UnifiedControllerType) -> String {
        switch controllerType {
        case .mihomoCompatible, .openClashMihomoCompatible, .nikkiMihomoCompatible, .cmfaCompatible, .stashCompatible, .smartProbe, .unknown:
            return localized("matrix.retry_test")
        case .surgeHTTPAPI:
            return localized("capability.next_open_surge_deck")
        case .singBoxCompatible, .stashCmfaCompatible:
            return localized("adapter.next_view_capability_matrix")
        case .unsupported:
            return localized("matrix.edit_controller")
        }
    }

    private func capabilityStatus(for streamState: ObservabilityReadinessState) -> CapabilityStatus {
        switch streamState {
        case .ready:
            return .supported
        case .partial:
            return .partial
        case .unavailable:
            return .unavailable
        case .notImplementedInUI, .controllerCapabilityUnknown, .futureOptionalStream:
            return .untested
        }
    }

    private func observabilityState(for status: CapabilityStatus) -> ObservabilityReadinessState {
        switch status {
        case .supported:
            return .ready
        case .partial:
            return .partial
        case .unavailable, .failed:
            return .unavailable
        case .untested:
            return .controllerCapabilityUnknown
        }
    }


}

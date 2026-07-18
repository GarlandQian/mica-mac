import MicaCore

extension ControllerScheme {
    var displayToken: String {
        switch self {
        case .http:
            "HTTP"
        case .https:
            "HTTPS"
        }
    }
}

extension RouterProfile {
    var visibleEndpointSummary: String {
        visibleEndpointSummary(language: MicaStrings.appLanguage)
    }

    func visibleEndpointSummary(language: AppLanguage) -> String {
        MicaStrings.localized("controller.visible_target_summary \(scheme.displayToken) \(endpointURL)", language: language)
    }

    var endpointURL: String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost: String
        if normalizedHost.isEmpty {
            displayHost = "-"
        } else if normalizedHost.hasPrefix("[") && normalizedHost.hasSuffix("]") {
            displayHost = normalizedHost
        } else if normalizedHost.contains(":") {
            displayHost = "[\(normalizedHost)]"
        } else {
            displayHost = normalizedHost
        }
        return "\(scheme.rawValue)://\(displayHost):\(port)"
    }
}

extension ControllerKind {
    var micaLabel: String {
        micaLabel(language: MicaStrings.appLanguage)
    }

    func micaLabel(language: AppLanguage) -> String {
        switch self {
        case .autoDetect:
            MicaStrings.localized("controller_kind.auto_detect", language: language)
        case .mihomoCompatible:
            MicaStrings.localized("controller_kind.mihomo", language: language)
        case .nikkiMihomoCompatible:
            MicaStrings.localized("controller_kind.nikki", language: language)
        case .openClashMihomoCompatible:
            MicaStrings.localized("controller_kind.openclash", language: language)
        case .surgeCompatible:
            MicaStrings.localized("controller_kind.surge", language: language)
        case .singBoxCompatible:
            MicaStrings.localized("controller_kind.sing_box", language: language)
        case .cmfaCompatible:
            MicaStrings.localized("controller_kind.cmfa", language: language)
        case .stashCompatible:
            MicaStrings.localized("controller_kind.stash", language: language)
        case .stashCmfaCompatible:
            MicaStrings.localized("controller_kind.stash_cmfa", language: language)
        case .unknown:
            MicaStrings.localized("controller_kind.unknown", language: language)
        case .unsupported:
            MicaStrings.localized("controller_kind.unsupported", language: language)
        }
    }

    var micaBadge: String {
        switch self {
        case .autoDetect:
            "AUTO"
        case .mihomoCompatible:
            "MHM"
        case .nikkiMihomoCompatible:
            "NIKKI"
        case .openClashMihomoCompatible:
            "OCL"
        case .surgeCompatible:
            "SURGE"
        case .singBoxCompatible:
            "SBOX"
        case .cmfaCompatible:
            "CMFA"
        case .stashCompatible:
            "STASH"
        case .stashCmfaCompatible:
            "CMFA"
        case .unknown:
            "UNK"
        case .unsupported:
            "NO"
        }
    }

    static var editableCases: [ControllerKind] {
        [.autoDetect, .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible, .surgeCompatible, .singBoxCompatible, .stashCmfaCompatible]
    }
}

extension SurgeControllerPlatform {
    var micaLabel: String {
        micaLabel(language: MicaStrings.appLanguage)
    }

    func micaLabel(language: AppLanguage) -> String {
        switch self {
        case .macLocal:
            MicaStrings.localized("surge_platform.mac_local", language: language)
        case .iosReachable:
            MicaStrings.localized("surge_platform.ios_reachable", language: language)
        case .remoteMac:
            MicaStrings.localized("surge_platform.remote_mac", language: language)
        }
    }
}

extension UnifiedControllerType {
    var micaLabel: String {
        micaLabel(language: MicaStrings.appLanguage)
    }

    func micaLabel(language: AppLanguage) -> String {
        switch self {
        case .mihomoCompatible:
            MicaStrings.localized("unified.label_mihomo", language: language)
        case .surgeHTTPAPI:
            MicaStrings.localized("unified.label_surge", language: language)
        case .openClashMihomoCompatible:
            MicaStrings.localized("unified.label_openclash", language: language)
        case .nikkiMihomoCompatible:
            MicaStrings.localized("unified.label_nikki", language: language)
        case .singBoxCompatible:
            MicaStrings.localized("unified.label_sing_box", language: language)
        case .cmfaCompatible:
            MicaStrings.localized("unified.label_cmfa", language: language)
        case .stashCompatible:
            MicaStrings.localized("unified.label_stash", language: language)
        case .stashCmfaCompatible:
            MicaStrings.localized("unified.label_stash_cmfa", language: language)
        case .smartProbe:
            MicaStrings.localized("unified.label_smart", language: language)
        case .unknown:
            MicaStrings.localized("unified.label_unknown", language: language)
        case .unsupported:
            MicaStrings.localized("unified.label_unsupported", language: language)
        }
    }

    var micaBoundarySummary: String {
        micaBoundarySummary(language: MicaStrings.appLanguage)
    }

    func micaBoundarySummary(language: AppLanguage) -> String {
        switch self {
        case .mihomoCompatible:
            MicaStrings.localized("unified.boundary_mihomo", language: language)
        case .surgeHTTPAPI:
            MicaStrings.localized("unified.boundary_surge", language: language)
        case .openClashMihomoCompatible:
            MicaStrings.localized("unified.boundary_openclash", language: language)
        case .nikkiMihomoCompatible:
            MicaStrings.localized("unified.boundary_nikki", language: language)
        case .singBoxCompatible:
            MicaStrings.localized("unified.boundary_sing_box", language: language)
        case .cmfaCompatible:
            MicaStrings.localized("unified.boundary_cmfa", language: language)
        case .stashCompatible:
            MicaStrings.localized("unified.boundary_stash", language: language)
        case .stashCmfaCompatible:
            MicaStrings.localized("unified.boundary_stash_cmfa", language: language)
        case .smartProbe:
            MicaStrings.localized("unified.boundary_smart", language: language)
        case .unknown:
            MicaStrings.localized("unified.boundary_unknown", language: language)
        case .unsupported:
            MicaStrings.localized("unified.boundary_unsupported", language: language)
        }
    }
}

extension UnifiedControllerAction {
    var micaLabel: String {
        micaLabel(language: MicaStrings.appLanguage)
    }

    func micaLabel(language: AppLanguage) -> String {
        switch self {
        case .testConnection:
            MicaStrings.localized("action.test", language: language)
        case .refreshSnapshot:
            MicaStrings.localized("action.refresh", language: language)
        case .reloadRules:
            MicaStrings.localized("action.reload_rules", language: language)
        case .setRuleDisabled:
            MicaStrings.localized("action.set_rule_state", language: language)
        case .reloadProviders:
            MicaStrings.localized("action.reload_providers", language: language)
        case .switchPolicy:
            MicaStrings.localized("action.switch_route", language: language)
        case .clearFixedSelection:
            MicaStrings.localized("action.clear_fixed_selection", language: language)
        case .testLatency:
            MicaStrings.localized("action.test_delay", language: language)
        case .changeMode:
            MicaStrings.localized("action.set_mode", language: language)
        case .closeConnection:
            MicaStrings.localized("action.close_connection", language: language)
        case .closeAllConnections:
            MicaStrings.localized("action.close_all", language: language)
        case .updateProvider:
            MicaStrings.localized("action.provider_update", language: language)
        case .healthCheckProvider:
            MicaStrings.localized("action.provider_health_check", language: language)
        case .reloadConfiguration:
            MicaStrings.localized("action.reload_configuration", language: language)
        case .updateGeoData:
            MicaStrings.localized("action.update_geo_data", language: language)
        case .dnsFlush:
            MicaStrings.localized("action.dns_flush", language: language)
        case .flushFakeIP:
            MicaStrings.localized("action.fakeip_flush", language: language)
        case .reloadProfile:
            MicaStrings.localized("action.surge_reload_profile", language: language)
        case .setLogLevel:
            MicaStrings.localized("action.set_log_level", language: language)
        case .setAllowLAN:
            MicaStrings.localized("action.set_allow_lan", language: language)
        case .setIPv6:
            MicaStrings.localized("action.set_ipv6", language: language)
        case .setTCPConcurrent:
            MicaStrings.localized("action.set_tcp_concurrent", language: language)
        case .setTUN:
            MicaStrings.localized("action.set_tun", language: language)
        case .setPort:
            MicaStrings.localized("action.set_port", language: language)
        case .setOutboundMode:
            MicaStrings.localized("action.surge_outbound", language: language)
        case .selectSurgePolicy:
            MicaStrings.localized("action.surge_policy_select", language: language)
        case .testSurgePolicy:
            MicaStrings.localized("action.surge_policy_test", language: language)
        case .killActiveRequest:
            MicaStrings.localized("action.surge_kill_request", language: language)
        case .copyDiagnostics:
            MicaStrings.localized("action.diagnostics_copy", language: language)
        }
    }
}

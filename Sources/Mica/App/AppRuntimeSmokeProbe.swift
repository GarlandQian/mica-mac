import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
enum AppRuntimeSmokeProbe {
    private enum OutputTarget {
        case standardOutput
        case file(String)
    }

    private struct Payload: Encodable {
        var probe: String
        var schemaVersion: Int
        var launchArguments: LaunchArguments
        var language: LanguageProbe
        var appearance: AppearanceProbe
        var fontScale: FontScaleProbe
        var localizedSamples: [String: String]
        var menuSamples: [String: String]
        var helpSamples: [String: String]
        var accessibilitySamples: [String: String]
        var workspaceSamples: [String: String]
        var surfaceSamples: [String: [String: String]]
        var preferenceTransitions: PreferenceTransitionProbe
        var privacy: PrivacyProbe
    }

    private struct LaunchArguments: Encodable {
        var language: String
        var appearance: String
        var fontScale: String
    }

    private struct LanguageProbe: Encodable {
        var rawValue: String
        var resolvedLanguageCode: String
        var localeIdentifier: String
        var followsSystem: Bool
    }

    private struct AppearanceProbe: Encodable {
        var rawValue: String
        var colorScheme: String
        var nsAppearanceName: String
        var appliedNSAppAppearanceName: String
        var effectiveSystemAppearance: String
        var followsSystem: Bool
    }

    private struct FontScaleProbe: Encodable {
        var rawValue: String
        var dynamicTypeSize: String
        var controlSize: String
        var multiplier: Double
    }

    private struct PrivacyProbe: Encodable {
        var activeUIFullControllerData: Bool
        var credentialsExcludedFromExports: Bool
        var rawResponseBodiesExcludedFromExports: Bool
        var aggregateOnly: Bool
        var networkAccess: Bool
        var realControllerData: Bool
        var controllerProfilesLoaded: Bool
        var coreLaunched: Bool
        var systemEnvironmentModified: Bool
    }

    private struct PreferenceTransitionProbe: Encodable {
        var languages: [String: LanguageTransitionProbe]
        var appearances: [String: AppearanceProbe]
        var fontScales: [String: FontScaleProbe]
    }

    private struct LanguageTransitionProbe: Encodable {
        var resolvedLanguageCode: String
        var localeIdentifier: String
        var localizedSamples: [String: String]
        var menuSamples: [String: String]
        var helpSamples: [String: String]
        var accessibilitySamples: [String: String]
        var workspaceSamples: [String: String]
        var surfaceSamples: [String: [String: String]]
    }

    static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) {
        guard let target = outputTarget(from: arguments) else {
            return
        }

        let snapshot = AppLaunchPreferences.resolvedSnapshot(from: arguments, defaults: defaults)
        let language = snapshot.language
        let appearance = snapshot.appearance
        let fontScale = snapshot.fontScale
        let languageCode = MicaStrings.resolvedLanguageCode(for: language)

        Bundle.setMicaLocalizationLanguage(languageCode)
        Bundle.enableModuleLocalization()
        appearance.applyToApplication()

        let languageProbe = LanguageProbe(
            rawValue: language.rawValue,
            resolvedLanguageCode: languageCode,
            localeIdentifier: language.resolvedLocale.identifier,
            followsSystem: language.usesSystemLocale
        )
        let appearanceProbe = appearanceProbe(for: appearance)
        let fontScaleProbe = fontScaleProbe(for: fontScale)
        let transitionProbe = preferenceTransitions(restoring: appearance)

        let payload = Payload(
            probe: "mica-runtime-smoke",
            schemaVersion: 1,
            launchArguments: LaunchArguments(
                language: language.rawValue,
                appearance: appearance.rawValue,
                fontScale: fontScale.rawValue
            ),
            language: languageProbe,
            appearance: appearanceProbe,
            fontScale: fontScaleProbe,
            localizedSamples: localizedSamples(language: language),
            menuSamples: menuSamples(language: language),
            helpSamples: helpSamples(language: language),
            accessibilitySamples: accessibilitySamples(language: language),
            workspaceSamples: workspaceSamples(language: language),
            surfaceSamples: surfaceSamples(language: language),
            preferenceTransitions: transitionProbe,
            privacy: PrivacyProbe(
                activeUIFullControllerData: true,
                credentialsExcludedFromExports: true,
                rawResponseBodiesExcludedFromExports: true,
                aggregateOnly: true,
                networkAccess: false,
                realControllerData: false,
                controllerProfilesLoaded: false,
                coreLaunched: false,
                systemEnvironmentModified: false
            )
        )

        do {
            try write(payload, to: target)
            Darwin.exit(0)
        } catch {
            writeFailure(error)
            Darwin.exit(2)
        }
    }

    private static func localizedSamples(language: AppLanguage) -> [String: String] {
        [
            "settings.language": localize("settings.language", language: language),
            "settings.language_simplified_chinese": localize("settings.language_simplified_chinese", language: language),
            "settings.appearance_system": localize("settings.appearance_system", language: language),
            "settings.font_scale_extra_large": localize("settings.font_scale_extra_large", language: language),
            "navigation.overview": localize("navigation.overview", language: language),
            "navigation.proxies": localize("navigation.proxies", language: language),
            "navigation.activity": localize("navigation.activity", language: language),
            "navigation.resources": localize("navigation.resources", language: language),
            "navigation.system": localize("navigation.system", language: language),
            "diagnostics.endpoint_checks": localize("diagnostics.endpoint_checks", language: language),
            "overview.current_data": localize("overview.current_data", language: language),
            "overview.traffic_summary": localize("overview.traffic_summary", language: language),
            "overview.endpoint_status": localize("overview.endpoint_status", language: language),
        ]
    }

    private static func menuSamples(language: AppLanguage) -> [String: String] {
        [
            "navigation.view_menu": localize("navigation.view_menu", language: language),
            "controller.command_menu": localize("controller.command_menu", language: language),
            "command.menu_new_controller": localize("command.menu_new_controller", language: language),
            "command.menu_test_connection": localize("command.menu_test_connection", language: language),
            "command.menu_refresh_data": localize("command.menu_refresh_data", language: language),
            "command.menu_copy_diagnostics_report": localize("command.menu_copy_diagnostics_report", language: language),
            "live.pause": localize("live.pause", language: language),
            "sidebar.edit": localize("sidebar.edit", language: language),
        ]
    }

    private static func helpSamples(language: AppLanguage) -> [String: String] {
        [
            "settings.help_language": localize("settings.help_language", language: language),
            "settings.help_appearance": localize("settings.help_appearance", language: language),
            "settings.help_font_scale": localize("settings.help_font_scale", language: language),
            "settings.help_global_group_visibility": localize("settings.help_global_group_visibility", language: language),
            "sidebar.help_create_profile": localize("sidebar.help_create_profile", language: language),
            "dashboard.help_test_controller": localize("dashboard.help_test_controller", language: language),
            "dashboard.help_refresh_controller": localize("dashboard.help_refresh_controller", language: language),
            "routing.help_inspector_test_delay": localize("routing.help_inspector_test_delay", language: language),
            "traffic.help_inspector_close_connection": localize("traffic.help_inspector_close_connection", language: language),
        ]
    }

    private static func accessibilitySamples(language: AppLanguage) -> [String: String] {
        [
            "settings.acc_language": localize("settings.acc_language", language: language),
            "settings.acc_appearance": localize("settings.acc_appearance", language: language),
            "settings.acc_font_scale": localize("settings.acc_font_scale", language: language),
            "sidebar.acc_add_router": localize("sidebar.acc_add_router", language: language),
            "routing.acc_mode_picker": localize("routing.acc_mode_picker", language: language),
            "action.test": localize("action.test", language: language),
            "action.refresh": localize("action.refresh", language: language),
        ]
    }

    private static func workspaceSamples(language: AppLanguage) -> [String: String] {
        var samples: [String: String] = [:]
        for area in WorkbenchDestination.allCases {
            samples[area.rawValue] = localize(area.titleKey, language: language)
        }
        return samples
    }

    private static func surfaceSamples(language: AppLanguage) -> [String: [String: String]] {
        [
            "settings": [
                "settings.language": localize("settings.language", language: language),
                "settings.appearance_system": localize("settings.appearance_system", language: language),
                "settings.font_scale_extra_large": localize("settings.font_scale_extra_large", language: language),
                "settings.controller_endpoint": localize("settings.controller_endpoint", language: language),
                "workbench.settings": localize("workbench.settings", language: language),
                "settings.security_console": localize("settings.security_console", language: language),
            ],
            "sidebar": [
                "sidebar.controllers": localize("sidebar.controllers", language: language),
                "sidebar.add_controller": localize("sidebar.add_controller", language: language),
                "navigation.overview": localize("navigation.overview", language: language),
                "navigation.proxies": localize("navigation.proxies", language: language),
                "sidebar.group_workbench": localize("sidebar.group_workbench", language: language),
                "sidebar.group_controller_management": localize("sidebar.group_controller_management", language: language),
            ],
            "toolbar": [
                "action.test": localize("action.test", language: language),
                "action.refresh": localize("action.refresh", language: language),
                "live.pause": localize("live.pause", language: language),
                "live.resume": localize("live.resume", language: language),
                "sidebar.edit": localize("sidebar.edit", language: language),
            ],
            "overview": [
                "workspace.overview": localize("workspace.overview", language: language),
                "overview.traffic_summary": localize("overview.traffic_summary", language: language),
                "overview.current_data": localize("overview.current_data", language: language),
                "overview.connection_activity": localize("overview.connection_activity", language: language),
                "overview.data_counts": localize("overview.data_counts", language: language),
                "overview.endpoint_status": localize("overview.endpoint_status", language: language),
                "overview.connecting_title": localize("overview.connecting_title", language: language),
            ],
            "controllers": [
                "sidebar.controllers": localize("sidebar.controllers", language: language),
                "controllers.controller": localize("controllers.controller", language: language),
                "dashboard.col_status": localize("dashboard.col_status", language: language),
                "controllers.actions": localize("controllers.actions", language: language),
                "controllers.use": localize("controllers.use", language: language),
                "controllers.search_prompt": localize("controllers.search_prompt", language: language),
            ],
            "policyGroups": [
                "dashboard.routing_modules_header": localize("dashboard.routing_modules_header", language: language),
                "routing.group_catalog": localize("routing.group_catalog", language: language),
                "routing.no_inspector": localize("routing.no_inspector", language: language),
                "routing.test_group": localize("routing.test_group", language: language),
                "routing.filter_nodes": localize("routing.filter_nodes", language: language),
                "routing.members_filtered_empty": localize("routing.members_filtered_empty", language: language),
                "routing.load_more_members": localize("routing.load_more_members", language: language),
            ],
            "connections": [
                "dashboard.tab_connections": localize("dashboard.tab_connections", language: language),
                "traffic.connection_host": localize("traffic.connection_host", language: language),
                "dashboard.col_id": localize("dashboard.col_id", language: language),
                "traffic.connection_process": localize("traffic.connection_process", language: language),
                "traffic.connection_process_path": localize("traffic.connection_process_path", language: language),
                "traffic.inbound_address": localize("traffic.inbound_address", language: language),
                "traffic.connection_uid": localize("traffic.connection_uid", language: language),
                "dashboard.col_chain": localize("dashboard.col_chain", language: language),
                "traffic.detail_connection": localize("traffic.detail_connection", language: language),
                "dashboard.no_matching_connections": localize("dashboard.no_matching_connections", language: language),
            ],
            "rules": [
                "dashboard.tab_rules": localize("dashboard.tab_rules", language: language),
                "dashboard.col_payload": localize("dashboard.col_payload", language: language),
                "dashboard.col_type": localize("dashboard.col_type", language: language),
                "dashboard.col_proxy": localize("dashboard.col_proxy", language: language),
                "traffic.detail_rule": localize("traffic.detail_rule", language: language),
            ],
            "sources": [
                "dashboard.tab_providers": localize("dashboard.tab_providers", language: language),
                "traffic.provider_kind": localize("traffic.provider_kind", language: language),
                "dashboard.col_vehicle": localize("dashboard.col_vehicle", language: language),
                "traffic.provider_behavior": localize("traffic.provider_behavior", language: language),
                "traffic.updated_at": localize("traffic.updated_at", language: language),
                "dashboard.no_matching_sources": localize("dashboard.no_matching_sources", language: language),
                "traffic.sources_empty_message": localize("traffic.sources_empty_message", language: language),
            ],
            "logs": [
                "dashboard.tab_logs": localize("dashboard.tab_logs", language: language),
                "traffic.log_level": localize("traffic.log_level", language: language),
                "traffic.log_time": localize("traffic.log_time", language: language),
                "traffic.log_payload": localize("traffic.log_payload", language: language),
                "live.pause_updates": localize("live.pause_updates", language: language),
                "traffic.follow_bottom": localize("traffic.follow_bottom", language: language),
                "traffic.jump_to_newest": localize("traffic.jump_to_newest", language: language),
                "traffic.clear_logs": localize("traffic.clear_logs", language: language),
                "dashboard.no_logs_yet": localize("dashboard.no_logs_yet", language: language),
                "dashboard.no_logs_yet_message": localize("dashboard.no_logs_yet_message", language: language),
                "dashboard.no_matching_logs": localize("dashboard.no_matching_logs", language: language),
                "traffic.empty_filtered": localize("traffic.empty_filtered", language: language),
            ],
            "coreConfig": [
                "workbench.configuration": localize("workbench.configuration", language: language),
                "dashboard.mode": localize("dashboard.mode", language: language),
                "overview.config_log_level": localize("overview.config_log_level", language: language),
                "overview.config_tun": localize("overview.config_tun", language: language),
                "overview.config_mixed_port": localize("overview.config_mixed_port", language: language),
            ],
            "coreActions": [
                "workbench.actions": localize("workbench.actions", language: language),
                "diagnostics.operation_dns_flush": localize("diagnostics.operation_dns_flush", language: language),
                "diagnostics.operation_cache_flush": localize("diagnostics.operation_cache_flush", language: language),
                "diagnostics.operation_core_restart": localize("diagnostics.operation_core_restart", language: language),
                "diagnostics.operation_core_upgrade": localize("diagnostics.operation_core_upgrade", language: language),
            ],
            "diagnostics": [
                "workspace.diagnostics": localize("workspace.diagnostics", language: language),
                "diagnostics.endpoint_checks": localize("diagnostics.endpoint_checks", language: language),
                "diagnostics.report_scope": localize("diagnostics.report_scope", language: language),
                "diagnostics.coverage_summary": localize("diagnostics.coverage_summary", language: language),
                "diagnostics.runtime_operations": localize("diagnostics.runtime_operations", language: language),
                "command.show_data_availability": localize("command.show_data_availability", language: language),
            ],
        ]
    }

    private static func localize(_ key: String, language: AppLanguage) -> String {
        MicaStrings.localizedKey(key, language: language)
    }

    private static func preferenceTransitions(restoring appearance: AppAppearance) -> PreferenceTransitionProbe {
        let languages = [AppLanguage.english, .simplifiedChinese].reduce(into: [String: LanguageTransitionProbe]()) { result, language in
            let languageCode = MicaStrings.resolvedLanguageCode(for: language)
            Bundle.setMicaLocalizationLanguage(languageCode)
            result[language.rawValue] = LanguageTransitionProbe(
                resolvedLanguageCode: languageCode,
                localeIdentifier: language.resolvedLocale.identifier,
                localizedSamples: localizedSamples(language: language),
                menuSamples: menuSamples(language: language),
                helpSamples: helpSamples(language: language),
                accessibilitySamples: accessibilitySamples(language: language),
                workspaceSamples: workspaceSamples(language: language),
                surfaceSamples: surfaceSamples(language: language)
            )
        }

        let appearances = AppAppearance.allCases.reduce(into: [String: AppearanceProbe]()) { result, candidate in
            candidate.applyToApplication()
            result[candidate.rawValue] = appearanceProbe(for: candidate)
        }

        appearance.applyToApplication()

        let fontScales = AppFontScale.allCases.reduce(into: [String: FontScaleProbe]()) { result, candidate in
            result[candidate.rawValue] = fontScaleProbe(for: candidate)
        }

        return PreferenceTransitionProbe(
            languages: languages,
            appearances: appearances,
            fontScales: fontScales
        )
    }

    private static func appearanceProbe(for appearance: AppAppearance) -> AppearanceProbe {
        AppearanceProbe(
            rawValue: appearance.rawValue,
            colorScheme: colorSchemeName(appearance.colorScheme),
            nsAppearanceName: nsAppearanceName(appearance.nsAppearance),
            appliedNSAppAppearanceName: nsAppearanceName(NSApplication.shared.appearance),
            effectiveSystemAppearance: effectiveSystemAppearanceName(),
            followsSystem: appearance == .system
        )
    }

    private static func fontScaleProbe(for fontScale: AppFontScale) -> FontScaleProbe {
        FontScaleProbe(
            rawValue: fontScale.rawValue,
            dynamicTypeSize: String(describing: fontScale.dynamicTypeSize),
            controlSize: String(describing: fontScale.controlSize),
            multiplier: Double(fontScale.multiplier)
        )
    }

    private static func colorSchemeName(_ colorScheme: ColorScheme?) -> String {
        switch colorScheme {
        case .dark:
            "dark"
        case .light:
            "light"
        case nil:
            "system"
        @unknown default:
            "unknown"
        }
    }

    private static func nsAppearanceName(_ appearance: NSAppearance?) -> String {
        appearance?.name.rawValue ?? "system"
    }

    private static func effectiveSystemAppearanceName() -> String {
        let appearance = NSApplication.shared.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }

    private static func outputTarget(from arguments: [String]) -> OutputTarget? {
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            guard argument.hasPrefix("-") else {
                index = arguments.index(after: index)
                continue
            }

            let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let key: String
            let value: String?

            if let separator = trimmed.firstIndex(of: "=") {
                key = String(trimmed[..<separator])
                value = String(trimmed[trimmed.index(after: separator)...])
                index = arguments.index(after: index)
            } else {
                key = trimmed
                let nextIndex = arguments.index(after: index)
                if nextIndex < arguments.endIndex, !arguments[nextIndex].hasPrefix("-") {
                    value = arguments[nextIndex]
                    index = arguments.index(after: nextIndex)
                } else {
                    value = nil
                    index = nextIndex
                }
            }

            switch key {
            case "micaRuntimeSmokeStdout":
                return .standardOutput
            case "micaRuntimeSmokeProbe":
                if let value,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .file(value)
                }
            default:
                continue
            }
        }

        return nil
    }

    private static func write(_ payload: Payload, to target: OutputTarget) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        switch target {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        case .file(let path):
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private static func writeFailure(_ error: Error) {
        let message = "mica-runtime-smoke failed: \(error.localizedDescription)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}

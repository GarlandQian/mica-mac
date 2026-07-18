import Foundation
import MicaCore

struct RouterDraft: Identifiable, Equatable {
    var id: RouterProfile.ID
    var displayName: String
    var controllerKind: ControllerKind
    var surgePlatform: SurgeControllerPlatform
    var scheme: ControllerScheme
    var host: String
    var portText: String
    var secret: String
    var hasStoredSecret: Bool
    var tlsPolicy: TLSValidationPolicy

    init(
        id: RouterProfile.ID = UUID(),
        displayName: String = MicaStrings.localized("editor.default_controller_name"),
        controllerKind: ControllerKind = .autoDetect,
        surgePlatform: SurgeControllerPlatform = .remoteMac,
        scheme: ControllerScheme = .http,
        host: String = "",
        portText: String = "9090",
        secret: String = "",
        hasStoredSecret: Bool = false,
        tlsPolicy: TLSValidationPolicy = .system
    ) {
        self.id = id
        self.displayName = displayName
        self.controllerKind = controllerKind
        self.surgePlatform = surgePlatform
        self.scheme = scheme
        self.host = host
        self.portText = portText
        self.secret = secret
        self.hasStoredSecret = hasStoredSecret
        self.tlsPolicy = tlsPolicy
    }

    init(profile: RouterProfile, secret: String, hasStoredSecret: Bool = false) {
        self.init(
            id: profile.id,
            displayName: profile.displayName,
            controllerKind: profile.controllerKind,
            surgePlatform: profile.surgePlatform,
            scheme: profile.scheme,
            host: profile.host,
            portText: "\(profile.port)",
            secret: secret,
            hasStoredSecret: hasStoredSecret,
            tlsPolicy: profile.tlsPolicy
        )
    }

    var shouldSaveSecret: Bool {
        !secret.isEmpty
    }

    var controllerURLLabel: String {
        let displayHost: String
        if normalizedHost.isEmpty {
            displayHost = "-"
        } else if normalizedHost.contains(":") {
            displayHost = "[\(normalizedHost)]"
        } else {
            displayHost = normalizedHost
        }
        return "\(scheme.rawValue)://\(displayHost):\(normalizedPortText)"
    }

    var visibleControllerTargetLabel: String {
        visibleControllerTargetLabel(language: MicaStrings.appLanguage)
    }

    func visibleControllerTargetLabel(language: AppLanguage) -> String {
        guard !normalizedHost.isEmpty else {
            return MicaStrings.localized("editor.target_not_configured", language: language)
        }
        return MicaStrings.localized("controller.visible_target_summary \(scheme.displayToken) \(controllerURLLabel)", language: language)
    }

    var tlsCheckLabel: String {
        tlsCheckLabel(language: MicaStrings.appLanguage)
    }

    func tlsCheckLabel(language: AppLanguage) -> String {
        tlsPolicy == .allowSelfSigned
            ? MicaStrings.localized("editor.tls_self_signed_short", language: language)
            : MicaStrings.localized("editor.tls_system_short", language: language)
    }

    var secretCheckLabel: String {
        secretCheckLabel(language: MicaStrings.appLanguage)
    }

    func secretCheckLabel(language: AppLanguage) -> String {
        shouldSaveSecret || hasStoredSecret
            ? MicaStrings.localized("editor.secret_configured", language: language)
            : MicaStrings.localized("editor.secret_empty", language: language)
    }

    var secretCheckState: ConnectionCheckState {
        shouldSaveSecret || hasStoredSecret ? .ready : .warning
    }

    var validationError: String? {
        validationError(language: MicaStrings.appLanguage)
    }

    func validationError(language: AppLanguage) -> String? {
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MicaStrings.localized("editor.validation_name_required", language: language)
        }

        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MicaStrings.localized("editor.validation_host_required", language: language)
        }

        guard let port = Int(normalizedPortText), (1...65_535).contains(port) else {
            return MicaStrings.localized("editor.validation_port_range", language: language)
        }

        let hostValue = normalizedHost
        if hostValue.contains("://") {
            return MicaStrings.localized("editor.validation_host_scheme", language: language)
        }

        if hostValue.contains("/") {
            return MicaStrings.localized("editor.validation_host_path", language: language)
        }

        if hostValue.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return MicaStrings.localized("editor.validation_host_spaces", language: language)
        }

        return nil
    }

    var profile: RouterProfile {
        RouterProfile(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            scheme: scheme,
            host: normalizedHost,
            port: Int(normalizedPortText) ?? 9090,
            secretReference: hasStoredSecret || shouldSaveSecret ? "keychain:\(id.uuidString)" : nil,
            tlsPolicy: tlsPolicy,
            controllerKind: controllerKind,
            surgePlatform: surgePlatform
        )
    }

    private var normalizedHost: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            return String(trimmed.dropFirst().dropLast())
        }

        return trimmed
    }

    private var normalizedPortText: String {
        portText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

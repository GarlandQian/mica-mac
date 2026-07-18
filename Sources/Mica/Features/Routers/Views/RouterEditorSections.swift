import MicaCore
import SwiftUI

extension RouterEditorView {
    @ViewBuilder
    var controllerFormContent: some View {
        Section {
            Picker(MicaStrings.localizedKey("editor.controller_family", language: appLanguage), selection: $draft.controllerKind) {
                ForEach(ControllerKind.editableCases, id: \.self) { kind in
                    Text(kind.micaLabel(language: appLanguage)).tag(kind)
                }
            }
            .help(MicaStrings.localizedKey("editor.help_controller_family", language: appLanguage))
            .accessibilityLabel(MicaStrings.localizedKey("editor.acc_controller_family", language: appLanguage))

            if draft.controllerKind == .surgeCompatible {
                Picker(MicaStrings.localizedKey("editor.surge_platform", language: appLanguage), selection: $draft.surgePlatform) {
                    ForEach(SurgeControllerPlatform.allCases, id: \.self) { platform in
                        Text(platform.micaLabel(language: appLanguage)).tag(platform)
                    }
                }
                .help(MicaStrings.localizedKey("editor.help_surge_platform", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("editor.acc_surge_platform", language: appLanguage))
            }
        } header: {
            MicaText("editor.controller_family_section")
        } footer: {
            MicaText("editor.controller_family_footer")
        }

        Section {
            TextField(MicaStrings.localizedKey("editor.name", language: appLanguage), text: $draft.displayName)
                .help(MicaStrings.localizedKey("editor.help_name", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("editor.acc_name", language: appLanguage))

            Picker(MicaStrings.localizedKey("editor.scheme", language: appLanguage), selection: $draft.scheme) {
                ForEach(ControllerScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayToken).tag(scheme)
                }
            }
            .help(MicaStrings.localizedKey("editor.help_scheme", language: appLanguage))
            .accessibilityLabel(MicaStrings.localizedKey("editor.acc_scheme", language: appLanguage))

            TextField(
                MicaStrings.localizedKey("editor.host", language: appLanguage),
                text: $draft.host,
                prompt: Text(MicaStrings.localizedKey("editor.host_prompt", language: appLanguage))
            )
            .textContentType(.URL)
            .help(MicaStrings.localizedKey("editor.help_host", language: appLanguage))
            .accessibilityLabel(MicaStrings.localizedKey("editor.acc_host", language: appLanguage))

            TextField(MicaStrings.localizedKey("editor.port", language: appLanguage), text: $draft.portText)
                .help(MicaStrings.localizedKey("editor.help_port", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("editor.acc_port", language: appLanguage))

            LabeledContent(MicaStrings.localizedKey("editor.summary_target", language: appLanguage)) {
                Text(verbatim: localizedVisibleControllerTargetLabel)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        } header: {
            MicaText("editor.device_link")
        }

        Section {
            if draft.hasStoredSecret {
                MicaLabel("editor.keychain_notice", systemImage: "key")
                    .foregroundStyle(.secondary)
            }

            SecureField(
                draft.hasStoredSecret
                    ? MicaStrings.localized("editor.replace_secret", language: appLanguage)
                    : MicaStrings.localized("editor.controller_secret", language: appLanguage),
                text: $draft.secret
            )
            .help(MicaStrings.localizedKey("editor.help_secret", language: appLanguage))
            .accessibilityLabel(MicaStrings.localizedKey("editor.acc_secret", language: appLanguage))

            Picker(MicaStrings.localizedKey("editor.tls", language: appLanguage), selection: $draft.tlsPolicy) {
                MicaText("editor.tls_system_trust").tag(TLSValidationPolicy.system)
                MicaText("editor.tls_self_signed").tag(TLSValidationPolicy.allowSelfSigned)
            }
            .help(MicaStrings.localizedKey("editor.help_tls", language: appLanguage))
            .accessibilityLabel(MicaStrings.localizedKey("editor.acc_tls", language: appLanguage))
        } header: {
            MicaText("editor.security_gate")
        }

        if showsValidation, let validationError {
            Section {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(MicaStyle.signalRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

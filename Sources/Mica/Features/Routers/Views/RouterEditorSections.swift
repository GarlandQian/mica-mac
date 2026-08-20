import MicaCore
import SwiftUI

extension RouterEditorView {
    @ViewBuilder
    var controllerFormContent: some View {
        Section {
            WorkbenchFormRow("editor.name") {
                TextField("", text: $draft.displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: MicaTheme.Metrics.formControlMax, alignment: .leading)
                    .help(MicaStrings.localizedKey("editor.help_name", language: appLanguage))
                    .accessibilityLabel(
                        MicaStrings.localizedKey("editor.acc_name", language: appLanguage)
                    )
            }

            WorkbenchFormRow("editor.controller_family") {
                Picker(
                    MicaStrings.localizedKey(
                        "editor.controller_family",
                        language: appLanguage
                    ),
                    selection: $draft.controllerKind
                ) {
                    ForEach(ControllerKind.editableCases, id: \.self) { kind in
                        Text(kind.micaLabel(language: appLanguage)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .help(
                    MicaStrings.localizedKey(
                        "editor.help_controller_family",
                        language: appLanguage
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "editor.acc_controller_family",
                        language: appLanguage
                    )
                )
            }

            if draft.controllerKind == .surgeCompatible {
                WorkbenchFormRow("editor.surge_platform") {
                    Picker(
                        MicaStrings.localizedKey(
                            "editor.surge_platform",
                            language: appLanguage
                        ),
                        selection: $draft.surgePlatform
                    ) {
                        ForEach(SurgeControllerPlatform.allCases, id: \.self) { platform in
                            Text(platform.micaLabel(language: appLanguage)).tag(platform)
                        }
                    }
                    .pickerStyle(.menu)
                    .help(
                        MicaStrings.localizedKey(
                            "editor.help_surge_platform",
                            language: appLanguage
                        )
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey(
                            "editor.acc_surge_platform",
                            language: appLanguage
                        )
                    )
                }
            }

        } header: {
            RouterEditorSectionHeader(
                titleKey: "editor.controller_family_section",
                systemImage: draft.controllerKind.editorSymbol
            )
        } footer: {
            Text(
                MicaStrings.localizedKey(
                    "editor.controller_family_footer",
                    language: appLanguage
                )
            )
        }

        Section {
            WorkbenchFormRow("editor.scheme") {
                Picker(
                    MicaStrings.localizedKey("editor.scheme", language: appLanguage),
                    selection: $draft.scheme
                ) {
                    ForEach(ControllerScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayToken).tag(scheme)
                    }
                }
                .pickerStyle(.menu)
                .help(MicaStrings.localizedKey("editor.help_scheme", language: appLanguage))
                .accessibilityLabel(
                    MicaStrings.localizedKey("editor.acc_scheme", language: appLanguage)
                )
            }

            WorkbenchFormRow("editor.host") {
                TextField(
                    "",
                    text: $draft.host,
                    prompt: Text(
                        MicaStrings.localizedKey(
                            "editor.host_prompt",
                            language: appLanguage
                        )
                    )
                )
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .frame(maxWidth: MicaTheme.Metrics.formControlMax, alignment: .leading)
                .help(MicaStrings.localizedKey("editor.help_host", language: appLanguage))
                .accessibilityLabel(
                    MicaStrings.localizedKey("editor.acc_host", language: appLanguage)
                )
            }

            WorkbenchFormRow("editor.port") {
                TextField("", text: $draft.portText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .help(MicaStrings.localizedKey("editor.help_port", language: appLanguage))
                .accessibilityLabel(
                    MicaStrings.localizedKey("editor.acc_port", language: appLanguage)
                )
            }
        } header: {
            RouterEditorSectionHeader(
                titleKey: "editor.device_link",
                systemImage: "link"
            )
        }

        Section {
            WorkbenchFormRow(
                draft.hasStoredSecret
                    ? "editor.replace_secret"
                    : "editor.controller_secret"
            ) {
                SecureField("", text: $draft.secret)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: MicaTheme.Metrics.formControlMax, alignment: .leading)
                .help(MicaStrings.localizedKey("editor.help_secret", language: appLanguage))
                .accessibilityLabel(
                    MicaStrings.localizedKey("editor.acc_secret", language: appLanguage)
                )
            }

            WorkbenchFormRow("editor.tls") {
                Picker(
                    MicaStrings.localizedKey("editor.tls", language: appLanguage),
                    selection: $draft.tlsPolicy
                ) {
                    MicaText("editor.tls_system_trust").tag(TLSValidationPolicy.system)
                    MicaText("editor.tls_self_signed")
                        .tag(TLSValidationPolicy.allowSelfSigned)
                }
                .pickerStyle(.menu)
                .help(MicaStrings.localizedKey("editor.help_tls", language: appLanguage))
                .accessibilityLabel(
                    MicaStrings.localizedKey("editor.acc_tls", language: appLanguage)
                )
            }
        } header: {
            RouterEditorSectionHeader(
                titleKey: "editor.security_gate",
                systemImage: "lock.shield"
            )
        } footer: {
            if draft.hasStoredSecret {
                Label(
                    MicaStrings.localizedKey(
                        "editor.keychain_notice",
                        language: appLanguage
                    ),
                    systemImage: "key.fill"
                )
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
            }
        }

        if showsValidation, let validationError {
            Section {
                WorkbenchManagementInlineState(
                    systemImage: "exclamationmark.triangle.fill",
                    title: validationError,
                    tint: MicaTheme.statusError
                )
            }
            .listRowBackground(Color.clear)
        }
    }

}

struct RouterEditorSectionHeader: View {
    @Environment(\.micaAppLanguage) private var appLanguage

    let titleKey: String
    let systemImage: String

    var body: some View {
        Label(
            MicaStrings.localizedKey(titleKey, language: appLanguage),
            systemImage: systemImage
        )
    }
}

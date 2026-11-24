import MicaCore
import SwiftUI

extension RouterEditorView {
    @ViewBuilder
    var controllerFormContent: some View {
        Section {
            WorkbenchFormRow("editor.name") {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    TextField("", text: $draft.displayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: MicaTheme.Metrics.formControlMax, alignment: .leading)
                        .help(MicaStrings.localizedKey("editor.help_name", language: appLanguage))
                        .accessibilityLabel(
                            MicaStrings.localizedKey("editor.acc_name", language: appLanguage)
                        )

                    if showsValidation, let nameError = draft.nameValidationError(language: appLanguage) {
                        Label(nameError, systemImage: "exclamationmark.triangle.fill")
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.statusError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            WorkbenchFormRow("editor.controller_family") {
                Picker(
                    MicaStrings.localizedKey(
                        "editor.controller_family",
                        language: appLanguage
                    ),
                    selection: $draft.controllerKind
                ) {
                    ForEach(controllerKindOptions, id: \.self) { kind in
                        Label(kind.micaLabel(language: appLanguage), systemImage: kind.editorSymbol)
                            .tag(kind)
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
            // Scheme, host, and port read as the one URL they build, with the
            // resulting endpoint echoed below as it is typed.
            WorkbenchFormRow("editor.address") {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    HStack(spacing: MicaTheme.Spacing.space1) {
                        Picker(
                            MicaStrings.localizedKey("editor.scheme", language: appLanguage),
                            selection: $draft.scheme
                        ) {
                            ForEach(ControllerScheme.allCases, id: \.self) { scheme in
                                Text(scheme.displayToken).tag(scheme)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        .help(MicaStrings.localizedKey("editor.help_scheme", language: appLanguage))
                        .accessibilityLabel(
                            MicaStrings.localizedKey("editor.acc_scheme", language: appLanguage)
                        )

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
                        .frame(minWidth: 140, maxWidth: MicaTheme.Metrics.formControlMax)
                        .help(MicaStrings.localizedKey("editor.help_host", language: appLanguage))
                        .accessibilityLabel(
                            MicaStrings.localizedKey("editor.acc_host", language: appLanguage)
                        )

                        Text(verbatim: ":")
                            .micaThemeFont(.dataLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        TextField(
                            "",
                            text: $draft.portText,
                            prompt: Text(verbatim: MicaStrings.localizedKey("editor.port", language: appLanguage))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 76, maxWidth: 100)
                        .help(MicaStrings.localizedKey("editor.help_port", language: appLanguage))
                        .accessibilityLabel(
                            MicaStrings.localizedKey("editor.acc_port", language: appLanguage)
                        )
                    }

                    if !draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label {
                            Text(verbatim: draft.controllerURLLabel)
                                .micaThemeFont(.dataCaption)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "link")
                        }
                        .micaThemeFont(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }

                    if showsValidation {
                        if let hostError = draft.hostValidationError(language: appLanguage) {
                            Label(hostError, systemImage: "exclamationmark.triangle.fill")
                                .micaThemeFont(.caption)
                                .foregroundStyle(MicaTheme.statusError)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let portError = draft.portValidationError(language: appLanguage) {
                            Label(portError, systemImage: "exclamationmark.triangle.fill")
                                .micaThemeFont(.caption)
                                .foregroundStyle(MicaTheme.statusError)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
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
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    HStack(spacing: MicaTheme.Spacing.space2) {
                        SecureField("", text: $draft.secret)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: MicaTheme.Metrics.formControlMax, alignment: .leading)
                            .disabled(draft.clearStoredSecret)
                            .help(MicaStrings.localizedKey("editor.help_secret", language: appLanguage))
                            .accessibilityLabel(
                                MicaStrings.localizedKey("editor.acc_secret", language: appLanguage)
                            )

                        if draft.hasStoredSecret {
                            Button {
                                draft.clearStoredSecret.toggle()
                                if draft.clearStoredSecret {
                                    draft.secret = ""
                                }
                            } label: {
                                Text(
                                    MicaStrings.localizedKey(
                                        draft.clearStoredSecret ? "action.undo" : "editor.remove_secret",
                                        language: appLanguage
                                    )
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if draft.clearStoredSecret {
                        Label(
                            MicaStrings.localizedKey("editor.secret_will_be_removed", language: appLanguage),
                            systemImage: "trash"
                        )
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.statusWarning)
                    }
                }
            }

            WorkbenchFormRow("editor.tls") {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    Picker(
                        MicaStrings.localizedKey("editor.tls", language: appLanguage),
                        selection: $draft.tlsPolicy
                    ) {
                        MicaText("editor.tls_system_trust").tag(TLSValidationPolicy.system)
                        MicaText("editor.tls_self_signed")
                            .tag(TLSValidationPolicy.allowSelfSigned)
                    }
                    .pickerStyle(.menu)
                    .opacity(draft.scheme == .https ? 1 : 0.65)
                    .help(MicaStrings.localizedKey("editor.help_tls", language: appLanguage))
                    .accessibilityLabel(
                        MicaStrings.localizedKey("editor.acc_tls", language: appLanguage)
                    )

                    if draft.scheme == .http {
                        Text(MicaStrings.localizedKey("editor.tls_https_only_note", language: appLanguage))
                            .micaThemeFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            RouterEditorSectionHeader(
                titleKey: "editor.security_gate",
                systemImage: "lock.shield"
            )
        } footer: {
            if draft.hasStoredSecret && !draft.clearStoredSecret {
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
    }

    private var controllerKindOptions: [ControllerKind] {
        var options = ControllerKind.editableCases
        if !options.contains(draft.controllerKind) {
            options.append(draft.controllerKind)
        }
        return options
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

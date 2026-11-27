import MicaCore
import SwiftUI

struct ControllerEditorSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RouterDraft
    @State private var isTesting = false
    @State private var testReport: ConnectionTestReport?
    @State private var isSaving = false
    @State private var saveError: String?

    private let titleKey: String

    init(state: ControllerEditorSheetState) {
        self.titleKey = state.titleKey
        _draft = State(initialValue: state.draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: L(titleKey, language: language))
                    .font(.headline)
                Spacer()
                Button(L("action.cancel", language: language)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            }
            .padding(.horizontal, MicaTheme.Spacing.lg)
            .padding(.vertical, MicaTheme.Spacing.md)

            MicaHairlineDivider()

            Form {
                Section(L("controllers.controller", language: language)) {
                    TextField(L("editor.name", language: language), text: $draft.displayName)

                    Picker(L("editor.controller_type", language: language), selection: $draft.controllerKind) {
                        ForEach(ControllerKind.editableCases, id: \.self) { kind in
                            Text(verbatim: kind.micaLabel(language: language)).tag(kind)
                        }
                    }

                    if draft.controllerKind == .surgeCompatible {
                        Picker(L("editor.platform", language: language), selection: $draft.surgePlatform) {
                            ForEach(SurgeControllerPlatform.allCases, id: \.self) { platform in
                                Text(verbatim: platform.micaLabel(language: language)).tag(platform)
                            }
                        }
                    }
                }

                Section(L("settings.controller_endpoint", language: language)) {
                    Picker(L("editor.scheme", language: language), selection: $draft.scheme) {
                        ForEach(ControllerScheme.allCases, id: \.self) { scheme in
                            Text(verbatim: scheme.displayToken).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(L("editor.host", language: language), text: $draft.host)
                    TextField(L("editor.port", language: language), text: $draft.portText)

                    if draft.scheme == .https {
                        Picker(L("editor.hs_tls", language: language), selection: $draft.tlsPolicy) {
                            Text(L("editor.tls_system_short", language: language)).tag(TLSValidationPolicy.system)
                            Text(L("editor.tls_self_signed_short", language: language)).tag(TLSValidationPolicy.allowSelfSigned)
                        }
                    }
                }

                Section(L("editor.hs_secret", language: language)) {
                    SecureField(
                        draft.hasStoredSecret && !draft.clearStoredSecret
                            ? L("editor.secret_configured", language: language)
                            : L("editor.secret_empty", language: language),
                        text: $draft.secret
                    )

                    if draft.hasStoredSecret, draft.secret.isEmpty {
                        Toggle(L("editor.remove_secret", language: language), isOn: $draft.clearStoredSecret)
                    }
                }

                if let validationError = draft.validationError(language: language) {
                    Section {
                        Text(verbatim: validationError)
                            .font(.callout)
                            .foregroundStyle(MicaTheme.statusWarning)
                    }
                }

                if let testReport {
                    Section(L("diagnostics.check_latest", language: language)) {
                        HStack(spacing: MicaTheme.Spacing.sm) {
                            MicaStatusDot(
                                color: testReport.summary == .ready ? MicaTheme.statusOK : MicaTheme.statusError,
                                size: 8
                            )
                            Text(verbatim: testReport.headline)
                                .font(.callout.weight(.medium))
                        }

                        ForEach(testReport.steps) { step in
                            HStack {
                                Text(verbatim: step.title)
                                    .font(.caption)
                                    .foregroundStyle(MicaTheme.textSecondary)
                                Spacer()
                                Text(verbatim: step.value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(step.state == .failed ? MicaTheme.statusError : MicaTheme.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if let saveError {
                    Section {
                        Text(verbatim: saveError)
                            .font(.callout)
                            .foregroundStyle(MicaTheme.statusError)
                    }
                }
            }
            .formStyle(.grouped)

            MicaHairlineDivider()

            HStack(spacing: MicaTheme.Spacing.sm) {
                Button {
                    runConnectionTest()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("action.test", language: language))
                    }
                }
                .disabled(isTesting || isSaving || draft.validationError(language: language) != nil)

                Spacer()

                Button(L("action.save_controller", language: language)) {
                    saveController()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || draft.validationError(language: language) != nil)
            }
            .padding(.horizontal, MicaTheme.Spacing.lg)
            .padding(.vertical, MicaTheme.Spacing.md)
        }
        .frame(width: 500, height: 560)
        .onChange(of: draft) { _, newDraft in
            if !newDraft.secret.isEmpty, newDraft.clearStoredSecret {
                draft.clearStoredSecret = false
            }
            saveError = nil
        }
    }

    private func runConnectionTest() {
        isTesting = true
        let snapshot = draft
        Task {
            let report = await appModel.testConnection(draft: snapshot)
            testReport = report
            isTesting = false
        }
    }

    private func saveController() {
        isSaving = true
        saveError = nil
        let snapshot = draft
        Task {
            do {
                _ = try await appModel.upsertRouter(from: snapshot)
                isSaving = false
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

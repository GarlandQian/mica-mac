import SwiftUI

extension RouterEditorView {
    @ViewBuilder
    var diagnosisSection: some View {
        Section {
            if testState.shouldShow {
                testReportView
            } else {
                previewRow("editor.controller_type", value: draft.controllerKind.micaLabel(language: appLanguage))
                previewRow("editor.hs_url", value: localizedVisibleControllerTargetLabel, monospaced: true)
                previewRow("editor.hs_tls", value: localizedTLSCheckLabel)
                previewRow("editor.hs_secret", value: localizedSecretCheckLabel)
                previewRow(
                    "editor.test",
                    value: MicaStrings.localizedKey("diagnostics.capability_status_untested", language: appLanguage)
                )
            }
        } header: {
            MicaText(testState.shouldShow ? "editor.connection_diagnosis" : "editor.controller_preview")
        }
    }

    var localizedVisibleControllerTargetLabel: String {
        draft.visibleControllerTargetLabel(language: appLanguage)
    }

    var localizedTLSCheckLabel: String {
        draft.tlsPolicy == .allowSelfSigned
            ? MicaStrings.localized("editor.tls_self_signed_short", language: appLanguage)
            : MicaStrings.localized("editor.tls_system_short", language: appLanguage)
    }

    var localizedSecretCheckLabel: String {
        draft.shouldSaveSecret || draft.hasStoredSecret
            ? MicaStrings.localized("editor.secret_configured", language: appLanguage)
            : MicaStrings.localized("editor.secret_empty", language: appLanguage)
    }

    @ViewBuilder
    var testReportView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                MicaText("editor.testing_reachability")
                    .fontWeight(.medium)
            }
            LabeledContent(MicaStrings.localizedKey("editor.hs_url", language: appLanguage)) {
                Text(verbatim: localizedVisibleControllerTargetLabel)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        case .report(let report):
            Text(verbatim: MicaStrings.relocalizedText(report.headline, language: appLanguage))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent(MicaStrings.localizedKey("editor.hs_url", language: appLanguage)) {
                Text(verbatim: localizedReportTargetLabel(report))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            ForEach(report.steps) { step in
                handshakeRow(
                    localizedReportStepTitle(step),
                    value: localizedReportStepValue(step),
                    state: step.state
                )
            }
            Label {
                Text(verbatim: MicaStrings.relocalizedText(report.nextStep, language: appLanguage))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.turn.down.right")
            }
            .foregroundStyle(testState.foregroundStyle)
        }
    }

    func testConnection() {
        showsValidation = true
        guard validationError == nil else { return }
        testState = .testing
        Task {
            let report = await appModel.testConnection(draft: draft)
            testState = .report(report)
        }
    }

    private func localizedReportTargetLabel(_ report: ConnectionTestReport) -> String {
        MicaStrings.relocalizedText(report.targetURL, language: appLanguage)
    }

    private func localizedReportStepTitle(_ step: ConnectionCheckStep) -> String {
        MicaStrings.relocalizedText(step.title, language: appLanguage)
    }

    private func localizedReportStepValue(_ step: ConnectionCheckStep) -> String {
        switch step.id {
        case "url": localizedVisibleControllerTargetLabel
        case "tls": localizedTLSCheckLabel
        case "secret": localizedSecretCheckLabel
        case "controller-type": draft.controllerKind.micaLabel(language: appLanguage)
        default: MicaStrings.relocalizedText(step.value, language: appLanguage)
        }
    }

    private func previewRow(_ titleKey: String, value: String, monospaced: Bool = false) -> some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            Text(verbatim: value)
                .font(monospaced ? .body.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

import SwiftUI

extension RouterEditorView {
    @ViewBuilder
    var diagnosisSection: some View {
        Section {
            testReportView
        } header: {
            RouterEditorSectionHeader(
                titleKey: "editor.connection_diagnosis",
                systemImage: testState.iconName
            )
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
            WorkbenchManagementInlineState(
                systemImage: "hourglass",
                title: MicaStrings.localizedKey(
                    "editor.testing_reachability",
                    language: appLanguage
                ),
                tint: MicaDesignTokens.signalCyan,
                isLoading: true
            )
            previewRow(
                "editor.hs_url",
                value: localizedVisibleControllerTargetLabel,
                monospaced: true
            )
        case .report(let report):
            WorkbenchManagementInlineState(
                systemImage: testState.iconName,
                title: MicaStrings.relocalizedText(
                    report.headline,
                    language: appLanguage
                ),
                tint: testState.foregroundStyle
            )
            previewRow(
                "editor.hs_url",
                value: localizedReportTargetLabel(report),
                monospaced: true
            )
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
            .labelStyle(MicaStatusLabelStyle(tint: testState.foregroundStyle))
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
        WorkbenchFormRow(titleKey) {
            WorkbenchFormValue(
                value: value,
                monospaced: monospaced,
                placeholder: value == MicaStrings.localizedKey(
                    "editor.target_not_configured",
                    language: appLanguage
                )
            )
        }
    }
}

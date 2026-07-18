import SwiftUI

struct WorkbenchDiagnosticsView: View {
    var appModel: AppModel

    @Environment(\.micaAppLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                LabeledContent(MicaStrings.localizedKey("settings.active_controller", language: appLanguage)) {
                    Text(verbatim: appModel.selectedRouter?.displayName ?? MicaStrings.localizedKey("settings.none", language: appLanguage))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(MicaStrings.localizedKey("settings.controller_endpoint", language: appLanguage)) {
                    Text(verbatim: appModel.selectedRouter?.endpointURL ?? MicaStrings.localizedKey("settings.none", language: appLanguage))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(MicaStrings.localizedKey("settings.controller_type", language: appLanguage)) {
                    Text(appModel.selectedRouter?.controllerKind.micaLabel(language: appLanguage) ?? MicaStrings.localizedKey("settings.none", language: appLanguage))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(MicaStrings.localizedKey("settings.health", language: appLanguage)) {
                    Text(appModel.controllerHealth.summary.label(language: appLanguage))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(MicaStrings.localizedKey("overview.last_health_check", language: appLanguage)) {
                    Text(checkedAtLabel)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                MicaText("settings.diagnostics_section")
            }

            Section {
                ForEach(appModel.controllerHealth.endpoints) { endpoint in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(endpoint.status.label(language: appLanguage))
                                .foregroundStyle(endpointTint(endpoint.status))
                            Text(endpoint.status.detail(language: appLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            MicaText(endpoint.endpoint.displayTitleKey)
                                .fontWeight(.medium)
                            Text(verbatim: endpoint.endpoint.apiPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                MicaText("overview.endpoint_status")
            }

            Section {
                DisclosureGroup(MicaStrings.localizedKey("diagnostics.capability_matrix_title", language: appLanguage)) {
                    ForEach(appModel.capabilityMatrixRows) { row in
                        diagnosticRow(row)
                    }
                }

                DisclosureGroup(MicaStrings.localizedKey("command.show_data_availability", language: appLanguage)) {
                    ForEach(appModel.controllerDataCoverageRows) { row in
                        diagnosticRow(row)
                    }
                }
            } header: {
                MicaText("diagnostics.capability_matrix_title")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(MicaStrings.localizedKey("workspace.diagnostics", language: appLanguage))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.copyEndpointResults()
                } label: {
                    Label(MicaStrings.localizedKey("export.copy_endpoint_results", language: appLanguage), systemImage: "doc.on.doc")
                }
                .help(MicaStrings.localizedKey("export.copy_endpoint_results", language: appLanguage))

                Button {
                    appModel.copyDiagnosticsReport()
                } label: {
                    Label(MicaStrings.localizedKey("settings.copy_diagnostics", language: appLanguage), systemImage: "doc.on.doc")
                }
                .help(MicaStrings.localizedKey("diagnostics.report_policy", language: appLanguage))
            }
        }
    }

    private func diagnosticRow(_ row: CapabilityMatrixRow) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.label(language: appLanguage))
                    .foregroundStyle(statusTint(row.status))
                Text(verbatim: row.evidence)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Text(verbatim: row.operationImpact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            Text(verbatim: row.title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checkedAtLabel: String {
        guard let checkedAt = appModel.controllerHealth.checkedAt else {
            return MicaStrings.localizedKey("settings.never", language: appLanguage)
        }
        return checkedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(appLanguage.resolvedLocale))
    }

    private func endpointTint(_ status: ControllerEndpointStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .checking: MicaStyle.signalCyan
        case .ready: MicaStyle.signalMint
        case .failed: MicaStyle.signalRed
        }
    }

    private func statusTint(_ status: CapabilityStatus) -> Color {
        switch status {
        case .supported: MicaStyle.signalMint
        case .partial, .untested: MicaStyle.signalAmber
        case .failed: MicaStyle.signalRed
        case .unavailable: .secondary
        }
    }
}

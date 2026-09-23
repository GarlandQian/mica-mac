import Foundation
import MicaCore
import SwiftUI

struct WorkbenchRuleDecisionPathRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchRuleDecisionPathProjection
    let targetIsNavigable: Bool
    let onOpenTarget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            ScrollView(.horizontal) {
                horizontalPath
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, MicaTheme.Spacing.space1)
            }
            .scrollIndicators(.automatic)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                statistics
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, MicaTheme.Spacing.space1)
            }
            .scrollIndicators(.automatic)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MicaTheme.Spacing.space3)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            typeStep
                .frame(minWidth: 130, maxWidth: 180)
            WorkbenchDecisionPathConnector()
            payloadStep
                .frame(minWidth: 170, maxWidth: 260)
            WorkbenchDecisionPathConnector()
            targetStep
                .frame(minWidth: 140, maxWidth: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_type",
            value: reported(projection.type),
            systemImage: "line.3.horizontal.decrease.circle",
            tint: MicaTheme.textSecondary,
            monospaced: true
        )
    }

    private var payloadStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_payload",
            value: reported(projection.payload),
            systemImage: "scope",
            tint: MicaTheme.textSecondary,
            monospaced: true
        )
    }

    private var targetStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_proxy",
            value: reported(projection.target),
            systemImage: targetIsNavigable
                ? "arrow.right.circle"
                : "point.3.connected.trianglepath.dotted",
            tint: targetIsNavigable
                ? MicaTheme.accent
                : .secondary,
            actionHelpKey: targetIsNavigable
                ? "traffic.open_target_policy"
                : nil,
            action: targetIsNavigable ? onOpenTarget : nil
        )
    }

    private var statistics: some View {
        HStack(spacing: MicaTheme.Spacing.space4) {
            statusReadout
            activityReadout
            hitReadout
            missReadout
        }
    }

    private var statusReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "dashboard.col_status",
            value: projection.status,
            systemImage: "circle.fill",
            tint: statusTint,
            monospaced: false
        )
    }

    private var activityReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "dashboard.active_sessions",
            value: projection.activeConnections.formatted(),
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: MicaTheme.textSecondary
        )
    }

    private var hitReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_hits",
            value: reported(projection.hitCount),
            systemImage: "scope",
            tint: MicaTheme.textSecondary
        )
    }

    private var missReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_misses",
            value: reported(projection.missCount),
            systemImage: "circle.slash",
            tint: MicaTheme.textSecondary
        )
    }

    private var statusTint: Color {
        switch projection.isDisabled {
        case true: MicaTheme.statusWarning
        case false: MicaTheme.statusOK
        case nil: .secondary
        }
    }

    private func reported(_ value: String?) -> String {
        value?.dataNonEmpty
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }

    private func reported(_ value: Int?) -> String {
        value?.formatted()
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }
}

struct WorkbenchRuleInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchRuleRow?
    let canMutate: Bool
    let isUpdating: Bool
    let failure: String?
    let close: () -> Void
    let disabled: Binding<Bool>

    var body: some View {
        if let row {
            let rule = row.rule
            WorkbenchDataInspectorShell(
                title: MicaStrings.localizedKey("traffic.detail_rule", language: language),
                subtitle: rule.index.map { "#\($0)" },
                statusText: row.statusText,
                statusTint: statusTint(rule),
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.rule_section_definition") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleDefinition(row)
                    )
                }

                if rule.hasMutableExtra, rule.index != nil {
                    WorkbenchDataInspectorSection("traffic.rule_section_state") {
                        Toggle(
                            MicaStrings.localizedKey("traffic.rule_disabled", language: language),
                            isOn: disabled
                        )
                        .toggleStyle(.switch)
                        .disabled(!canMutate || isUpdating)
                        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

                        if isUpdating {
                            ProgressView {
                                Text(MicaStrings.localizedKey("traffic.rule_updating", language: language))
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if let failure {
                    WorkbenchDataInspectorSection("traffic.rule_section_error") {
                        Label {
                            Text(verbatim: failure)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MicaTheme.statusError)
                        }
                    }
                }

                WorkbenchDataInspectorSection("traffic.rule_section_statistics") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleStatistics(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.rule_section_metadata") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleMetadata(row)
                    )
                }
            }
        }
    }

    private func statusTint(_ rule: RuleViewState) -> Color {
        switch rule.disabled {
        case true: MicaTheme.statusWarning
        case false: MicaTheme.statusOK
        case nil: .secondary
        }
    }
}

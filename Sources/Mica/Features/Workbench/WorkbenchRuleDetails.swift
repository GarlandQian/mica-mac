import Foundation
import MicaCore
import SwiftUI

struct WorkbenchRuleDecisionPathRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchRuleDecisionPathProjection
    let targetIsNavigable: Bool
    let onOpenTarget: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MicaSpacing.module) {
                horizontalPath
                Spacer(minLength: MicaSpacing.section)
                statistics
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                compactPath
                statistics
            }
        }
        .padding(.horizontal, MicaSpacing.module)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaSpacing.row) {
            typeStep
            WorkbenchDecisionPathConnector()
            payloadStep
            WorkbenchDecisionPathConnector()
            targetStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactPath: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeStep
            compactConnector
            payloadStep
            compactConnector
            targetStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactConnector: some View {
        Image(systemName: "chevron.down")
            .micaFont(.caption2, weight: .semibold)
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
            .accessibilityHidden(true)
    }

    private var typeStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_type",
            value: reported(projection.type),
            systemImage: "line.3.horizontal.decrease.circle",
            tint: MicaDesignTokens.signalViolet,
            monospaced: true
        )
    }

    private var payloadStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_payload",
            value: reported(projection.payload),
            systemImage: "scope",
            tint: MicaDesignTokens.signalCyan,
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
                ? MicaDesignTokens.accent
                : .secondary,
            actionHelpKey: targetIsNavigable
                ? "traffic.open_target_policy"
                : nil,
            action: targetIsNavigable ? onOpenTarget : nil
        )
    }

    private var statistics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.section) {
                statusReadout
                activityReadout
                hitReadout
                missReadout
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                HStack(spacing: MicaSpacing.section) {
                    statusReadout
                    activityReadout
                }
                HStack(spacing: MicaSpacing.section) {
                    hitReadout
                    missReadout
                }
            }
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
            tint: MicaDesignTokens.signalCyan
        )
    }

    private var hitReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_hits",
            value: reported(projection.hitCount),
            systemImage: "scope",
            tint: MicaDesignTokens.signalMint
        )
    }

    private var missReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.rule_misses",
            value: reported(projection.missCount),
            systemImage: "circle.slash",
            tint: MicaDesignTokens.signalAmber
        )
    }

    private var statusTint: Color {
        switch projection.isDisabled {
        case true: MicaDesignTokens.signalAmber
        case false: MicaDesignTokens.signalMint
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
                        .frame(minHeight: MicaBounds.controlMinHeight)

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
                                .foregroundStyle(MicaDesignTokens.signalRed)
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
        case true: MicaDesignTokens.signalAmber
        case false: MicaDesignTokens.signalMint
        case nil: .secondary
        }
    }
}

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
            HStack(spacing: MicaTheme.Spacing.space3) {
                horizontalPath
                Spacer(minLength: MicaTheme.Spacing.space2)
                statistics
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                ScrollView(.horizontal) {
                    horizontalPath
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal) {
                    statistics
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            typeStep
                .frame(minWidth: 100, maxWidth: 150)
            WorkbenchDecisionPathConnector()
            payloadStep
                .frame(minWidth: 130, maxWidth: 240)
            WorkbenchDecisionPathConnector()
            targetStep
                .frame(minWidth: 110, maxWidth: 200)
        }
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
                ? "arrow.right.circle.fill"
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
        HStack(spacing: MicaTheme.Spacing.space3) {
            statusReadout
            activityReadout
            if projection.hitCount != nil {
                hitReadout
            }
            if projection.missCount != nil {
                missReadout
            }
        }
    }

    private var statusReadout: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(MicaStrings.localizedKey("dashboard.col_status", language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(verbatim: projection.status)
                    .micaThemeFont(.dataCaption, weight: .semibold)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
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
    var onOpenTarget: (() -> Void)? = nil

    var body: some View {
        if let row {
            let rule = row.rule
            WorkbenchDataInspectorShell(
                title: MicaStrings.localizedKey("traffic.detail_rule", language: language),
                subtitle: rule.index.map { "#\($0)" },
                statusText: row.statusText,
                statusTint: statusTint(rule),
                close: close,
                actions: {
                    if let onOpenTarget {
                        WorkbenchIconCommand(
                            titleKey: "traffic.open_target_policy",
                            systemImage: "arrow.right.circle",
                            isEnabled: true,
                            action: onOpenTarget
                        )
                    }
                }
            ) {
                WorkbenchDataInspectorSection("traffic.rule_section_definition") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.ruleDefinition(row)
                    )
                }

                if rule.hasMutableExtra, rule.index != nil {
                    WorkbenchDataInspectorSection("traffic.rule_section_state") {
                        Toggle(
                            MicaStrings.localizedKey("routing.rule_enabled", language: language),
                            isOn: Binding(
                                get: { !disabled.wrappedValue },
                                set: { disabled.wrappedValue = !$0 }
                            )
                        )
                        .toggleStyle(.switch)
                        .micaThemeFont(.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .disabled(!canMutate || isUpdating)
                        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

                        if isUpdating {
                            ProgressView {
                                Text(MicaStrings.localizedKey("traffic.rule_updating", language: language))
                                    .micaThemeFont(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if let failure {
                    WorkbenchDataInspectorSection("traffic.rule_section_error") {
                        Label {
                            Text(verbatim: failure)
                                .micaThemeFont(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MicaTheme.statusError)
                        }
                        .padding(MicaTheme.Spacing.space2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)
                                .fill(MicaTheme.statusError.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)
                                .strokeBorder(MicaTheme.statusError.opacity(0.24), lineWidth: MicaTheme.Shape.hairline)
                        )
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
            .id(row.id)
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

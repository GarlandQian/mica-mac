import MicaCore
import SwiftUI

struct WorkbenchConnectionDecisionPathRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchConnectionDecisionPathProjection
    let ruleIsNavigable: Bool
    let policyTarget: (String) -> ProxyGroupOccurrence?
    let isActive: Bool
    let showsClose: Bool
    let canClose: Bool
    let closeGroup: WorkbenchConnectionCloseGroup?
    let canCloseGroup: Bool
    let isClosing: Bool
    let isClosingGroup: Bool
    let openRule: () -> Void
    let openPolicyGroup: (ProxyGroupOccurrence) -> Void
    let requestClose: () -> Void
    let requestCloseGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            ScrollView(.horizontal) {
                horizontalPath
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, MicaTheme.Spacing.space1)
            }
            .scrollIndicators(.automatic)
            .fixedSize(horizontal: false, vertical: true)

            if isActive {
                actionBar
            }
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surfaceRaised)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            originStep
                .frame(minWidth: 140, maxWidth: 200)
            WorkbenchDecisionPathConnector()
            inboundStep
                .frame(minWidth: 130, maxWidth: 190)
            WorkbenchDecisionPathConnector()
            ruleStep
                .frame(minWidth: 170, maxWidth: 250)
            ForEach(projection.segments) { segment in
                WorkbenchDecisionPathConnector()
                routeStep(segment)
                    .frame(minWidth: 140, maxWidth: 210)
            }
            WorkbenchDecisionPathConnector()
            destinationStep
                .frame(minWidth: 160, maxWidth: 240)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.connection_source",
            value: reported(projection.origin),
            systemImage: "network",
            tint: MicaTheme.textSecondary,
            monospaced: true
        )
    }

    private var inboundStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.inbound_name",
            value: reported(projection.inbound),
            systemImage: "arrow.down.to.line",
            tint: MicaTheme.textSecondary,
            monospaced: true
        )
    }

    private var ruleStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_rule",
            value: "\(reported(projection.rule)) · \(reported(projection.payload))",
            systemImage: "line.3.horizontal.decrease.circle",
            tint: ruleIsNavigable ? MicaTheme.accent : MicaTheme.textSecondary,
            monospaced: true,
            action: ruleIsNavigable ? openRule : nil
        )
    }

    @ViewBuilder
    private func routeStep(
        _ segment: WorkbenchConnectionDecisionPathSegment
    ) -> some View {
        if segment.kind == .policy,
           let target = policyTarget(segment.value) {
            WorkbenchDecisionPathStep(
                titleKey: segment.kind.titleKey,
                value: segment.value,
                systemImage: "arrow.right.circle",
                tint: MicaTheme.accent,
                actionHelpKey: "traffic.open_target_policy",
                action: { openPolicyGroup(target) }
            )
        } else {
            WorkbenchDecisionPathStep(
                titleKey: segment.kind.titleKey,
                value: segment.value,
                systemImage: segment.kind.systemImage,
                tint: MicaTheme.textSecondary
            )
        }
    }

    private var destinationStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.connection_destination",
            value: reported(projection.destination),
            systemImage: "scope",
            tint: .secondary,
            monospaced: true
        )
    }

    private var actionBar: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            WorkbenchDecisionReadout(
                titleKey: "dashboard.col_chain",
                value: projection.segments.count.formatted(),
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: MicaTheme.textSecondary
            )

            Spacer(minLength: MicaTheme.Spacing.space3)

            if showsClose {
                if isClosing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: MicaTheme.Metrics.iconControlSize, minHeight: MicaTheme.Metrics.iconControlSize)
                } else {
                    WorkbenchIconCommand(
                        titleKey: "action.close_connection",
                        systemImage: "xmark.circle",
                        isEnabled: canClose,
                        role: .destructive,
                        action: requestClose
                    )
                    .foregroundStyle(MicaTheme.statusError)
                }
            }

            if let closeGroup, closeGroup.connections.count > 1 {
                if isClosingGroup {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: MicaTheme.Metrics.iconControlSize, minHeight: MicaTheme.Metrics.iconControlSize)
                } else {
                    WorkbenchIconCommand(
                        titleKey: "action.close_connection_group",
                        systemImage: "rectangle.3.group.bubble.left",
                        isEnabled: canCloseGroup,
                        role: .destructive,
                        action: requestCloseGroup
                    )
                    .foregroundStyle(MicaTheme.statusError)
                }
            }
        }
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
    }

    private func reported(_ value: String) -> String {
        value.dataNonEmpty
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }
}

struct WorkbenchConnectionInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchConnectionRow?
    let isActive: Bool
    let close: () -> Void

    var body: some View {
        if let row {
            let connection = row.connection
            WorkbenchDataInspectorShell(
                title: row.host,
                subtitle: connection.id,
                statusText: MicaStrings.localizedKey(
                    isActive ? "traffic.connection_state_active" : "traffic.connection_state_closed",
                    language: language
                ),
                statusTint: isActive ? MicaTheme.statusOK : .secondary,
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.connection_section_identity") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.connectionIdentity(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.connection_section_routing") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.connectionRouting(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.connection_section_transfer") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.connectionTransfer(
                            row,
                            language: language
                        )
                    )
                }

                WorkbenchDataInspectorSection("traffic.connection_section_metadata") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.connectionMetadata(row)
                    )

                    if !row.metadataAdditionalFields.isEmpty {
                        WorkbenchConnectionAdditionalFieldList(
                            titleKey: "traffic.connection_metadata_fields",
                            fields: row.metadataAdditionalFields
                        )
                    }

                    if !row.connectionAdditionalFields.isEmpty {
                        WorkbenchConnectionAdditionalFieldList(
                            titleKey: "traffic.connection_additional_fields",
                            fields: row.connectionAdditionalFields
                        )
                    }
                }

            }
        }
    }
}

private struct WorkbenchConnectionAdditionalFieldList: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let fields: [WorkbenchConnectionAdditionalField]

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            HStack(spacing: MicaTheme.Spacing.space1) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.caption, weight: .semibold)

                Text(verbatim: fields.count.formatted())
                    .micaThemeFont(.dataCaption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(fields) { field in
                    WorkbenchConnectionJSONNode(
                        path: field.key,
                        label: field.key,
                        value: field.value
                    )
                }
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(MicaTheme.separator)
                    .frame(width: 1)
            }
        }
        .padding(.top, MicaTheme.Spacing.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkbenchConnectionJSONNode: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let path: String
    let label: String
    let value: MihomoJSONValue

    @State private var isExpanded = false

    var body: some View {
        switch value {
        case .object(let values):
            expandableNode(
                summary: MicaStrings.localized(
                    "traffic.connection_fields_count \(values.count)",
                    language: language
                )
            ) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    if let child = values[key] {
                        WorkbenchConnectionJSONNode(
                            path: "\(path).\(key)",
                            label: key,
                            value: child
                        )
                    }
                }
            }

        case .array(let values):
            expandableNode(
                summary: MicaStrings.localized(
                    "traffic.connection_items_count \(values.count)",
                    language: language
                )
            ) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, child in
                    WorkbenchConnectionJSONNode(
                        path: "\(path)[\(index)]",
                        label: MicaStrings.localized(
                            "traffic.connection_item \(index + 1)",
                            language: language
                        ),
                        value: child
                    )
                }
            }

        case .string(let text):
            scalarNode(text.isEmpty ? "\"\"" : text)
        case .number(let number):
            scalarNode(numberText(number))
        case .bool(let value):
            scalarNode(String(value))
        case .null:
            scalarNode("null")
        }
    }

    private func scalarNode(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
            Text(verbatim: label)
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 92, idealWidth: 112, alignment: .leading)

            Text(verbatim: text)
                .micaThemeFont(.dataLabel)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, MicaTheme.Spacing.space2)
        .padding(.vertical, MicaTheme.Spacing.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func expandableNode<Children: View>(
        summary: String,
        @ViewBuilder children: () -> Children
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: MicaTheme.Spacing.space1) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    Text(verbatim: label)
                        .micaThemeFont(.label, weight: .medium)
                        .lineLimit(1)

                    Spacer(minLength: MicaTheme.Spacing.space2)

                    Text(verbatim: summary)
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, MicaTheme.Spacing.space2)
                .padding(.vertical, MicaTheme.Spacing.space1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(summary)
            .accessibilityHint(
                MicaStrings.localized(
                    isExpanded ? "overview.show_less" : "overview.show_all",
                    language: language
                )
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    children()
                }
                .padding(.leading, MicaTheme.Spacing.space3)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberText(_ number: Double) -> String {
        guard number.isFinite else { return String(number) }
        if number.rounded() == number,
           number >= Double(Int64.min),
           number <= Double(Int64.max) {
            return String(Int64(number))
        }
        return String(number)
    }
}

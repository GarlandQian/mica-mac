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
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            ViewThatFits(in: .horizontal) {
                horizontalPath
                verticalPath
            }

            if isActive {
                actionBar
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var horizontalPath: some View {
        HStack(spacing: MicaSpacing.row) {
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

    private var verticalPath: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            originStep
            verticalConnector
            inboundStep
            verticalConnector
            ruleStep

            ForEach(projection.segments) { segment in
                verticalConnector
                routeStep(segment)
            }

            verticalConnector
            destinationStep
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.connection_source",
            value: reported(projection.origin),
            systemImage: "network",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    private var inboundStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "traffic.inbound_name",
            value: reported(projection.inbound),
            systemImage: "arrow.down.to.line",
            tint: MicaDesignTokens.signalMint,
            monospaced: true
        )
    }

    private var verticalConnector: some View {
        WorkbenchDecisionPathConnector()
            .rotationEffect(.degrees(90))
            .padding(.leading, MicaSpacing.row)
    }

    private var ruleStep: some View {
        WorkbenchDecisionPathStep(
            titleKey: "dashboard.col_rule",
            value: "\(reported(projection.rule)) · \(reported(projection.payload))",
            systemImage: "line.3.horizontal.decrease.circle",
            tint: ruleIsNavigable ? MicaDesignTokens.accent : MicaDesignTokens.signalViolet,
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
                tint: MicaDesignTokens.accent,
                actionHelpKey: "traffic.open_target_policy",
                action: { openPolicyGroup(target) }
            )
        } else {
            WorkbenchDecisionPathStep(
                titleKey: segment.kind.titleKey,
                value: segment.value,
                systemImage: segment.kind.systemImage,
                tint: segment.kind == .provider
                    ? MicaDesignTokens.signalViolet
                    : MicaDesignTokens.signalCyan
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
        HStack(spacing: MicaSpacing.tight) {
            WorkbenchDecisionReadout(
                titleKey: "dashboard.col_chain",
                value: projection.segments.count.formatted(),
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: MicaDesignTokens.signalCyan
            )

            Spacer(minLength: MicaSpacing.module)

            if showsClose {
                if isClosing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
                } else {
                    WorkbenchIconCommand(
                        titleKey: "action.close_connection",
                        systemImage: "xmark.circle",
                        isEnabled: canClose,
                        role: .destructive,
                        action: requestClose
                    )
                    .foregroundStyle(MicaDesignTokens.signalRed)
                }
            }

            if let closeGroup, closeGroup.connections.count > 1 {
                if isClosingGroup {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
                } else {
                    WorkbenchIconCommand(
                        titleKey: "action.close_connection_group",
                        systemImage: "rectangle.3.group.bubble.left",
                        isEnabled: canCloseGroup,
                        role: .destructive,
                        action: requestCloseGroup
                    )
                    .foregroundStyle(MicaDesignTokens.signalRed)
                }
            }
        }
        .frame(minHeight: MicaBounds.controlMinHeight)
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
                statusTint: isActive ? MicaDesignTokens.signalMint : .secondary,
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
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            HStack(spacing: MicaSpacing.tight) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.caption, weight: .semibold)

                Text(verbatim: fields.count.formatted())
                    .micaFont(.caption2, weight: .semibold, design: .monospaced)
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
                    .fill(MicaDesignTokens.separator)
                    .frame(width: 1)
            }
        }
        .padding(.top, MicaSpacing.tight)
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
        HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
            Text(verbatim: label)
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 92, idealWidth: 112, alignment: .leading)

            Text(verbatim: text)
                .micaFont(.callout, design: .monospaced)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, MicaSpacing.row)
        .padding(.vertical, MicaSpacing.tight)
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
                HStack(spacing: MicaSpacing.tight) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .micaFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    Text(verbatim: label)
                        .micaFont(.callout, weight: .medium)
                        .lineLimit(1)

                    Spacer(minLength: MicaSpacing.row)

                    Text(verbatim: summary)
                        .micaFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, MicaSpacing.row)
                .padding(.vertical, MicaSpacing.tight)
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
                .padding(.leading, MicaSpacing.module)
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

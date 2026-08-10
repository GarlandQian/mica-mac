import MicaCore
import SwiftUI

struct ProxyExpandedGroupPresentation: Identifiable, Equatable {
    let occurrence: ProxyGroupOccurrence
    let item: ProxyGroupDirectoryItem
    let isExpanded: Bool
    let members: [ProxyNodeRowProjection]
    let filter: String
    let inspectedMemberID: String?
    let inspectedMember: ProxyNodeRowProjection?
    let isSwitching: Bool
    let isTesting: Bool
    let isClearingFixed: Bool
    let canClearFixed: Bool

    var id: String { occurrence.id }
}

struct ProxyPolicyGroupPanel: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: ProxyExpandedGroupPresentation
    let scrollInteractionTracker: ProxyScrollInteractionTracker
    let commandsEnabled: Bool
    let canSelect: Bool
    let canTestGroup: Bool
    let canTestNode: Bool
    let measuringNode: PolicyNodeLatencyTestTarget?
    let onToggle: () -> Void
    let onFilterChange: (String) -> Void
    let onSelectMember: (String) -> Void
    let onTestMember: (String) -> Void
    let onTestGroup: () -> Void
    let onClearFixed: () -> Void
    let onCloseInspector: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            groupHeader

            if presentation.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.24),
            value: presentation.isExpanded
        )
    }

    private var groupHeader: some View {
        VStack(spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.row) {
                Button(action: onToggle) {
                    HStack(spacing: MicaSpacing.module) {
                        Image(
                            systemName: presentation.isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .micaFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                            Text(verbatim: presentation.item.groupID)
                                .micaFont(.headline, weight: .semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(verbatim: groupSubtitle)
                                .micaFont(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: MicaSpacing.section)

                        VStack(alignment: .trailing, spacing: MicaSpacing.tight) {
                            Text(
                                MicaStrings.localizedKey(
                                    "dashboard.current_node",
                                    language: language
                                )
                            )
                            .micaFont(.caption2)
                            .foregroundStyle(.secondary)

                            HStack(spacing: MicaSpacing.row) {
                                Text(verbatim: presentation.item.selected)
                                    .micaFont(.callout, weight: .semibold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let delay = presentation.item.selectedDelay {
                                    Text(verbatim: OverviewFormat.latency(delay))
                                        .micaFont(
                                            .caption,
                                            weight: .semibold,
                                            design: .monospaced
                                        )
                                        .foregroundStyle(
                                            OverviewFormat.latencyTint(delay)
                                        )
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(maxWidth: 360, alignment: .trailing)
                    }
                    .padding(.leading, MicaSpacing.module)
                    .padding(.vertical, MicaSpacing.row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(presentation.item.groupID), \(presentation.item.selected)"
                )

                groupActions
                    .padding(.trailing, MicaSpacing.row)
            }

            ProxyLatencyDistributionView(
                distribution: presentation.item.latencyDistribution
            )
            .padding(.horizontal, MicaSpacing.module)
            .padding(.bottom, MicaSpacing.row)
        }
        .background(
            presentation.isExpanded
                ? MicaDesignTokens.elevatedFill.opacity(0.56)
                : MicaDesignTokens.contentFill.opacity(0.62)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: MicaBounds.moduleRadius,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            if presentation.isExpanded {
                Capsule(style: .continuous)
                    .fill(MicaDesignTokens.accent)
                    .frame(width: 3)
                    .padding(.vertical, MicaSpacing.row)
            }
        }
    }

    @ViewBuilder
    private var groupActions: some View {
        HStack(spacing: MicaSpacing.tight) {
            if canTestGroup || presentation.isTesting {
                Button(action: onTestGroup) {
                    if presentation.isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !canTestGroup
                        || !commandsEnabled
                        || presentation.isTesting
                        || presentation.isSwitching
                        || presentation.isClearingFixed
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .help(
                    MicaStrings.localizedKey(
                        "routing.test_group",
                        language: language
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.test_group",
                        language: language
                    )
                )
            }

            if presentation.canClearFixed || presentation.isClearingFixed {
                Button(action: onClearFixed) {
                    if presentation.isClearingFixed {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "pin.slash")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !presentation.canClearFixed
                        || !commandsEnabled
                        || presentation.isClearingFixed
                        || presentation.isSwitching
                        || presentation.isTesting
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .help(
                    MicaStrings.localizedKey(
                        "routing.clear_fixed_selection",
                        language: language
                    )
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.clear_fixed_selection",
                        language: language
                    )
                )
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.module) {
                TextField(
                    MicaStrings.localizedKey(
                        "routing.filter_nodes_placeholder",
                        language: language
                    ),
                    text: Binding(
                        get: { presentation.filter },
                        set: { value in onFilterChange(value) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200, maxWidth: 420)
                .accessibilityLabel(
                    MicaStrings.localizedKey(
                        "routing.filter_nodes",
                        language: language
                    )
                )

                Spacer(minLength: MicaSpacing.row)

                Text(
                    MicaStrings.localized(
                        "routing.member_window \(presentation.members.count) \(presentation.item.memberCount)",
                        language: language
                    )
                )
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, MicaSpacing.tight)

            if presentation.members.isEmpty {
                Label(
                    MicaStrings.localizedKey(
                        presentation.filter.proxyNilIfBlank == nil
                            ? "routing.members_empty"
                            : "routing.members_filtered_empty",
                        language: language
                    ),
                    systemImage: "tray"
                )
                .micaFont(.callout)
                .foregroundStyle(.secondary)
                .padding(MicaSpacing.section)
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 340, maximum: 460),
                            spacing: MicaSpacing.row,
                            alignment: .top
                        ),
                    ],
                    alignment: .leading,
                    spacing: MicaSpacing.row
                ) {
                    ForEach(presentation.members) { member in
                        ProxyPolicyNodeTile(
                            member: member,
                            scrollInteractionTracker: scrollInteractionTracker,
                            isInspected: presentation.inspectedMemberID
                                == member.id,
                            commandsEnabled: commandsEnabled,
                            canSelect: canSelect
                                && presentation.occurrence.group.selectable,
                            canTest: canTestNode,
                            isSwitching: presentation.isSwitching,
                            isMeasuring: measuringNode?.groupID
                                == presentation.occurrence.group.id
                                && measuringNode?.nodeName == member.name,
                            onSelect: { onSelectMember(member.id) },
                            onTest: { onTestMember(member.id) }
                        )
                    }
                }

                if let inspectedMember = presentation.inspectedMember {
                    ProxyPolicyNodeInlineDetails(
                        member: inspectedMember,
                        detail: presentation.occurrence.group.detail(
                            for: inspectedMember.name
                        ),
                        onClose: onCloseInspector
                    )
                    .id(inspectedMember.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var groupSubtitle: String {
        let availability = MicaStrings.localized(
            "routing.available_nodes_count \(presentation.item.availableMemberCount) \(presentation.item.memberCount)",
            language: language
        )
        return "\(presentation.item.type)  ·  \(availability)"
    }
}

private struct ProxyLatencyDistributionView: View {
    let distribution: ProxyLatencyDistribution

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(max(0, distribution.buckets.count - 1)) * 2
            let drawableWidth = max(0, geometry.size.width - totalSpacing)

            HStack(spacing: 2) {
                ForEach(distribution.buckets) { bucket in
                    Capsule(style: .continuous)
                        .fill(bucket.tint)
                        .frame(
                            width: max(
                                bucket.count > 0 ? 3 : 0,
                                drawableWidth * bucket.fraction
                            )
                        )
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct ProxyPolicyNodeTile: View {
    @Environment(\.micaAppLanguage) private var language

    @State private var isHovered = false

    let member: ProxyNodeRowProjection
    let scrollInteractionTracker: ProxyScrollInteractionTracker
    let isInspected: Bool
    let commandsEnabled: Bool
    let canSelect: Bool
    let canTest: Bool
    let isSwitching: Bool
    let isMeasuring: Bool
    let onSelect: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(member.isControllerSelected ? MicaDesignTokens.accent : statusTint)
                .frame(width: 3)
                .padding(.vertical, MicaSpacing.row)
                .accessibilityHidden(true)

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                    HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                        Text(verbatim: member.name)
                            .micaFont(
                                .callout,
                                weight: member.isControllerSelected
                                    ? .semibold
                                    : .regular
                            )
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: MicaSpacing.row)

                        if isMeasuring {
                            ProgressView()
                                .controlSize(.small)
                        } else if let delay = member.delay {
                            Text(verbatim: OverviewFormat.latency(delay))
                                .micaFont(
                                    .caption,
                                    weight: .semibold,
                                    design: .monospaced
                                )
                                .foregroundStyle(OverviewFormat.latencyTint(delay))
                                .monospacedDigit()
                        }
                    }

                    if let descriptor = member.descriptor {
                        Text(verbatim: descriptor)
                            .micaFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }

                    HStack(spacing: MicaSpacing.module) {
                        if let rank = member.usageRank {
                            Text(verbatim: rank.label(language: language))
                                .micaFont(.caption2, weight: .semibold)
                                .foregroundStyle(usageTint(rank))
                                .lineLimit(1)
                        }

                        if member.isControllerSelected {
                            Label(
                                MicaStrings.localizedKey(
                                    "dashboard.inspector_current",
                                    language: language
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .micaFont(.caption2, weight: .semibold)
                            .foregroundStyle(MicaDesignTokens.accent)
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, MicaSpacing.module)
                .padding(.vertical, MicaSpacing.module)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(member.name)
            .accessibilityAddTraits(isInspected ? .isSelected : [])

            if canTest || isMeasuring {
                Button(action: onTest) {
                    if isMeasuring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(
                    !canTest
                        || !commandsEnabled
                        || isMeasuring
                        || isSwitching
                )
                .frame(
                    minWidth: MicaBounds.iconControlSize,
                    minHeight: MicaBounds.iconControlSize
                )
                .padding(.trailing, MicaSpacing.tight)
                .opacity(
                    isHovered || isInspected || isMeasuring
                        ? 1
                        : 0.42
                )
                .help(
                    MicaStrings.localized(
                        "routing.help_test_node \(member.name)",
                        language: language
                    )
                )
            }
        }
        .frame(minHeight: 70, alignment: .leading)
        .background(tileFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MicaBounds.badgeRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MicaBounds.badgeRadius,
                style: .continuous
            )
            .stroke(
                tileStroke,
                lineWidth: member.isControllerSelected ? 1.5 : 1
            )
        }
        .onHover { hovering in
            guard !hovering || !scrollInteractionTracker.isScrolling,
                  isHovered != hovering else { return }
            isHovered = hovering
        }
        .animation(
            scrollInteractionTracker.isScrolling
                ? nil
                : .easeOut(duration: 0.12),
            value: isHovered
        )
    }

    private var tileFill: Color {
        if member.isControllerSelected {
            return MicaDesignTokens.accentSoft
        }
        if isInspected {
            return MicaDesignTokens.accentSoft.opacity(0.62)
        }
        if isHovered {
            return MicaDesignTokens.elevatedFill.opacity(0.62)
        }
        return MicaDesignTokens.contentFill.opacity(0.34)
    }

    private var tileStroke: Color {
        if member.isControllerSelected {
            return MicaDesignTokens.accent.opacity(0.78)
        }
        if isInspected {
            return MicaDesignTokens.accent.opacity(0.42)
        }
        if isHovered {
            return MicaDesignTokens.separator.opacity(0.48)
        }
        return .clear
    }

    private var statusTint: Color {
        switch member.alive {
        case true: MicaDesignTokens.signalOK
        case false: MicaDesignTokens.signalError
        case nil: .secondary
        }
    }

    private func usageTint(_ rank: PolicyGroupUsageRank) -> Color {
        switch rank {
        case .mostUsed: MicaDesignTokens.accent
        case .occasionallyUsed: MicaDesignTokens.signalCyan
        case .rarelyUsed, .reported: .secondary
        }
    }
}

private struct ProxyPolicyNodeInlineDetails: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let member: ProxyNodeRowProjection
    let detail: ProxyNodeViewState?
    let onClose: () -> Void

    @State private var showsAdditionalFields = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: MicaSpacing.module) {
                VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                    Text(verbatim: member.name)
                        .micaFont(.headline, weight: .semibold)
                        .textSelection(.enabled)

                    HStack(spacing: MicaSpacing.module) {
                        if let availabilityText {
                            Label(
                                availabilityText,
                                systemImage: availabilitySymbol
                            )
                                .micaFont(.caption, weight: .semibold)
                                .foregroundStyle(availabilityTint)
                        }

                        if member.isControllerSelected {
                            Label(
                                MicaStrings.localizedKey(
                                    "dashboard.inspector_current",
                                    language: language
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .micaFont(.caption, weight: .semibold)
                            .foregroundStyle(MicaDesignTokens.accent)
                        }
                    }
                }

                Spacer(minLength: MicaSpacing.row)

                if let displayedDelay {
                    VStack(alignment: .trailing, spacing: MicaSpacing.tight) {
                        Text(localized("routing.current_latency"))
                            .micaFont(.caption2)
                            .foregroundStyle(.secondary)

                        Text(verbatim: OverviewFormat.latency(displayedDelay))
                            .micaFont(
                                .callout,
                                weight: .semibold,
                                design: .monospaced
                            )
                            .foregroundStyle(
                                OverviewFormat.latencyTint(displayedDelay)
                            )
                            .monospacedDigit()
                    }
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(
                            minWidth: MicaBounds.iconControlSize,
                            minHeight: MicaBounds.iconControlSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(
                    MicaStrings.localizedKey(
                        "routing.help_close_inspector",
                        language: language
                    )
                )
            }
            .padding(MicaSpacing.section)

            Divider()

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 260, maximum: 420),
                        spacing: MicaSpacing.section,
                        alignment: .top
                    ),
                ],
                alignment: .leading,
                spacing: MicaSpacing.section
            ) {
                if !overviewFacts.isEmpty {
                    ProxyNodeFactSection(
                        title: localized("routing.node_section_overview"),
                        systemImage: "info.circle",
                        facts: overviewFacts
                    )
                }

                if !transportFacts.isEmpty {
                    ProxyNodeFactSection(
                        title: localized("routing.node_section_transport"),
                        systemImage: "arrow.left.arrow.right",
                        facts: transportFacts
                    )
                }

                if !testingFacts.isEmpty {
                    ProxyNodeFactSection(
                        title: localized("routing.node_section_testing"),
                        systemImage: "gauge.with.dots.needle.67percent",
                        facts: testingFacts
                    )
                }
            }
            .padding(MicaSpacing.section)

            if !additionalFields.isEmpty {
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    Divider()

                    Button {
                        withAnimation(
                            reduceMotion ? nil : .snappy(duration: 0.2)
                        ) {
                            showsAdditionalFields.toggle()
                        }
                    } label: {
                        HStack(spacing: MicaSpacing.row) {
                            Image(
                                systemName: showsAdditionalFields
                                    ? "chevron.down"
                                    : "chevron.right"
                            )
                            .micaFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)

                            Text(
                                MicaStrings.localizedKey(
                                    "routing.additional_fields",
                                    language: language
                                )
                            )
                            .micaFont(.callout, weight: .semibold)

                            Text(verbatim: additionalFields.count.formatted())
                                .micaFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Spacer(minLength: MicaSpacing.row)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MicaSpacing.section)

                    if showsAdditionalFields {
                        ProxyNodeFactList(
                            facts: additionalFields.map {
                                ProxyNodeFact(
                                    id: "reported.\($0.key)",
                                    label: $0.key,
                                    value: $0.value,
                                    monospaced: true
                                )
                            }
                        )
                        .padding(.leading, MicaSpacing.section + MicaSpacing.row)
                        .padding(.trailing, MicaSpacing.section)
                        .transition(.opacity)
                    }
                }
                .padding(.bottom, MicaSpacing.section)
            }
        }
        .background(MicaDesignTokens.elevatedFill.opacity(0.34))
        .clipShape(
            RoundedRectangle(
                cornerRadius: MicaBounds.badgeRadius,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(
                    member.isControllerSelected
                        ? MicaDesignTokens.accent
                        : availabilityTint
                )
                .frame(width: 3)
                .padding(.vertical, MicaSpacing.module)
        }
    }

    private var overviewFacts: [ProxyNodeFact] {
        var facts = [
            ProxyNodeFact(
                id: "overview.type",
                label: localized("dashboard.col_type"),
                value: detail?.type.proxyNilIfBlank ?? member.type?.proxyNilIfBlank
            ),
            ProxyNodeFact(
                id: "overview.provider",
                label: localized("routing.node_provider"),
                value: detail?.providerName?.proxyNilIfBlank
            ),
            ProxyNodeFact(
                id: "overview.interface",
                label: localized("routing.node_interface"),
                value: detail?.interfaceName?.proxyNilIfBlank,
                monospaced: true
            ),
            ProxyNodeFact(
                id: "overview.hidden",
                label: localized("routing.node_hidden"),
                value: detail?.hidden.map(localizedBoolean)
            ),
        ]

        if let rank = member.usageRank {
            facts.append(
                ProxyNodeFact(
                    id: "overview.smart-rank",
                    label: localized("routing.smart_usage"),
                    value: rank.label(language: language)
                )
            )
        }
        return facts.compactMap(\.nonEmpty)
    }

    private var transportFacts: [ProxyNodeFact] {
        (detail?.transportCapabilities ?? []).map {
            ProxyNodeFact(
                id: "transport.\($0.id)",
                label: $0.name,
                value: localizedBoolean($0.isEnabled)
            )
        }
    }

    private var testingFacts: [ProxyNodeFact] {
        let projection = ProxyMemberDetailProjection(detail: detail)
        return [
            ProxyNodeFact(
                id: "testing.latest-delay",
                label: localized("routing.current_latency"),
                value: projection.latestHistoryDelay.map(OverviewFormat.latency),
                monospaced: true
            ),
            ProxyNodeFact(
                id: "testing.latest-time",
                label: localized("routing.last_measurement"),
                value: projection.latestHistoryTime?.proxyNilIfBlank,
                monospaced: true
            ),
            ProxyNodeFact(
                id: "testing.samples",
                label: localized("routing.delay_history"),
                value: detail?.history.isEmpty == false
                    ? detail?.history.count.formatted()
                    : nil,
                monospaced: true
            ),
            ProxyNodeFact(
                id: "testing.url",
                label: localized("routing.test_url"),
                value: detail?.testURL?.proxyNilIfBlank,
                monospaced: true
            ),
        ].compactMap(\.nonEmpty)
    }

    private var additionalFields: [ProxyReportedMetadataField] {
        ProxyReportedMetadataField.fields(in: detail?.reportedMetadata ?? [:])
    }

    private var displayedDelay: Int? {
        ProxyMemberDetailProjection(detail: detail).latestHistoryDelay
            ?? member.delay
    }

    private var reportedAvailability: Bool? {
        detail?.alive ?? member.alive
    }

    private var availabilityText: String? {
        reportedAvailability.map {
            localized($0 ? "routing.node_alive" : "routing.node_unavailable")
        }
    }

    private var availabilitySymbol: String {
        reportedAvailability == false
            ? "xmark.circle.fill"
            : "checkmark.circle.fill"
    }

    private var availabilityTint: Color {
        switch reportedAvailability {
        case true: MicaDesignTokens.signalOK
        case false: MicaDesignTokens.signalError
        case nil: .secondary
        }
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }

    private func localizedBoolean(_ value: Bool) -> String {
        localized(value ? "overview.config_enabled" : "overview.config_disabled")
    }
}

private struct ProxyNodeFact: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String?
    var monospaced = false

    var nonEmpty: ProxyNodeFact? {
        guard value?.proxyNilIfBlank != nil else { return nil }
        return self
    }
}

private struct ProxyNodeFactSection: View {
    let title: String
    let systemImage: String
    let facts: [ProxyNodeFact]

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            Label(title, systemImage: systemImage)
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(MicaDesignTokens.signalInfo)

            ProxyNodeFactList(facts: facts)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ProxyNodeFactList: View {
    let facts: [ProxyNodeFact]

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: MicaSpacing.module,
            verticalSpacing: MicaSpacing.row
        ) {
            ForEach(facts) { fact in
                GridRow(alignment: .firstTextBaseline) {
                    Text(verbatim: fact.label)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(verbatim: fact.value ?? "")
                        .micaFont(
                            .callout,
                            design: fact.monospaced ? .monospaced : .default
                        )
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ProxyLatencyDistributionBucket {
    var tint: Color {
        switch kind {
        case .fast: MicaDesignTokens.signalOK
        case .normal: MicaDesignTokens.signalCyan
        case .slow: MicaDesignTokens.signalWarning
        case .timeout: MicaDesignTokens.signalError
        case .unavailable: MicaDesignTokens.separator
        }
    }
}

private extension ProxyNodeRowProjection {
    var descriptor: String? {
        let values = [
            type?.proxyNilIfBlank,
            transportNames.isEmpty ? nil : transportNames.joined(separator: " / "),
            providerName?.proxyNilIfBlank,
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "  ·  ")
    }
}

private extension String {
    var proxyNilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

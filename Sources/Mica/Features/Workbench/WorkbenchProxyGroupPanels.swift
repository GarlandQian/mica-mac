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
    let healthSummary: ProxyGroupHealthSummary
    let healthFilter: ProxyHealthFilter
    let isSwitching: Bool
    let isTesting: Bool
    let isClearingFixed: Bool
    let canClearFixed: Bool

    var id: String { occurrence.id }
}

struct ProxyPolicyGroupPanel: View {
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: ProxyExpandedGroupPresentation
    let scrollInteractionTracker: ProxyScrollInteractionTracker
    let highlightedGroupID: String?
    let highlightedMemberID: String?
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
    let onLocateCurrent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            groupHeader

            if presentation.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? nil : MicaTheme.Motion.reveal,
            value: presentation.isExpanded
        )
    }

    private var groupHeader: some View {
        VStack(spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Button(action: onToggle) {
                    HStack(spacing: MicaTheme.Spacing.space3) {
                        Image(
                            systemName: presentation.isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                            Text(verbatim: presentation.item.groupID)
                                .micaThemeFont(.body, weight: .semibold)
                                .foregroundStyle(MicaTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(verbatim: groupSubtitle)
                                .micaThemeFont(.caption)
                                .foregroundStyle(MicaTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: MicaTheme.Spacing.space4)

                        VStack(alignment: .trailing, spacing: MicaTheme.Spacing.space1) {
                            Text(
                                MicaStrings.localizedKey(
                                    "dashboard.current_node",
                                    language: language
                                )
                            )
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textSecondary)

                            HStack(spacing: MicaTheme.Spacing.space2) {
                                Text(verbatim: presentation.item.selected)
                                    .micaThemeFont(.label, weight: .semibold)
                                    .foregroundStyle(MicaTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let delay = presentation.item.selectedDelay,
                                   delay > 0 {
                                    Text(verbatim: OverviewFormat.latency(delay))
                                        .micaThemeFont(.dataCaption, weight: .semibold)
                                        .foregroundStyle(
                                            OverviewFormat.latencyTint(delay)
                                        )
                                }
                            }
                        }
                        .frame(maxWidth: 360, alignment: .trailing)
                    }
                    .padding(.leading, MicaTheme.Spacing.space3)
                    .padding(.vertical, MicaTheme.Spacing.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(presentation.item.groupID), \(presentation.item.selected)"
                )

                groupActions
                    .padding(.trailing, MicaTheme.Spacing.space2)
            }

            ProxyLatencyDistributionView(
                distribution: presentation.item.latencyDistribution
            )
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.bottom, MicaTheme.Spacing.space2)

            healthSummary
                .padding(.horizontal, MicaTheme.Spacing.space3)
                .padding(.bottom, MicaTheme.Spacing.space2)
        }
        .background(MicaTheme.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MicaTheme.Metrics.moduleRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MicaTheme.Metrics.moduleRadius,
                style: .continuous
            )
            .strokeBorder(
                MicaTheme.separator,
                lineWidth: MicaTheme.Shape.hairline
            )
        }
    }

    @ViewBuilder
    private var groupActions: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Button(action: onLocateCurrent) {
                Image(systemName: "scope")
            }
            .buttonStyle(.borderless)
            .disabled(presentation.item.selected.proxyNonBlank == nil)
            .frame(
                minWidth: MicaTheme.Metrics.iconControlSize,
                minHeight: MicaTheme.Metrics.iconControlSize
            )
            .help(
                MicaStrings.localizedKey(
                    "routing.locate_current_node",
                    language: language
                )
            )
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    "routing.locate_current_node",
                    language: language
                )
            )

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
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
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
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
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
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space3) {
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

                Spacer(minLength: MicaTheme.Spacing.space2)

                Text(
                    MicaStrings.localized(
                        "routing.member_window \(presentation.members.count) \(presentation.item.memberCount)",
                        language: language
                    )
                )
                .micaThemeFont(.dataCaption)
                .foregroundStyle(MicaTheme.textSecondary)
            }
            .padding(.horizontal, MicaTheme.Spacing.space1)

            if presentation.members.isEmpty {
                MicaEmptyState(
                    systemImage: "tray",
                    titleKey: presentation.filter.proxyNilIfBlank == nil
                        && presentation.healthFilter == .all
                        ? "routing.members_empty"
                        : presentation.healthFilter == .all
                            ? "routing.members_filtered_empty"
                            : "routing.health_filter_empty"
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 340, maximum: 460),
                            spacing: MicaTheme.Spacing.space2,
                            alignment: .top
                        ),
                    ],
                    alignment: .leading,
                    spacing: MicaTheme.Spacing.space2
                ) {
                    ForEach(presentation.members) { member in
                        ProxyPolicyNodeTile(
                            member: member,
                            scrollInteractionTracker: scrollInteractionTracker,
                            isInspected: presentation.inspectedMemberID
                                == member.id,
                            isHighlighted: highlightedGroupID == presentation.id
                                && highlightedMemberID == member.id,
                            commandsEnabled: commandsEnabled,
                            canSelect: canSelect
                                && presentation.occurrence.group.selectable,
                            canTest: canTestNode,
                            isSwitching: presentation.isSwitching,
                            isMeasuring: measuringNode?.groupID
                                == presentation.occurrence.group.id
                                && measuringNode?.nodeName == member.name,
                            onSelect: {
                                workspaceStore.selectInspector(
                                    .proxyNode(
                                        groupName: presentation.occurrence.group.id,
                                        groupOccurrenceID: presentation.id,
                                        nodeName: member.name
                                    )
                                )
                                onSelectMember(member.id)
                            },
                            onTest: { onTestMember(member.id) }
                        )
                        .id(
                            ProxyProjection.revealTargetID(
                                groupID: presentation.id,
                                memberID: member.id
                            )
                        )
                    }
                }
            }
        }
    }

    private var groupSubtitle: String {
        let availability = MicaStrings.localized(
            "routing.available_nodes_count \(presentation.item.availableMemberCount) \(presentation.item.memberCount)",
            language: language
        )
        let health = MicaStrings.localizedKey(
            presentation.healthSummary.status.titleKey,
            language: language
        )
        return "\(presentation.item.type)  ·  \(health)  ·  \(availability)"
    }

    private var healthSummary: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Circle()
                .fill(presentation.healthSummary.status.tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(
                MicaStrings.localized(
                    "routing.health_counts \(presentation.healthSummary.availableCount) \(presentation.healthSummary.unavailableCount) \(presentation.healthSummary.unknownCount) \(presentation.healthSummary.slowCount)",
                    language: language
                )
            )
            .micaThemeFont(.dataCaption)
            .foregroundStyle(MicaTheme.textSecondary)

            Spacer(minLength: MicaTheme.Spacing.space2)

            Text(
                MicaStrings.localizedKey(
                    presentation.healthSummary.status.titleKey,
                    language: language
                )
            )
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(presentation.healthSummary.status.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            MicaStrings.localized(
                "routing.health_accessibility \(presentation.item.groupID) \(presentation.healthSummary.availableCount) \(presentation.healthSummary.unavailableCount) \(presentation.healthSummary.unknownCount) \(presentation.healthSummary.slowCount)",
                language: language
            )
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false

    let member: ProxyNodeRowProjection
    let scrollInteractionTracker: ProxyScrollInteractionTracker
    let isInspected: Bool
    let isHighlighted: Bool
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
                .fill(member.isControllerSelected ? MicaTheme.accent : statusTint)
                .frame(width: 3)
                .padding(.vertical, MicaTheme.Spacing.space2)
                .accessibilityHidden(true)

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                        Text(verbatim: member.name)
                            .micaThemeFont(
                                .label,
                                weight: member.isControllerSelected
                                    ? .semibold
                                    : .regular
                            )
                            .foregroundStyle(MicaTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: MicaTheme.Spacing.space2)

                        if isMeasuring {
                            ProgressView()
                                .controlSize(.small)
                        } else if let delay = member.delay, delay > 0 {
                            Text(verbatim: OverviewFormat.latency(delay))
                                .micaThemeFont(.dataCaption, weight: .semibold)
                                .foregroundStyle(OverviewFormat.latencyTint(delay))
                        }
                    }

                    if let descriptor = member.descriptor {
                        Text(verbatim: descriptor)
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }

                    HStack(spacing: MicaTheme.Spacing.space3) {
                        if let rank = member.usageRank {
                            Text(verbatim: rank.label(language: language))
                                .micaThemeFont(.caption, weight: .semibold)
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
                            .micaThemeFont(.caption, weight: .semibold)
                            .foregroundStyle(MicaTheme.accent)
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, MicaTheme.Spacing.space3)
                .padding(.vertical, MicaTheme.Spacing.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(member.tooltip(language: language))
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
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
                )
                .padding(.trailing, MicaTheme.Spacing.space1)
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
                .accessibilityLabel(
                    MicaStrings.localized(
                        "routing.test_node \(member.name)",
                        language: language
                    )
                )
                .accessibilityHint(
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
                cornerRadius: MicaTheme.Metrics.badgeRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MicaTheme.Metrics.badgeRadius,
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
            reduceMotion || scrollInteractionTracker.isScrolling
                ? nil
                : MicaTheme.Motion.press,
            value: isHovered || isHighlighted
        )
    }

    private var tileFill: Color {
        if isHighlighted {
            return MicaTheme.accent.opacity(0.2)
        }
        if member.isControllerSelected {
            return MicaTheme.accent.opacity(0.14)
        }
        if isInspected {
            return MicaTheme.accent.opacity(0.14)
        }
        if isHovered {
            return MicaTheme.surfaceRaised
        }
        return MicaTheme.surface
    }

    private var tileStroke: Color {
        if isHighlighted {
            return MicaTheme.accent
        }
        if member.isControllerSelected {
            return MicaTheme.accent
        }
        if isInspected {
            return MicaTheme.accent.opacity(0.5)
        }
        if isHovered {
            return MicaTheme.separator
        }
        return .clear
    }

    private var statusTint: Color {
        switch member.health {
        case .healthy: MicaTheme.statusOK
        case .degraded: MicaTheme.statusWarning
        case .unavailable: MicaTheme.statusError
        case .unknown: MicaTheme.textTertiary
        }
    }

    private func usageTint(_ rank: PolicyGroupUsageRank) -> Color {
        switch rank {
        case .mostUsed: MicaTheme.accent
        case .occasionallyUsed: MicaTheme.textSecondary
        case .rarelyUsed, .reported: MicaTheme.textTertiary
        }
    }
}

private extension ProxyLatencyDistributionBucket {
    /// Latency health semantics match `OverviewFormat.latencyTint`: fast/normal
    /// are healthy, slow warns, timeout errors, unmeasured stays neutral.
    var tint: Color {
        switch kind {
        case .fast, .normal: MicaTheme.statusOK
        case .slow: MicaTheme.statusWarning
        case .timeout: MicaTheme.statusError
        case .unavailable: MicaTheme.textTertiary
        }
    }
}

private extension ProxyGroupHealthSummary.Status {
    var titleKey: String {
        switch self {
        case .healthy: "routing.health_healthy"
        case .degraded: "routing.health_degraded"
        case .failed: "routing.health_failed"
        case .unknown: "routing.health_unknown"
        }
    }

    var tint: Color {
        switch self {
        case .healthy: MicaTheme.statusOK
        case .degraded: MicaTheme.statusWarning
        case .failed: MicaTheme.statusError
        case .unknown: MicaTheme.textTertiary
        }
    }
}

private extension ProxyNodeHealthState {
    var titleKey: String {
        switch self {
        case .healthy: "routing.health_healthy"
        case .degraded: "routing.health_degraded"
        case .unavailable: "routing.health_unavailable"
        case .unknown: "routing.health_unknown"
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

    func tooltip(language: AppLanguage) -> String {
        let status = MicaStrings.localizedKey(
            health.titleKey,
            language: language
        )
        let latency = delay.flatMap { delay in
            delay > 0 ? OverviewFormat.latency(delay) : nil
        }
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
        let values = [name, status, latency]
            + [descriptor].compactMap { $0 }
        return values.joined(separator: "  ·  ")
    }
}

private extension String {
    var proxyNilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

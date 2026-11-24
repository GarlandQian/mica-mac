import AppKit
import Foundation
import MicaCore
import SwiftUI

struct ProxyActiveGroupPresentation: Identifiable, Equatable {
    let occurrence: ProxyGroupOccurrence
    let item: ProxyGroupDirectoryItem
    let members: [ProxyNodeRowProjection]
    let filter: String
    let inspectedMemberID: String?
    let healthSummary: ProxyGroupHealthSummary
    let healthFilter: ProxyHealthFilter
    let isSwitching: Bool
    let isTesting: Bool
    let isClearingFixed: Bool
    let canClearFixed: Bool

    var id: String { occurrence.id }
}

struct ProxyBoundedAccessibilityCatalog: View {
    @Environment(\.micaAppLanguage) private var language

    let index: ProxyAccessibilityIndex
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let selectedElementID: String?
    let activeGroupID: String?
    let inspectedMemberID: String?
    let commandsEnabled: Bool
    let canSelectMember: Bool
    let canTestGroup: Bool
    let canTestNode: Bool
    let canClearFixedSelection: Bool
    let activity: ProxyOperationActivity
    let onActivateGroup: (String, LiveCommandScope) -> Void
    let onLocateCurrent: (String, LiveCommandScope) -> Void
    let onTestGroup: (String, LiveCommandScope) -> Void
    let onClearFixed: (String, LiveCommandScope) -> Void
    let onSelectMember: (String, String, LiveCommandScope) -> Void
    let onInspectMember: (String, String, LiveCommandScope) -> Void
    let onTestMember: (String, String, LiveCommandScope) -> Void

    @State private var cursor = WorkbenchAccessibilityWindowCursor()

    var body: some View {
        let localization = MicaStrings.localizationContext(for: language)
        let window = currentWindow

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            WorkbenchAccessibilityPageControls(
                window: window,
                moveToLowerBound: move(to:)
            )

            ForEach(index.elements(in: window.range)) { element in
                elementRow(element, localization: localization)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey("routing.group_catalog", language: language)
        )
        .onAppear {
            reconcile(revealing: selectedElementID)
        }
        .onChange(of: controllerID) { _, _ in
            resetForSession()
        }
        .onChange(of: generation) { _, _ in
            resetForSession()
        }
        .onChange(of: index.orderedIDs) { _, _ in
            reconcile(revealing: nil)
        }
        .onChange(of: selectedElementID) { _, selectedElementID in
            guard let selectedElementID else { return }
            reconcile(revealing: selectedElementID)
        }
    }

    private var currentWindow: WorkbenchAccessibilityWindow {
        WorkbenchAccessibilityWindow.resolve(
            totalCount: index.totalCount,
            preferredLowerBound: cursor.lowerBound
        )
    }

    @ViewBuilder
    private func elementRow(
        _ element: ProxyAccessibilityIndex.Element,
        localization: MicaStrings.LocalizationContext
    ) -> some View {
        switch element {
        case .group(let group):
            groupRow(group, localization: localization)
        case .member(let member):
            memberRow(member, localization: localization)
        }
    }

    private func groupRow(
        _ group: ProxyAccessibilityIndex.GroupElement,
        localization: MicaStrings.LocalizationContext
    ) -> some View {
        let groupID = group.occurrence.id
        let reportedGroupID = group.occurrence.group.id
        let isSwitching = activity.isSwitching(groupID: reportedGroupID)
        let isTesting = activity.isTesting(groupID: reportedGroupID)
        let isClearing = activity.clearingFixedGroupID == reportedGroupID
        let canLocate = group.item.selected.proxyNonBlank != nil
        let canRunTest = canTestGroup
            && commandsEnabled
            && !isSwitching
            && !isTesting
            && !isClearing
        let canClear = canClearFixedSelection
            && group.item.hasFixedSelection
            && commandsEnabled
            && !isSwitching
            && !isTesting
            && !isClearing

        return Button {
            guard let commandScope else { return }
            onActivateGroup(groupID, commandScope)
        } label: {
            Text(verbatim: groupSummary(group, localization: localization))
        }
        .accessibilityAddTraits(activeGroupID == groupID ? .isSelected : [])
        .accessibilityHint(
            localization.localizedKey(
                "routing.open_group"
            )
        )
        .accessibilityActions {
            if canLocate {
                Button(localization.localizedKey("routing.locate_current_node")) {
                    guard let commandScope else { return }
                    onLocateCurrent(groupID, commandScope)
                }
            }
            if canRunTest {
                Button(localization.localizedKey("routing.test_group")) {
                    guard let commandScope else { return }
                    onTestGroup(groupID, commandScope)
                }
            }
            if canClear {
                Button(localization.localizedKey("routing.clear_fixed_selection")) {
                    guard let commandScope else { return }
                    onClearFixed(groupID, commandScope)
                }
            }
        }
    }

    private func memberRow(
        _ element: ProxyAccessibilityIndex.MemberElement,
        localization: MicaStrings.LocalizationContext
    ) -> some View {
        let member = element.member
        let isSwitching = activity.isSwitching(groupID: element.groupName)
        let isMeasuring = activity.isMeasuring(
            groupID: element.groupName,
            nodeName: member.name
        )
        let isClearing = activity.clearingFixedGroupID == element.groupName
        let canRunTest = canTestNode
            && commandsEnabled
            && !isSwitching
            && !isMeasuring
            && !isClearing
        let canSwitch = canSelectMember
            && element.groupSelectable
            && commandsEnabled
            && !isSwitching
            && !isClearing
            && !member.isControllerSelected

        return Button {
            guard let commandScope else { return }
            onInspectMember(
                element.groupOccurrenceID,
                member.id,
                commandScope
            )
        } label: {
            Text(verbatim: memberSummary(element, localization: localization))
        }
        .accessibilityAddTraits(
            inspectedMemberID == member.id
                ? .isSelected
                : []
        )
        .accessibilityHint(
            localization.localized("routing.inspect_node %@", arguments: [member.name])
        )
        .accessibilityActions {
            if canSwitch {
                Button(
                    localization.localized("routing.use_node %@", arguments: [member.name])
                ) {
                    guard let commandScope else { return }
                    onSelectMember(element.groupOccurrenceID, member.id, commandScope)
                }
            }
            if canRunTest {
                Button(
                    localization.localized(
                        "routing.test_node %@",
                        arguments: [member.name]
                    )
                ) {
                    guard let commandScope else { return }
                    onTestMember(
                        element.groupOccurrenceID,
                        member.id,
                        commandScope
                    )
                }
            }
        }
    }

    private var commandScope: LiveCommandScope? {
        LiveCommandScope(controllerID: controllerID, generation: generation)
    }

    private func groupSummary(
        _ group: ProxyAccessibilityIndex.GroupElement,
        localization: MicaStrings.LocalizationContext
    ) -> String {
        let health = localization.localizedKey(group.item.health.status.titleKey)
        let availability = localization.localized(
            "routing.available_nodes_count %lld %lld",
            arguments: [
                String(group.item.availableMemberCount),
                String(group.item.memberCount),
            ]
        )
        let counts = localization.localized(
            "routing.health_counts %lld %lld %lld %lld",
            arguments: [
                String(group.item.health.availableCount),
                String(group.item.health.unavailableCount),
                String(group.item.health.unknownCount),
                String(group.item.health.slowCount),
            ]
        )
        let current = localization.localized(
            "format.label_value %@ %@",
            arguments: [
                localization.localizedKey("dashboard.current_node"),
                group.item.selected,
            ]
        )
        return [
            group.item.groupID,
            group.item.type,
            current,
            health,
            availability,
            counts,
        ].joined(separator: "  ·  ")
    }

    private func memberSummary(
        _ element: ProxyAccessibilityIndex.MemberElement,
        localization: MicaStrings.LocalizationContext
    ) -> String {
        let member = element.member
        let health = localization.localizedKey(member.health.titleKey)
        let latency = member.delay.flatMap { delay in
            delay > 0 ? OverviewFormat.latency(delay) : nil
        } ?? localization.localizedKey("overview.config_not_reported")
        var values = [element.groupName, member.name, health, latency]
        if let descriptor = member.descriptor {
            values.append(descriptor)
        }
        if let usageRank = member.usageRank {
            values.append(usageRank.label(language: language))
        }
        if member.isControllerSelected {
            values.append(localization.localizedKey("dashboard.inspector_current"))
        }
        return values.joined(separator: "  ·  ")
    }

    private func move(to lowerBound: Int) {
        cursor.move(
            to: lowerBound,
            totalCount: index.totalCount,
            idAt: index.id(at:)
        )
    }

    private func reconcile(revealing selectedElementID: String?) {
        cursor.reconcile(
            totalCount: index.totalCount,
            revealing: selectedElementID,
            indexOf: index.index(of:),
            idAt: index.id(at:)
        )
    }

    private func resetForSession() {
        cursor.reset()
        reconcile(revealing: selectedElementID)
    }
}

struct ProxyPolicyGroupDirectoryRow: View {
    @State private var isHovered = false
    let item: ProxyGroupDirectoryItem
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)

        Button(action: onActivate) {
            HStack(spacing: 0) {
                Capsule(style: .continuous)
                    .fill(isActive ? MicaTheme.accent : .clear)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: MicaTheme.Spacing.space1 + 2) {
                        Circle()
                            .fill(item.health.status.tint)
                            .frame(width: 6, height: 6)
                        Text(verbatim: item.groupID)
                            .micaThemeFont(.label, weight: isActive ? .semibold : .regular)
                            .foregroundStyle(MicaTheme.textPrimary)
                            .lineLimit(1)
                        if item.hasFixedSelection {
                            Image(systemName: "pin.fill")
                                .micaThemeFont(.caption, weight: .semibold)
                                .foregroundStyle(MicaTheme.accent)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: "\(item.availableMemberCount)/\(item.memberCount)")
                            .micaThemeFont(.dataCaption)
                            .foregroundStyle(MicaTheme.textTertiary)
                    }
                    HStack(spacing: MicaTheme.Spacing.space1 + 2) {
                        Text(verbatim: item.selected)
                            .micaThemeFont(.caption)
                            .foregroundStyle(isActive ? MicaTheme.accent : MicaTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let delay = item.selectedDelay, delay > 0 {
                            Text(verbatim: OverviewFormat.latency(delay))
                                .micaThemeFont(.dataCaption, weight: .medium)
                                .foregroundStyle(OverviewFormat.latencyTint(delay))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        } else if let type = item.type.proxyNonBlank {
                            Text(verbatim: type)
                                .micaThemeFont(.caption)
                                .foregroundStyle(MicaTheme.textTertiary)
                                .lineLimit(1)
                                .layoutPriority(-1)
                        }
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, MicaTheme.Spacing.space2)
                .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive
                    ? (isHovered ? MicaTheme.accent.opacity(0.16) : MicaTheme.accent.opacity(0.12))
                    : (isHovered ? MicaTheme.surfaceHover : .clear),
                in: shape
            )
            .contentShape(shape)
            .padding(.horizontal, MicaTheme.Spacing.space1 + 2)
            .opacity(item.hidden ? 0.68 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("proxy-directory:\(item.id)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(helpText)
    }

    private var helpText: String {
        [
            item.groupID,
            item.type.proxyNonBlank,
            item.selected.proxyNonBlank,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct ProxyPolicyActiveGroupHeader: View {
    @Environment(\.micaAppLanguage) private var language
    let presentation: ProxyActiveGroupPresentation
    let commandsEnabled: Bool
    let canTestGroup: Bool
    let onTestGroup: () -> Void
    let onClearFixed: () -> Void
    let onLocateCurrent: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MicaTheme.Spacing.space3) {
                identity
                Spacer(minLength: 4)
                actions
            }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                identity
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MicaTheme.Spacing.space3)
        .background(MicaTheme.surface)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Text(verbatim: presentation.item.groupID)
                    .micaThemeFont(.body, weight: .semibold)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)
                if let type = presentation.item.type.proxyNonBlank {
                    Text(verbatim: type)
                        .micaThemeFont(.caption, weight: .medium)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(MicaTheme.surfaceSecondary, in: Capsule())
                        .lineLimit(1)
                }
                Text(verbatim: "\(presentation.healthSummary.availableCount)/\(presentation.item.memberCount)")
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(MicaTheme.textTertiary)
            }
            HStack(spacing: 5) {
                Image(systemName: presentation.item.hasFixedSelection ? "pin.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(MicaTheme.accent)
                Text(verbatim: presentation.item.selected)
                    .lineLimit(1)
                if let delay = presentation.item.selectedDelay, delay > 0 {
                    Text(verbatim: OverviewFormat.latency(delay))
                        .micaThemeFont(.dataCaption, weight: .semibold)
                        .foregroundStyle(OverviewFormat.latencyTint(delay))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .micaThemeFont(.caption)
            .foregroundStyle(MicaTheme.textSecondary)

            if presentation.healthSummary.memberCount > 0 {
                ProxyGroupHealthStrip(summary: presentation.healthSummary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Button(action: onLocateCurrent) {
                Image(systemName: "scope")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .help(MicaStrings.localizedKey("routing.locate_current_node", language: language))
            .accessibilityLabel(MicaStrings.localizedKey("routing.locate_current_node", language: language))
            .disabled(presentation.item.selected.proxyNonBlank == nil)
            if canTestGroup || presentation.isTesting {
                Button(action: onTestGroup) {
                    HStack(spacing: 5) {
                        if presentation.isTesting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "bolt")
                        }
                        Text(MicaStrings.localizedKey("routing.test_group", language: language))
                    }
                }
                // The group's primary command reads as a button, not quiet text.
                .buttonStyle(.bordered)
                .disabled(!commandsEnabled || !canTestGroup || presentation.isTesting
                    || presentation.isSwitching || presentation.isClearingFixed)
            }
            if presentation.canClearFixed || presentation.isClearingFixed {
                Button(action: onClearFixed) {
                    if presentation.isClearingFixed {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(minWidth: 28, minHeight: 28)
                    } else {
                        Image(systemName: "pin.slash")
                            .frame(minWidth: 28, minHeight: 28)
                    }
                }
                .help(MicaStrings.localizedKey("routing.clear_fixed_selection", language: language))
                .accessibilityLabel(MicaStrings.localizedKey("routing.clear_fixed_selection", language: language))
                .disabled(!commandsEnabled || !presentation.canClearFixed
                    || presentation.isClearingFixed || presentation.isSwitching || presentation.isTesting)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct ProxyGroupHealthStrip: View {
    let summary: ProxyGroupHealthSummary

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            GeometryReader { geometry in
                let totalWidth = max(0, geometry.size.width)
                let totalCount = max(1, summary.memberCount)
                let buckets = summary.latencyDistribution.buckets
                HStack(spacing: 1) {
                    ForEach(buckets) { bucket in
                        let width = max(2, totalWidth * CGFloat(bucket.count) / CGFloat(totalCount))
                        Rectangle()
                            .fill(color(for: bucket.kind))
                            .frame(width: width)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MicaTheme.surfaceSecondary)
                .clipShape(Capsule())
            }
            .frame(maxWidth: 168, minHeight: 4, maxHeight: 4)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                if summary.availableCount > 0 {
                    Label {
                        Text(verbatim: summary.availableCount.formatted())
                    } icon: {
                        Circle()
                            .fill(MicaTheme.statusOK)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(MicaTheme.textSecondary)
                }
                if summary.slowCount > 0 {
                    Label {
                        Text(verbatim: summary.slowCount.formatted())
                    } icon: {
                        Circle()
                            .fill(MicaTheme.statusWarning)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(MicaTheme.textSecondary)
                }
                if summary.unavailableCount > 0 {
                    Label {
                        Text(verbatim: summary.unavailableCount.formatted())
                    } icon: {
                        Circle()
                            .fill(MicaTheme.statusError)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(MicaTheme.textSecondary)
                }
            }
            .micaThemeFont(.dataCaption)
            .labelStyle(.titleAndIcon)
        }
    }

    private func color(for kind: ProxyLatencyDistributionBucket.Kind) -> Color {
        switch kind {
        case .fast: MicaTheme.statusOK
        case .normal: MicaTheme.Chart.download
        case .slow: MicaTheme.statusWarning
        case .timeout, .unavailable: MicaTheme.statusError.opacity(0.65)
        }
    }
}

struct ProxyPolicyNodeTile: View {
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
    var isClearingFixed: Bool = false
    let onSelect: () -> Void
    let onInspect: () -> Void
    let onTest: () -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil

    private var hasSecondaryMetadata: Bool {
        member.descriptor != nil || member.usageRank != nil || member.isControllerSelected
    }

    var body: some View {
        HStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(member.isControllerSelected ? MicaTheme.accent : statusTint)
                .frame(width: 3)
                .padding(.vertical, MicaTheme.Spacing.space2)
                .accessibilityHidden(true)

            Button(action: onInspect) {
                VStack(alignment: .leading, spacing: hasSecondaryMetadata ? MicaTheme.Spacing.space1 : 0) {
                    HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                        Image(systemName: isInspected ? "chevron.down" : "chevron.right")
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textTertiary)
                            .frame(width: 12, alignment: .center)
                            .accessibilityHidden(true)
                        Text(verbatim: member.name)
                            .micaThemeFont(
                                .label,
                                weight: member.isControllerSelected ? .semibold : .regular
                            )
                            .foregroundStyle(MicaTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: MicaTheme.Spacing.space2)

                        latencyView
                    }

                    if hasSecondaryMetadata {
                        HStack(spacing: MicaTheme.Spacing.space2) {
                            if let descriptor = member.descriptor {
                                Text(verbatim: descriptor)
                                    .micaThemeFont(.caption)
                                    .foregroundStyle(MicaTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            if let rank = member.usageRank {
                                Text(verbatim: rank.label(language: language))
                                    .micaThemeFont(.caption, weight: .semibold)
                                    .foregroundStyle(usageTint(rank))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            if member.isControllerSelected {
                                Text(
                                    MicaStrings.localizedKey(
                                        "dashboard.inspector_current",
                                        language: language
                                    )
                                )
                                .micaThemeFont(.caption, weight: .semibold)
                                .foregroundStyle(MicaTheme.accent)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.leading, 18)
                    }
                }
                .padding(.horizontal, MicaTheme.Spacing.space3)
                .padding(.vertical, MicaTheme.Spacing.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isInspected ? .isSelected : [])
            .accessibilityIdentifier("proxy-node-inspect:\(member.id)")
            .accessibilityLabel(inspectAccessibilityLabel)
            .accessibilityHint(
                MicaStrings.localized("routing.inspect_node \(member.name)", language: language)
            )

            if canSelect {
                Button(action: onSelect) {
                    Image(systemName: member.isControllerSelected
                        ? "checkmark.circle.fill" : "arrow.right.circle")
                        .foregroundStyle(member.isControllerSelected
                            ? MicaTheme.accent : MicaTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(!commandsEnabled || isSwitching || isClearingFixed || member.isControllerSelected)
                .frame(
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
                )
                .help(switchHelpText)
                .accessibilityLabel(switchHelpText)
                .accessibilityIdentifier("proxy-node-select:\(member.id)")
            }

            if canTest || isMeasuring {
                Button(action: onTest) {
                    Image(systemName: "bolt")
                }
                .buttonStyle(.borderless)
                .disabled(!canTest || !commandsEnabled || isMeasuring || isSwitching || isClearingFixed)
                .frame(
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
                )
                .padding(.trailing, MicaTheme.Spacing.space1)
                .opacity(
                    (isHovered && !scrollInteractionTracker.isNodesScrolling) || isInspected || isMeasuring
                        ? 1
                        : 0.78
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
                .accessibilityIdentifier("proxy-node-test:\(member.id)")
                .accessibilityHint(
                    MicaStrings.localized(
                        "routing.help_test_node \(member.name)",
                        language: language
                    )
                )
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .background(tileFill)
        .clipShape(tileShape)
        .overlay {
            tileShape.strokeBorder(tileStroke, lineWidth: 1)
        }
        .contextMenu {
            if canSelect && !member.isControllerSelected {
                Button(action: onSelect) {
                    Label(
                        MicaStrings.localized("routing.use_node \(member.name)", language: language),
                        systemImage: "arrow.right.circle"
                    )
                }
                .disabled(!commandsEnabled || isSwitching || isClearingFixed)
            }
            if canTest {
                Button(action: onTest) {
                    Label(
                        MicaStrings.localized("routing.test_node \(member.name)", language: language),
                        systemImage: "bolt"
                    )
                }
                .disabled(!commandsEnabled || isMeasuring || isSwitching || isClearingFixed)
            }
            Button(action: onInspect) {
                Label(
                    MicaStrings.localizedKey(
                        isInspected ? "routing.collapse_details" : "routing.inspect_details",
                        language: language
                    ),
                    systemImage: isInspected ? "chevron.up" : "info.circle"
                )
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(member.name, forType: .string)
            } label: {
                Label(
                    MicaStrings.localizedKey("action.copy_name", language: language),
                    systemImage: "doc.on.doc"
                )
            }
        }
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            onHoverChanged?(hovering)
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                onHoverChanged?(false)
            }
        }
        .anchorPreference(key: ProxyNodePreviewAnchorKey.self, value: .bounds) {
            isHovered && !scrollInteractionTracker.isNodesScrolling ? [member.id: $0] : [:]
        }
        .animation(
            reduceMotion || scrollInteractionTracker.isNodesScrolling
                ? nil
                : MicaTheme.Motion.press,
            value: isHovered || isHighlighted
        )
    }

    @ViewBuilder
    private var latencyView: some View {
        if isMeasuring {
            ProgressView()
                .controlSize(.small)
        } else if member.health == .unavailable {
            Text(
                MicaStrings.localizedKey(
                    "routing.health_unavailable",
                    language: language
                )
            )
            .micaThemeFont(.caption, weight: .medium)
            .foregroundStyle(MicaTheme.statusError)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        } else if let delay = member.delay, delay > 0 {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: OverviewFormat.latency(delay))
                    .micaThemeFont(.dataCaption, weight: .semibold)
                    .foregroundStyle(OverviewFormat.latencyTint(delay))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let fraction = member.latencyFraction {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MicaTheme.surfaceSecondary)
                        Capsule()
                            .fill(OverviewFormat.latencyTint(delay))
                            .frame(width: max(3, 38 * CGFloat(fraction)))
                    }
                    .frame(width: 38, height: 2)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var switchHelpText: String {
        if member.isControllerSelected {
            return MicaStrings.localizedKey("dashboard.inspector_current", language: language)
        }
        return MicaStrings.localized("routing.use_node \(member.name)", language: language)
    }

    private var inspectAccessibilityLabel: String {
        var parts = [member.name]
        if member.health == .unavailable {
            parts.append(MicaStrings.localizedKey("routing.health_unavailable", language: language))
        } else if let delay = member.delay, delay > 0 {
            parts.append(OverviewFormat.latency(delay))
        }
        if member.isControllerSelected {
            parts.append(MicaStrings.localizedKey("dashboard.inspector_current", language: language))
        }
        return parts.joined(separator: ", ")
    }

    /// An opened tile is the header of its detail card, so only its top
    /// corners round; `ProxyInspectedNodeFrame` outlines the whole card.
    private var tileShape: UnevenRoundedRectangle {
        let radius = MicaTheme.Shape.rowRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: isInspected ? 0 : radius,
            bottomTrailingRadius: isInspected ? 0 : radius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    private var isActiveHovered: Bool {
        isHovered && !scrollInteractionTracker.isNodesScrolling
    }

    private var tileFill: Color {
        if isHighlighted {
            return MicaTheme.accent.opacity(0.20)
        }
        if isInspected {
            return isActiveHovered ? MicaTheme.accent.opacity(0.16) : MicaTheme.accent.opacity(0.12)
        }
        if member.isControllerSelected {
            return isActiveHovered ? MicaTheme.accent.opacity(0.13) : MicaTheme.accent.opacity(0.08)
        }
        if isActiveHovered {
            return MicaTheme.surfaceHover
        }
        return MicaTheme.surface
    }

    private var tileStroke: Color {
        if isHighlighted && !isInspected {
            return MicaTheme.accent
        }
        if isActiveHovered && !isInspected {
            return MicaTheme.surfaceBorder
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

struct ProxyPolicyNodeGridCard: View {
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
    var isClearingFixed: Bool = false
    let onSelect: () -> Void
    let onInspect: () -> Void
    let onTest: () -> Void

    private var isActiveHovered: Bool {
        isHovered && !scrollInteractionTracker.isNodesScrolling
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                Circle()
                    .fill(member.isControllerSelected ? MicaTheme.accent : statusTint)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(verbatim: member.name)
                    .micaThemeFont(.label, weight: member.isControllerSelected ? .semibold : .medium)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isMeasuring {
                    ProgressView()
                        .controlSize(.small)
                } else if member.health == .unavailable {
                    Text(MicaStrings.localizedKey("routing.health_unavailable", language: language))
                        .micaThemeFont(.dataCaption, weight: .medium)
                        .foregroundStyle(MicaTheme.statusError)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else if let delay = member.delay, delay > 0 {
                    Text(verbatim: OverviewFormat.latency(delay))
                        .micaThemeFont(.dataCaption, weight: .semibold)
                        .foregroundStyle(OverviewFormat.latencyTint(delay))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: MicaTheme.Spacing.space1) {
                if let descriptor = member.descriptor {
                    Text(verbatim: descriptor)
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .lineLimit(1)
                } else if member.isControllerSelected {
                    Text(MicaStrings.localizedKey("dashboard.inspector_current", language: language))
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.accent)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if canSelect {
                    Button(action: onSelect) {
                        Image(systemName: member.isControllerSelected ? "checkmark.circle.fill" : "arrow.right.circle")
                            .foregroundStyle(member.isControllerSelected ? MicaTheme.accent : MicaTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!commandsEnabled || isSwitching || isClearingFixed || member.isControllerSelected)
                }
                if canTest || isMeasuring {
                    Button(action: onTest) {
                        Image(systemName: "bolt")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canTest || !commandsEnabled || isMeasuring || isSwitching || isClearingFixed)
                    .opacity(isActiveHovered || isInspected ? 1 : 0.75)
                }
            }

            if let delay = member.delay, delay > 0, member.health != .unavailable, let fraction = member.latencyFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MicaTheme.surfaceSecondary)
                        Capsule()
                            .fill(OverviewFormat.latencyTint(delay))
                            .frame(width: max(4, geometry.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 2)
                .accessibilityHidden(true)
            }
        }
        .padding(MicaTheme.Spacing.space3)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(cardFill, in: shape)
        .overlay {
            shape.strokeBorder(cardBorder, lineWidth: isInspected || isHighlighted ? 1.5 : 1)
        }
        .contentShape(shape)
        .onTapGesture(perform: onInspect)
        .onHover { isHovered = $0 }
        .contextMenu {
            if canSelect && !member.isControllerSelected {
                Button(action: onSelect) {
                    Label(
                        MicaStrings.localized("routing.use_node \(member.name)", language: language),
                        systemImage: "arrow.right.circle"
                    )
                }
                .disabled(!commandsEnabled || isSwitching || isClearingFixed)
            }
            if canTest {
                Button(action: onTest) {
                    Label(
                        MicaStrings.localized("routing.test_node \(member.name)", language: language),
                        systemImage: "bolt"
                    )
                }
                .disabled(!commandsEnabled || isMeasuring || isSwitching || isClearingFixed)
            }
            Button(action: onInspect) {
                Label(
                    MicaStrings.localizedKey(
                        isInspected ? "routing.collapse_details" : "routing.inspect_details",
                        language: language
                    ),
                    systemImage: isInspected ? "chevron.up" : "info.circle"
                )
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(member.name, forType: .string)
            } label: {
                Label(
                    MicaStrings.localizedKey("action.copy_name", language: language),
                    systemImage: "doc.on.doc"
                )
            }
        }
        .animation(
            reduceMotion || scrollInteractionTracker.isNodesScrolling ? nil : MicaTheme.Motion.press,
            value: isHovered || isHighlighted || isInspected
        )
    }

    private var cardFill: Color {
        if isHighlighted { return MicaTheme.accent.opacity(0.18) }
        if isInspected { return MicaTheme.surfaceElevated }
        if member.isControllerSelected { return isActiveHovered ? MicaTheme.accent.opacity(0.12) : MicaTheme.accent.opacity(0.08) }
        return isActiveHovered ? MicaTheme.surfaceHover : MicaTheme.surface
    }

    private var cardBorder: Color {
        if isHighlighted || isInspected { return MicaTheme.accent.opacity(0.65) }
        if member.isControllerSelected { return MicaTheme.accent.opacity(0.32) }
        return isActiveHovered ? MicaTheme.surfaceBorderStrong : MicaTheme.surfaceBorder
    }

    private var statusTint: Color {
        switch member.health {
        case .healthy: MicaTheme.statusOK
        case .degraded: MicaTheme.statusWarning
        case .unavailable: MicaTheme.statusError
        case .unknown: MicaTheme.textTertiary
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

extension ProxyNodeRowProjection {
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

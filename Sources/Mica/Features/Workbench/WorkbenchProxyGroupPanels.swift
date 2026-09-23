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
        let canRunTest = canTestNode
            && commandsEnabled
            && !isSwitching
            && !isMeasuring
        let canSwitch = canSelectMember
            && element.groupSelectable
            && commandsEnabled
            && !isSwitching
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
        let current = "\(localization.localizedKey("dashboard.current_node")): \(group.item.selected)"
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
    @Environment(\.micaAppLanguage) private var language
    let item: ProxyGroupDirectoryItem
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    Circle()
                        .fill(item.health.status.tint)
                        .frame(width: 6, height: 6)
                    Text(verbatim: item.groupID)
                        .micaThemeFont(.label, weight: isActive ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: item.memberCount.formatted())
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(MicaTheme.textTertiary)
                }
                Text(verbatim: item.selected)
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 14)
            }
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.vertical, MicaTheme.Spacing.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? MicaTheme.accent.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proxy-directory:\(item.id)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help("\(item.groupID) · \(item.type) · \(item.selected)")
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
        }
        .padding(MicaTheme.Spacing.space3)
        .background(MicaTheme.surface)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Text(verbatim: presentation.item.groupID)
                    .micaThemeFont(.body, weight: .semibold)
                    .lineLimit(1)
                Text(verbatim: presentation.item.type)
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                Text(verbatim: presentation.item.memberCount.formatted())
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(MicaTheme.textTertiary)
            }
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MicaTheme.accent)
                Text(verbatim: presentation.item.selected)
                    .lineLimit(1)
                if let delay = presentation.item.selectedDelay, delay > 0 {
                    Text(verbatim: OverviewFormat.latency(delay))
                        .foregroundStyle(OverviewFormat.latencyTint(delay))
                }
            }
            .micaThemeFont(.caption)
            .foregroundStyle(MicaTheme.textSecondary)
        }
    }

    private var actions: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Button(action: onLocateCurrent) {
                Image(systemName: "scope")
            }
            .help(MicaStrings.localizedKey("routing.locate_current_node", language: language))
            .accessibilityLabel(MicaStrings.localizedKey("routing.locate_current_node", language: language))
            .disabled(presentation.item.selected.proxyNonBlank == nil)
            if canTestGroup || presentation.isTesting {
                Button(action: onTestGroup) {
                    Label(MicaStrings.localizedKey("routing.test_group", language: language),
                          systemImage: presentation.isTesting ? "hourglass" : "bolt")
                }
                .disabled(!commandsEnabled || !canTestGroup || presentation.isTesting
                    || presentation.isSwitching || presentation.isClearingFixed)
            }
            if presentation.canClearFixed || presentation.isClearingFixed {
                Button(action: onClearFixed) {
                    Image(systemName: "pin.slash")
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
    let onSelect: () -> Void
    let onInspect: () -> Void
    let onTest: () -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(member.isControllerSelected ? MicaTheme.accent : statusTint)
                .frame(width: 3)
                .padding(.vertical, MicaTheme.Spacing.space2)
                .accessibilityHidden(true)

            Button(action: onInspect) {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                        Image(systemName: isInspected ? "chevron.down" : "chevron.right")
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textTertiary)
                            .accessibilityHidden(true)
                        Text(verbatim: member.name)
                            .micaThemeFont(
                                .label,
                                weight: member.isControllerSelected
                                    ? .semibold
                                    : .regular
                            )
                            .foregroundStyle(MicaTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: MicaTheme.Spacing.space2)

                        if isMeasuring {
                            ProgressView()
                                .controlSize(.small)
                        } else if let delay = member.delay, delay > 0 {
                            Text(verbatim: OverviewFormat.latency(delay))
                                .micaThemeFont(.dataCaption, weight: .semibold)
                                .foregroundStyle(OverviewFormat.latencyTint(delay))
                        } else if member.health == .unavailable {
                            Text(
                                MicaStrings.localizedKey(
                                    "routing.health_unavailable",
                                    language: language
                                )
                            )
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.statusError)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }

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
                        }
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
            .accessibilityLabel(
                MicaStrings.localized(
                    "routing.inspect_node \(member.name)",
                    language: language
                )
            )

            if canSelect {
                Button(action: onSelect) {
                    Image(systemName: member.isControllerSelected
                        ? "checkmark.circle.fill" : "arrow.right.circle")
                        .foregroundStyle(member.isControllerSelected
                            ? MicaTheme.accent : MicaTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .disabled(!commandsEnabled || isSwitching || member.isControllerSelected)
                .frame(
                    minWidth: MicaTheme.Metrics.iconControlSize,
                    minHeight: MicaTheme.Metrics.iconControlSize
                )
                .help(MicaStrings.localized("routing.use_node \(member.name)", language: language))
                .accessibilityLabel(
                    MicaStrings.localized("routing.use_node \(member.name)", language: language)
                )
                .accessibilityIdentifier("proxy-node-select:\(member.id)")
            }

            if canTest || isMeasuring {
                Button(action: onTest) {
                    Image(systemName: "bolt")
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
                    (isHovered && !scrollInteractionTracker.isScrolling) || isInspected || isMeasuring
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
                .accessibilityIdentifier("proxy-node-test:\(member.id)")
                .accessibilityHint(
                    MicaStrings.localized(
                        "routing.help_test_node \(member.name)",
                        language: language
                    )
                )
            }
        }
        .frame(minHeight: 48, alignment: .leading)
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
                lineWidth: 1
            )
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
            return MicaTheme.accent.opacity(0.09)
        }
        if isInspected {
            return MicaTheme.accent.opacity(0.14)
        }
        if isHovered && !scrollInteractionTracker.isScrolling {
            return MicaTheme.surfaceRaised
        }
        return MicaTheme.surface
    }

    private var tileStroke: Color {
        if isHighlighted {
            return MicaTheme.accent
        }
        if isInspected {
            return MicaTheme.accent.opacity(0.5)
        }
        if isHovered && !scrollInteractionTracker.isScrolling {
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

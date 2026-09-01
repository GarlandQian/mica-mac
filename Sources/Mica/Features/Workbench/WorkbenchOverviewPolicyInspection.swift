import Foundation
import MicaCore
import SwiftUI

// MARK: - Inspection index (moved from the removed policy HUD)

struct OverviewPolicyMemberInspection: Equatable {
    let name: String
    let groupName: String
    let groupOccurrenceID: String
    let groupType: String
    let isControllerSelected: Bool
    let detail: ProxyNodeViewState?
    let delay: Int?
    let usageRank: PolicyGroupUsageRank?
}

struct OverviewPolicyGroupInspection: Equatable {
    let name: String
    let occurrenceID: String
    let type: String
    let selected: String
    let members: [String]
    let selectedMember: OverviewPolicyMemberInspection

    var memberCount: Int { members.count }
}

enum OverviewPolicyInspectionResolution: Equatable {
    case group(OverviewPolicyGroupInspection)
    case member(OverviewPolicyMemberInspection)
    case ambiguous
    case missing
}

struct OverviewPolicyInspectionIndex: Equatable {
    struct OperationCounts: Equatable {
        let groupWriteCount: Int
        let memberWriteCount: Int
    }

    private let groupsByName: [String: [OverviewPolicyGroupInspection]]
    private let membersByName: [String: [OverviewPolicyMemberInspection]]
    private let groupsByOccurrenceID: [String: OverviewPolicyGroupInspection]
    private let membersByOccurrenceID: [
        String: [String: [OverviewPolicyMemberInspection]]
    ]
    let operationCounts: OperationCounts

    init(catalog: PolicyGroupCatalogSnapshot) {
        var groupsByName: [String: [OverviewPolicyGroupInspection]] = [:]
        var membersByName: [String: [OverviewPolicyMemberInspection]] = [:]
        var groupsByOccurrenceID: [String: OverviewPolicyGroupInspection] = [:]
        var membersByOccurrenceID: [
            String: [String: [OverviewPolicyMemberInspection]]
        ] = [:]
        var memberWriteCount = 0

        var groupOccurrences: [String: Int] = [:]
        for group in catalog.groups {
            let occurrence = groupOccurrences[group.id, default: 0]
            groupOccurrences[group.id] = occurrence + 1
            let occurrenceID = ProxyGroupKey(
                groupID: group.id,
                occurrence: occurrence
            ).rawValue
            for memberName in group.options {
                let member = Self.member(
                    named: memberName,
                    in: group,
                    occurrenceID: occurrenceID,
                    isControllerSelected: group.selected == memberName
                )
                membersByName[memberName, default: []].append(member)
                membersByOccurrenceID[occurrenceID, default: [:]][
                    memberName,
                    default: []
                ].append(member)
                memberWriteCount += 1
            }

            let selectedMember = Self.member(
                named: group.selected,
                in: group,
                occurrenceID: occurrenceID,
                isControllerSelected: true
            )
            let inspection = OverviewPolicyGroupInspection(
                name: group.id,
                occurrenceID: occurrenceID,
                type: group.type,
                selected: group.selected,
                members: group.options,
                selectedMember: selectedMember
            )
            groupsByName[group.id, default: []].append(inspection)
            groupsByOccurrenceID[occurrenceID] = inspection
        }

        self.groupsByName = groupsByName
        self.membersByName = membersByName
        self.groupsByOccurrenceID = groupsByOccurrenceID
        self.membersByOccurrenceID = membersByOccurrenceID
        operationCounts = OperationCounts(
            groupWriteCount: catalog.groups.count,
            memberWriteCount: memberWriteCount
        )
    }

    func resolve(name: String) -> OverviewPolicyInspectionResolution {
        if let groups = groupsByName[name] {
            return groups.count == 1 ? .group(groups[0]) : .ambiguous
        }
        if let members = membersByName[name] {
            return members.count == 1 ? .member(members[0]) : .ambiguous
        }
        return .missing
    }

    func resolve(
        groupOccurrenceID: String,
        nodeName: String? = nil
    ) -> OverviewPolicyInspectionResolution {
        guard let group = groupsByOccurrenceID[groupOccurrenceID] else {
            return .missing
        }
        guard let nodeName else { return .group(group) }
        let members = membersByOccurrenceID[groupOccurrenceID]?[nodeName] ?? []
        return members.count == 1 ? .member(members[0]) :
            members.isEmpty ? .missing : .ambiguous
    }

    private static func member(
        named name: String,
        in group: ProxyGroupViewState,
        occurrenceID: String,
        isControllerSelected: Bool
    ) -> OverviewPolicyMemberInspection {
        let detail = group.detail(for: name)
        return OverviewPolicyMemberInspection(
            name: name,
            groupName: group.id,
            groupOccurrenceID: occurrenceID,
            groupType: group.type,
            isControllerSelected: isControllerSelected,
            detail: detail,
            delay: group.delays[name] ?? detail?.latestHistoryDelay,
            usageRank: group.usageRank(for: name)
        )
    }
}

@MainActor
final class OverviewPolicyInspectionCache {
    struct Statistics: Equatable {
        var buildCount = 0
        var cacheHitCount = 0
    }

    private var revision: UInt64?
    private var index = OverviewPolicyInspectionIndex(catalog: .empty)
    private(set) var statistics = Statistics()

    func resolve(
        revision: UInt64,
        catalog: PolicyGroupCatalogSnapshot
    ) -> OverviewPolicyInspectionIndex {
        if self.revision == revision {
            statistics.cacheHitCount += 1
            return index
        }
        self.revision = revision
        index = OverviewPolicyInspectionIndex(catalog: catalog)
        statistics.buildCount += 1
        return index
    }
}

// MARK: - Inspection field composition

struct OverviewPolicyInspectionField: Identifiable, Equatable {
    enum Label: Equatable {
        case localized(String)
        case verbatim(String)

        func resolved(language: AppLanguage) -> String {
            switch self {
            case .localized(let key):
                MicaStrings.localizedKey(key, language: language)
            case .verbatim(let value):
                value
            }
        }
    }

    enum Tone: Equatable {
        case neutral
        case healthy
        case warning
        case failure
        case accent
    }

    let id: String
    let label: Label
    let value: String
    var tone: Tone = .neutral
    var monospaced = false
}

struct OverviewPolicyInspectionSection: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let fields: [OverviewPolicyInspectionField]
}

struct OverviewPolicyInspectionSnapshot: Equatable {
    enum Kind: Equatable {
        case policyGroup
        case policyMember
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let sections: [OverviewPolicyInspectionSection]

    var fields: [OverviewPolicyInspectionField] {
        sections.flatMap(\.fields)
    }
}

/// Complete policy-inspection field composition shown in the workspace
/// inspector (task 08-17 Phase 3.3). This is the same complete field set the
/// removed floating HUD rendered: group/member identity, type, selection,
/// ordered members, availability, latency, provider, interface,
/// hidden/fixed/icon, every reported transport state (including `false`),
/// SMART rank, latest test detail + URL, and all additional controller fields
/// in stable key order. Resolution is name-exact and unique-only; ambiguous or
/// missing names return `nil` so callers can present the truthful fallback.
enum OverviewPolicyInspectionProjection {
    static func snapshot(
        groupOccurrenceID: String,
        nodeName: String?,
        policyIndex: OverviewPolicyInspectionIndex,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot? {
        switch policyIndex.resolve(
            groupOccurrenceID: groupOccurrenceID,
            nodeName: nodeName
        ) {
        case .group(let group):
            return groupSnapshot(group: group, language: language)
        case .member(let member):
            return memberSnapshot(member: member, language: language)
        case .ambiguous, .missing:
            return nil
        }
    }

    static func snapshot(
        name: String,
        policyIndex: OverviewPolicyInspectionIndex,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot? {
        switch policyIndex.resolve(name: name) {
        case .group(let group):
            return groupSnapshot(group: group, language: language)
        case .member(let member):
            return memberSnapshot(member: member, language: language)
        case .ambiguous, .missing:
            return nil
        }
    }

    private static func groupSnapshot(
        group: OverviewPolicyGroupInspection,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot {
        var overview: [OverviewPolicyInspectionField] = []
        append(
            id: "group-type",
            titleKey: "overview.hud.group_type",
            value: group.type,
            to: &overview
        )
        append(
            id: "selection",
            titleKey: "overview.hud.current_selection",
            value: group.selected,
            tone: .accent,
            to: &overview
        )
        overview.append(
            OverviewPolicyInspectionField(
                id: "member-count",
                label: .localized("overview.hud.member_count"),
                value: group.memberCount.formatted(),
                monospaced: true
            )
        )
        append(
            id: "members",
            titleKey: "overview.hud.members",
            value: group.members.joined(separator: " · "),
            to: &overview
        )
        overview.append(contentsOf: memberOverviewFields(
            group.selectedMember,
            language: language
        ))

        return OverviewPolicyInspectionSnapshot(
            kind: .policyGroup,
            title: group.name,
            subtitle: nonBlank(group.type),
            sections: memberSections(
                overview: overview,
                member: group.selectedMember,
                language: language
            )
        )
    }

    private static func memberSnapshot(
        member: OverviewPolicyMemberInspection,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot {
        var overview: [OverviewPolicyInspectionField] = []
        append(
            id: "group",
            titleKey: "overview.hud.group",
            value: member.groupName,
            to: &overview
        )
        append(
            id: "group-type",
            titleKey: "overview.hud.group_type",
            value: member.groupType,
            to: &overview
        )
        overview.append(contentsOf: memberOverviewFields(member, language: language))

        return OverviewPolicyInspectionSnapshot(
            kind: .policyMember,
            title: member.name,
            subtitle: nonBlank(member.detail?.type) ?? nonBlank(member.groupType),
            sections: memberSections(
                overview: overview,
                member: member,
                language: language
            )
        )
    }

    private static func memberOverviewFields(
        _ member: OverviewPolicyMemberInspection,
        language: AppLanguage
    ) -> [OverviewPolicyInspectionField] {
        var fields: [OverviewPolicyInspectionField] = []
        appendAvailability(member.detail?.alive, language: language, to: &fields)
        appendLatency(member.delay, id: "latency", to: &fields)
        guard let detail = member.detail else {
            append(
                id: "rank",
                titleKey: "overview.hud.smart_rank",
                value: member.usageRank?.label(language: language),
                to: &fields
            )
            return fields
        }
        append(id: "type", titleKey: "overview.hud.type", value: detail.type, to: &fields)
        append(
            id: "provider",
            titleKey: "overview.hud.provider",
            value: detail.providerName,
            to: &fields
        )
        append(
            id: "interface",
            titleKey: "overview.hud.interface",
            value: detail.interfaceName,
            monospaced: true,
            to: &fields
        )
        append(
            id: "hidden",
            titleKey: "routing.node_hidden",
            value: detail.hidden.map { localizedBoolean($0, language: language) },
            to: &fields
        )
        append(
            id: "fixed",
            titleKey: "routing.fixed_selection",
            value: detail.fixed,
            to: &fields
        )
        append(
            id: "icon",
            titleKey: "routing.icon_url",
            value: detail.icon,
            monospaced: true,
            to: &fields
        )
        append(
            id: "rank",
            titleKey: "overview.hud.smart_rank",
            value: member.usageRank?.label(language: language),
            to: &fields
        )
        return fields
    }

    private static func memberSections(
        overview: [OverviewPolicyInspectionField],
        member: OverviewPolicyMemberInspection,
        language: AppLanguage
    ) -> [OverviewPolicyInspectionSection] {
        var sections: [OverviewPolicyInspectionSection] = []
        appendSection(
            id: "overview",
            titleKey: "routing.node_section_overview",
            fields: overview,
            to: &sections
        )

        guard let detail = member.detail else { return sections }

        let transports = detail.transportCapabilities.map { capability in
            OverviewPolicyInspectionField(
                id: "transport.\(capability.id)",
                label: .verbatim(capability.name),
                value: localizedBoolean(capability.isEnabled, language: language)
            )
        }
        appendSection(
            id: "transport",
            titleKey: "routing.node_section_transport",
            fields: transports,
            to: &sections
        )

        let detailProjection = ProxyMemberDetailProjection(detail: detail)
        var testing: [OverviewPolicyInspectionField] = []
        appendLatency(
            detailProjection.latestHistoryDelay,
            id: "test-delay",
            titleKey: "overview.hud.test_delay",
            to: &testing
        )
        append(
            id: "test-time",
            titleKey: "overview.hud.test_time",
            value: detailProjection.latestHistoryTime,
            monospaced: true,
            to: &testing
        )
        if let history = detailProjection.history, !history.isEmpty {
            testing.append(
                OverviewPolicyInspectionField(
                    id: "test-samples",
                    label: .localized("routing.delay_history"),
                    value: history.count.formatted(),
                    monospaced: true
                )
            )
        }
        append(
            id: "test-url",
            titleKey: "overview.hud.test_url",
            value: detail.testURL,
            monospaced: true,
            to: &testing
        )
        appendSection(
            id: "testing",
            titleKey: "routing.node_section_testing",
            fields: testing,
            to: &sections
        )

        let reportedFields = detailProjection.reportedFields.map { field in
            OverviewPolicyInspectionField(
                id: "metadata.\(field.key)",
                label: .verbatim(field.key),
                value: field.value,
                monospaced: true
            )
        }
        appendSection(
            id: "reported-fields",
            titleKey: "routing.node_section_reported_fields",
            fields: reportedFields,
            to: &sections
        )
        return sections
    }

    private static func appendAvailability(
        _ alive: Bool?,
        language: AppLanguage,
        to fields: inout [OverviewPolicyInspectionField]
    ) {
        guard let alive else { return }
        fields.append(
            OverviewPolicyInspectionField(
                id: "availability",
                label: .localized("overview.hud.availability"),
                value: MicaStrings.localizedKey(
                    alive ? "routing.node_alive" : "routing.node_unavailable",
                    language: language
                ),
                tone: alive ? .healthy : .failure
            )
        )
    }

    private static func appendLatency(
        _ delay: Int?,
        id: String,
        titleKey: String = "overview.hud.latency",
        to fields: inout [OverviewPolicyInspectionField]
    ) {
        guard let delay else { return }
        fields.append(
            OverviewPolicyInspectionField(
                id: id,
                label: .localized(titleKey),
                value: OverviewFormat.latency(delay),
                tone: delay > 0 ? latencyTone(delay) : .neutral,
                monospaced: true
            )
        )
    }

    private static func latencyTone(_ delay: Int) -> OverviewPolicyInspectionField.Tone {
        switch LatencyHealthGrade.allCases.first(where: { $0.includes(delay: delay) }) {
        case .fast: .healthy
        case .normal: .accent
        case .slow: .warning
        case .timeout, .none: .failure
        }
    }

    private static func append(
        id: String,
        titleKey: String,
        value: String?,
        tone: OverviewPolicyInspectionField.Tone = .neutral,
        monospaced: Bool = false,
        to fields: inout [OverviewPolicyInspectionField]
    ) {
        guard let value = nonBlank(value) else { return }
        fields.append(
            OverviewPolicyInspectionField(
                id: id,
                label: .localized(titleKey),
                value: value,
                tone: tone,
                monospaced: monospaced
            )
        )
    }

    private static func appendSection(
        id: String,
        titleKey: String,
        fields: [OverviewPolicyInspectionField],
        to sections: inout [OverviewPolicyInspectionSection]
    ) {
        guard !fields.isEmpty else { return }
        sections.append(
            OverviewPolicyInspectionSection(
                id: id,
                titleKey: titleKey,
                fields: fields
            )
        )
    }

    private static func localizedBoolean(
        _ value: Bool,
        language: AppLanguage
    ) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : value
    }
}

// MARK: - Workspace inspector content

/// Policy-group/member detail in the workspace inspector (design.md §3). This
/// is the Phase 3.3 replacement for the removed node-anchored floating HUD:
/// topology policy-node clicks select `.proxyGroup` / `.proxyNode` here and
/// the inspector renders the complete inspection field composition with flat
/// Mica Ops sections, mono data values, and hairline separators. The
/// same-window Open Proxies / Open Connections actions keep their HUD-era
/// eligibility rules (Open Proxies for every policy selection; Open
/// Connections when exactly one live path routes through the selection).
struct WorkbenchPolicyInspectorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewWindowRuntime.self) private var overviewRuntime
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @Environment(\.micaAppLanguage) private var language

    let selection: WorkbenchInspectorSelection
    @Binding var destination: WorkbenchDestination

    @State private var inspectionCache = OverviewPolicyInspectionCache()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                inspectionContent
                actionSection
            }
            .padding(MicaTheme.Spacing.space3)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var inspectionContent: some View {
        let policyIndex = inspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        if let snapshot = inspectionSnapshot(policyIndex: policyIndex) {
            header(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                systemImage: symbolName(for: snapshot.kind)
            )
            MicaHairlineSeparator()
            ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) {
                index,
                section in
                if index > 0 {
                    MicaHairlineSeparator()
                }
                fieldSection(section)
            }
        } else {
            header(
                title: inspectedName,
                subtitle: nil,
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            MicaHairlineSeparator()
            Text(
                MicaStrings.localizedKey(
                    "workbench.inspector_policy_unresolved",
                    language: language
                )
            )
            .micaThemeFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inspectionSnapshot(
        policyIndex: OverviewPolicyInspectionIndex
    ) -> OverviewPolicyInspectionSnapshot? {
        switch selection {
        case .proxyGroup(let groupName, let occurrenceID):
            guard let occurrenceID else {
                return OverviewPolicyInspectionProjection.snapshot(
                    name: groupName,
                    policyIndex: policyIndex,
                    language: language
                )
            }
            return OverviewPolicyInspectionProjection.snapshot(
                groupOccurrenceID: occurrenceID,
                nodeName: nil,
                policyIndex: policyIndex,
                language: language
            )
        case .proxyNode(_, let occurrenceID, let nodeName):
            guard let occurrenceID else {
                return OverviewPolicyInspectionProjection.snapshot(
                    name: nodeName,
                    policyIndex: policyIndex,
                    language: language
                )
            }
            return OverviewPolicyInspectionProjection.snapshot(
                groupOccurrenceID: occurrenceID,
                nodeName: nodeName,
                policyIndex: policyIndex,
                language: language
            )
        case .none, .connection, .rule, .log, .source, .controller:
            return nil
        }
    }

    private var inspectedName: String {
        switch selection {
        case .proxyGroup(let groupName, _):
            groupName
        case .proxyNode(_, _, let nodeName):
            nodeName
        case .none, .connection, .rule, .log, .source, .controller:
            ""
        }
    }

    private func symbolName(for kind: OverviewPolicyInspectionSnapshot.Kind) -> String {
        switch kind {
        case .policyGroup: "point.3.connected.trianglepath.dotted"
        case .policyMember: "bolt.horizontal.circle"
        }
    }

    private func header(
        title: String,
        subtitle: String?,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Image(systemName: systemImage)
                .foregroundStyle(MicaTheme.textSecondary)
                .frame(width: MicaTheme.Metrics.iconControlSize, height: MicaTheme.Metrics.iconControlSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .micaThemeFont(.label, weight: .semibold)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let subtitle = subtitle?.overviewNonBlank {
                    Text(verbatim: subtitle)
                        .micaThemeFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func fieldSection(_ section: OverviewPolicyInspectionSection) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            Text(MicaStrings.localizedKey(section.titleKey, language: language))
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(MicaTheme.textSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                ForEach(section.fields) { field in
                    fieldRow(field)
                }
            }
        }
    }

    private func fieldRow(_ field: OverviewPolicyInspectionField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: field.label.resolved(language: language))
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(verbatim: field.value)
                .micaThemeFont(
                    field.monospaced ? .dataCaption : .caption,
                    weight: .medium
                )
                .foregroundStyle(field.tone.tint)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            MicaHairlineSeparator()
            if proxyNavigationTarget != nil {
                Button(action: openProxies) {
                    Label(
                        MicaStrings.localizedKey(
                            WorkbenchDestination.proxies.titleKey,
                            language: language
                        ),
                        systemImage: WorkbenchDestination.proxies.symbolName
                    )
                }
            }
            if let singlePath {
                Button { openPath(singlePath) } label: {
                    Label(
                        MicaStrings.localizedKey(
                            WorkbenchDestination.connections.titleKey,
                            language: language
                        ),
                        systemImage: "arrow.right"
                    )
                }
            }
        }
        .controlSize(.small)
    }

    /// HUD-era eligibility preserved: Open Connections appears only when the
    /// live topology highlight resolves to exactly one path for the pinned
    /// selection.
    private var singlePath: ConnectionTopology.PathRecord? {
        guard let controllerID = appModel.selectedRouterID,
              let runtime = overviewRuntime.registry.existingTopologyRuntime(
                  controllerID: controllerID,
                  generation: appModel.controllerSessionPresentation.generation
              ) else {
            return nil
        }
        let paths = runtime.interaction.snapshot.highlight.paths
        return paths.count == 1 ? paths.first : nil
    }

    private func openProxies() {
        guard let target = proxyNavigationTarget else { return }
        workspaceStore.stageProxyNavigation(target)
        destination = .proxies
    }

    private var proxyNavigationTarget: WorkbenchProxyNavigationSelection? {
        guard let controllerID = appModel.selectedRouterID else { return nil }
        let generation = appModel.controllerSessionPresentation.generation
        let policyIndex = inspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        switch selection {
        case .proxyNode(_, let groupOccurrenceID, let nodeName):
            guard let groupOccurrenceID,
                  case .member = policyIndex.resolve(
                      groupOccurrenceID: groupOccurrenceID,
                      nodeName: nodeName
                  ) else {
                return nil
            }
            return ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: generation,
                groupOccurrenceID: groupOccurrenceID,
                nodeName: nodeName
            )
        case .proxyGroup(let groupName, let groupOccurrenceID):
            guard let groupOccurrenceID,
                  case .group(let group) = policyIndex.resolve(
                      groupOccurrenceID: groupOccurrenceID
                  ),
                  group.name == groupName,
                  let nodeName = group.selected.proxyNonBlank
                      ?? group.members.lazy.compactMap(\.proxyNonBlank).first else {
                return nil
            }
            return ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: generation,
                groupOccurrenceID: groupOccurrenceID,
                nodeName: nodeName
            )
        case .none, .connection, .rule, .log, .source, .controller:
            return nil
        }
    }

    private func openPath(_ path: ConnectionTopology.PathRecord) {
        if let controllerID = appModel.selectedRouterID {
            workspaceStore.stageConnectionNavigation(
                WorkbenchConnectionNavigationSelection(
                    controllerID: controllerID,
                    generation: appModel.controllerSessionPresentation.generation,
                    sourceIndex: path.sourceIndex,
                    reportedConnectionID: path.reportedConnectionID
                )
            )
        }
        destination = .connections
    }
}

private extension OverviewPolicyInspectionField.Tone {
    var tint: Color {
        switch self {
        case .neutral: MicaTheme.textPrimary
        case .healthy: MicaTheme.statusOK
        case .warning: MicaTheme.statusWarning
        case .failure: MicaTheme.statusError
        case .accent: MicaTheme.accent
        }
    }
}

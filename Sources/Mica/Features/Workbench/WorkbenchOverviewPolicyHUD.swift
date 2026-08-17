import CoreGraphics
import Foundation
import MicaCore

struct OverviewPolicyMemberInspection: Equatable {
    let name: String
    let groupName: String
    let groupType: String
    let isControllerSelected: Bool
    let detail: ProxyNodeViewState?
    let delay: Int?
    let usageRank: PolicyGroupUsageRank?
}

struct OverviewPolicyGroupInspection: Equatable {
    let name: String
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
    let operationCounts: OperationCounts

    init(catalog: PolicyGroupCatalogSnapshot) {
        var groupsByName: [String: [OverviewPolicyGroupInspection]] = [:]
        var membersByName: [String: [OverviewPolicyMemberInspection]] = [:]
        var memberWriteCount = 0

        for group in catalog.groups {
            for memberName in group.options {
                let member = Self.member(
                    named: memberName,
                    in: group,
                    isControllerSelected: group.selected == memberName
                )
                membersByName[memberName, default: []].append(member)
                memberWriteCount += 1
            }

            let selectedMember = Self.member(
                named: group.selected,
                in: group,
                isControllerSelected: true
            )
            groupsByName[group.id, default: []].append(
                OverviewPolicyGroupInspection(
                    name: group.id,
                    type: group.type,
                    selected: group.selected,
                    members: group.options,
                    selectedMember: selectedMember
                )
            )
        }

        self.groupsByName = groupsByName
        self.membersByName = membersByName
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

    private static func member(
        named name: String,
        in group: ProxyGroupViewState,
        isControllerSelected: Bool
    ) -> OverviewPolicyMemberInspection {
        let detail = group.detail(for: name)
        return OverviewPolicyMemberInspection(
            name: name,
            groupName: group.id,
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

struct OverviewPolicyHUDField: Identifiable, Equatable {
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

struct OverviewPolicyHUDSection: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let fields: [OverviewPolicyHUDField]
}

struct OverviewPolicyHUDSnapshot: Equatable {
    enum Kind: Equatable {
        case policyGroup
        case policyMember
        case route
    }

    let selection: OverviewTopologySelection
    let kind: Kind
    let title: String
    let subtitle: String?
    let sections: [OverviewPolicyHUDSection]
    let isExpanded: Bool
    let canOpenProxies: Bool

    var fields: [OverviewPolicyHUDField] {
        sections.flatMap(\.fields)
    }
}

enum OverviewPolicyHUDProjection {
    static func snapshot(
        selection: OverviewTopologySelection,
        isPinned: Bool,
        topologyIndex: OverviewTopologyIndex,
        policyIndex: OverviewPolicyInspectionIndex,
        language: AppLanguage
    ) -> OverviewPolicyHUDSnapshot {
        guard case .node(let nodeID) = selection,
              let node = topologyIndex.node(id: nodeID),
              case .policyHop = node.columnID else {
            return routeSnapshot(
                selection: selection,
                isPinned: isPinned,
                topologyIndex: topologyIndex,
                language: language,
                canOpenProxies: false
            )
        }

        switch policyIndex.resolve(name: node.name) {
        case .group(let group):
            return groupSnapshot(
                selection: selection,
                group: group,
                isPinned: isPinned,
                language: language
            )
        case .member(let member):
            return memberSnapshot(
                selection: selection,
                member: member,
                isPinned: isPinned,
                language: language
            )
        case .ambiguous, .missing:
            return routeSnapshot(
                selection: selection,
                isPinned: isPinned,
                topologyIndex: topologyIndex,
                language: language,
                canOpenProxies: true
            )
        }
    }

    private static func groupSnapshot(
        selection: OverviewTopologySelection,
        group: OverviewPolicyGroupInspection,
        isPinned: Bool,
        language: AppLanguage
    ) -> OverviewPolicyHUDSnapshot {
        var overview: [OverviewPolicyHUDField] = []
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
            OverviewPolicyHUDField(
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

        return OverviewPolicyHUDSnapshot(
            selection: selection,
            kind: .policyGroup,
            title: group.name,
            subtitle: nonBlank(group.type),
            sections: memberSections(
                overview: overview,
                member: group.selectedMember,
                language: language
            ),
            isExpanded: isPinned,
            canOpenProxies: true
        )
    }

    private static func memberSnapshot(
        selection: OverviewTopologySelection,
        member: OverviewPolicyMemberInspection,
        isPinned: Bool,
        language: AppLanguage
    ) -> OverviewPolicyHUDSnapshot {
        var overview: [OverviewPolicyHUDField] = []
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

        return OverviewPolicyHUDSnapshot(
            selection: selection,
            kind: .policyMember,
            title: member.name,
            subtitle: nonBlank(member.detail?.type) ?? nonBlank(member.groupType),
            sections: memberSections(
                overview: overview,
                member: member,
                language: language
            ),
            isExpanded: isPinned,
            canOpenProxies: true
        )
    }

    private static func memberOverviewFields(
        _ member: OverviewPolicyMemberInspection,
        language: AppLanguage
    ) -> [OverviewPolicyHUDField] {
        var fields: [OverviewPolicyHUDField] = []
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
        overview: [OverviewPolicyHUDField],
        member: OverviewPolicyMemberInspection,
        language: AppLanguage
    ) -> [OverviewPolicyHUDSection] {
        var sections: [OverviewPolicyHUDSection] = []
        appendSection(
            id: "overview",
            titleKey: "routing.node_section_overview",
            fields: overview,
            to: &sections
        )

        guard let detail = member.detail else { return sections }

        let transports = detail.transportCapabilities.map { capability in
            OverviewPolicyHUDField(
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
        var testing: [OverviewPolicyHUDField] = []
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
                OverviewPolicyHUDField(
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
            OverviewPolicyHUDField(
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

    private static func routeSnapshot(
        selection: OverviewTopologySelection,
        isPinned: Bool,
        topologyIndex: OverviewTopologyIndex,
        language: AppLanguage,
        canOpenProxies: Bool
    ) -> OverviewPolicyHUDSnapshot {
        OverviewPolicyHUDSnapshot(
            selection: selection,
            kind: .route,
            title: OverviewTopologyProjection.selectionLabel(
                selection,
                in: topologyIndex,
                language: language
            ),
            subtitle: OverviewTopologyProjection.selectionDescription(
                selection,
                in: topologyIndex,
                language: language
            ),
            sections: [],
            isExpanded: isPinned,
            canOpenProxies: canOpenProxies
        )
    }

    private static func appendAvailability(
        _ alive: Bool?,
        language: AppLanguage,
        to fields: inout [OverviewPolicyHUDField]
    ) {
        guard let alive else { return }
        fields.append(
            OverviewPolicyHUDField(
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
        to fields: inout [OverviewPolicyHUDField]
    ) {
        guard let delay, delay > 0 else { return }
        fields.append(
            OverviewPolicyHUDField(
                id: id,
                label: .localized(titleKey),
                value: OverviewFormat.latency(delay),
                tone: latencyTone(delay),
                monospaced: true
            )
        )
    }

    private static func latencyTone(_ delay: Int) -> OverviewPolicyHUDField.Tone {
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
        tone: OverviewPolicyHUDField.Tone = .neutral,
        monospaced: Bool = false,
        to fields: inout [OverviewPolicyHUDField]
    ) {
        guard let value = nonBlank(value) else { return }
        fields.append(
            OverviewPolicyHUDField(
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
        fields: [OverviewPolicyHUDField],
        to sections: inout [OverviewPolicyHUDSection]
    ) {
        guard !fields.isEmpty else { return }
        sections.append(
            OverviewPolicyHUDSection(
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

enum OverviewPolicyHUDSide: Int, CaseIterable, Equatable, Sendable {
    case trailing
    case leading
    case above
    case below
}

struct OverviewPolicyHUDPlacement: Equatable, Sendable {
    let frame: CGRect
    let side: OverviewPolicyHUDSide
}

enum OverviewPolicyHUDPlacementResolver {
    private static let gap: CGFloat = 12

    static func resolve(
        anchorRect: CGRect,
        labelRect: CGRect,
        hudSize: CGSize,
        graphBounds: CGRect,
        obstacles: [CGRect],
        preferredSide: OverviewPolicyHUDSide
    ) -> OverviewPolicyHUDPlacement {
        let safeBounds = graphBounds.insetBy(dx: 10, dy: 10)
        let candidates = OverviewPolicyHUDSide.allCases.map { side in
            (side, candidateFrame(
                side: side,
                anchorRect: anchorRect,
                labelRect: labelRect,
                hudSize: hudSize
            ))
        }
        let winner = candidates.min { left, right in
            score(
                frame: left.1,
                side: left.0,
                anchorRect: anchorRect,
                graphBounds: safeBounds,
                obstacles: obstacles,
                preferredSide: preferredSide
            ) < score(
                frame: right.1,
                side: right.0,
                anchorRect: anchorRect,
                graphBounds: safeBounds,
                obstacles: obstacles,
                preferredSide: preferredSide
            )
        } ?? (preferredSide, CGRect(origin: anchorRect.origin, size: hudSize))

        return OverviewPolicyHUDPlacement(
            frame: clamp(winner.1, to: safeBounds),
            side: winner.0
        )
    }

    static func preferredSide(
        for labelSide: OverviewTopologyLayout.NodeGeometry.LabelSide
    ) -> OverviewPolicyHUDSide {
        switch labelSide {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private static func candidateFrame(
        side: OverviewPolicyHUDSide,
        anchorRect: CGRect,
        labelRect: CGRect,
        hudSize: CGSize
    ) -> CGRect {
        let anchor = anchorRect.union(labelRect)
        switch side {
        case .trailing:
            return CGRect(
                x: anchor.maxX + gap,
                y: anchor.midY - hudSize.height / 2,
                width: hudSize.width,
                height: hudSize.height
            )
        case .leading:
            return CGRect(
                x: anchor.minX - gap - hudSize.width,
                y: anchor.midY - hudSize.height / 2,
                width: hudSize.width,
                height: hudSize.height
            )
        case .above:
            return CGRect(
                x: anchor.midX - hudSize.width / 2,
                y: anchor.minY - gap - hudSize.height,
                width: hudSize.width,
                height: hudSize.height
            )
        case .below:
            return CGRect(
                x: anchor.midX - hudSize.width / 2,
                y: anchor.maxY + gap,
                width: hudSize.width,
                height: hudSize.height
            )
        }
    }

    private static func score(
        frame: CGRect,
        side: OverviewPolicyHUDSide,
        anchorRect: CGRect,
        graphBounds: CGRect,
        obstacles: [CGRect],
        preferredSide: OverviewPolicyHUDSide
    ) -> Double {
        let boundedArea = intersectionArea(frame, graphBounds)
        let outOfBoundsArea = max(area(frame) - boundedArea, 0)
        let anchorOverlap = intersectionArea(frame, anchorRect)
        let obstacleOverlap = obstacles.reduce(CGFloat.zero) {
            $0 + intersectionArea(frame, $1)
        }
        let dx = frame.midX - anchorRect.midX
        let dy = frame.midY - anchorRect.midY
        let distance = sqrt(dx * dx + dy * dy)
        let preferredPenalty = side == preferredSide ? 0 : Double(side.rawValue + 1)
        return Double(outOfBoundsArea) * 10_000
            + Double(anchorOverlap) * 1_000_000
            + Double(obstacleOverlap) * 48
            + Double(distance) * 0.02
            + preferredPenalty
    }

    private static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(max(frame.width, 1), max(bounds.width, 1))
        let height = min(max(frame.height, 1), max(bounds.height, 1))
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return area(intersection)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }
}

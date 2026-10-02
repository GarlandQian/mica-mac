import MicaCore
import Observation
import SwiftUI

struct ProxyNodeDetailIdentity: Hashable {
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let groupID: String
    let memberID: String
}

/// Proxies-page composition of the shared node inspection. The active group
/// header directly above the member list owns group identity, so the node
/// detail omits only the group name and group type; every other reported
/// field remains.
enum ProxyNodeInspectionProjection {
    static let groupContextFieldIDs: Set<String> = ["group", "group-type"]

    static func snapshot(
        member: ProxyNodeRowProjection,
        in occurrence: ProxyGroupOccurrence,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot {
        let complete = OverviewPolicyInspectionProjection.memberSnapshot(
            member: OverviewPolicyMemberInspection(
                name: member.name,
                groupName: occurrence.group.id,
                groupOccurrenceID: occurrence.id,
                groupType: occurrence.group.type,
                isControllerSelected: member.isControllerSelected,
                detail: occurrence.group.detail(for: member.name),
                delay: member.delay,
                usageRank: member.usageRank
            ),
            language: language
        )
        return OverviewPolicyInspectionSnapshot(
            kind: complete.kind,
            title: complete.title,
            subtitle: complete.subtitle,
            sections: complete.sections.compactMap { section in
                let fields = section.fields.filter { !groupContextFieldIDs.contains($0.id) }
                return fields.isEmpty ? nil : OverviewPolicyInspectionSection(
                    id: section.id,
                    titleKey: section.titleKey,
                    fields: fields
                )
            }
        )
    }

    static func history(
        member: ProxyNodeRowProjection,
        in occurrence: ProxyGroupOccurrence
    ) -> [ProxyDelayHistorySnapshot] {
        occurrence.group.detail(for: member.name)?.history ?? []
    }
}

/// Arranges one node's inspection into a glanceable summary, capability
/// tags, and titled cards. It only regroups projected fields: every field in
/// the snapshot appears exactly once.
struct ProxyNodeDetailComposition: Equatable {
    /// Short facts that read best as labeled tags, in presentation order.
    static let summaryFieldIDs = ["availability", "latency", "type", "provider", "rank"]
    /// Cards lead with configuration, then runtime, testing, and the rest.
    static let sectionOrder = ["protocol", "overview", "testing", "reported-fields"]

    let summary: [OverviewPolicyInspectionField]
    let capabilities: [OverviewPolicyInspectionField]
    let sections: [OverviewPolicyInspectionSection]

    init(snapshot: OverviewPolicyInspectionSnapshot) {
        let fields = snapshot.fields
        summary = Self.summaryFieldIDs.compactMap { id in
            fields.first { $0.id == id }
        }
        let summaryIDs = Set(summary.map(\.id))
        var capabilities: [OverviewPolicyInspectionField] = []
        var sections: [OverviewPolicyInspectionSection] = []
        for section in snapshot.sections {
            var remaining: [OverviewPolicyInspectionField] = []
            for field in section.fields where !summaryIDs.contains(field.id) {
                if section.id == "transport", field.booleanValue != nil {
                    capabilities.append(field)
                } else {
                    remaining.append(field)
                }
            }
            if !remaining.isEmpty {
                sections.append(OverviewPolicyInspectionSection(
                    id: section.id,
                    titleKey: section.titleKey,
                    fields: remaining
                ))
            }
        }
        self.capabilities = capabilities
        self.sections = sections.enumerated().sorted { left, right in
            let leftRank = Self.sectionOrder.firstIndex(of: left.element.id) ?? Self.sectionOrder.count
            let rightRank = Self.sectionOrder.firstIndex(of: right.element.id) ?? Self.sectionOrder.count
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
    }

    var isEmpty: Bool {
        summary.isEmpty && capabilities.isEmpty && sections.isEmpty
    }
}

/// Only the opened row owns parameter views and secret reveal state.
/// The containing identity changes across member/controller/session boundaries.
struct ProxyInlineNodeDetails: View {
    let snapshot: OverviewPolicyInspectionSnapshot
    var history: [ProxyDelayHistorySnapshot] = []

    var body: some View {
        let composition = ProxyNodeDetailComposition(snapshot: snapshot)

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            if composition.isEmpty {
                ProxyNodeNoDetails()
            }

            if !composition.summary.isEmpty || !composition.capabilities.isEmpty {
                MicaTagFlow(spacing: MicaTheme.Spacing.space1 + 2) {
                    ForEach(composition.summary) { field in
                        ProxyNodeSummaryTag(field: field)
                    }
                    ForEach(composition.capabilities) { field in
                        ProxyNodeCapabilityTag(field: field)
                    }
                }
            }

            ProxyNodeSectionColumns(spacing: MicaTheme.Spacing.space2) {
                ForEach(composition.sections) { section in
                    ProxyNodeDetailCard(
                        section: section,
                        history: section.id == "testing" ? history : []
                    )
                }
            }
        }
        .padding(MicaTheme.Spacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proxy-inline-details")
    }
}

private struct ProxyNodeNoDetails: View {
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        Label {
            Text(MicaStrings.localizedKey("routing.node_no_details", language: language))
        } icon: {
            Image(systemName: "info.circle")
        }
        .micaThemeFont(.caption)
        .foregroundStyle(MicaTheme.textSecondary)
    }
}

private struct ProxyNodeSummaryTag: View {
    @Environment(\.micaAppLanguage) private var language

    let field: OverviewPolicyInspectionField

    var body: some View {
        let label = field.label.resolved(language: language)

        HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space1) {
            if field.id == "availability" {
                Circle()
                    .fill(field.tone.tint)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .accessibilityHidden(true)
            } else {
                Text(verbatim: label)
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            Text(verbatim: field.value)
                .micaThemeFont(field.monospaced ? .dataCaption : .caption, weight: .semibold)
                .foregroundStyle(field.tone == .neutral ? MicaTheme.textPrimary : field.tone.tint)
                .textSelection(.enabled)
        }
        .micaThemeFont(.caption)
        .lineLimit(1)
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .padding(.vertical, 3)
        .background(MicaTheme.surface, in: Capsule())
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label): \(field.value)"))
    }
}

/// Reported capabilities read as a checklist: the symbol carries the state,
/// never color alone, and the localized value stays in help and VoiceOver.
private struct ProxyNodeCapabilityTag: View {
    @Environment(\.micaAppLanguage) private var language

    let field: OverviewPolicyInspectionField

    var body: some View {
        let isEnabled = field.booleanValue ?? false
        let label = field.label.resolved(language: language)

        HStack(spacing: MicaTheme.Spacing.space1) {
            Image(systemName: isEnabled ? "checkmark" : "xmark")
                .micaThemeFont(.caption, weight: .bold)
                .foregroundStyle(isEnabled ? MicaTheme.statusOK : MicaTheme.textTertiary)
                .accessibilityHidden(true)
            Text(verbatim: label)
                .micaThemeFont(.caption, weight: .medium)
                .foregroundStyle(isEnabled ? MicaTheme.textPrimary : MicaTheme.textSecondary)
                .strikethrough(!isEnabled, color: MicaTheme.textTertiary)
        }
        .lineLimit(1)
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .padding(.vertical, 3)
        .overlay {
            Capsule().strokeBorder(MicaTheme.separator, lineWidth: MicaTheme.Shape.hairline)
        }
        .help("\(label): \(field.value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label): \(field.value)"))
    }
}

private struct ProxyNodeDetailCard: View {
    @Environment(\.micaAppLanguage) private var language

    let section: OverviewPolicyInspectionSection
    var history: [ProxyDelayHistorySnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            Label {
                Text(MicaStrings.localizedKey(section.titleKey, language: language))
                    .micaThemeFont(.label, weight: .semibold)
                    .foregroundStyle(MicaTheme.textPrimary)
            } icon: {
                Image(systemName: symbolName)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.accent)
            }
            .accessibilityAddTraits(.isHeader)

            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: MicaTheme.Spacing.space3,
                verticalSpacing: MicaTheme.Spacing.space1 + 2
            ) {
                ForEach(section.fields) { field in
                    ProxyNodeFieldRow(field: field)
                }
            }

            if !history.isEmpty {
                ProxyNodeLatencyHistory(history: history)
            }
        }
        .padding(MicaTheme.Spacing.space3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .micaCard(cornerRadius: MicaTheme.Metrics.moduleRadius)
        .accessibilityElement(children: .contain)
    }

    private var symbolName: String {
        switch section.id {
        case "protocol": "network"
        case "overview": "gauge.with.dots.needle.33percent"
        case "testing": "stopwatch"
        case "transport": "checklist"
        default: "curlybraces"
        }
    }
}

/// One aligned key-value row. Labels share a bounded leading column so values
/// start at the same edge; long reported keys wrap instead of pushing values.
private struct ProxyNodeFieldRow: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.locale) private var locale
    @State private var isRevealed = false

    let field: OverviewPolicyInspectionField

    var body: some View {
        let label = field.label.resolved(language: language)
        let formattedTime = ProxyNodeTimeFormat.display(field: field, locale: locale)

        GridRow {
            Text(verbatim: label)
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 124, alignment: .leading)
                .help(field.reportedKey ?? label)

            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space1) {
                PolicyInspectionFieldValue(
                    field: field,
                    isRevealed: isRevealed,
                    displayValue: formattedTime
                )
                .help(formattedTime == nil ? "" : field.value)
                if field.isSensitive {
                    PolicyInspectionRevealButton(
                        field: field,
                        isRevealed: $isRevealed,
                        showsTitle: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: field.value) { _, _ in
            isRevealed = false
        }
    }
}

/// Test timestamps are reported as RFC 3339 text. Present the same instant in
/// the reader's locale; the reported text stays available as help.
enum ProxyNodeTimeFormat {
    static let timeFieldIDs: Set<String> = ["test-time"]

    static func display(field: OverviewPolicyInspectionField, locale: Locale) -> String? {
        guard timeFieldIDs.contains(field.id), let date = date(from: field.value) else { return nil }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)
        )
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(trimmed) {
            return date
        }
        if let date = try? Date.ISO8601FormatStyle().parse(trimmed) {
            return date
        }
        // Go's RFC 3339 nanosecond form carries more fractional digits than
        // the ISO 8601 parser accepts; the instant to the second is unchanged.
        guard let range = trimmed.range(of: #"\.\d+"#, options: .regularExpression) else { return nil }
        return try? Date.ISO8601FormatStyle().parse(trimmed.replacingCharacters(in: range, with: ""))
    }
}

/// The controller's own delay history, oldest to newest. A zero delay is a
/// reported failure and draws as a short red marker rather than a latency.
private struct ProxyNodeLatencyHistory: View {
    @Environment(\.micaAppLanguage) private var language

    let history: [ProxyDelayHistorySnapshot]

    private var delays: [Int] {
        history.compactMap(\.delay)
    }

    var body: some View {
        let delays = delays
        if delays.count >= 2 {
            let peak = max(delays.max() ?? 1, 1)
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                Text(MicaStrings.localizedKey("routing.delay_history", language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(delays.enumerated()), id: \.offset) { _, delay in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(delay > 0 ? OverviewFormat.latencyTint(delay) : MicaTheme.statusError)
                            .frame(
                                maxWidth: 14,
                                minHeight: 3,
                                maxHeight: delay > 0 ? max(3, 32 * CGFloat(delay) / CGFloat(peak)) : 3
                            )
                            .help(delay > 0 ? OverviewFormat.latency(delay) : timeoutLabel)
                    }
                }
                .frame(height: 32, alignment: .bottom)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MicaStrings.localizedKey("routing.delay_history", language: language))
            .accessibilityValue(
                delays.map { $0 > 0 ? OverviewFormat.latency($0) : timeoutLabel }
                    .joined(separator: ", ")
            )
        }
    }

    private var timeoutLabel: String {
        LatencyHealthGrade.timeout.label(language: language)
    }
}

/// Balanced columns for detail cards: two columns once each card can keep a
/// readable key-value width, otherwise one. Each card joins the shorter
/// column, preserving section order within a column.
private struct ProxyNodeSectionColumns: Layout {
    var spacing: CGFloat
    var minimumColumnWidth: CGFloat = 300

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        let placement = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: placement.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in placement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let columns = subviews.count > 1 && width >= minimumColumnWidth * 2 + spacing ? 2 : 1
        let columnWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights = Array(repeating: CGFloat(0), count: columns)
        var frames: [CGRect] = []
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let y = heights[column] == 0 ? 0 : heights[column] + spacing
            frames.append(CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: y,
                width: columnWidth,
                height: height
            ))
            heights[column] = y + height
        }
        return (frames, heights.max() ?? 0)
    }
}

struct ProxyNodePreviewAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ProxyNodeHoverRequest: Equatable {
    let memberID: String?
    let isScrolling: Bool
    var inspectedMemberID: String? = nil

    var previewCandidateID: String? {
        isScrolling || memberID == inspectedMemberID ? nil : memberID
    }
}

/// The page passes this reference without observing its fields. Pointer movement
/// therefore invalidates the preview leaf and the two affected rows, not the
/// directory, command bar, accessibility catalog, and whole node list.
@MainActor
@Observable
final class ProxyNodeHoverState {
    private(set) var memberID: String?

    func setHovered(_ memberID: String, isHovered: Bool) {
        if isHovered {
            self.memberID = memberID
        } else if self.memberID == memberID {
            self.memberID = nil
        }
    }

    func reset() {
        memberID = nil
    }
}

/// The delayed preview owns its state locally. Keep the current hover candidate
/// while scrolling so a stationary pointer resumes its preview after scrolling.
struct ProxyNodeHoverOverlay: View {
    @Environment(\.micaAppLanguage) private var language
    @State private var previewMemberID: String?

    let state: ProxyNodeHoverState
    let scrollInteractionTracker: ProxyScrollInteractionTracker
    let presentation: ProxyActiveGroupPresentation
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { geometry in
            if !scrollInteractionTracker.isScrolling,
               let previewMemberID,
               previewMemberID == state.memberID,
               previewMemberID != presentation.inspectedMemberID,
               let anchor = anchors[previewMemberID],
               let member = presentation.members.first(where: { $0.id == previewMemberID }) {
                let snapshot = ProxyNodeInspectionProjection.snapshot(
                    member: member, in: presentation.occurrence, language: language
                )
                if let layout = ProxyNodePreviewLayout.resolve(
                    viewport: geometry.size,
                    anchor: geometry[anchor],
                    fieldCount: snapshot.fields.count
                ) {
                    ProxyNodeHoverPreview(snapshot: snapshot, size: layout.frame.size)
                        .offset(x: layout.frame.minX, y: layout.frame.minY)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: request) {
            previewMemberID = nil
            let candidateRequest = request
            guard let candidate = candidateRequest.previewCandidateID else { return }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, candidateRequest == request else { return }
            previewMemberID = candidate
        }
    }

    private var request: ProxyNodeHoverRequest {
        ProxyNodeHoverRequest(
            memberID: state.memberID,
            isScrolling: scrollInteractionTracker.isScrolling,
            inspectedMemberID: presentation.inspectedMemberID
        )
    }
}

struct ProxyNodePreviewLayout: Equatable {
    let frame: CGRect

    static func resolve(
        viewport: CGSize,
        anchor: CGRect,
        fieldCount: Int
    ) -> Self? {
        let inset: CGFloat = 8
        let available = CGRect(origin: .zero, size: viewport).insetBy(dx: inset, dy: inset)
        guard available.width >= 220, available.height >= 144,
              anchor.intersects(CGRect(origin: .zero, size: viewport)) else { return nil }
        let width = min(340, available.width)
        let height = min(CGFloat(104 + min(6, max(0, fieldCount)) * 24), available.height)
        let below = anchor.maxY + 4
        let proposedY = below + height <= available.maxY
            ? below : anchor.minY - height - 4
        return Self(frame: CGRect(
            x: available.maxX - width,
            y: min(max(available.minY, proposedY), available.maxY - height),
            width: width,
            height: height
        ))
    }
}

/// A pointer-transparent overlay, not a window or focusable popover.
/// Preview never exposes a secret, even when the inline detail revealed it.
struct ProxyNodeHoverPreview: View {
    @Environment(\.micaAppLanguage) private var language
    let snapshot: OverviewPolicyInspectionSnapshot
    let size: CGSize

    /// Reported configuration first: it is what the row itself cannot show.
    private var fields: [OverviewPolicyInspectionField] {
        let parameters = snapshot.sections.first { $0.id == "protocol" }?.fields ?? []
        let other = snapshot.fields.filter { field in
            !parameters.contains(where: { $0.id == field.id })
        }
        return Array((parameters + other).prefix(6))
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            previewContent(fieldLimit: 6)
            previewContent(fieldLimit: 3)
            previewContent(fieldLimit: 1)
            Text(verbatim: snapshot.title)
                .micaThemeFont(.label, weight: .semibold)
                .lineLimit(2)
        }
        .padding(MicaTheme.Spacing.space3)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        // A transient layer floating above the member list: glass, not a card.
        .micaFloatingGlass()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func previewContent(fieldLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            Text(verbatim: snapshot.title)
                .micaThemeFont(.label, weight: .semibold)
                .lineLimit(2)
            ForEach(Array(fields.prefix(fieldLimit))) { field in
                HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                    Text(verbatim: field.label.resolved(language: language))
                        .foregroundStyle(MicaTheme.textSecondary)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .leading)
                    Text(verbatim: field.displayValue())
                        .micaThemeFont(field.monospaced ? .dataCaption : .caption, weight: .medium)
                        .foregroundStyle(field.tone.tint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .micaThemeFont(.caption)
            }
            Text(MicaStrings.localizedKey("routing.node_preview_hint", language: language))
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textTertiary)
                .lineLimit(2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An opened node reads as one card: its row is the tinted header and the
/// detail is the body, framed together instead of floating as a second block.
struct ProxyInspectedNodeFrame: ViewModifier {
    let isInspected: Bool

    func body(content: Content) -> some View {
        if isInspected {
            let shape = RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)
            content
                .background(MicaTheme.canvas, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(MicaTheme.accent.opacity(0.45), lineWidth: MicaTheme.Shape.hairline)
                }
                .padding(.vertical, MicaTheme.Spacing.space1)
        } else {
            content
        }
    }
}

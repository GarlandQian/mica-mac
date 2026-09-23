import MicaCore
import SwiftUI

struct ProxyNodeDetailIdentity: Hashable {
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let groupID: String
    let memberID: String
}

enum ProxyNodeInspectionProjection {
    static func snapshot(
        member: ProxyNodeRowProjection,
        in occurrence: ProxyGroupOccurrence,
        language: AppLanguage
    ) -> OverviewPolicyInspectionSnapshot {
        OverviewPolicyInspectionProjection.memberSnapshot(
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
    }
}

/// Only the opened row owns parameter views and secret reveal state.
/// The containing identity changes across member/controller/session boundaries.
struct ProxyInlineNodeDetails: View {
    @Environment(\.micaAppLanguage) private var language
    let snapshot: OverviewPolicyInspectionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            Text(verbatim: snapshot.title)
                .micaThemeFont(.label, weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    Text(MicaStrings.localizedKey(section.titleKey, language: language))
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ProxyInlineFieldLayout {
                        ForEach(section.fields) { field in
                            WorkbenchPolicyInspectionFieldRow(field: field, layout: .compact)
                        }
                    }
                }
            }
        }
        .padding(MicaTheme.Spacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surfaceRaised.opacity(0.55))
        .accessibilityIdentifier("proxy-inline-details")
    }
}

/// Two columns only when complete labels and values fit each half. A section
/// containing long IDs or metadata paths receives the full available width.
private struct ProxyInlineFieldLayout: Layout {
    private let columnSpacing: CGFloat = 28
    private let rowSpacing: CGFloat = MicaTheme.Spacing.space2

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let columns = columnCount(width: width, subviews: subviews)
        let columnWidth = max(0, (width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns))
        let heights = rowHeights(columnWidth: columnWidth, columns: columns, subviews: subviews)
        return CGSize(
            width: width,
            height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columns = columnCount(width: bounds.width, subviews: subviews)
        let columnWidth = max(0, (bounds.width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns))
        let heights = rowHeights(columnWidth: columnWidth, columns: columns, subviews: subviews)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let row = index / columns
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + columnSpacing), y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: heights[row])
            )
            if column == columns - 1 { y += heights[row] + rowSpacing }
        }
    }

    private func columnCount(width: CGFloat, subviews: Subviews) -> Int {
        guard subviews.count > 1 else { return 1 }
        let halfWidth = (width - columnSpacing) / 2
        return subviews.allSatisfy { $0.sizeThatFits(.unspecified).width <= halfWidth } ? 2 : 1
    }

    private func rowHeights(columnWidth: CGFloat, columns: Int, subviews: Subviews) -> [CGFloat] {
        var heights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            if index % columns == 0 {
                heights.append(height)
            } else {
                heights[heights.count - 1] = max(heights[heights.count - 1], height)
            }
        }
        return heights
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

    private var fields: [OverviewPolicyInspectionField] {
        let parameters = snapshot.sections.first { $0.id == "protocol" }?.fields ?? []
        let other = snapshot.fields.filter { field in
            field.id != "group" && field.id != "group-type"
                && !parameters.contains(where: { $0.id == field.id })
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
        .background(MicaTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MicaTheme.Metrics.badgeRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MicaTheme.Metrics.badgeRadius)
                .stroke(MicaTheme.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
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
                        .frame(width: 100, alignment: .leading)
                    Text(verbatim: field.displayValue())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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

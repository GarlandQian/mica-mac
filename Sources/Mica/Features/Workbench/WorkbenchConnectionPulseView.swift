import Foundation
import MicaCore
import SwiftUI

struct WorkbenchConnectionPulseStrip: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchConnectionPulseProjection
    var onSelectOwner: ((String) -> Void)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var regularLayout: some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
            metrics
                .fixedSize(horizontal: true, vertical: false)

            Divider()
                .padding(.vertical, MicaTheme.Spacing.space1)

            WorkbenchConnectionOwnerDistribution(
                owners: projection.owners,
                remainingCount: projection.remainingOwnerCount,
                totalCount: projection.visibleCount,
                onSelectOwner: onSelectOwner
            )
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            metrics

            WorkbenchConnectionOwnerDistribution(
                owners: projection.owners,
                remainingCount: projection.remainingOwnerCount,
                totalCount: projection.visibleCount,
                onSelectOwner: onSelectOwner
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            metricsRow
            metricsGrid
        }
    }

    private var metricsRow: some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
            countMetric
            uploadMetric
            downloadMetric
            totalMetric
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var metricsGrid: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: MicaTheme.Spacing.space3,
            verticalSpacing: MicaTheme.Spacing.space2
        ) {
            GridRow {
                countMetric
                uploadMetric
            }
            GridRow {
                downloadMetric
                totalMetric
            }
        }
    }

    private var countMetric: some View {
        metric(
            titleKey: "overview.connection_count",
            value: projection.visibleCount.formatted(),
            detail: countDetail,
            systemImage: projection.scope == .active
                ? "point.3.connected.trianglepath.dotted"
                : "clock",
            tint: projection.scope == .active
                ? MicaTheme.statusOK
                : .secondary
        )
    }

    private var uploadMetric: some View {
        metric(
            titleKey: "dashboard.col_upload",
            value: uploadValue,
            detail: uploadDetail,
            systemImage: "arrow.up",
            tint: MicaTheme.Chart.upload
        )
    }

    private var downloadMetric: some View {
        metric(
            titleKey: "dashboard.col_download",
            value: downloadValue,
            detail: downloadDetail,
            systemImage: "arrow.down",
            tint: MicaTheme.Chart.download
        )
    }

    private var totalMetric: some View {
        metric(
            titleKey: "overview.traffic_total",
            value: bytes(projection.totalBytes),
            detail: nil,
            systemImage: "sum",
            tint: MicaTheme.textSecondary
        )
    }

    private func metric(
        titleKey: String,
        value: String,
        detail: String?,
        systemImage: String,
        tint: Color
    ) -> some View {
        WorkbenchConnectionPulseMetric(
            titleKey: titleKey,
            value: value,
            detail: detail,
            systemImage: systemImage,
            tint: tint
        )
        // Task 08-23 R6: intrinsic width - capped frames truncated the
        // accumulated-bytes detail line.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var countDetail: String? {
        guard projection.isFiltered else { return nil }
        return MicaStrings.localized(
            "traffic.connection_total_count \(projection.totalCount)",
            language: language
        )
    }

    private var uploadValue: String {
        projection.scope == .active
            ? rate(projection.uploadRate)
            : bytes(projection.uploadBytes)
    }

    private var downloadValue: String {
        projection.scope == .active
            ? rate(projection.downloadRate)
            : bytes(projection.downloadBytes)
    }

    private var uploadDetail: String? {
        guard projection.scope == .active else { return nil }
        return accumulated(projection.uploadBytes)
    }

    private var downloadDetail: String? {
        guard projection.scope == .active else { return nil }
        return accumulated(projection.downloadBytes)
    }

    private func accumulated(_ value: Int64?) -> String? {
        guard let formatted = WorkbenchDataFormat.bytes(value) else { return nil }
        return MicaStrings.localized(
            "traffic.connection_accumulated \(formatted)",
            language: language
        )
    }

    private func bytes(_ value: Int64?) -> String {
        WorkbenchDataFormat.bytes(value)
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }

    private func rate(_ value: Int64?) -> String {
        WorkbenchDataFormat.rate(value.map(Int.init), language: language)
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }
}

private struct WorkbenchConnectionPulseMetric: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String
    let detail: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .caption.weight(.semibold),
                frameSize: 16
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)

                Text(verbatim: value)
                    .micaThemeFont(.dataLabel, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let detail = detail?.dataNonEmpty {
                    Text(verbatim: detail)
                        .micaThemeFont(.dataCaption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchConnectionOwnerDistribution: View {
    @Environment(\.micaAppLanguage) private var language

    let owners: [WorkbenchConnectionPulseOwner]
    let remainingCount: Int
    let totalCount: Int
    let onSelectOwner: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            HStack(spacing: MicaTheme.Spacing.space1) {
                WorkbenchSymbol(
                    systemName: "person.2",
                    tint: MicaTheme.textSecondary,
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )

                Text(
                    MicaStrings.localizedKey(
                        "overview.aggregate_by_owner",
                        language: language
                    )
                )
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
            }

            distributionBar

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaTheme.Spacing.space3) {
                    legendItems
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    legendItems
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var distributionBar: some View {
        if totalCount > 0 {
            GeometryReader { proxy in
                let segmentCount = owners.count + (remainingCount > 0 ? 1 : 0)
                let totalSpacing = CGFloat(max(0, segmentCount - 1)) * 2
                let availableWidth = max(0, proxy.size.width - totalSpacing)

                HStack(spacing: 2) {
                    ForEach(owners.enumerated(), id: \.element.id) { index, owner in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(at: index))
                            .frame(
                                width: segmentWidth(
                                    count: owner.count,
                                    availableWidth: availableWidth
                                )
                            )
                    }

                    if remainingCount > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(otherColor)
                            .frame(
                                width: segmentWidth(
                                    count: remainingCount,
                                    availableWidth: availableWidth
                                )
                            )
                    }
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(owners.enumerated(), id: \.element.id) { index, owner in
            legendItem(
                label: ownerLabel(owner.identity),
                filterTerm: ownerFilterTerm(owner.identity),
                count: owner.count,
                color: color(at: index)
            )
        }

        if remainingCount > 0 {
            legendItem(
                label: MicaStrings.localizedKey(
                    "traffic.connection_other_sources",
                    language: language
                ),
                filterTerm: nil,
                count: remainingCount,
                color: otherColor
            )
        }
    }

    @ViewBuilder
    private func legendItem(
        label: String,
        filterTerm: String?,
        count: Int,
        color: Color
    ) -> some View {
        let itemContent = HStack(spacing: MicaTheme.Spacing.space1) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: label)
                .micaThemeFont(.caption)
                .lineLimit(1)

            Text(verbatim: count.formatted())
                .micaThemeFont(.dataCaption, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help(label)

        if let filterTerm, let onSelectOwner {
            Button {
                onSelectOwner(filterTerm)
            } label: {
                itemContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        } else {
            itemContent
                .accessibilityElement(children: .combine)
        }
    }

    private func ownerFilterTerm(_ identity: WorkbenchConnectionOwnerIdentity) -> String? {
        switch identity {
        case .process(let value), .source(let value):
            value
        case .inner, .unreported:
            nil
        }
    }

    private func ownerLabel(_ identity: WorkbenchConnectionOwnerIdentity) -> String {
        switch identity {
        case .inner:
            MicaStrings.localizedKey("traffic.connection_group_inner", language: language)
        case .process(let value), .source(let value):
            value
        case .unreported:
            MicaStrings.localizedKey(
                "traffic.connection_group_unreported",
                language: language
            )
        }
    }

    private func segmentWidth(count: Int, availableWidth: CGFloat) -> CGFloat {
        guard totalCount > 0 else { return 0 }
        return availableWidth * CGFloat(count) / CGFloat(totalCount)
    }

    private var otherColor: Color {
        Color.secondary.opacity(0.45)
    }

    private func color(at index: Int) -> Color {
        switch index {
        case 0: MicaTheme.accent
        case 1: MicaTheme.Chart.download
        default: MicaTheme.Chart.upload
        }
    }
}

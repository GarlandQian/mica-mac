import Foundation
import MicaCore
import SwiftUI

struct WorkbenchConnectionPulseStrip: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchConnectionPulseProjection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
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
                totalCount: projection.visibleCount
            )
            .frame(minWidth: 260, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
            metrics

            WorkbenchConnectionOwnerDistribution(
                owners: projection.owners,
                remainingCount: projection.remainingOwnerCount,
                totalCount: projection.visibleCount
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
            tint: MicaTheme.textSecondary
        )
    }

    private var downloadMetric: some View {
        metric(
            titleKey: "dashboard.col_download",
            value: downloadValue,
            detail: downloadDetail,
            systemImage: "arrow.down",
            tint: MicaTheme.textSecondary
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
        .frame(minWidth: 104, idealWidth: 120, maxWidth: 148, alignment: .leading)
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

    private func accumulated(_ value: Int64?) -> String {
        MicaStrings.localized(
            "traffic.connection_accumulated \(bytes(value))",
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkbenchConnectionOwnerDistribution: View {
    @Environment(\.micaAppLanguage) private var language

    let owners: [WorkbenchConnectionPulseOwner]
    let remainingCount: Int
    let totalCount: Int

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
                            .fill(Color.secondary.opacity(0.4))
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
                count: remainingCount,
                color: Color.secondary.opacity(0.7)
            )
        }
    }

    private func legendItem(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
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
        .accessibilityElement(children: .combine)
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

    private func color(at index: Int) -> Color {
        switch index {
        case 0: MicaTheme.accent
        case 1: MicaTheme.textSecondary
        default: MicaTheme.textTertiary
        }
    }
}

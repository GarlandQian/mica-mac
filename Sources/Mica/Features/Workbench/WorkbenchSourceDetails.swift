import Foundation
import MicaCore
import SwiftUI

struct WorkbenchSourceFocusRail: View {
    @Environment(\.micaAppLanguage) private var language

    let projection: WorkbenchSourceFocusProjection
    let supportsUpdate: Bool
    let supportsHealthCheck: Bool
    let canUpdate: Bool
    let canHealthCheck: Bool
    let isUpdating: Bool
    let isChecking: Bool
    let update: () -> Void
    let healthCheck: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                focusIdentity
                lifecycleReadouts
                Spacer(minLength: MicaSpacing.module)
                actions
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                focusIdentity
                lifecycleReadouts
                actions
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.contentFill)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var focusIdentity: some View {
        HStack(spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: "shippingbox",
                tint: MicaDesignTokens.signalViolet,
                size: .focus
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: projection.name)
                    .micaFont(.callout, weight: .semibold)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(verbatim: projection.configuration)
                    .micaFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 180, maxWidth: 300, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lifecycleReadouts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.section) {
                updateReadout
                itemReadout
                updatedReadout
                if supportsHealthCheck {
                    healthReadout
                }
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                HStack(spacing: MicaSpacing.section) {
                    updateReadout
                    itemReadout
                }
                HStack(spacing: MicaSpacing.section) {
                    updatedReadout
                    if supportsHealthCheck {
                        healthReadout
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.provider_updatable",
            value: projection.updatableStatus,
            systemImage: "arrow.triangle.2.circlepath",
            tint: supportsUpdate ? MicaDesignTokens.signalMint : .secondary,
            monospaced: false
        )
    }

    private var itemReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.provider_items",
            value: projection.itemCount,
            systemImage: "list.number",
            tint: MicaDesignTokens.signalCyan,
            monospaced: true
        )
    }

    private var updatedReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.updated_at",
            value: projection.updatedAt,
            systemImage: "clock.arrow.circlepath",
            tint: .secondary,
            monospaced: true
        )
    }

    private var healthReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.provider_health_check",
            value: projection.health ?? projection.healthAvailability,
            systemImage: "waveform.path.ecg",
            tint: projection.health == nil
                ? MicaDesignTokens.signalCyan
                : MicaDesignTokens.signalMint,
            monospaced: projection.health != nil
        )
    }

    private var actions: some View {
        HStack(spacing: MicaSpacing.tight) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
            } else if supportsHealthCheck {
                WorkbenchIconCommand(
                    titleKey: "action.provider_health_check",
                    systemImage: "waveform.path.ecg",
                    isEnabled: canHealthCheck,
                    action: healthCheck
                )
            }

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: MicaBounds.iconControlSize, minHeight: MicaBounds.iconControlSize)
            } else if supportsUpdate {
                WorkbenchIconCommand(
                    titleKey: "action.provider_update",
                    systemImage: "arrow.clockwise",
                    isEnabled: canUpdate,
                    action: update
                )
            }
        }
        .frame(minHeight: MicaBounds.controlMinHeight, alignment: .trailing)
    }
}

struct WorkbenchProviderUpdateAllProgressView: View {
    @Environment(\.micaAppLanguage) private var language

    let progress: ProviderUpdateAllProgress

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaSpacing.module) {
                    currentStatus
                    Spacer(minLength: MicaSpacing.module)
                    counters
                }

                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    currentStatus
                    counters
                }
            }

            ProgressView(
                value: Double(progress.completed),
                total: Double(max(progress.total, 1))
            )
            .progressViewStyle(.linear)
            .tint(progress.failed > 0 ? MicaDesignTokens.signalAmber : MicaDesignTokens.accent)
            .accessibilityLabel(
                MicaStrings.localizedKey(
                    "traffic.provider_update_all_progress",
                    language: language
                )
            )
            .accessibilityValue(
                MicaStrings.localized(
                    "traffic.provider_update_completed_count \(progress.completed) \(progress.total)",
                    language: language
                )
            )

            if !progress.failures.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        ForEach(progress.failures) { failure in
                            Label {
                                Text(verbatim: "\(failure.target.name): \(failure.message)")
                                    .micaFont(.caption)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(MicaDesignTokens.signalAmber)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 112)
            }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .background(MicaDesignTokens.elevatedFill)
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(progressTint)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
    }

    private var progressTint: Color {
        if progress.isRunning {
            return MicaDesignTokens.signalCyan
        }
        return progress.failed > 0
            ? MicaDesignTokens.signalAmber
            : MicaDesignTokens.signalMint
    }

    private var currentStatus: some View {
        HStack(spacing: MicaSpacing.row) {
            if progress.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: progress.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        progress.failed == 0
                            ? MicaDesignTokens.signalMint
                            : MicaDesignTokens.signalAmber
                    )
                    .accessibilityHidden(true)
            }

            Text(verbatim: currentStatusText)
                .micaFont(.callout, weight: .semibold)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var currentStatusText: String {
        if let current = progress.current {
            return MicaStrings.localized(
                "traffic.provider_update_current \(current.name)",
                language: language
            )
        }

        return MicaStrings.localizedKey(
            progress.isRunning
                ? "traffic.provider_update_refreshing"
                : "traffic.provider_update_complete",
            language: language
        )
    }

    private var counters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                completedCounter
                succeededCounter
                failedCounter
            }

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                completedCounter
                succeededCounter
                failedCounter
            }
        }
    }

    private var completedCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_completed_count \(progress.completed) \(progress.total)",
                language: language
            ),
            systemImage: "list.bullet"
        )
    }

    private var succeededCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_succeeded_count \(progress.succeeded)",
                language: language
            ),
            systemImage: "checkmark.circle",
            tint: MicaDesignTokens.signalMint
        )
    }

    private var failedCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_failed_count \(progress.failed)",
                language: language
            ),
            systemImage: "exclamationmark.triangle",
            tint: progress.failed > 0 ? MicaDesignTokens.signalAmber : .secondary
        )
    }

    private func progressCounter(
        _ text: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        Label {
            Text(verbatim: text)
                .micaFont(.caption).monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchSourceInspector: View {
    @Environment(\.micaAppLanguage) private var language

    let row: WorkbenchSourceRow?
    let updateFailure: String?
    let healthFailure: String?
    let close: () -> Void

    var body: some View {
        if let row {
            let source = row.source
            WorkbenchDataInspectorShell(
                title: source.name,
                statusText: MicaStrings.localizedKey(
                    source.updatable
                        ? "traffic.provider_updatable_yes"
                        : "traffic.provider_updatable_no",
                    language: language
                ),
                statusTint: source.updatable ? MicaDesignTokens.signalMint : .secondary,
                close: close
            ) {
                WorkbenchDataInspectorSection("traffic.source_section_configuration") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.sourceConfiguration(row)
                    )
                }

                WorkbenchDataInspectorSection("traffic.source_section_status") {
                    WorkbenchDataInspectorValueList(
                        values: WorkbenchDataInspectorProjection.sourceStatus(row)
                    )
                    if let updateFailure {
                        WorkbenchDataInspectorField(
                            titleKey: "traffic.update_status",
                            value: updateFailure
                        )
                    }
                    if let healthFailure {
                        WorkbenchDataInspectorField(
                            titleKey: "traffic.health_check_status",
                            value: healthFailure
                        )
                    }
                }
            }
        }
    }
}

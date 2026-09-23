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
            HStack(spacing: MicaTheme.Spacing.space3) {
                focusIdentity
                    .frame(minWidth: 180)
                lifecycleReadouts
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: MicaTheme.Spacing.space3)
                actions
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                HStack(spacing: MicaTheme.Spacing.space2) {
                    focusIdentity
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: MicaTheme.Spacing.space2)
                    actions
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }

                ScrollView(.horizontal) {
                    lifecycleReadouts
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.bottom, MicaTheme.Spacing.space1)
                }
                .scrollIndicators(.automatic)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var focusIdentity: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            WorkbenchSymbol(
                systemName: "shippingbox",
                tint: MicaTheme.textSecondary,
                size: .focus
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: projection.name)
                    .micaThemeFont(.label, weight: .semibold)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(projection.name)
                Text(verbatim: projection.configuration)
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(projection.configuration)
            }
        }
        .frame(minWidth: 0, maxWidth: 300, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lifecycleReadouts: some View {
        HStack(spacing: MicaTheme.Spacing.space4) {
            updateReadout
            itemReadout
            updatedReadout
            if supportsHealthCheck {
                healthReadout
            }
        }
    }

    private var updateReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.provider_updatable",
            value: projection.updatableStatus,
            systemImage: "arrow.triangle.2.circlepath",
            tint: MicaTheme.textSecondary,
            monospaced: false
        )
    }

    private var itemReadout: some View {
        WorkbenchDecisionReadout(
            titleKey: "traffic.provider_items",
            value: projection.itemCount,
            systemImage: "list.number",
            tint: MicaTheme.textSecondary,
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
            tint: MicaTheme.textSecondary,
            monospaced: projection.health != nil
        )
    }

    private var actions: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        minWidth: MicaTheme.Metrics.iconControlSize,
                        minHeight: MicaTheme.Metrics.iconControlSize
                    )
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
                    .frame(
                        minWidth: MicaTheme.Metrics.iconControlSize,
                        minHeight: MicaTheme.Metrics.iconControlSize
                    )
            } else if supportsUpdate {
                WorkbenchIconCommand(
                    titleKey: "action.provider_update",
                    systemImage: "arrow.clockwise",
                    isEnabled: canUpdate,
                    action: update
                )
            }
        }
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .trailing)
    }
}

struct WorkbenchProviderUpdateAllProgressView: View {
    @Environment(\.micaAppLanguage) private var language

    let progress: ProviderUpdateAllProgress

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaTheme.Spacing.space3) {
                    currentStatus
                    Spacer(minLength: MicaTheme.Spacing.space3)
                    counters
                }

                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    currentStatus
                    counters
                }
            }

            ProgressView(
                value: Double(progress.completed),
                total: Double(max(progress.total, 1))
            )
            .progressViewStyle(.linear)
            .tint(progress.failed > 0 ? MicaTheme.statusWarning : MicaTheme.accent)
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
                    LazyVStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                        ForEach(progress.failures) { failure in
                            Label {
                                Text(verbatim: "\(failure.target.name): \(failure.message)")
                                    .micaThemeFont(.caption)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(MicaTheme.statusWarning)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 112)
            }
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .background(MicaTheme.surfaceRaised)
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
            return MicaTheme.accent
        }
        return progress.failed > 0
            ? MicaTheme.statusWarning
            : MicaTheme.statusOK
    }

    private var currentStatus: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if progress.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: progress.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        progress.failed == 0
                            ? MicaTheme.statusOK
                            : MicaTheme.statusWarning
                    )
                    .accessibilityHidden(true)
            }

            Text(verbatim: currentStatusText)
                .micaThemeFont(.label, weight: .semibold)
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
            HStack(spacing: MicaTheme.Spacing.space3) {
                completedCounter
                succeededCounter
                failedCounter
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
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
            tint: MicaTheme.statusOK
        )
    }

    private var failedCounter: some View {
        progressCounter(
            MicaStrings.localized(
                "traffic.provider_update_failed_count \(progress.failed)",
                language: language
            ),
            systemImage: "exclamationmark.triangle",
            tint: progress.failed > 0 ? MicaTheme.statusWarning : .secondary
        )
    }

    private func progressCounter(
        _ text: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        Label {
            Text(verbatim: text)
                .micaThemeFont(.dataCaption)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Source detail content rendered by the workspace inspector container
/// (`WorkbenchInspectorContainer`, design.md §3); the live row resolves through
/// the destination-registered `sourceRowResolver` (task 08-17 Phase 5B).
/// Mutation affordances (update / health check) stay on the focus rail; this
/// inspector stays read-only and shows the complete controller-reported field
/// set plus any per-provider update / health-check failure.
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
                statusTint: MicaTheme.textSecondary,
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

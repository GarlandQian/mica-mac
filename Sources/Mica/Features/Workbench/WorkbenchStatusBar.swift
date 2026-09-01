import Foundation
import MicaCore
import SwiftUI

// MARK: - Toolbar

enum WorkbenchSessionControlKind: Equatable {
    case test
    case refresh
    case pause
}

struct WorkbenchSessionControlButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let kind: WorkbenchSessionControlKind

    var body: some View {
        let title = MicaStrings.localizedKey(titleKey, language: language)
        let help = MicaStrings.localizedKey(helpKey, language: language)

        Button(action: perform) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(
                    width: MicaTheme.Metrics.iconControlSize,
                    height: MicaTheme.Metrics.iconControlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text(title))
    }

    private var session: ControllerSessionPresentationState {
        appModel.controllerSessionPresentation
    }

    private var titleKey: String {
        switch kind {
        case .test:
            "action.test"
        case .refresh:
            "action.refresh"
        case .pause:
            session.controls.dashboardUpdatesPaused ? "live.resume" : "live.pause"
        }
    }

    private var helpKey: String {
        switch kind {
        case .test:
            "dashboard.help_test_controller"
        case .refresh:
            "dashboard.help_refresh_controller"
        case .pause:
            titleKey
        }
    }

    private var systemImage: String {
        switch kind {
        case .test:
            MicaSymbols.Command.test
        case .refresh:
            MicaSymbols.Command.refresh
        case .pause:
            session.controls.dashboardUpdatesPaused
                ? MicaSymbols.Operation.resume
                : MicaSymbols.Operation.pause
        }
    }

    private var tint: Color {
        kind == .pause && session.controls.dashboardUpdatesPaused
            ? MicaTheme.statusWarning
            : .primary
    }

    private var isEnabled: Bool {
        switch kind {
        case .test:
            appModel.canTestSelectedRouter
        case .refresh:
            appModel.canRefreshSelectedRouter
        case .pause:
            appModel.canTogglePresentationPause
        }
    }

    private func perform() {
        guard isEnabled else { return }
        switch kind {
        case .test:
            appModel.testSelectedRouter()
        case .refresh:
            appModel.refreshSelectedRouter()
        case .pause:
            appModel.toggleDashboardUpdatesPaused()
        }
    }
}

// MARK: - Status

struct WorkbenchOperationOutcomePresentation: Equatable {
    enum Tone: Equatable {
        case success
        case partial
        case failure
    }

    let tone: Tone
    let titleKey: String
    let symbolName: String
    let message: String
    let action: String?
    let target: String?
    let nextStep: String?

    init?(operationState: OperationState?) {
        guard let operationState else { return nil }

        switch operationState.kind {
        case .working:
            return nil
        case .success:
            tone = .success
            titleKey = "lifecycle.success"
            symbolName = "checkmark.circle.fill"
        case .partial:
            tone = .partial
            titleKey = "lifecycle.partial"
            symbolName = "exclamationmark.triangle.fill"
        case .error:
            tone = .failure
            titleKey = "lifecycle.failed"
            symbolName = "xmark.octagon.fill"
        }

        message = operationState.message
        action = Self.normalized(operationState.action)
        target = Self.normalized(operationState.target)
        nextStep = Self.normalized(operationState.nextStep)
    }

    var context: String? {
        [action, target]
            .compactMap { $0 }
            .joined(separator: " - ")
            .nilIfEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct WorkbenchBottomChrome: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        WorkbenchStatusBar(operationState: appModel.operationState)
    }
}

private struct WorkbenchStatusBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let operationState: OperationState?

    var body: some View {
        let status = sessionStatus

        ViewThatFits(in: .horizontal) {
            statusRow(status: status, showsTimestamp: true)
                .fixedSize(horizontal: true, vertical: false)
            statusRow(status: status, showsTimestamp: false)
                .fixedSize(horizontal: true, vertical: false)
            compactStatusRow(status: status)
        }
        .micaThemeFont(.caption)
        .frame(
            maxWidth: .infinity,
            minHeight: MicaTheme.Metrics.statusBarHeight,
            alignment: .leading
        )
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .background(MicaTheme.canvas)
        .overlay(alignment: .top) { MicaHairlineSeparator() }
        .accessibilityElement(children: .combine)
    }

    private func statusRow(
        status: WorkbenchSessionStatus,
        showsTimestamp: Bool
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
            activityIdentity(status: status, compact: false)

            if showsTimestamp, let timestamp = status.timestamp {
                statusDivider
                timestampLabel(timestamp)
            }
        }
    }

    private func compactStatusRow(status: WorkbenchSessionStatus) -> some View {
        HStack(spacing: MicaTheme.Spacing.space3) {
            activityIdentity(status: status, compact: true)
                .layoutPriority(2)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func activityIdentity(
        status: WorkbenchSessionStatus,
        compact: Bool
    ) -> some View {
        if let operationOutcome {
            operationIdentity(operationOutcome, compact: compact)
        } else {
            sessionIdentity(status)
        }
    }

    private func sessionIdentity(_ status: WorkbenchSessionStatus) -> some View {
        Label {
            Text(verbatim: status.summary)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
        }
        .help(status.summary)
    }

    private func operationIdentity(
        _ presentation: WorkbenchOperationOutcomePresentation,
        compact: Bool
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Image(systemName: presentation.symbolName)
                .foregroundStyle(operationTint(presentation.tone))
                .accessibilityHidden(true)

            Text(
                MicaStrings.localizedKey(
                    presentation.titleKey,
                    language: language
                )
            )
            .fontWeight(.semibold)

            Text(verbatim: presentation.message)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            if !compact, let context = presentation.context {
                statusDivider

                Text(verbatim: context)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            if !compact, let nextStep = presentation.nextStep {
                statusDivider

                Label {
                    Text(verbatim: nextStep)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: MicaSymbols.Data.nextStep)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
            }
        }
        .help(operationHelp(presentation))
    }

    private func operationTint(
        _ tone: WorkbenchOperationOutcomePresentation.Tone
    ) -> Color {
        switch tone {
        case .success:
            MicaTheme.statusOK
        case .partial:
            MicaTheme.statusWarning
        case .failure:
            MicaTheme.statusError
        }
    }

    private func operationHelp(
        _ presentation: WorkbenchOperationOutcomePresentation
    ) -> String {
        var lines = [
            MicaStrings.localizedKey(
                presentation.titleKey,
                language: language
            ),
            presentation.message,
        ]

        if let context = presentation.context {
            lines.append(context)
        }

        if let nextStep = presentation.nextStep {
            lines.append(
                [
                    MicaStrings.localizedKey(
                        "diagnostics.check_next",
                        language: language
                    ),
                    nextStep,
                ]
                .joined(separator: ": ")
            )
        }

        return lines.joined(separator: "\n")
    }

    private var statusDivider: some View {
        MicaHairlineSeparator(axis: .vertical)
            .frame(height: 14)
    }

    private func timestampLabel(_ timestamp: Date) -> some View {
        Label {
            Text(timestamp, format: .dateTime.hour().minute().second())
                .micaThemeFont(.dataLabel)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .foregroundStyle(MicaTheme.textSecondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var operationOutcome: WorkbenchOperationOutcomePresentation? {
        WorkbenchOperationOutcomePresentation(operationState: operationState)
    }

    private var sessionStatus: WorkbenchSessionStatus {
        let session = appModel.controllerSessionPresentation
        let state = session.state
        let lastSuccessAt = session.lastSuccessAt

        if let operation = operationState, operation.kind == .working {
            return WorkbenchSessionStatus(
                summary: operation.message,
                symbol: "arrow.clockwise",
                tint: MicaTheme.accent,
                timestamp: lastSuccessAt
            )
        }

        let controls = session.controls
        if controls.dashboardUpdatesPaused {
            return WorkbenchSessionStatus(
                summary: MicaStrings.localizedKey(
                    "operation.dashboard_updates_paused",
                    language: language
                ),
                symbol: "pause.circle.fill",
                tint: MicaTheme.statusWarning,
                timestamp: controls.presentationPausedAt
            )
        }

        switch state {
        case .idle:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "circle",
                tint: MicaTheme.textTertiary
            )
        case .connecting:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "arrow.triangle.2.circlepath",
                tint: MicaTheme.accent
            )
        case .staleReconnecting(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "arrow.triangle.2.circlepath",
                tint: MicaTheme.statusWarning,
                timestamp: lastSuccessAt
            )
        case .live:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "checkmark.circle.fill",
                tint: MicaTheme.statusOK
            )
        case .partial(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "exclamationmark.triangle.fill",
                tint: MicaTheme.statusWarning,
                timestamp: lastSuccessAt
            )
        case .failedBeforeFirstSnapshot(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaTheme.statusError,
                timestamp: nil
            )
        case .failed(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaTheme.statusError,
                timestamp: lastSuccessAt
            )
        case .stopped:
            return makeSessionStatus(
                state: state,
                lastSuccessAt: lastSuccessAt,
                symbol: "stop.circle",
                tint: MicaTheme.textTertiary
            )
        }
    }

    private func makeSessionStatus(
        state: LiveSessionState,
        lastSuccessAt: Date?,
        symbol: String,
        tint: Color
    ) -> WorkbenchSessionStatus {
        WorkbenchSessionStatus(
            summary: state.label(language: language),
            symbol: symbol,
            tint: tint,
            timestamp: lastSuccessAt
        )
    }
}

private struct WorkbenchSessionStatus {
    let summary: String
    let symbol: String
    let tint: Color
    let timestamp: Date?
}

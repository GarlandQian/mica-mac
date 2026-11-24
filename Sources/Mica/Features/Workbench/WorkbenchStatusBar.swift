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

        // Native toolbar label: the Liquid Glass toolbar supplies the
        // capsule, hover, pressed, and overflow-menu presentations.
        Button(action: perform) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
            }
        }
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
    var onOpenDiagnostics: (() -> Void)? = nil

    var body: some View {
        WorkbenchStatusBar(
            operationState: appModel.operationState,
            onOpenDiagnostics: onOpenDiagnostics
        )
    }
}

private struct WorkbenchStatusBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let operationState: OperationState?
    let onOpenDiagnostics: (() -> Void)?

    var body: some View {
        let status = sessionStatus

        HStack(spacing: MicaTheme.Spacing.space3) {
            sessionIdentity(status)
                .layoutPriority(1)

            if let displayableTime = workbenchDisplayableDate(status.timestamp) {
                timestampLabel(displayableTime)
                    .layoutPriority(0)
            }

            if let outcome = operationOutcome {
                operationPill(outcome)
                    .layoutPriority(2)
            }

            Spacer(minLength: MicaTheme.Spacing.space2)

            HStack(spacing: MicaTheme.Spacing.space2) {
                WorkbenchStatusBarModeControl()
                WorkbenchStatusBarTrafficTicker()
            }
            .layoutPriority(1)
        }
        .micaThemeFont(.caption)
        .frame(
            maxWidth: .infinity,
            minHeight: MicaTheme.Metrics.statusBarHeight,
            maxHeight: MicaTheme.Metrics.statusBarHeight,
            alignment: .leading
        )
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .background(MicaTheme.surfaceSecondary)
        .overlay(alignment: .top) { MicaHairlineSeparator() }
        .task(id: operationState) {
            guard let activeState = operationState, activeState.kind == .success else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, appModel.operationState == activeState else { return }
            appModel.operationState = nil
        }
    }

    @ViewBuilder
    private func sessionIdentity(_ status: WorkbenchSessionStatus) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if status.isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tint)
                    .accessibilityHidden(true)
            }

            Text(verbatim: status.summary)
                .foregroundStyle(MicaTheme.textPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(status.summary)
    }

    @ViewBuilder
    private func operationPill(
        _ presentation: WorkbenchOperationOutcomePresentation
    ) -> some View {
        let tint = operationTint(presentation.tone)
        let opensDiagnostics = (presentation.tone == .failure || presentation.tone == .partial)
            && onOpenDiagnostics != nil

        HStack(spacing: MicaTheme.Spacing.space1) {
            if opensDiagnostics, let onOpenDiagnostics {
                Button {
                    onOpenDiagnostics()
                } label: {
                    operationPillLabel(presentation, tint: tint)
                }
                .buttonStyle(.plain)
            } else {
                operationPillLabel(presentation, tint: tint)
            }

            Button {
                appModel.operationState = nil
            } label: {
                Image(systemName: "xmark")
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(MicaStrings.localizedKey("action.close", language: language))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .micaSoftPill(tint)
        .help(operationHelp(presentation))
    }

    private func operationPillLabel(
        _ presentation: WorkbenchOperationOutcomePresentation,
        tint: Color
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Image(systemName: presentation.symbolName)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(MicaStrings.localizedKey(presentation.titleKey, language: language))
                .fontWeight(.semibold)
                .foregroundStyle(tint)

            Text(verbatim: presentation.message)
                .foregroundStyle(MicaTheme.textPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
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

    private func timestampLabel(_ timestamp: Date) -> some View {
        Label {
            Text(timestamp, format: .dateTime.hour().minute().second())
                .micaThemeFont(.dataCaption)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .foregroundStyle(MicaTheme.textTertiary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var operationOutcome: WorkbenchOperationOutcomePresentation? {
        WorkbenchOperationOutcomePresentation(operationState: operationState)
    }

    private var sessionStatus: WorkbenchSessionStatus {
        let session = appModel.controllerSessionPresentation
        let state = session.state
        let lastSuccessAt = workbenchDisplayableDate(session.lastSuccessAt)

        if let operation = operationState, operation.kind == .working {
            return WorkbenchSessionStatus(
                summary: operation.message,
                symbol: "arrow.clockwise",
                tint: MicaTheme.accent,
                timestamp: lastSuccessAt,
                isWorking: true
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
                timestamp: workbenchDisplayableDate(controls.presentationPausedAt),
                isWorking: false
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
                timestamp: lastSuccessAt,
                isWorking: false
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
                timestamp: lastSuccessAt,
                isWorking: false
            )
        case .failedBeforeFirstSnapshot(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaTheme.statusError,
                timestamp: nil,
                isWorking: false
            )
        case .failed(let message):
            return WorkbenchSessionStatus(
                summary: message,
                symbol: "xmark.octagon.fill",
                tint: MicaTheme.statusError,
                timestamp: lastSuccessAt,
                isWorking: false
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
            timestamp: lastSuccessAt,
            isWorking: false
        )
    }
}

private struct WorkbenchSessionStatus {
    let summary: String
    let symbol: String
    let tint: Color
    let timestamp: Date?
    let isWorking: Bool
}

private struct WorkbenchStatusBarModeControl: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        let options = availableModeOptions
        if appModel.selectedRouter != nil, !options.isEmpty {
            let currentMode = appModel.controllerMetadata.mode
            let canSwitch = canSwitchMode
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        guard !modesMatch(option, currentMode),
                              let scope = LiveCommandScope(
                                controllerID: appModel.selectedRouterID,
                                generation: appModel.controllerSessionPresentation.generation
                              ) else { return }
                        appModel.setMode(option, scope: scope)
                    } label: {
                        Label(
                            MicaStrings.displayMode(option, language: language),
                            systemImage: modesMatch(option, currentMode) ? "checkmark" : "arrow.triangle.branch"
                        )
                    }
                    .disabled(modesMatch(option, currentMode))
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .micaThemeFont(.caption, weight: .medium)
                        .foregroundStyle(MicaTheme.accent)
                    Text(verbatim: MicaStrings.displayMode(currentMode, language: language))
                        .micaThemeFont(.caption, weight: .medium)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MicaTheme.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(MicaTheme.surfaceBorder, lineWidth: 1)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(!canSwitch)
            .opacity(canSwitch ? 1 : 0.6)
            .help(MicaStrings.localizedKey("dashboard.mode", language: language))
        }
    }

    private var availableModeOptions: [String] {
        var seen = Set<String>()
        return appModel.controllerMetadata.config.modeOptions.filter { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return seen.insert(trimmed.lowercased()).inserted
        }
    }

    private var canSwitchMode: Bool {
        guard let router = appModel.selectedRouter else { return false }
        let modeAction = appModel.modeChangeAction(for: router)
        return appModel.controllerSessionPresentation.state.allowsLiveCommands
            && appModel.supportsUnifiedAction(modeAction)
            && !appModel.changingMode
            && !appModel.hasSurgeOperationInFlight
    }

    private func modesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private struct WorkbenchStatusBarTrafficTicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let session = appModel.controllerSessionPresentation
        if appModel.selectedRouter != nil,
           appModel.selectedUnifiedCapabilities.traffic,
           session.state.allowsLiveCommands {
            let rate = appModel.liveTrafficRate
            HStack(spacing: MicaTheme.Spacing.space2) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.Chart.upload)
                    Text(verbatim: OverviewFormat.rate(rate.upload))
                        .micaThemeFont(.dataCaption, weight: .medium)
                        .foregroundStyle(MicaTheme.textSecondary)
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .micaThemeFont(.caption, weight: .semibold)
                        .foregroundStyle(MicaTheme.Chart.download)
                    Text(verbatim: OverviewFormat.rate(rate.download))
                        .micaThemeFont(.dataCaption, weight: .medium)
                        .foregroundStyle(MicaTheme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(MicaTheme.surface.opacity(0.75), in: Capsule())
            .overlay {
                Capsule().strokeBorder(MicaTheme.surfaceBorder, lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

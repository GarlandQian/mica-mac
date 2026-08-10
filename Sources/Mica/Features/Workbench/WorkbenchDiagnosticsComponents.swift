import MicaCore
import SwiftUI

// MARK: - Shared flat headings

struct WorkbenchSectionHeading: View {
    @Environment(\.micaAppLanguage) private var language

    let systemImage: String
    let titleKey: String
    var tint = MicaDesignTokens.signalCyan

    var body: some View {
        HStack(spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .callout.weight(.semibold),
                frameSize: 18
            )
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.headline, weight: .semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Diagnostics canvas and verdict

struct WorkbenchDiagnosticsCanvas<Content: View>: View {
    private let content: (CGFloat) -> Content

    init(
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = MicaBounds.pagePadding(for: geometry.size.width)
            let contentWidth = max(0, geometry.size.width - horizontalPadding * 2)

            ScrollView {
                VStack(alignment: .leading, spacing: MicaSpacing.section) {
                    content(contentWidth)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, MicaSpacing.section)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .micaObserveScrollPerformance()
        }
    }
}

struct WorkbenchDiagnosticsVerdictHeader: View {
    @Environment(\.micaAppLanguage) private var language

    let snapshot: WorkbenchDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    verdictIdentity
                    Spacer(minLength: MicaSpacing.module)
                    controllerIdentity
                }
                VStack(alignment: .leading, spacing: MicaSpacing.module) {
                    verdictIdentity
                    controllerIdentity
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaSpacing.section) {
                    freshnessFact
                    checkedFact
                    targetFact
                }
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    freshnessFact
                    checkedFact
                    targetFact
                }
            }
        }
        .padding(.bottom, MicaSpacing.module)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var verdictIdentity: some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Group {
                if snapshot.overallState == .checking {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    WorkbenchSymbol(
                        systemName: snapshot.overallState.systemImage,
                        tint: snapshot.overallState.tint,
                        font: .title.weight(.semibold),
                        frameSize: 32
                    )
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    MicaStrings.localizedKey(
                        snapshot.overallState.labelKey,
                        language: language
                    )
                )
                .micaFont(.title2, weight: .semibold)

                Text(
                    MicaStrings.localizedKey(
                        snapshot.overallState.detailKey,
                        language: language
                    )
                )
                .micaFont(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var controllerIdentity: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label {
                Text(verbatim: snapshot.controllerName)
            } icon: {
                Image(systemName: "server.rack")
                    .foregroundStyle(snapshot.overallState.tint)
            }
            .micaFont(.callout, weight: .semibold)

            Text(verbatim: snapshot.visibleTarget)
                .micaFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    private var freshnessFact: some View {
        diagnosticsFact(
            titleKey: "diagnostics.freshness",
            value: snapshot.freshness.label(language: language),
            systemImage: snapshot.freshness.systemImage,
            tint: snapshot.freshness.tint
        )
    }

    private var checkedFact: some View {
        diagnosticsFact(
            titleKey: "diagnostics.check_latest",
            value: formatted(snapshot.checkedAt),
            systemImage: "clock",
            tint: .secondary
        )
    }

    private var targetFact: some View {
        diagnosticsFact(
            titleKey: "diagnostics.technical_target_scope",
            value: MicaStrings.localizedKey(snapshot.targetScope.titleKey, language: language),
            systemImage: snapshot.targetScope == .thisMac ? "desktopcomputer" : "network",
            tint: snapshot.targetScope == .unconfigured
                ? MicaDesignTokens.signalAmber
                : MicaDesignTokens.signalCyan
        )
    }

    private func diagnosticsFact(
        titleKey: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .caption.weight(.semibold),
                frameSize: 16
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.caption2, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .micaFont(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ date: Date?) -> String {
        guard let date = workbenchDisplayableDate(date) else {
            return MicaStrings.localizedKey("diagnostics.never", language: language)
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(language.resolvedLocale)
        )
    }
}

// MARK: - Issue workspace

struct WorkbenchDiagnosticsIssueWorkspace: View {
    @Environment(\.micaAppLanguage) private var language

    let issues: [WorkbenchDiagnosticsIssue]
    let usesSplitLayout: Bool
    @Binding var selectedIssueID: String?
    let onAction: (WorkbenchDiagnosticsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            WorkbenchSectionHeading(
                systemImage: "exclamationmark.bubble",
                titleKey: "diagnostics.needs_attention",
                tint: issues.contains(where: { $0.severity == .critical })
                    ? MicaDesignTokens.signalRed
                    : MicaDesignTokens.signalAmber
            )

            if usesSplitLayout {
                HStack(alignment: .top, spacing: MicaSpacing.section) {
                    issueList(compact: false)
                        .frame(minWidth: 320, idealWidth: 350, maxWidth: 380, alignment: .topLeading)

                    Divider()

                    if let selectedIssue {
                        WorkbenchDiagnosticsIssueDetail(
                            issue: selectedIssue,
                            onAction: onAction
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                issueList(compact: true)
            }
        }
        .onMoveCommand(perform: moveSelection)
    }

    private var selectedIssue: WorkbenchDiagnosticsIssue? {
        guard let selectedIssueID else { return issues.first }
        return issues.first { $0.id == selectedIssueID }
    }

    private func issueList(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                if index > 0 { Divider() }
                WorkbenchDiagnosticsIssueRow(
                    issue: issue,
                    isSelected: selectedIssueID == issue.id
                ) {
                    selectedIssueID = issue.id
                }

                if compact, selectedIssueID == issue.id {
                    WorkbenchDiagnosticsIssueDetail(
                        issue: issue,
                        onAction: onAction
                    )
                    .padding(.leading, MicaSpacing.section)
                    .padding(.bottom, MicaSpacing.module)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !issues.isEmpty else { return }
        let currentIndex = issues.firstIndex { $0.id == selectedIssueID } ?? 0
        switch direction {
        case .up:
            selectedIssueID = issues[max(0, currentIndex - 1)].id
        case .down:
            selectedIssueID = issues[min(issues.count - 1, currentIndex + 1)].id
        case .left, .right:
            break
        @unknown default:
            break
        }
    }
}

private struct WorkbenchDiagnosticsIssueRow: View {
    @Environment(\.micaAppLanguage) private var language

    let issue: WorkbenchDiagnosticsIssue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: MicaSpacing.row) {
                Rectangle()
                    .fill(issue.severity.tint)
                    .frame(width: 3)
                    .accessibilityHidden(true)

                WorkbenchSymbol(
                    systemName: issue.severity.systemImage,
                    tint: issue.severity.tint,
                    font: .callout.weight(.semibold),
                    frameSize: 18
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: issue.title)
                        .micaFont(.callout, weight: .semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        MicaStrings.localized(
                            "diagnostics.affected_count \(issue.affectedDestinations.count)",
                            language: language
                        )
                    )
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: MicaSpacing.row)
                Image(systemName: "chevron.forward")
                    .micaFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, MicaSpacing.row)
            .padding(.trailing, MicaSpacing.row)
            .background(isSelected ? MicaDesignTokens.accentSoft : Color.clear)
            .clipShape(.rect(cornerRadius: MicaBounds.moduleRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(issue.severity.label(language: language)), \(issue.title)"
        )
        .accessibilityValue(
            MicaStrings.localized(
                "diagnostics.affected_count \(issue.affectedDestinations.count)",
                language: language
            )
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct WorkbenchDiagnosticsIssueDetail: View {
    @Environment(\.micaAppLanguage) private var language

    let issue: WorkbenchDiagnosticsIssue
    let onAction: (WorkbenchDiagnosticsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                Text(verbatim: issue.title)
                    .micaFont(.title3, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: issue.detail)
                    .micaFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !issue.affectedDestinations.isEmpty {
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    Text(MicaStrings.localizedKey("diagnostics.affected_areas", language: language))
                        .micaFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)

                    impactGrid
                }
            }

            if !issue.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(MicaStrings.localizedKey("diagnostics.evidence", language: language))
                        .micaFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, MicaSpacing.tight)

                    ForEach(Array(issue.evidence.enumerated()), id: \.element.id) { index, evidence in
                        if index > 0 { Divider() }
                        evidenceRow(evidence)
                    }
                }
            }

            if let action = issue.primaryAction {
                Button {
                    onAction(action)
                } label: {
                    Label(
                        MicaStrings.localizedKey(action.titleKey, language: language),
                        systemImage: action.systemImage
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var impactGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: MicaSpacing.row)],
            alignment: .leading,
            spacing: MicaSpacing.row
        ) {
            ForEach(issue.affectedDestinations) { destination in
                Label(
                    MicaStrings.localizedKey(destination.titleKey, language: language),
                    systemImage: destination.symbolName
                )
                .micaFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func evidenceRow(
        _ evidence: WorkbenchDiagnosticsEvidence
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                evidenceLabel(evidence)
                Spacer(minLength: MicaSpacing.module)
                evidenceValue(evidence)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                evidenceLabel(evidence)
                evidenceValue(evidence)
            }
        }
        .padding(.vertical, MicaSpacing.tight)
    }

    private func evidenceLabel(
        _ evidence: WorkbenchDiagnosticsEvidence
    ) -> some View {
        Text(MicaStrings.localizedKey(evidence.titleKey, language: language))
            .micaFont(.caption)
            .foregroundStyle(.secondary)
    }

    private func evidenceValue(
        _ evidence: WorkbenchDiagnosticsEvidence
    ) -> some View {
        Text(verbatim: evidence.value)
            .micaFont(.caption, design: evidence.monospaced ? .monospaced : .default)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

// MARK: - Available areas and evidence

struct WorkbenchDiagnosticsAvailableAreas: View {
    @Environment(\.micaAppLanguage) private var language

    let areas: [WorkbenchDiagnosticsArea]
    let onNavigate: (WorkbenchDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.module) {
            WorkbenchSectionHeading(
                systemImage: "checkmark.circle",
                titleKey: "diagnostics.available_now",
                tint: MicaDesignTokens.signalMint
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 250), spacing: MicaSpacing.module)],
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(areas) { area in
                    Button {
                        onNavigate(area.destination)
                    } label: {
                        HStack(spacing: MicaSpacing.row) {
                            WorkbenchSymbol(
                                systemName: area.systemImage,
                                tint: MicaDesignTokens.signalMint,
                                font: .callout.weight(.semibold),
                                frameSize: 18
                            )
                            Text(MicaStrings.localizedKey(area.titleKey, language: language))
                                .micaFont(.callout, weight: .medium)
                                .foregroundStyle(.primary)
                            Spacer(minLength: MicaSpacing.row)
                            Image(systemName: "arrow.up.right")
                                .micaFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, MicaSpacing.row)
                        .contentShape(.rect)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct WorkbenchDiagnosticsTechnicalDetails: View {
    @Environment(\.micaAppLanguage) private var language

    let groups: [WorkbenchDiagnosticsTechnicalGroup]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: MicaSpacing.module) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    if groupIndex > 0 { Divider() }
                    technicalGroup(group)
                }

                Label {
                    Text(
                        MicaStrings.localizedKey(
                            "diagnostics.report_excludes_credentials",
                            language: language
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(MicaDesignTokens.signalCyan)
                }
                .micaFont(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, MicaSpacing.module)
        } label: {
            WorkbenchSectionHeading(
                systemImage: "wrench.and.screwdriver",
                titleKey: "diagnostics.technical_details"
            )
        }
        .disclosureGroupStyle(.automatic)
    }

    private func technicalGroup(
        _ group: WorkbenchDiagnosticsTechnicalGroup
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MicaStrings.localizedKey(group.titleKey, language: language))
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.bottom, MicaSpacing.tight)

            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                technicalRow(item)
            }
        }
    }

    private func technicalRow(
        _ item: WorkbenchDiagnosticsTechnicalItem
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.module) {
                technicalLabel(item)
                Spacer(minLength: MicaSpacing.module)
                technicalValue(item)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                technicalLabel(item)
                technicalValue(item)
            }
        }
        .padding(.vertical, MicaSpacing.tight)
    }

    private func technicalLabel(
        _ item: WorkbenchDiagnosticsTechnicalItem
    ) -> some View {
        Text(MicaStrings.localizedKey(item.titleKey, language: language))
            .micaFont(.caption)
            .foregroundStyle(.secondary)
    }

    private func technicalValue(
        _ item: WorkbenchDiagnosticsTechnicalItem
    ) -> some View {
        Text(verbatim: item.value)
            .micaFont(.caption, design: item.monospaced ? .monospaced : .default)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

// MARK: - Shared status colors

extension ControllerHealthSummary {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .checking: MicaDesignTokens.signalCyan
        case .partial, .unknown: MicaDesignTokens.signalAmber
        case .authFailed, .wrongTarget, .offline: MicaDesignTokens.signalRed
        }
    }

    var workbenchSymbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .partial: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        case .authFailed, .wrongTarget, .offline: "xmark.octagon.fill"
        }
    }
}

extension ConnectionCheckState {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .warning: MicaDesignTokens.signalAmber
        case .failed: MicaDesignTokens.signalRed
        }
    }

    var workbenchSymbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle"
        case .failed: "xmark.octagon"
        }
    }
}

extension ControllerEndpointStatus {
    var workbenchTint: Color {
        switch self {
        case .ready: MicaDesignTokens.signalMint
        case .checking: MicaDesignTokens.signalCyan
        case .failed: MicaDesignTokens.signalRed
        case .idle: .secondary
        }
    }
}

extension CapabilityStatus {
    var workbenchTint: Color {
        switch self {
        case .supported: MicaDesignTokens.signalMint
        case .partial, .untested: MicaDesignTokens.signalAmber
        case .failed: MicaDesignTokens.signalRed
        case .unavailable: .secondary
        }
    }
}

extension WorkbenchDiagnosticsOverallState {
    var labelKey: String {
        switch self {
        case .checking: "diagnostics.verdict_checking"
        case .ready: "diagnostics.verdict_ready"
        case .needsAttention: "diagnostics.verdict_attention"
        case .blocked: "diagnostics.verdict_blocked"
        }
    }

    var detailKey: String {
        switch self {
        case .checking: "diagnostics.verdict_checking_detail"
        case .ready: "diagnostics.verdict_ready_detail"
        case .needsAttention: "diagnostics.verdict_attention_detail"
        case .blocked: "diagnostics.verdict_blocked_detail"
        }
    }

    var tint: Color {
        switch self {
        case .checking: MicaDesignTokens.signalCyan
        case .ready: MicaDesignTokens.signalMint
        case .needsAttention: MicaDesignTokens.signalAmber
        case .blocked: MicaDesignTokens.signalRed
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.circle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }
}

private extension WorkbenchDiagnosticsFreshness {
    func label(language: AppLanguage) -> String {
        switch self {
        case .checking:
            MicaStrings.localized("diagnostics.freshness_checking", language: language)
        case .live(let date):
            datedLabel("diagnostics.freshness_live %@", date: date, language: language)
        case .retained(let date):
            datedLabel("diagnostics.freshness_retained %@", date: date, language: language)
        case .paused(let date):
            datedLabel("diagnostics.freshness_paused %@", date: date, language: language)
        case .unavailable:
            MicaStrings.localized("diagnostics.freshness_unavailable", language: language)
        }
    }

    var tint: Color {
        switch self {
        case .checking: MicaDesignTokens.signalCyan
        case .live: MicaDesignTokens.signalMint
        case .retained, .paused: MicaDesignTokens.signalAmber
        case .unavailable: MicaDesignTokens.signalRed
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "arrow.clockwise"
        case .live: "dot.radiowaves.left.and.right"
        case .retained: "clock.arrow.circlepath"
        case .paused: "pause.circle"
        case .unavailable: "network.slash"
        }
    }

    private func datedLabel(
        _ key: String.LocalizationValue,
        date: Date?,
        language: AppLanguage
    ) -> String {
        let value: String
        if let date = workbenchDisplayableDate(date) {
            value = date.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(language.resolvedLocale)
            )
        } else {
            value = MicaStrings.localized("diagnostics.never", language: language)
        }
        switch self {
        case .live:
            return MicaStrings.localized("diagnostics.freshness_live \(value)", language: language)
        case .retained:
            return MicaStrings.localized("diagnostics.freshness_retained \(value)", language: language)
        case .paused:
            return MicaStrings.localized("diagnostics.freshness_paused \(value)", language: language)
        case .checking, .unavailable:
            return MicaStrings.localized(key, language: language)
        }
    }
}

private extension WorkbenchDiagnosticsIssueSeverity {
    func label(language: AppLanguage) -> String {
        switch self {
        case .critical:
            MicaStrings.localizedKey("diagnostics.severity_critical", language: language)
        case .warning:
            MicaStrings.localizedKey("diagnostics.severity_warning", language: language)
        }
    }

    var tint: Color {
        switch self {
        case .critical: MicaDesignTokens.signalRed
        case .warning: MicaDesignTokens.signalAmber
        }
    }

    var systemImage: String {
        switch self {
        case .critical: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

import Foundation
import MicaCore
import SwiftUI
import Synchronization

// MARK: - Shared data-page structure

enum WorkbenchDataWidthMode: Equatable {
    case full
    case compact
    case stacked
}

enum WorkbenchDataRowGeometry {
    /// Stable table geometry avoids row churn while leaving enough room for
    /// the two-line data cells used by Connections, Rules, Sources, and Logs.
    static let height: CGFloat = 40
}

struct WorkbenchDataWidthBudget: Equatable {
    let fullMinimum: CGFloat
    let compactMinimum: CGFloat

    func mode(for width: CGFloat) -> WorkbenchDataWidthMode {
        if width >= fullMinimum {
            .full
        } else if width >= compactMinimum {
            .compact
        } else {
            .stacked
        }
    }
}

struct WorkbenchDataResponsive<Content: View>: View {
    let budget: WorkbenchDataWidthBudget
    private let content: (WorkbenchDataWidthMode) -> Content

    init(
        budget: WorkbenchDataWidthBudget,
        @ViewBuilder content: @escaping (WorkbenchDataWidthMode) -> Content
    ) {
        self.budget = budget
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
#if DEBUG
            resolvedContent(for: budget.mode(for: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
            content(budget.mode(for: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
    }

#if DEBUG
    private func resolvedContent(for mode: WorkbenchDataWidthMode) -> Content {
        MicaPerformanceObservation.recordDebug(
            .dataTableEvaluation,
            metadata: MicaPerformanceMetadata(count: 1)
        )
        return content(mode)
    }
#endif
}

struct WorkbenchDataScrollRequest: Equatable {
    let id: String
    let token: UUID

    init(id: String, token: UUID = UUID()) {
        self.id = id
        self.token = token
    }
}

enum WorkbenchDataScrollTransition: Equatable {
    case began
    case ended
}

struct WorkbenchDataScrollPhaseState: Equatable {
    private(set) var isUserScrolling = false

    mutating func update(isUserScrolling nextValue: Bool) -> WorkbenchDataScrollTransition? {
        guard nextValue != isUserScrolling else { return nil }
        isUserScrolling = nextValue
        return nextValue ? .began : .ended
    }

    mutating func reset() {
        isUserScrolling = false
    }
}

@MainActor
private final class WorkbenchScrollPerformanceTracker {
    private var isScrolling = false

    func update(_ phase: ScrollPhase) {
        let nextIsScrolling = phase != .idle
        guard nextIsScrolling != isScrolling else { return }
        isScrolling = nextIsScrolling
        record(isScrolling: nextIsScrolling)
    }

    func finish() {
        guard isScrolling else { return }
        isScrolling = false
        record(isScrolling: false)
    }

    private func record(isScrolling: Bool) {
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: isScrolling ? 1 : 2
            )
        )
    }
}

@MainActor
private struct WorkbenchScrollPerformanceModifier: ViewModifier {
    @State private var tracker = WorkbenchScrollPerformanceTracker()

    func body(content: Content) -> some View {
#if DEBUG
        content
            .onScrollPhaseChange { _, phase in
                tracker.update(phase)
            }
            .onDisappear {
                tracker.finish()
            }
#else
        content
#endif
    }
}

@MainActor
final class WorkbenchDataInteractionCoordinator {
    private(set) var isUserScrolling = false

    fileprivate func apply(_ transition: WorkbenchDataScrollTransition) {
        switch transition {
        case .began:
            isUserScrolling = true
        case .ended:
            isUserScrolling = false
        }
    }

    fileprivate func reset() {
        isUserScrolling = false
    }
}

struct WorkbenchDataTableViewport<Content: View>: View {
    let generation: UUID
    let restorationID: String?
    let request: WorkbenchDataScrollRequest?
    let anchor: UnitPoint
    let interaction: WorkbenchDataInteractionCoordinator
    let onInteractionBegan: () -> Void
    let onInteractionEnded: () -> Void
    let onAnchorCommit: (String?) -> Void
    private let content: Content

    @State private var anchorID: String?
    @State private var phaseState = WorkbenchDataScrollPhaseState()

    init(
        generation: UUID,
        restorationID: String?,
        request: WorkbenchDataScrollRequest? = nil,
        anchor: UnitPoint = .top,
        interaction: WorkbenchDataInteractionCoordinator,
        onInteractionBegan: @escaping () -> Void = {},
        onInteractionEnded: @escaping () -> Void = {},
        onAnchorCommit: @escaping (String?) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.generation = generation
        self.restorationID = restorationID
        self.request = request
        self.anchor = anchor
        self.interaction = interaction
        self.onInteractionBegan = onInteractionBegan
        self.onInteractionEnded = onInteractionEnded
        self.onAnchorCommit = onAnchorCommit
        self.content = content()
    }

    var body: some View {
        content
            .scrollPosition(id: $anchorID, anchor: anchor)
            .onAppear {
                if anchorID == nil {
                    anchorID = restorationID
                }
            }
            .onChange(of: generation) {
                finishInteractionIfNeeded()
                anchorID = restorationID
            }
            .onChange(of: restorationID) { _, nextID in
                if !phaseState.isUserScrolling {
                    anchorID = nextID
                }
            }
            .onChange(of: request) { _, nextRequest in
                if let nextRequest {
                    anchorID = nextRequest.id
                }
            }
            .onScrollPhaseChange { _, phase in
                handleScrollPhase(phase)
            }
            .onDisappear {
                finishInteractionIfNeeded()
                onAnchorCommit(anchorID)
            }
    }

    private func handleScrollPhase(_ phase: ScrollPhase) {
        let isUserScrolling = switch phase {
        case .tracking, .interacting, .decelerating:
            true
        case .idle, .animating:
            false
        }

        if let transition = phaseState.update(isUserScrolling: isUserScrolling) {
            apply(transition)
        }

        if phase == .idle {
            onAnchorCommit(anchorID)
        }
    }

    private func finishInteractionIfNeeded() {
        if let transition = phaseState.update(isUserScrolling: false) {
            apply(transition)
        } else {
            interaction.reset()
        }
        phaseState.reset()
    }

    private func apply(_ transition: WorkbenchDataScrollTransition) {
#if DEBUG
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: transition == .began ? 1 : 2
            )
        )
#endif
        interaction.apply(transition)
        switch transition {
        case .began:
            onInteractionBegan()
        case .ended:
            onInteractionEnded()
        }
    }
}

extension View {
    func micaWorkbenchTable(accessibilityLabel: String) -> some View {
        tableStyle(.bordered(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(MicaDesignTokens.contentFill)
            .tint(MicaDesignTokens.accent)
            .environment(\.defaultMinListRowHeight, WorkbenchDataRowGeometry.height)
            .accessibilityLabel(accessibilityLabel)
    }

    func micaObserveScrollPerformance() -> some View {
        modifier(WorkbenchScrollPerformanceModifier())
    }
}

struct WorkbenchDataActivityIndicator: View {
    @Environment(\.micaAppLanguage) private var language

    let isActive: Bool
    let titleKey: String

    var body: some View {
        Group {
            if isActive {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        MicaStrings.localizedKey(titleKey, language: language)
                    )
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: MicaBounds.iconControlSize,
            height: MicaBounds.controlMinHeight
        )
    }
}

struct WorkbenchDataBrowserScaffold<Commands: View, Supplementary: View, Content: View>: View {
    let staleMessage: String?
    private let commands: Commands
    private let supplementary: Supplementary
    private let content: Content

    init(
        staleMessage: String?,
        @ViewBuilder commands: () -> Commands,
        @ViewBuilder supplementary: () -> Supplementary,
        @ViewBuilder content: () -> Content
    ) {
        self.staleMessage = staleMessage
        self.commands = commands()
        self.supplementary = supplementary()
        self.content = content()
    }

    var body: some View {
        WorkbenchPageScaffold {
            VStack(spacing: 0) {
                commands

                if let staleMessage {
                    WorkbenchStaleNotice(message: staleMessage)
                }

                supplementary
            }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MicaDesignTokens.pageFill)
        }
    }
}

struct WorkbenchDataPrimaryCell: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = .secondary
    var titleIsMonospaced = false
    var detailIsMonospaced = true

    var body: some View {
        HStack(alignment: .center, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .micaFont(
                        .callout,
                        weight: .semibold,
                        design: titleIsMonospaced ? .monospaced : .default
                    )
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let detail = detail?.dataNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(
                            .caption,
                            design: detailIsMonospaced ? .monospaced : .default
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchDataText: View {
    let value: String
    var style: MicaTextStyle = .callout
    var weight: Font.Weight?
    var design: Font.Design = .default
    var tone: HierarchicalShapeStyle = .primary
    var alignment: Alignment = .leading
    var maximumLineCount = 1

    var body: some View {
        Text(verbatim: value)
            .micaFont(style, weight: weight, design: design)
            .foregroundStyle(tone)
            .lineLimit(maximumLineCount)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

struct WorkbenchDataMetric: View {
    let value: String
    var tone: HierarchicalShapeStyle = .primary

    var body: some View {
        WorkbenchDataText(
            value: value,
            style: .caption,
            design: .monospaced,
            tone: tone,
            alignment: .trailing
        )
        .monospacedDigit()
    }
}

enum WorkbenchDataState: Equatable {
    case noController
    case loading
    case unsupported
    case empty
    case filterEmpty(staleMessage: String?)
    case failed(String)
    case content(staleMessage: String?)

    var staleMessage: String? {
        switch self {
        case .filterEmpty(let message), .content(let message):
            message
        case .noController, .loading, .unsupported, .empty, .failed:
            nil
        }
    }
}

enum WorkbenchDataStateResolver {
    static func endpoint(
        hasController: Bool,
        isSupported: Bool,
        sourceCount: Int,
        visibleCount: Int,
        isFiltering: Bool,
        endpointStatus: ControllerEndpointStatus?,
        snapshotState: EnhancedSnapshotState? = nil,
        sessionState: LiveSessionState? = nil,
        language: AppLanguage = .english
    ) -> WorkbenchDataState {
        guard hasController else { return .noController }

        let endpointFailure = failureMessage(
            endpointStatus: endpointStatus,
            snapshotState: snapshotState
        )
        let sessionMessage = sessionStaleMessage(
            sessionState,
            language: language
        )
        let staleMessage = sessionMessage ?? endpointFailure
        let loading = endpointStatus?.isChecking == true
            || snapshotState?.isLoading == true
            || sessionState == .connecting

        if sourceCount == 0 {
            if !isSupported { return .unsupported }
            if loading { return .loading }
            if let staleMessage { return .failed(staleMessage) }
            return .empty
        }

        if visibleCount == 0, isFiltering {
            return .filterEmpty(staleMessage: staleMessage)
        }

        return .content(staleMessage: staleMessage)
    }

    static func logs(
        hasController: Bool,
        isSupported: Bool,
        sourceCount: Int,
        visibleCount: Int,
        isFiltering: Bool,
        streamState: LiveStreamState,
        sessionState: LiveSessionState? = nil,
        language: AppLanguage = .english
    ) -> WorkbenchDataState {
        guard hasController else { return .noController }

        let sessionMessage = sessionStaleMessage(
            sessionState,
            language: language
        )
        let staleMessage = sessionMessage
            ?? streamStaleMessage(streamState, language: language)

        if sourceCount == 0 {
            if !isSupported { return .unsupported }
            if sessionState == .connecting {
                return .loading
            }
            switch streamState {
            case .idle, .connecting: return .loading
            default: break
            }
            if let staleMessage { return .failed(staleMessage) }
            return .empty
        }

        if visibleCount == 0, isFiltering {
            return .filterEmpty(staleMessage: staleMessage)
        }

        return .content(staleMessage: staleMessage)
    }

    private static func sessionStaleMessage(
        _ state: LiveSessionState?,
        language: AppLanguage
    ) -> String? {
        guard let state else { return nil }
        switch state {
        case .live:
            return nil
        case .idle:
            return MicaStrings.localizedKey("connection.disconnected", language: language)
        case .connecting:
            return state.label(language: language)
        case .staleReconnecting(let message), .partial(let message),
             .failedBeforeFirstSnapshot(let message), .failed(let message):
            return message.dataNonEmpty ?? state.label(language: language)
        case .stopped:
            return MicaStrings.localizedKey("live.detail_stopped", language: language)
        }
    }

    private static func streamStaleMessage(
        _ state: LiveStreamState,
        language: AppLanguage
    ) -> String? {
        switch state {
        case .live, .nearLive:
            return nil
        case .idle:
            return MicaStrings.localizedKey("live.detail_idle", language: language)
        case .connecting:
            return MicaStrings.localizedKey("live.detail_connecting", language: language)
        case .partial(let message), .failed(let message), .unavailable(let message):
            return message.dataNonEmpty ?? state.label(language: language)
        case .stopped:
            return MicaStrings.localizedKey("live.detail_stopped", language: language)
        }
    }

    private static func failureMessage(
        endpointStatus: ControllerEndpointStatus?,
        snapshotState: EnhancedSnapshotState?
    ) -> String? {
        if case .some(.unavailable(let message)) = snapshotState {
            return message
        }
        if case .some(.failed(let message)) = endpointStatus {
            return message
        }
        return nil
    }
}

struct WorkbenchDataInlineConfirmation: View {
    @Environment(\.micaAppLanguage) private var language

    let message: String
    let confirmTitleKey: String
    let isConfirmEnabled: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) { confirmationContent }
            VStack(alignment: .leading, spacing: MicaSpacing.row) { confirmationContent }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.signalRed.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand(perform: cancel)
    }

    @ViewBuilder
    private var confirmationContent: some View {
        Label {
            Text(verbatim: message)
                .micaFont(.callout)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaDesignTokens.signalRed)
        }

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("action.cancel", language: language), action: cancel)
            .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey(confirmTitleKey, language: language),
            role: .destructive,
            action: confirm
        )
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .disabled(!isConfirmEnabled)
        .frame(minHeight: MicaBounds.controlMinHeight)
    }
}

struct WorkbenchDataInspectorShell<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let title: String
    var subtitle: String?
    var statusText: String?
    var statusTint: Color = .secondary
    let close: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        statusText: String? = nil,
        statusTint: Color = .secondary,
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusTint = statusTint
        self.close = close
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MicaSpacing.section) {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        Text(verbatim: title)
                            .micaFont(.title3, weight: .semibold)
                            .textSelection(.enabled)

                        if let subtitle = subtitle?.dataNonEmpty {
                            Text(verbatim: subtitle)
                                .micaFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let statusText = statusText?.dataNonEmpty {
                            WorkbenchStatusBadge(text: statusText, tint: statusTint)
                        }
                    }

                    Spacer(minLength: MicaSpacing.row)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.borderless)
                    .frame(
                        minWidth: MicaBounds.iconControlSize,
                        minHeight: MicaBounds.iconControlSize
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey("dashboard.close_inspector", language: language)
                    )
                }

                content
            }
            .padding(MicaSpacing.section)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .micaObserveScrollPerformance()
        .background(MicaDesignTokens.contentFill)
    }
}

struct WorkbenchDataInspectorSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    private let content: Content

    init(_ titleKey: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDataInspectorField: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String?
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Text(
                verbatim: value?.dataNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
            )
            .micaFont(.callout, design: monospaced ? .monospaced : .default)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDataInspectorValue: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let value: String?
    var monospaced = false
}

struct WorkbenchDataInspectorValueList: View {
    let values: [WorkbenchDataInspectorValue]

    var body: some View {
        ForEach(values) { item in
            WorkbenchDataInspectorField(
                titleKey: item.titleKey,
                value: item.value,
                monospaced: item.monospaced
            )
        }
    }
}

enum WorkbenchDataInspectorProjection {
    static func value(
        _ id: String,
        _ titleKey: String,
        _ value: String?,
        monospaced: Bool = false
    ) -> WorkbenchDataInspectorValue {
        WorkbenchDataInspectorValue(
            id: id,
            titleKey: titleKey,
            value: value,
            monospaced: monospaced
        )
    }
}

enum WorkbenchDataFormat {
    private static let iso8601DateFormatter = Mutex(ISO8601DateFormatter())

    struct MetricsFormatter {
        let language: AppLanguage
        private let rateSuffix: String

        init(language: AppLanguage) {
            self.language = language
            rateSuffix = MicaStrings.resolvedLanguageCode(for: language)
                == AppLanguage.simplifiedChinese.rawValue ? "/秒" : "/s"
        }

        func bytes(_ value: Int?) -> String? {
            guard let value else { return nil }
            return WorkbenchDataFormat.compactBytes(Int64(value))
        }

        func bytes(_ value: Int64?) -> String? {
            guard let value else { return nil }
            return WorkbenchDataFormat.compactBytes(value)
        }

        func rate(_ value: Int?) -> String? {
            guard let value else { return nil }
            guard value > 0 else { return "0 B/s" }
            guard let bytes = bytes(value) else { return nil }
            return bytes + rateSuffix
        }
    }

    static func bytes(_ value: Int?) -> String? {
        MetricsFormatter(language: .english).bytes(value)
    }

    static func bytes(_ value: Int64?) -> String? {
        MetricsFormatter(language: .english).bytes(value)
    }

    static func rate(_ value: Int?, language: AppLanguage) -> String? {
        MetricsFormatter(language: language).rate(value)
    }

    private static func compactBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        guard value >= 1_024 else { return "\(value) B" }

        let rawValue = Double(value)
        var divisor = 1_024.0
        var unitIndex = 1
        while unitIndex < units.count - 1, rawValue >= divisor * 1_024 {
            divisor *= 1_024
            unitIndex += 1
        }

        let scaled = rawValue / divisor
        if unitIndex == 1 {
            return "\(Int(scaled.rounded())) \(units[unitIndex])"
        }

        let tenths = Int((scaled * 10).rounded())
        let whole = tenths / 10
        let decimal = tenths % 10
        let number = decimal == 0 ? "\(whole)" : "\(whole).\(decimal)"
        return "\(number) \(units[unitIndex])"
    }

    static func address(_ host: String?, port: String?) -> String? {
        let host = host?.dataNonEmpty
        let port = port?.dataNonEmpty
        switch (host, port) {
        case let (.some(host), .some(port)):
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        case let (.some(host), .none):
            return host
        case let (.none, .some(port)):
            return port
        case (.none, .none):
            return nil
        }
    }

    static func chain(_ values: [String]?) -> String? {
        values?
            .compactMap(\.dataNonEmpty)
            .joined(separator: " → ")
            .dataNonEmpty
    }

    static func json(_ values: [String: MihomoJSONValue]) -> String? {
        guard !values.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(values) else { return nil }
        return String(data: data, encoding: .utf8)?.dataNonEmpty
    }

    static func receivedTime(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    static func receivedDateTime(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(language.resolvedLocale)
        )
    }

    static func providerUpdatedAt(_ raw: String?, language: AppLanguage) -> String? {
        guard let raw = reportedTimestamp(raw) else { return nil }
        let date = iso8601DateFormatter.withLock {
            $0.date(from: raw)
        }
        if let date {
            return date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(language.resolvedLocale)
            )
        }
        return raw
    }

    static func reportedTimestamp(_ raw: String?) -> String? {
        guard let raw = raw?.dataNonEmpty else { return nil }
        guard !raw.hasPrefix("0001-"), !raw.hasPrefix("1970-") else { return nil }
        return raw
    }

    static func reported(_ value: String?, language: AppLanguage) -> String {
        value?.dataNonEmpty
            ?? MicaStrings.localizedKey(
                "overview.config_not_reported",
                language: language
            )
    }

    static func joined(
        _ values: [String?],
        separator: String = " · "
    ) -> String? {
        values
            .compactMap { $0?.dataNonEmpty }
            .joined(separator: separator)
            .dataNonEmpty
    }
}

extension String {
    var dataNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WorkbenchStableRowIdentity: Equatable {
    let id: String
    let family: String
}

enum WorkbenchStableIdentityToken {
    static func make(_ components: [String]) -> String {
        let value = components
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct WorkbenchStableRowIdentityBuilder {
    private let duplicateReportedIDs: Set<String>
    private var occurrences: [String: Int] = [:]
    private var used: Set<String> = []

    init(reportedIDs: [String], reserving reservedIDs: Set<String> = []) {
        var counts: [String: Int] = [:]
        for reportedID in reportedIDs.compactMap(\.dataNonEmpty) {
            counts[reportedID, default: 0] += 1
        }
        duplicateReportedIDs = Set(counts.compactMap { key, value in
            value > 1 ? key : nil
        })
        used = reservedIDs
    }

    mutating func make(
        reportedID: String?,
        fallbackComponents: [String]
    ) -> WorkbenchStableRowIdentity {
        let reportedID = reportedID?.dataNonEmpty
        let family: String
        if let reportedID, !duplicateReportedIDs.contains(reportedID) {
            family = reportedID
        } else if let reportedID {
            let fallback = WorkbenchStableIdentityToken.make(fallbackComponents)
            family = "\(reportedID)#\(fallback)"
        } else {
            let fallback = WorkbenchStableIdentityToken.make(fallbackComponents)
            family = "unreported#\(fallback)"
        }

        var occurrence = occurrences[family, default: 0]
        var candidate = occurrence == 0 ? family : "\(family)#\(occurrence + 1)"

        while used.contains(candidate) {
            occurrence += 1
            candidate = "\(family)#\(occurrence + 1)"
        }

        occurrences[family] = occurrence + 1
        used.insert(candidate)
        return WorkbenchStableRowIdentity(id: candidate, family: family)
    }
}

enum WorkbenchDataSelection {
    static func reconciled<Row: Identifiable & Equatable>(
        _ selection: String?,
        previousRows: [Row],
        nextVisibleRows: [Row],
        identityFamily: (Row) -> String
    ) -> String? where Row.ID == String {
        guard let selection else {
            return nil
        }
        guard let previous = previousRows.first(where: { $0.id == selection }) else {
            return nextVisibleRows.contains(where: { $0.id == selection }) ? selection : nil
        }

        let family = identityFamily(previous)
        let previousFamilyRows = previousRows.filter { identityFamily($0) == family }
        let nextFamilyRows = nextVisibleRows.filter { identityFamily($0) == family }

        guard !nextFamilyRows.isEmpty else { return nil }
        if previousFamilyRows.count == 1, nextFamilyRows.count == 1 {
            return nextFamilyRows[0].id
        }

        let previousIDs = previousFamilyRows.map(\.id)
        let nextIDs = nextFamilyRows.map(\.id)
        guard previousIDs == nextIDs,
              let exact = nextFamilyRows.first(where: { $0.id == selection }),
              exact == previous else {
            return nil
        }
        return selection
    }
}

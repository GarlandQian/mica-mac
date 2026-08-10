import SwiftUI

/// Subtle press feedback for icon commands and tappable rows (L1).
struct WorkbenchPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : WorkbenchMotion.press, value: configuration.isPressed)
    }
}

struct WorkbenchSymbol: View {
    /// Semantic symbol sizing (design.md 1.4): nav section headers, inline
    /// row glyphs, and larger focus-area icons. Explicit font/frameSize
    /// remain available for one-off cases.
    enum Size {
        case nav, inline, focus

        var font: Font {
            switch self {
            case .nav: .system(size: 15, weight: .medium)
            case .inline: .system(size: 13, weight: .regular)
            case .focus: .system(size: 17, weight: .semibold)
            }
        }

        var frame: CGFloat {
            switch self {
            case .nav: 18
            case .inline: 16
            case .focus: 24
            }
        }
    }

    let systemName: String
    var tint: Color = MicaDesignTokens.signalCyan
    var font: Font = .body.weight(.semibold)
    var frameSize: CGFloat = 20

    init(
        systemName: String,
        tint: Color = MicaDesignTokens.signalCyan,
        font: Font = .body.weight(.semibold),
        frameSize: CGFloat = 20
    ) {
        self.systemName = systemName
        self.tint = tint
        self.font = font
        self.frameSize = frameSize
    }

    init(systemName: String, tint: Color = MicaDesignTokens.signalCyan, size: Size) {
        self.init(systemName: systemName, tint: tint, font: size.font, frameSize: size.frame)
    }

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(font)
            .foregroundStyle(tint)
            .frame(width: frameSize, height: frameSize)
            .accessibilityHidden(true)
    }
}

// MARK: - Decision Paths

struct WorkbenchDecisionPathStep: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String
    let systemImage: String
    var tint: Color = MicaDesignTokens.signalCyan
    var monospaced = false
    var actionHelpKey: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(
                    actionHelpKey.map {
                        MicaStrings.localizedKey($0, language: language)
                    } ?? value
                )
            } else {
                content
                    .textSelection(.enabled)
                    .help(value)
            }
        }
        .padding(.vertical, MicaSpacing.tight)
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: MicaSpacing.row) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .caption.weight(.semibold),
                frameSize: 16
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(
                    MicaStrings.localizedKey(
                        titleKey,
                        language: language
                    )
                )
                .micaFont(.caption)
                .foregroundStyle(.secondary)

                Text(verbatim: value)
                    .micaFont(
                        .callout,
                        weight: monospaced ? .regular : .medium,
                        design: monospaced ? .monospaced : .default
                    )
                    .foregroundStyle(
                        action == nil
                            ? AnyShapeStyle(.primary)
                            : AnyShapeStyle(tint)
                    )
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, MicaSpacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDecisionPathConnector: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .micaFont(.caption2, weight: .semibold)
            .foregroundStyle(.tertiary)
            .frame(width: 12)
            .accessibilityHidden(true)
    }
}

struct WorkbenchDecisionReadout: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String
    var systemImage: String?
    var tint: Color = .secondary
    var monospaced = true

    var body: some View {
        HStack(spacing: MicaSpacing.tight) {
            if let systemImage {
                WorkbenchSymbol(
                    systemName: systemImage,
                    tint: tint,
                    font: .caption.weight(.semibold),
                    frameSize: 14
                )
            }

            Text(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                )
            )
            .foregroundStyle(.secondary)

            Text(verbatim: value)
                .micaFont(
                    .caption,
                    weight: .semibold,
                    design: monospaced ? .monospaced : .default
                )
                .foregroundStyle(tint)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .micaFont(.caption)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Structure

struct WorkbenchChromeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MicaDesignTokens.chromeSeparator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct WorkbenchPageScaffold<Commands: View, Content: View>: View {
    private let commands: Commands
    private let content: Content

    init(
        @ViewBuilder commands: () -> Commands,
        @ViewBuilder content: () -> Content
    ) {
        self.commands = commands()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            commands
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MicaDesignTokens.pageFill)
        }
        .background(MicaDesignTokens.pageFill)
    }
}

extension WorkbenchPageScaffold where Commands == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(commands: { EmptyView() }, content: content)
    }
}

struct WorkbenchCommandBar<Summary: View, Controls: View, Commands: View>: View {
    private let summary: Summary
    private let controls: Controls
    private let commands: Commands

    init(
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder controls: () -> Controls = { EmptyView() },
        @ViewBuilder commands: () -> Commands = { EmptyView() }
    ) {
        self.summary = summary()
        self.controls = controls()
        self.commands = commands()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaSpacing.module) {
                summary
                controls
                Spacer(minLength: MicaSpacing.module)
                commands
            }

            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                HStack(spacing: MicaSpacing.module) {
                    summary
                    Spacer(minLength: MicaSpacing.row)
                    commands
                }
                controls
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: MicaBounds.commandBarHeight,
            alignment: .leading
        )
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .background(MicaDesignTokens.pageFill)
        .overlay(alignment: .bottom) { WorkbenchChromeSeparator() }
    }
}

struct WorkbenchCommandSummary: View {
    @Environment(\.micaAppLanguage) private var language

    let symbolName: String
    let titleKey: String
    let value: String
    var detail: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            inlineSummary
                .fixedSize(horizontal: true, vertical: false)
            stackedSummary
        }
        .accessibilityElement(children: .combine)
    }

    private var inlineSummary: some View {
        HStack(spacing: MicaSpacing.row) {
            summaryIcon
            summaryTitle

            if let detail {
                Divider()
                    .frame(height: 14)

                Text(verbatim: detail)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var stackedSummary: some View {
        HStack(spacing: MicaSpacing.row) {
            summaryIcon

            VStack(alignment: .leading, spacing: 1) {
                summaryTitle

                if let detail {
                    Text(verbatim: detail)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var summaryIcon: some View {
        WorkbenchSymbol(systemName: symbolName)
    }

    private var summaryTitle: some View {
        HStack(spacing: MicaSpacing.tight) {
            Text(verbatim: value)
                .micaFont(.callout, weight: .semibold)
            Text(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                )
            )
            .micaFont(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct WorkbenchSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    var systemImage: String?
    var detailKey: String?
    /// Grouped sections sit on the native grouped background with no opaque
    /// card fill; raised sections keep the content band for data-reuse views.
    var grouped = false
    private let content: Content

    init(
        _ titleKey: String,
        systemImage: String? = nil,
        detailKey: String? = nil,
        grouped: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.detailKey = detailKey
        self.grouped = grouped
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(alignment: .top, spacing: MicaSpacing.row) {
                if let systemImage {
                    WorkbenchSymbol(
                        systemName: systemImage,
                        font: .callout.weight(.semibold),
                        frameSize: 18
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        MicaStrings.localizedKey(
                            titleKey,
                            language: language
                        )
                    )
                    .micaFont(.headline, weight: .semibold)

                    if let detailKey {
                        Text(
                            MicaStrings.localizedKey(
                                detailKey,
                                language: language
                            )
                        )
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            WorkbenchContentBand(surface: grouped ? .grouped : .raised) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchContentBand<Content: View>: View {
    /// Grouped surfaces sit on the native grouped background with hairline
    /// row separators and no white card fill; raised surfaces keep the opaque
    /// content band for data pages and summaries that need stronger separation.
    enum Surface {
        case grouped
        case raised
    }

    private let content: Content
    private let surface: Surface

    init(surface: Surface = .raised, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, MicaSpacing.module)
            .padding(.vertical, MicaSpacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface == .raised ? MicaDesignTokens.contentFill : .clear)
    }
}
// MARK: - Dashboard

struct WorkbenchMetricTile<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            content
        }
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WorkbenchMetricLabel: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: MicaSpacing.tight) {
            WorkbenchSymbol(
                systemName: systemImage,
                tint: tint,
                font: .caption.weight(.semibold),
                frameSize: 16
            )

            Text(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                )
            )
            .foregroundStyle(.secondary)
        }
        .micaFont(.caption)
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchMetricValue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    var tint: Color = .primary

    var body: some View {
        Text(verbatim: text)
            .micaFont(.title2, weight: .semibold).monospacedDigit()
            .foregroundStyle(tint)
            .micaNumericTransition(reduceMotion: reduceMotion)
            .animation(WorkbenchMotion.numeric, value: text)
            .textSelection(.enabled)
    }
}

// MARK: - States

enum WorkbenchStateKind {
    case noController
    case loading
    case unsupported
    case empty
    case filterEmpty
    case failed

    var symbolName: String {
        switch self {
        case .noController: "network"
        case .loading: "arrow.triangle.2.circlepath"
        case .unsupported: "slash.circle"
        case .empty: "tray"
        case .filterEmpty: "line.3.horizontal.decrease.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .failed: MicaDesignTokens.signalRed
        case .unsupported: MicaDesignTokens.signalAmber
        default: .secondary
        }
    }
}

struct WorkbenchStateView: View {
    @Environment(\.micaAppLanguage) private var language

    let kind: WorkbenchStateKind
    let titleKey: String
    var detailKey: String?
    var message: String?
    var actionTitleKey: String?
    var actionSystemImage: String = "arrow.clockwise"
    var isActionEnabled = true
    var action: (() -> Void)?

    var body: some View {
        let title = MicaStrings.localizedKey(titleKey, language: language)
        let detail = detailKey.map {
            MicaStrings.localizedKey($0, language: language)
        }

        ContentUnavailableView {
            Label {
                Text(title)
                    .micaFont(.headline, weight: .semibold)
            } icon: {
                if kind == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(kind.tint)
                        .accessibilityHidden(true)
                }
            }
        } description: {
            VStack(spacing: MicaSpacing.tight) {
                if let detail, detail != title {
                    Text(detail)
                        .micaFont(.callout)
                }

                if let message, message != title, message != detail {
                    Text(verbatim: message)
                        .micaFont(.callout)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 420)
        } actions: {
            if let action, let actionTitleKey {
                Button(action: action) {
                    Label(
                        MicaStrings.localizedKey(
                            actionTitleKey,
                            language: language
                        ),
                        systemImage: actionSystemImage
                    )
                    .micaFont(.callout, weight: .medium)
                }
                .disabled(!isActionEnabled)
                .frame(minHeight: MicaBounds.controlMinHeight)
            }
        }
        .padding(MicaSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaDesignTokens.pageFill)
    }
}

struct WorkbenchStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: MicaSpacing.tight) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .micaFont(.caption, weight: .medium)
        .padding(.horizontal, MicaSpacing.row)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(
                cornerRadius: MicaBounds.badgeRadius,
                style: .continuous
            )
            .fill(tint.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchStaleNotice: View {
    let message: String

    var body: some View {
        Label {
            Text(verbatim: message)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaDesignTokens.signalAmber)
        }
        .micaFont(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.signalAmber.opacity(0.08))
    }
}

struct WorkbenchIconCommand: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    var isEnabled = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                ),
                systemImage: systemImage
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(WorkbenchPressableButtonStyle())
        .disabled(!isEnabled)
        .help(MicaStrings.localizedKey(titleKey, language: language))
        .frame(
            minWidth: MicaBounds.iconControlSize,
            minHeight: MicaBounds.iconControlSize
        )
        .contentShape(Rectangle())
    }
}

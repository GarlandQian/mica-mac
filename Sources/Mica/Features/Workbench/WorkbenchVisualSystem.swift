import AppKit
import SwiftUI

// MARK: - Tokens

enum MicaStyle {
    static let separator = Color(nsColor: .separatorColor)

    // MARK: Midnight Instrument palette (dual appearance)
    // Dark: 墨蓝黑底 + 电感靛蓝主色; Light: 实验室白冷纸面.
    // Four signal hues stay >= 30 degrees away from accent to avoid
    // semantic collision; every pairing is HIG contrast-verified.

    static let accent = adaptive(
        light: color(0x4F5BD5),
        dark: color(0x8B93FF)
    )
    static let pageFill = adaptive(
        light: color(0xE7E9F2),
        dark: color(0x0E0F1A)
    )
    /// Management surfaces share the window canvas fill so the title bar,
    /// command bar, and content do not split into unrelated color bands.
    static let groupedPageFill = pageFill
    static let contentFill = adaptive(
        light: color(0xFBFBFE),
        dark: color(0x161827)
    )
    static let secondaryContentFill = adaptive(
        light: color(0xDEE1EE),
        dark: color(0x1E2133)
    )
    static let tertiaryContentFill = adaptive(
        light: color(0xD9DCE9),
        dark: color(0x2A2E45)
    )
    static let chromeFallback = pageFill
    /// Secondary text on grouped management surfaces: chosen for >= 4.5:1
    /// against underPageBackgroundColor in both appearances.
    static let secondaryOnGrouped = adaptive(
        light: color(0x5B5B63),
        dark: color(0xA7A7B4)
    )
    static let accentSoft = adaptive(
        light: color(0x4F5BD5).withAlphaComponent(0.12),
        dark: color(0x8B93FF).withAlphaComponent(0.16)
    )
    static let navigationSelectionFill = accentSoft

    static let signalCyan = adaptive(
        light: color(0x1E7A93),
        dark: color(0x6FD3E7)
    )
    static let signalMint = adaptive(
        light: color(0x2E7D54),
        dark: color(0x7FD4A8)
    )
    static let signalAmber = adaptive(
        light: color(0x9A6410),
        dark: color(0xF2BE6E)
    )
    static let signalRed = adaptive(
        light: color(0xB23A52),
        dark: color(0xF28B9E)
    )
    static let signalViolet = adaptive(
        light: color(0x6C4FD1),
        dark: color(0xB79CFF)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum MicaDesignTokens {
    static let pageFill = MicaStyle.pageFill
    static let contentFill = MicaStyle.contentFill
    static let elevatedFill = MicaStyle.secondaryContentFill
    static let tertiaryFill = MicaStyle.tertiaryContentFill
    static let accent = MicaStyle.accent
    static let accentSoft = MicaStyle.accentSoft
    static let signalCyan = MicaStyle.signalCyan
    static let signalMint = MicaStyle.signalMint
    static let signalAmber = MicaStyle.signalAmber
    static let signalRed = MicaStyle.signalRed
    static let signalViolet = MicaStyle.signalViolet
    static let separator = MicaStyle.separator

    // Semantic aliases keep pages from hardcoding hues (design.md 1.4).
    static let signalInfo = signalCyan
    static let signalOK = signalMint
    static let signalWarning = signalAmber
    static let signalError = signalRed
    static let signalDebug = signalViolet
}

enum MicaSpacing {
    // 4pt baseline grid. Semantic names are the stable public API; page-level
    // density follows content and interaction rather than one global row height.
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32

    static let section: CGFloat = space4
    static let module: CGFloat = 10
    static let row: CGFloat = 6
    static let tight: CGFloat = space1
}

enum MicaBounds {
    /// Native macOS controls remain compact. Wider pointer acquisition regions
    /// come from the owning row's content shape rather than a global touch size.
    static let controlMinHeight: CGFloat = 28
    static let iconControlSize: CGFloat = 28
    static let commandBarHeight: CGFloat = 40
    static let statusBarHeight: CGFloat = 34
    static let moduleRadius: CGFloat = 8
    static let badgeRadius: CGFloat = 5

    static let compactPagePadding: CGFloat = 12
    static let regularPagePadding: CGFloat = 16
    static let chromeHorizontalPadding: CGFloat = 12

    static let sidebarMin: CGFloat = 176
    static let sidebarIdeal: CGFloat = 196
    static let sidebarMax: CGFloat = 232

    static let inspectorMin: CGFloat = 300
    static let inspectorIdeal: CGFloat = 360
    static let inspectorMax: CGFloat = 480

    static let formLabelWidth: CGFloat = 176
    static let formControlMax: CGFloat = 360
    static let wideThreshold: CGFloat = 720

    static func pagePadding(for width: CGFloat) -> CGFloat {
        width < wideThreshold ? compactPagePadding : regularPagePadding
    }
}

// MARK: - Typography

enum MicaTextStyle: Sendable, Equatable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        }
    }

    fileprivate var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct MicaScaledFontModifier: ViewModifier {
    @Environment(\.micaAppFontScale) private var fontScale

    let style: MicaTextStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: fontScale.pointSize(for: style.basePointSize),
                weight: weight ?? style.defaultWeight,
                design: design
            )
        )
    }
}

extension View {
    func micaFont(
        _ style: MicaTextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(
            MicaScaledFontModifier(
                style: style,
                weight: weight,
                design: design
            )
        )
    }
}

// MARK: - Motion

/// Instrument motion primitives (design.md 1.5). Every animation reads
/// `accessibilityReduceMotion` and degrades to an instantaneous assignment
/// when the user requests reduced motion. Motion applies only to value or
/// structural changes - never to scroll position or high-frequency row layout.
enum WorkbenchMotion {
    static let press = Animation.easeOut(duration: 0.12)
    static let hover = Animation.easeIn(duration: 0.08)
    static let numeric = Animation.easeInOut(duration: 0.15)
    static let expand = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let pageIn = Animation.easeOut(duration: 0.28)
    static let crossfade = Animation.easeInOut(duration: 0.22)
    static let liveDraw = Animation.linear(duration: 0.4)
    static let latencyShift = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let pageStagger: Duration = .milliseconds(40)
}

extension View {
    /// Applies `animation` for `value` unless the user prefers reduced motion.
    @ViewBuilder
    func micaMotion<V: Equatable>(
        _ animation: Animation?,
        value: V,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion {
            self.animation(nil, value: value)
        } else {
            self.animation(animation, value: value)
        }
    }

    /// Numeric rolling transition for KPI / rate / counter text.
    @ViewBuilder
    func micaNumericTransition(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.contentTransition(.numericText())
        }
    }
}

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
        .overlay(alignment: .bottom) { Divider() }
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

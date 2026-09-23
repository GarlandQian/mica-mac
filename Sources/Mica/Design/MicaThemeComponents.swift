import SwiftUI

// MARK: - Panel

/// A bounded tool surface with a subtle border.
struct MicaPanel<Content: View>: View {
    var fill: Color = MicaTheme.surface
    var padding: CGFloat = MicaTheme.Spacing.panelPadding
    var alignment: Alignment = .topLeading
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(
                fill,
                in: RoundedRectangle(
                    cornerRadius: MicaTheme.Shape.panelRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MicaTheme.Shape.panelRadius,
                    style: .continuous
                )
                .strokeBorder(MicaTheme.separator, lineWidth: MicaTheme.Shape.hairline)
            }
    }
}

extension View {
    /// Wraps the view in a bounded tool surface.
    func micaPanel(
        fill: Color = MicaTheme.surface,
        padding: CGFloat = MicaTheme.Spacing.panelPadding,
        alignment: Alignment = .topLeading
    ) -> some View {
        MicaPanel(fill: fill, padding: padding, alignment: alignment) { self }
    }
}

// MARK: - Hairline separator

/// A separator that follows the current appearance.
struct MicaHairlineSeparator: View {
    var axis: Axis = .horizontal
    var color: Color = MicaTheme.separator

    var body: some View {
        switch axis {
        case .horizontal:
            color.frame(maxWidth: .infinity, maxHeight: MicaTheme.Shape.hairline)
        case .vertical:
            color.frame(maxWidth: MicaTheme.Shape.hairline, maxHeight: .infinity)
        }
    }
}

// MARK: - Mono metric

/// Live-data metric: small secondary label above an SF Mono tabular value.
/// Numeric changes roll via `.numericText()` unless the user prefers reduced
/// motion, in which case the new value renders statically.
struct MicaMonoMetric: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Localization key resolved through `MicaStrings`; `nil` hides the label.
    var labelKey: String? = nil
    let value: String
    var unit: String? = nil
    var role: MicaTheme.TextRole = .dataBody
    var valueColor: Color = MicaTheme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1 / 2) {
            if let labelKey {
                Text(MicaStrings.localizedKey(labelKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space1) {
                Text(value)
                    .micaThemeFont(role)
                    .foregroundStyle(valueColor)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let unit {
                    Text(unit)
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(MicaTheme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status dot and badge

/// Status-colored dot for controller-reported state. Provide a localized
/// `accessibilityLabel` when the dot carries meaning on its own; otherwise it
/// stays hidden and the owning row speaks the status.
struct MicaStatusDot: View {
    let status: MicaTheme.Status
    var size: CGFloat = 8
    var accessibilityLabel: String? = nil

    @ViewBuilder
    var body: some View {
        let dot = Circle()
            .fill(status.color)
            .frame(width: size, height: size)
        if let accessibilityLabel {
            dot.accessibilityLabel(accessibilityLabel)
        } else {
            dot.accessibilityHidden(true)
        }
    }
}

/// Compact status badge: semibold status-colored text on a status-tinted fill.
/// `text` is controller-reported or already localized by the caller.
struct MicaStatusBadge: View {
    let status: MicaTheme.Status
    let text: String

    var body: some View {
        Text(text)
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(status.color)
            .padding(.horizontal, MicaTheme.Spacing.space2 - 2)
            .padding(.vertical, MicaTheme.Spacing.space1 / 2)
            .background(
                status.color.opacity(0.14),
                in: RoundedRectangle(
                    cornerRadius: MicaTheme.Shape.panelRadius,
                    style: .continuous
                )
            )
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Section header

/// Semibold section title with an optional trailing control. The title is a
/// localization key resolved through `MicaStrings`.
struct MicaSectionHeader<Trailing: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    @ViewBuilder let trailing: Trailing

    init(titleKey: String, @ViewBuilder trailing: () -> Trailing) {
        self.titleKey = titleKey
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.title3)
                .foregroundStyle(MicaTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: MicaTheme.Spacing.space2)
            trailing
        }
    }
}

extension MicaSectionHeader where Trailing == EmptyView {
    init(titleKey: String) {
        self.init(titleKey: titleKey) { EmptyView() }
    }
}

// MARK: - Empty state

/// Density-first empty state for panels and data regions: tertiary symbol,
/// secondary title, optional tertiary message. Keys resolve through
/// `MicaStrings`; no hero whitespace.
struct MicaEmptyState: View {
    @Environment(\.micaAppLanguage) private var language

    let systemImage: String
    let titleKey: String
    var messageKey: String? = nil

    var body: some View {
        VStack(spacing: MicaTheme.Spacing.space2) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(MicaTheme.textTertiary)
                .accessibilityHidden(true)
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.title3)
                .foregroundStyle(MicaTheme.textSecondary)
            if let messageKey {
                Text(MicaStrings.localizedKey(messageKey, language: language))
                    .micaThemeFont(.body)
                    .foregroundStyle(MicaTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(MicaTheme.Spacing.space5)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Workbench primitives

/// Subtle press feedback for icon commands and tappable rows.
struct WorkbenchPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : MicaTheme.Motion.press, value: configuration.isPressed)
    }
}

struct WorkbenchSymbol: View {
    /// Semantic symbol sizing: nav section headers, inline row glyphs, and
    /// larger focus-area icons. Explicit font/frameSize remain available for
    /// one-off cases.
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
    var tint: Color = MicaTheme.textSecondary
    var font: Font = .body.weight(.semibold)
    var frameSize: CGFloat = 20

    init(
        systemName: String,
        tint: Color = MicaTheme.textSecondary,
        font: Font = .body.weight(.semibold),
        frameSize: CGFloat = 20
    ) {
        self.systemName = systemName
        self.tint = tint
        self.font = font
        self.frameSize = frameSize
    }

    init(systemName: String, tint: Color = MicaTheme.textSecondary, size: Size) {
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
    var tint: Color = MicaTheme.textSecondary
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
        .padding(.vertical, MicaTheme.Spacing.space1)
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: MicaTheme.Spacing.space2) {
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
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)

                Text(verbatim: value)
                    .micaThemeFont(
                        monospaced ? .dataLabel : .label,
                        weight: monospaced ? .regular : .medium
                    )
                    .foregroundStyle(
                        action == nil
                            ? AnyShapeStyle(.primary)
                            : AnyShapeStyle(tint)
                    )
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDecisionPathConnector: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .micaThemeFont(.caption, weight: .semibold)
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
        HStack(spacing: MicaTheme.Spacing.space1) {
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
                .micaThemeFont(
                    monospaced ? .dataCaption : .caption,
                    weight: .semibold
                )
                .foregroundStyle(tint)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .micaThemeFont(.caption)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Structure

struct WorkbenchChromeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MicaTheme.separator)
            .frame(height: MicaTheme.Shape.hairline)
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
        // The split view supplies the viewport. Intrinsic measurements of a
        // wrapping command bar must not become the window's minimum height.
        GeometryReader { geometry in
            VStack(spacing: 0) {
                commands
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .background(MicaTheme.canvas)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(MicaTheme.canvas)
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
            HStack(spacing: MicaTheme.Spacing.space3) {
                summary
                controls
                Spacer(minLength: MicaTheme.Spacing.space3)
                commands
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                HStack(spacing: MicaTheme.Spacing.space3) {
                    summary
                    Spacer(minLength: MicaTheme.Spacing.space2)
                    commands
                }
                controls
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space1)
        .frame(
            maxWidth: .infinity,
            minHeight: MicaTheme.Metrics.commandBarHeight,
            alignment: .leading
        )
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .background(MicaTheme.canvas)
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
        HStack(spacing: MicaTheme.Spacing.space2) {
            summaryIcon
            summaryTitle

            if let detail {
                Divider()
                    .frame(height: 14)

                Text(verbatim: detail)
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var stackedSummary: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            summaryIcon

            VStack(alignment: .leading, spacing: 1) {
                summaryTitle

                if let detail {
                    Text(verbatim: detail)
                        .micaThemeFont(.caption)
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
        HStack(spacing: MicaTheme.Spacing.space1) {
            Text(verbatim: value)
                .micaThemeFont(.dataLabel, weight: .semibold)
            Text(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                )
            )
            .micaThemeFont(.label)
            .foregroundStyle(.secondary)
        }
    }
}

struct WorkbenchSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    var systemImage: String?
    var detailKey: String?
    /// Grouped sections sit directly on the page background.
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
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
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
                    .micaThemeFont(.body, weight: .semibold)

                    if let detailKey {
                        Text(
                            MicaStrings.localizedKey(
                                detailKey,
                                language: language
                            )
                        )
                        .micaThemeFont(.caption)
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
    /// Raised bands distinguish summaries from grouped form rows.
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
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.vertical, MicaTheme.Spacing.space1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface == .raised ? MicaTheme.surface : .clear)
    }
}

// MARK: - Metrics

struct WorkbenchMetricTile<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            content
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WorkbenchMetricLabel: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
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
        .micaThemeFont(.caption)
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchMetricValue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    var tint: Color = .primary

    var body: some View {
        Text(verbatim: text)
            .micaThemeFont(.title, weight: .semibold).monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : MicaTheme.Motion.stateChange, value: text)
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
        case .failed: MicaTheme.statusError
        case .unsupported: MicaTheme.statusWarning
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
                    .micaThemeFont(.body, weight: .semibold)
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
            VStack(spacing: MicaTheme.Spacing.space1) {
                if let detail, detail != title {
                    Text(detail)
                        .micaThemeFont(.label)
                }

                if let message, message != title, message != detail {
                    Text(verbatim: message)
                        .micaThemeFont(.label)
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
                    .micaThemeFont(.label, weight: .medium)
                }
                .disabled(!isActionEnabled)
                .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
            }
        }
        .padding(MicaTheme.Spacing.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaTheme.canvas)
    }
}

struct WorkbenchStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .micaThemeFont(.caption, weight: .medium)
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(
                cornerRadius: MicaTheme.Metrics.badgeRadius,
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
                .foregroundStyle(MicaTheme.statusWarning)
        }
        .micaThemeFont(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.statusWarning.opacity(0.08))
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
            minWidth: MicaTheme.Metrics.iconControlSize,
            minHeight: MicaTheme.Metrics.iconControlSize
        )
        .contentShape(Rectangle())
    }
}

import SwiftUI

// MARK: - Panel

/// A bounded tool surface: a crisp bordered card with subtle light-mode elevation.
struct MicaPanel<Content: View>: View {
    var fill: Color = MicaTheme.surface
    var padding: CGFloat = MicaTheme.Spacing.panelPadding
    var alignment: Alignment = .topLeading
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .micaElevatedCard(fill)
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

// MARK: - Tag flow

/// Wraps tags and chips onto as many lines as the width requires, keeping
/// their order and clamping oversized children so they never overflow.
struct MicaTagFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        let rows = arrange(width: availableWidth, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        let finiteWidth = width.isFinite && width > 0 ? width : nil
        let subviewProposal = ProposedViewSize(width: finiteWidth, height: nil)

        for index in subviews.indices {
            let measured = subviews[index].sizeThatFits(subviewProposal)
            let clampedWidth = finiteWidth.map { min(measured.width, $0) } ?? measured.width
            let itemSize = CGSize(width: clampedWidth, height: measured.height)

            let proposedWidth = current.items.isEmpty ? itemSize.width : current.width + spacing + itemSize.width
            if proposedWidth > width, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? itemSize.width : current.width + spacing + itemSize.width
            current.height = max(current.height, itemSize.height)
            current.items.append(RowItem(index: index, size: itemSize))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
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
struct MicaMonoMetric: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

/// Status-colored dot for controller-reported state.
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

/// Compact status badge: semibold status-colored text on a soft tinted capsule.
struct MicaStatusBadge: View {
    let status: MicaTheme.Status
    let text: String

    var body: some View {
        Text(text)
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(status.color)
            .padding(.horizontal, MicaTheme.Spacing.space2)
            .padding(.vertical, 3)
            .micaSoftPill(status.color)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Section header

/// Semibold section title with an optional soft-tinted icon and trailing control.
struct MicaSectionHeader<Trailing: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    var systemImage: String? = nil
    var tint: Color = MicaTheme.accent
    @ViewBuilder let trailing: Trailing

    init(
        titleKey: String,
        systemImage: String? = nil,
        tint: Color = MicaTheme.accent,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }
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
    init(
        titleKey: String,
        systemImage: String? = nil,
        tint: Color = MicaTheme.accent
    ) {
        self.init(titleKey: titleKey, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

// MARK: - Empty state

/// Refined empty state for panels, inspectors, and sidebars.
struct MicaEmptyState: View {
    @Environment(\.micaAppLanguage) private var language

    let systemImage: String
    let titleKey: String
    var messageKey: String? = nil
    var tint: Color = MicaTheme.textSecondary

    var body: some View {
        VStack(spacing: MicaTheme.Spacing.space3) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(
                    MicaTheme.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(MicaTheme.surfaceBorder, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(spacing: MicaTheme.Spacing.space1) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.body, weight: .semibold)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let messageKey {
                    Text(MicaStrings.localizedKey(messageKey, language: language))
                        .micaThemeFont(.label)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 280)
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
    @State private var isHovered = false

    let titleKey: String
    let value: String
    let systemImage: String
    var tint: Color = MicaTheme.textSecondary
    var monospaced = false
    var actionHelpKey: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)

        Group {
            if let action {
                Button(action: action) {
                    content
                        .padding(.horizontal, MicaTheme.Spacing.space2)
                        .padding(.vertical, MicaTheme.Spacing.space1)
                        .background(
                            isHovered ? tint.opacity(0.12) : tint.opacity(0.06),
                            in: shape
                        )
                        .overlay {
                            shape.strokeBorder(
                                tint.opacity(isHovered ? 0.35 : 0.18),
                                lineWidth: 1
                            )
                        }
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .micaStateChangeAnimation(MicaTheme.Motion.press, value: isHovered)
                .contentShape(shape)
                .help(
                    actionHelpKey.map {
                        MicaStrings.localizedKey($0, language: language)
                    } ?? value
                )
            } else {
                content
                    .padding(.horizontal, MicaTheme.Spacing.space1)
                    .padding(.vertical, MicaTheme.Spacing.space1)
                    .textSelection(.enabled)
                    .help(value)
            }
        }
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
                .foregroundStyle(MicaTheme.textSecondary)

                Text(verbatim: value)
                    .micaThemeFont(
                        monospaced ? .dataLabel : .label,
                        weight: monospaced ? .regular : .medium
                    )
                    .foregroundStyle(
                        action == nil
                            ? AnyShapeStyle(MicaTheme.textPrimary)
                            : AnyShapeStyle(tint)
                    )
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDecisionPathConnector: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .micaThemeFont(.caption, weight: .semibold)
            .foregroundStyle(MicaTheme.textTertiary)
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
    var valueTint: Color = MicaTheme.textPrimary
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
            .foregroundStyle(MicaTheme.textSecondary)
            .lineLimit(1)

            Text(verbatim: value)
                .micaThemeFont(
                    monospaced ? .dataCaption : .caption,
                    weight: .semibold
                )
                .foregroundStyle(valueTint)
                .monospacedDigit()
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .micaThemeFont(.caption)
        .fixedSize(horizontal: true, vertical: false)
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
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: MicaTheme.Spacing.space2)
                    commands
                        .fixedSize(horizontal: true, vertical: false)
                }
                HStack(spacing: MicaTheme.Spacing.space3) {
                    controls
                }
            }

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                summary
                HStack(spacing: MicaTheme.Spacing.space2) {
                    commands
                    Spacer(minLength: 0)
                }
                HStack(spacing: MicaTheme.Spacing.space3) {
                    controls
                }
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space1 + 2)
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
                    .foregroundStyle(MicaTheme.textSecondary)
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
                        .foregroundStyle(MicaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var summaryIcon: some View {
        WorkbenchSymbol(systemName: symbolName, tint: MicaTheme.accent)
    }

    private var summaryTitle: some View {
        HStack(spacing: MicaTheme.Spacing.space1) {
            Text(verbatim: value)
                .micaThemeFont(.dataLabel, weight: .semibold)
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)
            Text(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                )
            )
            .micaThemeFont(.label)
            .foregroundStyle(MicaTheme.textSecondary)
            .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct WorkbenchSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    var systemImage: String?
    var detailKey: String?
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
                        tint: MicaTheme.accent,
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
                        .foregroundStyle(MicaTheme.textSecondary)
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
            .micaCard(
                surface == .raised ? MicaTheme.surface : .clear,
                cornerRadius: MicaTheme.Metrics.moduleRadius,
                bordered: surface == .raised,
                elevated: surface == .raised
            )
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
            .foregroundStyle(MicaTheme.textSecondary)
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
        case .noController: MicaTheme.accent
        default: MicaTheme.textSecondary
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

        VStack(spacing: MicaTheme.Spacing.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(kind == .loading ? MicaTheme.surface : kind.tint.opacity(0.10))
                    .frame(width: 52, height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                kind == .loading ? MicaTheme.surfaceBorder : kind.tint.opacity(0.22),
                                lineWidth: 1
                            )
                    }

                if kind == .loading {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kind.tint)
                        .accessibilityHidden(true)
                }
            }

            VStack(spacing: MicaTheme.Spacing.space1 + 2) {
                Text(title)
                    .micaThemeFont(.title3)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .multilineTextAlignment(.center)

                if let detail, detail != title {
                    Text(detail)
                        .micaThemeFont(.label)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message, message != title, message != detail {
                    Text(verbatim: message)
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(kind == .failed ? MicaTheme.statusError : MicaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, MicaTheme.Spacing.space3)
                        .padding(.vertical, MicaTheme.Spacing.space2)
                        .background(
                            kind == .failed ? MicaTheme.statusError.opacity(0.08) : MicaTheme.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: MicaTheme.Shape.rowRadius, style: .continuous)
                        )
                        .padding(.top, MicaTheme.Spacing.space1)
                }
            }
            .frame(maxWidth: 440)

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
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!isActionEnabled)
                .padding(.top, MicaTheme.Spacing.space1)
            }
        }
        .padding(MicaTheme.Spacing.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MicaTheme.canvas)
    }
}

struct WorkbenchStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space1 + 1) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .foregroundStyle(MicaTheme.textPrimary)
        }
        .micaThemeFont(.caption, weight: .semibold)
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .padding(.vertical, 3)
        .micaSoftPill(tint)
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
        .micaThemeFont(.caption, weight: .medium)
        .foregroundStyle(MicaTheme.textPrimary)
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.statusWarning.opacity(0.10))
        .overlay(alignment: .bottom) {
            MicaHairlineSeparator(color: MicaTheme.statusWarning.opacity(0.25))
        }
    }
}

struct WorkbenchIconCommand: View {
    @Environment(\.micaAppLanguage) private var language
    @State private var isHovered = false

    let titleKey: String
    let systemImage: String
    var isEnabled = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        Button(role: role, action: action) {
            Label(
                MicaStrings.localizedKey(
                    titleKey,
                    language: language
                ),
                systemImage: systemImage
            )
            .labelStyle(.iconOnly)
            .frame(
                minWidth: MicaTheme.Metrics.iconControlSize,
                minHeight: MicaTheme.Metrics.iconControlSize
            )
            .background(isHovered && isEnabled ? MicaTheme.surfaceHover : .clear, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(WorkbenchPressableButtonStyle())
        .onHover { isHovered = $0 }
        .micaStateChangeAnimation(MicaTheme.Motion.press, value: isHovered)
        .disabled(!isEnabled)
        .help(MicaStrings.localizedKey(titleKey, language: language))
    }
}

/// A titled bar command. Bulk and destructive operations name themselves
/// instead of hiding behind an icon; the role colors destructive titles.
struct WorkbenchLabeledCommand: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let systemImage: String
    var isEnabled = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        let title = MicaStrings.localizedKey(titleKey, language: language)

        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isEnabled)
        .help(title)
    }
}

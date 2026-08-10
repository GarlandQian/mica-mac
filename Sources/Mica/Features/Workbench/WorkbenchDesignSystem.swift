import AppKit
import SwiftUI

// MARK: - Tokens

enum MicaStyle {
    static let separator = Color(nsColor: .separatorColor)
    static let chromeSeparator = separator.opacity(0.72)

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
    static let chromeSeparator = MicaStyle.chromeSeparator

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

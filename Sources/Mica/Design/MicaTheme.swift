import AppKit
import SwiftUI

// MARK: - Tokens

/// Shared appearance, typography, and layout for the native workspace.
///
/// macOS 27 owns the window's glass control chrome (toolbar, sidebar, and
/// inspector). Content sits on a calm layered canvas with crisp 1pt bordered
/// surfaces, calibrated high-contrast status tones, and subtle light-mode
/// elevation shadows.
enum MicaTheme {
    // MARK: Color

    /// Page fill: cool light slate in Light mode, deep graphite in Dark mode.
    static let canvas = Color(micaLight: rgb(0xF3F5F8), dark: rgb(0x13151A))
    /// Primary elevated card surface.
    static let surface = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x1C1F26))
    /// Secondary recessed wells (directory sidebar, track pills, nested chips).
    static let surfaceSecondary = Color(micaLight: rgb(0xEAECEF), dark: rgb(0x171A21))
    /// Slightly lifted surface for active tiles or nested controls.
    static let surfaceElevated = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x232730))
    /// Pointer hover on a grouped row or tile.
    static let surfaceHover = Color(micaLight: rgba(0x0F172A, 0.045), dark: rgba(0xFFFFFF, 0.06))
    /// Crisp 1pt border around cards and modules.
    static let surfaceBorder = Color(micaLight: rgba(0x0F172A, 0.08), dark: rgba(0xFFFFFF, 0.085))
    /// Higher-contrast border for Increase Contrast or emphasized containers.
    static let surfaceBorderStrong = Color(micaLight: rgba(0x0F172A, 0.16), dark: rgba(0xFFFFFF, 0.16))
    /// System hairline; follows Increase Contrast.
    static let separator = Color(nsColor: .separatorColor)

    /// Text ramps with guaranteed readability across light and dark surfaces.
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(micaLight: rgba(0x475569, 0.78), dark: rgba(0x94A3B8, 0.78))

    /// Follow the user's macOS accent preference for selection and commands.
    static let accent = Color(nsColor: .controlAccentColor)

    enum Chart {
        static let upload = Color(micaLight: rgb(0x0891B2), dark: rgb(0x2DD4BF))
        static let download = Color(micaLight: rgb(0x2563EB), dark: rgb(0x60A5FA))
        static let connections = Color(micaLight: rgb(0xEA580C), dark: rgb(0xFB923C))
        static let memory = Color(micaLight: rgb(0x7C3AED), dark: rgb(0xA78BFA))
    }

    enum Topology {
        /// Opaque route canvas background matching `surface`.
        static let panelSurface = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x191C22))
        /// Opaque node card surface so cards cleanly occlude edges beneath them.
        static let nodeSurface = Color(micaLight: rgb(0xF8FAFC), dark: rgb(0x232730))
        static let headerSurface = Color(micaLight: rgb(0xF1F4F8), dark: rgb(0x1E222A))
    }

    /// Fixed miniature window colors for the Settings appearance tiles; each
    /// tile depicts its appearance regardless of the current one.
    enum AppearancePreview {
        static let lightWindow = Color(nsColor: rgb(0xF3F5F8))
        static let lightSidebar = Color(nsColor: rgb(0xE6E9EF))
        static let lightLine = Color(nsColor: rgb(0xCBD5E1))
        static let darkWindow = Color(nsColor: rgb(0x13151A))
        static let darkSidebar = Color(nsColor: rgb(0x1F232C))
        static let darkLine = Color(nsColor: rgb(0x334155))
    }

    /// Calibrated high-contrast status tones meeting WCAG AA even at 11pt.
    static let statusOK = Color(micaLight: rgb(0x15803D), dark: rgb(0x34D399))
    static let statusWarning = Color(micaLight: rgb(0xC2410C), dark: rgb(0xFBBF24))
    static let statusError = Color(micaLight: rgb(0xDC2626), dark: rgb(0xF87171))
    static let statusInfo = Color(micaLight: rgb(0x2563EB), dark: rgb(0x60A5FA))

    /// Category tints distinguish routing stages from live health status.
    enum ColumnTint {
        /// Sources: cool steel blue.
        static let source = Color(micaLight: rgb(0x3B6291), dark: rgb(0x60A5FA))
        /// Matched rules: warm amber.
        static let rule = Color(micaLight: rgb(0xB45309), dark: rgb(0xFBBF24))
        /// Proxy chain hops: soft violet.
        static let policyHop = Color(micaLight: rgb(0x6D28D9), dark: rgb(0xA78BFA))
        /// Chain exits: vibrant rose.
        static let finalOutbound = Color(micaLight: rgb(0xBE185D), dark: rgb(0xF472B6))
    }

    /// Non-selected edges while a trajectory is active.
    static let edgeDimmed = Color(micaLight: rgba(0x1E293B, 0.16), dark: rgba(0xE2E8F0, 0.16))

    private static func rgb(_ hex: UInt32) -> NSColor {
        rgba(hex, 1)
    }

    private static func rgba(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Resolve colors against the current native appearance.
    init(micaLight light: NSColor, dark: NSColor) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }
}

// MARK: - Status

extension MicaTheme {
    /// Semantic status for controller-reported state.
    enum Status: Sendable, Equatable {
        case ok
        case warning
        case error
        case neutral

        var color: Color {
            switch self {
            case .ok: MicaTheme.statusOK
            case .warning: MicaTheme.statusWarning
            case .error: MicaTheme.statusError
            case .neutral: MicaTheme.textTertiary
            }
        }
    }
}

// MARK: - Typography

extension MicaTheme {
    enum TextRole: Sendable, Equatable {
        case caption
        case label
        case body
        case title3
        case title
        case hero
        case heroLarge
        case dataCaption
        case dataLabel
        case dataBody
        case dataTitle
        case dataHero
        case dataHeroLarge

        var basePointSize: CGFloat {
            switch self {
            case .caption, .dataCaption: 11
            case .label, .dataLabel: 12
            case .body, .dataBody: 13
            case .title3, .dataTitle: 15
            case .title: 17
            case .hero, .dataHero: 22
            case .heroLarge, .dataHeroLarge: 28
            }
        }

        fileprivate var isMonospaced: Bool {
            switch self {
            case .dataCaption, .dataLabel, .dataBody, .dataTitle, .dataHero, .dataHeroLarge:
                true
            case .caption, .label, .body, .title3, .title, .hero, .heroLarge:
                false
            }
        }

        fileprivate var defaultWeight: Font.Weight {
            switch self {
            case .title3, .title: .semibold
            default: .regular
            }
        }
    }

    static func pointSize(for role: TextRole, scale: AppFontScale) -> CGFloat {
        scale.pointSize(for: role.basePointSize)
    }

    static func font(
        for role: TextRole,
        scale: AppFontScale = .comfortable,
        weight: Font.Weight? = nil
    ) -> Font {
        let size = pointSize(for: role, scale: scale)
        let resolvedWeight = weight ?? role.defaultWeight
        if role.isMonospaced {
            return .system(size: size, weight: resolvedWeight, design: .monospaced)
        }
        return .system(size: size, weight: resolvedWeight, design: .default)
    }
}

private struct MicaThemeFontModifier: ViewModifier {
    @Environment(\.micaAppFontScale) private var fontScale

    let role: MicaTheme.TextRole
    let weight: Font.Weight?

    @ViewBuilder
    func body(content: Content) -> some View {
        let scaled = content.font(MicaTheme.font(for: role, scale: fontScale, weight: weight))
        if role.isMonospaced {
            scaled.monospacedDigit()
        } else {
            scaled
        }
    }
}

extension View {
    /// Applies a text role using the user's font-scale preference.
    func micaThemeFont(_ role: MicaTheme.TextRole, weight: Font.Weight? = nil) -> some View {
        modifier(MicaThemeFontModifier(role: role, weight: weight))
    }
}

// MARK: - Spacing, Shape, Metrics

extension MicaTheme {
    /// Four-point baseline grid.
    enum Spacing {
        static let space1: CGFloat = 4
        static let space2: CGFloat = 8
        static let space3: CGFloat = 12
        static let space4: CGFloat = 16
        static let space5: CGFloat = 24

        static let panelPaddingCompact: CGFloat = space3
        static let panelPadding: CGFloat = space4
    }

    enum Shape {
        static let panelRadius: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let hairline: CGFloat = 1
    }

    enum Metrics {
        static let dataRowHeightMin: CGFloat = 22
        static let dataRowHeightMax: CGFloat = 28

        static let iconControlSize: CGFloat = 28
        static let moduleRadius: CGFloat = 10
        static let controlMinHeight: CGFloat = 28
        static let commandBarHeight: CGFloat = 40
        static let chromeHorizontalPadding: CGFloat = 12

        static let compactPagePadding: CGFloat = 12
        static let regularPagePadding: CGFloat = 16
        static let wideThreshold: CGFloat = 720

        static func pagePadding(for width: CGFloat) -> CGFloat {
            width < wideThreshold ? compactPagePadding : regularPagePadding
        }

        static let statusBarHeight: CGFloat = 30
        static let inspectorMin: CGFloat = 300
        static let inspectorIdeal: CGFloat = 360
        static let inspectorMax: CGFloat = 480
        static let formLabelWidth: CGFloat = 176
        static let formControlMax: CGFloat = 360
        static let sidebarMin: CGFloat = 196
        static let sidebarIdeal: CGFloat = 220
        static let sidebarMax: CGFloat = 280
    }
}

// MARK: - Motion

extension MicaTheme {
    enum Motion {
        static let press = Animation.snappy(duration: 0.12)
        static let stateChange = Animation.smooth(duration: 0.16)
        static let reveal = Animation.smooth(duration: 0.2)
    }
}

private struct MicaStateChangeAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func micaStateChangeAnimation<Value: Equatable>(
        _ animation: Animation? = MicaTheme.Motion.stateChange,
        value: Value
    ) -> some View {
        modifier(MicaStateChangeAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Surfaces

private struct MicaCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let fill: Color
    let cornerRadius: CGFloat
    let bordered: Bool
    let elevated: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let borderColor = contrast == .increased
            ? MicaTheme.surfaceBorderStrong
            : MicaTheme.surfaceBorder

        content
            .background(fill, in: shape)
            .overlay {
                if bordered {
                    shape.strokeBorder(borderColor, lineWidth: contrast == .increased ? 1.25 : 1)
                }
            }
            .shadow(
                color: (elevated && colorScheme == .light) ? Color.black.opacity(0.05) : .clear,
                radius: 8,
                x: 0,
                y: 2
            )
            .containerShape(shape)
    }
}

private struct MicaSoftPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    func body(content: Content) -> some View {
        let fillOpacity = colorScheme == .dark ? 0.16 : 0.10
        let strokeOpacity = colorScheme == .dark ? 0.28 : 0.20

        content
            .background(tint.opacity(fillOpacity), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            }
    }
}

extension View {
    /// Grouped content card with crisp hairline border and subtle light-mode elevation.
    func micaCard(
        _ fill: Color = MicaTheme.surface,
        cornerRadius: CGFloat = MicaTheme.Shape.panelRadius,
        bordered: Bool = true,
        elevated: Bool = false
    ) -> some View {
        let appliesChrome = fill != .clear
        return modifier(
            MicaCardModifier(
                fill: fill,
                cornerRadius: cornerRadius,
                bordered: bordered && appliesChrome,
                elevated: elevated && appliesChrome
            )
        )
    }

    /// Elevated top-level Bento card with subtle drop shadow in Light mode.
    func micaElevatedCard(
        _ fill: Color = MicaTheme.surface,
        cornerRadius: CGFloat = MicaTheme.Shape.panelRadius
    ) -> some View {
        micaCard(fill, cornerRadius: cornerRadius, bordered: true, elevated: true)
    }

    /// Soft-tinted semantic capsule pill with matching hairline stroke.
    func micaSoftPill(_ tint: Color) -> some View {
        modifier(MicaSoftPillModifier(tint: tint))
    }

    /// Liquid Glass for Mica's transient floating previews and overlays.
    func micaFloatingGlass(
        cornerRadius: CGFloat = MicaTheme.Shape.panelRadius
    ) -> some View {
        glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

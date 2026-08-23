import AppKit
import SwiftUI

// MARK: - Tokens

/// Mica Ops design tokens (task 08-17 design.md §2). One consolidated namespace
/// for color, typography, spacing, shape, and motion. Introduced additively in
/// Phase 1; the previous token system was deleted in Phase 7.3, and the shared
/// Workbench primitives moved into `MicaThemeComponents.swift` in Phase 4B.
///
/// Rules (design.md §2): the accent never decorates; status colors never brand;
/// text contrast stays >= 4.5:1 (primary) and >= 3:1 (secondary/large data).
enum MicaTheme {
    // MARK: Color

    /// Window background.
    static let canvas = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x0D0E10))
    /// Panels and sidebar selections.
    static let surface = Color(micaLight: rgb(0xF5F6F7), dark: rgb(0x15171A))
    /// Inspector and popovers.
    static let surfaceRaised = Color(micaLight: rgb(0xFFFFFF), dark: rgb(0x1C1F23))
    /// Opaque hairlines only.
    static let separator = Color(micaLight: rgb(0xD9DBDF), dark: rgb(0x2A2D32))

    /// System-compatible text ramps; both appearances resolve through the
    /// system label colors so contrast tracks the user's accessibility settings.
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    /// Signal teal: selection, active path, primary action, live indicator ONLY.
    static let accent = Color(micaLight: rgb(0x0B8F66), dark: rgb(0x34D1A3))

    /// Controller-reported status ONLY; system equivalents keep both
    /// appearances and increase-contrast adaptations for free.
    static let statusOK = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusError = Color(nsColor: .systemRed)

    /// Muted column identity tints for the overview topology flow graph
    /// (task 08-23). Hues dodge the teal accent and the vivid status colors
    /// and stay desaturated, so controller-reported status always reads above
    /// the flow encoding.
    enum ColumnTint {
        /// Sources: muted slate blue.
        static let source = Color(micaLight: rgb(0x5B7089), dark: rgb(0x7E93B0))
        /// Matched rules: muted warm sand.
        static let rule = Color(micaLight: rgb(0x9A7B4F), dark: rgb(0xC4A876))
        /// Proxy chain hops: muted violet.
        static let policyHop = Color(micaLight: rgb(0x7A68AC), dark: rgb(0xA495D6))
        /// Chain exits: muted dusty rose.
        static let finalOutbound = Color(micaLight: rgb(0xA85F74), dark: rgb(0xCE8499))
    }

    /// Non-selected edges while a trajectory is active: an explicit alpha-baked
    /// neutral (tertiaryLabelColor's own ~26% alpha made these invisible in
    /// light mode).
    static let edgeDimmed = Color(micaLight: rgba(0x14181D, 0.16), dark: rgba(0xE8ECF1, 0.14))

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
    /// Dynamic light/dark color created in code (design.md §2) - no asset
    /// catalog. Mirrors the `adaptive(light:dark:)` provider pattern in
    /// superseded workbench token file.
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
    /// Semantic status for controller-reported state. Colors come only from the
    /// status tokens; `neutral` reuses the tertiary text ramp for unknown or
    /// inactive state without introducing a new color token.
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
    /// Type scale (design.md §2). UI roles render SF Pro at 11/12/13/15/17 with
    /// semibold titles plus 22/28 hero values. `data*` roles render SF Mono
    /// (`Font.system(design: .monospaced)`) with tabular numerals and are the only roles
    /// allowed for live data (latency, rates, IPs, ports, counts, timestamps).
    ///
    /// Every role scales through `AppFontScale.pointSize(for:)` - the same
    /// multiplier the superseded scaled-font modifier applied - so the user's
    /// font-scale preference keeps working for MicaTheme text.
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

    /// Scaled point size for a role under the user's font-scale preference.
    static func pointSize(for role: TextRole, scale: AppFontScale) -> CGFloat {
        scale.pointSize(for: role.basePointSize)
    }

    /// Resolved font for a role. Non-View callers (Canvas/NSView rendering)
    /// pass the `AppFontScale` they already carry; SwiftUI callers should
    /// prefer `micaThemeFont`, which reads the scale from the environment.
    static func font(
        for role: TextRole,
        scale: AppFontScale = .comfortable,
        weight: Font.Weight? = nil
    ) -> Font {
        let size = pointSize(for: role, scale: scale)
        let resolvedWeight = weight ?? role.defaultWeight
        if role.isMonospaced {
            // SF Mono: the SDK spells `Font.monospacedSystem` as `.monospaced`
            // design on the system font (the face the superseded scaled-font modifier used for data).
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
            // Tabular numerals everywhere live data appears (design.md §2).
            scaled.monospacedDigit()
        } else {
            scaled
        }
    }
}

extension View {
    /// Applies a MicaTheme text role, scaled by the user's font-scale
    /// preference via the same `AppFontScale` multiplier the superseded
    /// scaled-font modifier applied.
    func micaThemeFont(_ role: MicaTheme.TextRole, weight: Font.Weight? = nil) -> some View {
        modifier(MicaThemeFontModifier(role: role, weight: weight))
    }
}

// MARK: - Spacing, Shape, Metrics

extension MicaTheme {
    /// 4pt baseline grid (design.md §2).
    enum Spacing {
        static let space1: CGFloat = 4
        static let space2: CGFloat = 8
        static let space3: CGFloat = 12
        static let space4: CGFloat = 16
        static let space5: CGFloat = 24

        /// Panel padding stays within 12-16pt.
        static let panelPaddingCompact: CGFloat = space3
        static let panelPadding: CGFloat = space4
    }

    enum Shape {
        static let panelRadius: CGFloat = 6
        static let windowRadius: CGFloat = 10
        /// Flat hairline separators replace elevation; no shadows in dark mode.
        static let hairline: CGFloat = 1
    }

    enum Metrics {
        /// Density-first data-list row heights (design.md §2 typography).
        static let dataRowHeightMin: CGFloat = 22
        static let dataRowHeightMax: CGFloat = 28

        /// Compact icon-button bounds (Phase 4 migration of
        /// superseded bounds token; same value).
        static let iconControlSize: CGFloat = 28
        /// Group-module corner radius (Phase 4 migration of
        /// superseded bounds token; same value).
        static let moduleRadius: CGFloat = 8
        /// Dense-cell corner radius (Phase 4 migration of
        /// superseded bounds token; same value).
        static let badgeRadius: CGFloat = 5
        /// Minimum height for standalone controls (Phase 4B migration of
        /// superseded bounds token; same value).
        static let controlMinHeight: CGFloat = 28
        /// Fixed command-bar height (Phase 4B migration of
        /// superseded bounds token; same value).
        static let commandBarHeight: CGFloat = 40
        /// Horizontal padding for window chrome strips (Phase 4B migration of
        /// superseded bounds token; same value).
        static let chromeHorizontalPadding: CGFloat = 12

        /// Compact page horizontal padding (Phase 5C migration of
        /// superseded bounds token; same value).
        static let compactPagePadding: CGFloat = 12
        /// Regular page horizontal padding (Phase 5C migration of
        /// superseded bounds token; same value).
        static let regularPagePadding: CGFloat = 16
        /// Width threshold switching compact to regular page padding (Phase 5C
        /// migration of superseded bounds token; same value).
        static let wideThreshold: CGFloat = 720

        /// Page horizontal padding for a content width (Phase 5C migration of
        /// superseded bounds token; same value).
        static func pagePadding(for width: CGFloat) -> CGFloat {
            width < wideThreshold ? compactPagePadding : regularPagePadding
        }

        /// Fixed status-bar height (Phase 6A migration of
        /// superseded bounds token; same value).
        static let statusBarHeight: CGFloat = 34
        /// Inspector column width limits (Phase 6A migration of
        /// superseded bounds token; same value).
        static let inspectorMin: CGFloat = 300
        static let inspectorIdeal: CGFloat = 360
        static let inspectorMax: CGFloat = 480
        /// Management form label column width (Phase 6A migration of
        /// superseded bounds token; same value).
        static let formLabelWidth: CGFloat = 176
        /// Management form control maximum width (Phase 6A migration of
        /// superseded bounds token; same value).
        static let formControlMax: CGFloat = 360
        /// Sidebar column width limits (Phase 7 migration of
        /// superseded bounds token; same value).
        static let sidebarMin: CGFloat = 176
        static let sidebarIdeal: CGFloat = 196
        static let sidebarMax: CGFloat = 232
    }
}

// MARK: - Motion

extension MicaTheme {
    /// State-change motion only: 120-200ms ease-out (design.md §2). No idle
    /// loops exist in this system; callers must gate every animation on
    /// `accessibilityReduceMotion` (use `micaStateChangeAnimation`).
    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let stateChange = Animation.easeOut(duration: 0.15)
        static let reveal = Animation.easeOut(duration: 0.2)
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
    /// Animates a state change with a MicaTheme motion token unless the user
    /// prefers reduced motion, in which case the change applies instantly.
    func micaStateChangeAnimation<Value: Equatable>(
        _ animation: Animation? = MicaTheme.Motion.stateChange,
        value: Value
    ) -> some View {
        modifier(MicaStateChangeAnimationModifier(animation: animation, value: value))
    }
}

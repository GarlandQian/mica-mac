import AppKit
import SwiftUI

enum MicaStyle {
    // System materials own the window, sidebar, toolbar, and data backgrounds.
    // Rose Pine remains a semantic tint/status palette, including as an opaque
    // fallback for accessibility settings that reduce transparency.
    static let separator = Color(nsColor: .separatorColor)

    // Unified content-card tokens (MicaContentCard). One radius/padding/border
    // vocabulary shared by every workbench surface so cards never drift in
    // shape or rhythm across tabs.
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 10
    static let cardTintBorderOpacity: Double = 0.18
    // Semantic signal palette (Rose Pine Dawn/Main). Each color is used as a
    // text/icon foreground somewhere in the app, so every light variant is
    // tuned to clear WCAG 4.5:1 against a white content card (verified via
    // apple-hig-expert `hig_checker.py`); the same constants also feed graphic
    // uses (chart marks, delay dots, share bars) where the darker value still
    // clears the 3.0:1 graphic bar comfortably. Dark variants already cleared
    // 4.5:1 except mint, which is lightened here. Do not lighten the light
    // variants back toward the original Dawn values without re-checking contrast.
    static let accent = adaptiveColor(
        light: nsColor(0.478, 0.404, 0.561),
        dark: nsColor(0.769, 0.655, 0.906)
    )
    static let contentFill = Color(nsColor: .textBackgroundColor)
    static let pageFill = Color(nsColor: .windowBackgroundColor)
    static let glassFallback = Color(nsColor: .controlBackgroundColor)

    static let signalMint = adaptiveColor(
        light: nsColor(0.157, 0.412, 0.514),
        dark: nsColor(0.264, 0.626, 0.771)
    )
    static let signalCyan = adaptiveColor(
        light: nsColor(0.263, 0.467, 0.498),
        dark: nsColor(0.612, 0.812, 0.847)
    )
    static let signalAmber = adaptiveColor(
        light: nsColor(0.588, 0.392, 0.122),
        dark: nsColor(0.965, 0.757, 0.467)
    )
    static let signalRed = adaptiveColor(
        light: nsColor(0.635, 0.341, 0.427),
        dark: nsColor(0.922, 0.435, 0.573)
    )
    static let signalViolet = adaptiveColor(
        light: nsColor(0.492, 0.416, 0.577),
        dark: nsColor(0.769, 0.655, 0.906)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }

    private static func nsColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

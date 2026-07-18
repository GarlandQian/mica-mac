import SwiftUI

enum AppFontScale: String, CaseIterable, Identifiable {
    case standard
    case comfortable
    case large
    case extraLarge

    var id: String { rawValue }

    static func stored(_ rawValue: String?) -> AppFontScale {
        switch rawValue {
        case AppFontScale.standard.rawValue:
            .standard
        case AppFontScale.comfortable.rawValue:
            .comfortable
        case AppFontScale.large.rawValue:
            .large
        case AppFontScale.extraLarge.rawValue:
            .extraLarge
        default:
            .comfortable
        }
    }

    /// Maps the user-facing scale to a `DynamicTypeSize`. macOS clamps the
    /// effective range to roughly `xSmall...xxLarge`, so the four steps are
    /// spread across the widest available range to make the difference between
    /// Standard, Comfortable, Large, and Extra Large visually distinct.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .standard:
            .small
        case .comfortable:
            .large
        case .large:
            .xLarge
        case .extraLarge:
            .xxLarge
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .standard:
            0.92
        case .comfortable:
            1.0
        case .large:
            1.16
        case .extraLarge:
            1.32
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .standard:
            .small
        case .comfortable:
            .regular
        case .large, .extraLarge:
            .large
        }
    }

    var titleKey: String {
        switch self {
        case .standard:
            "settings.font_scale_standard"
        case .comfortable:
            "settings.font_scale_comfortable"
        case .large:
            "settings.font_scale_large"
        case .extraLarge:
            "settings.font_scale_extra_large"
        }
    }
}

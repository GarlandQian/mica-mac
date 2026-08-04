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

    /// Keeps four clearly separated semantic text steps. Layout breakpoints
    /// remain width-driven, so changing this preference never rearranges rows.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .standard:
            .small
        case .comfortable:
            .large
        case .large:
            .xxLarge
        case .extraLarge:
            .xxxLarge
        }
    }

    /// macOS does not visibly resize every explicit semantic `Font` from a
    /// `dynamicTypeSize` override, so Mica also scales its own text roles.
    var multiplier: CGFloat {
        switch self {
        case .standard:
            0.92
        case .comfortable:
            1
        case .large:
            1.16
        case .extraLarge:
            1.32
        }
    }

    func pointSize(for basePointSize: CGFloat) -> CGFloat {
        (basePointSize * multiplier * 2).rounded() / 2
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

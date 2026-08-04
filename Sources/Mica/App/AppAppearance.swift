import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static func stored(_ rawValue: String?) -> AppAppearance {
        switch rawValue {
        case AppAppearance.light.rawValue:
            .light
        case AppAppearance.dark.rawValue:
            .dark
        case AppAppearance.system.rawValue:
            .system
        default:
            .system
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func applyToApplication() {
        let application = NSApplication.shared
        application.appearance = nsAppearance
        for window in application.windows {
            window.appearance = nsAppearance
            window.contentView?.appearance = nsAppearance
            window.contentViewController?.view.appearance = nsAppearance
            window.invalidateShadow()
            window.displayIfNeeded()
        }
    }

    var titleKey: String {
        switch self {
        case .system:
            "settings.appearance_system"
        case .light:
            "settings.appearance_light"
        case .dark:
            "settings.appearance_dark"
        }
    }
}

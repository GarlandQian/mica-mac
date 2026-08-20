import MicaCore
import SwiftUI

extension ControllerKind {
    var sidebarSymbol: String {
        switch self {
        case .surgeCompatible:
            MicaSymbols.Controller.surge
        case .singBoxCompatible:
            MicaSymbols.Controller.singBox
        case .cmfaCompatible, .stashCompatible, .stashCmfaCompatible:
            MicaSymbols.Controller.stashCmfa
        case .mihomoCompatible:
            MicaSymbols.Controller.mihomo
        case .nikkiMihomoCompatible:
            MicaSymbols.Controller.nikki
        case .openClashMihomoCompatible:
            MicaSymbols.Controller.openClash
        case .autoDetect:
            MicaSymbols.Controller.autoDetect
        case .unknown:
            MicaSymbols.Controller.unknown
        case .unsupported:
            MicaSymbols.Controller.unsupported
        }
    }

    var sidebarTint: Color {
        switch self {
        case .autoDetect:
            MicaTheme.textSecondary
        case .mihomoCompatible:
            MicaTheme.statusOK
        case .nikkiMihomoCompatible:
            MicaTheme.textSecondary
        case .openClashMihomoCompatible:
            MicaTheme.statusWarning
        case .surgeCompatible:
            MicaTheme.statusError
        case .singBoxCompatible:
            MicaTheme.textSecondary
        case .cmfaCompatible, .stashCompatible, .stashCmfaCompatible:
            MicaTheme.textSecondary
        case .unknown:
            .secondary
        case .unsupported:
            MicaTheme.statusError
        }
    }
}

extension ConnectionState {
    var sidebarTint: Color {
        switch self {
        case .connected:
            MicaTheme.statusOK
        case .connecting:
            MicaTheme.textSecondary
        case .failed:
            MicaTheme.statusError
        case .disconnected:
            .secondary
        }
    }

    var sidebarLabel: String {
        sidebarLabel(language: MicaStrings.appLanguage)
    }

    func sidebarLabel(language: AppLanguage) -> String {
        switch self {
        case .connected:
            MicaStrings.localized("sidebar.live", language: language)
        case .connecting:
            MicaStrings.localized("sidebar.connecting", language: language)
        case .failed:
            MicaStrings.localized("sidebar.alert", language: language)
        case .disconnected:
            MicaStrings.localized("sidebar.idle", language: language)
        }
    }

    var sidebarIconName: String {
        switch self {
        case .connected:
            MicaSymbols.Command.ready
        case .connecting:
            MicaSymbols.Command.working
        case .failed:
            "xmark.octagon.fill"
        case .disconnected:
            "minus.circle"
        }
    }
}

extension ControllerHealthSummary {
    var sidebarLabel: String {
        sidebarLabel(language: MicaStrings.appLanguage)
    }

    func sidebarLabel(language: AppLanguage) -> String {
        switch self {
        case .ready:
            MicaStrings.localized("sidebar.ready", language: language)
        case .partial:
            MicaStrings.localized("sidebar.partial", language: language)
        case .authFailed:
            MicaStrings.localized("sidebar.auth", language: language)
        case .wrongTarget:
            MicaStrings.localized("sidebar.target", language: language)
        case .offline:
            MicaStrings.localized("sidebar.offline", language: language)
        case .checking:
            MicaStrings.localized("sidebar.check", language: language)
        case .unknown:
            MicaStrings.localized("sidebar.health", language: language)
        }
    }

    var sidebarTint: Color {
        switch self {
        case .ready:
            MicaTheme.statusOK
        case .partial, .checking:
            MicaTheme.statusWarning
        case .authFailed, .wrongTarget, .offline:
            MicaTheme.statusError
        case .unknown:
            .secondary
        }
    }

    var sidebarIconName: String {
        switch self {
        case .ready:
            "checkmark.seal.fill"
        case .partial, .checking:
            "exclamationmark.triangle.fill"
        case .authFailed, .wrongTarget, .offline:
            "xmark.octagon.fill"
        case .unknown:
            "minus.circle"
        }
    }
}

extension TrialSessionHealth {
    var sidebarLabel: String {
        sidebarLabel(language: MicaStrings.appLanguage)
    }

    func sidebarLabel(language: AppLanguage) -> String {
        switch self {
        case .idle:
            MicaStrings.localized("sidebar.session_idle", language: language)
        case .fresh:
            MicaStrings.localized("sidebar.fresh", language: language)
        case .stale:
            MicaStrings.localized("sidebar.stale", language: language)
        case .partial:
            MicaStrings.localized("sidebar.partial", language: language)
        case .failed:
            MicaStrings.localized("sidebar.failed", language: language)
        }
    }

    var sidebarTint: Color {
        switch self {
        case .idle:
            .secondary
        case .fresh:
            MicaTheme.statusOK
        case .stale, .partial:
            MicaTheme.statusWarning
        case .failed:
            MicaTheme.statusError
        }
    }

    var sidebarIconName: String {
        switch self {
        case .idle:
            "minus.circle"
        case .fresh:
            "checkmark.seal.fill"
        case .stale, .partial:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }
}

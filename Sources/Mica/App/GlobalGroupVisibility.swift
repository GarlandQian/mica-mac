import Foundation

/// Controls whether the GLOBAL policy group is shown in the policy list.
/// `.followMode` shows GLOBAL only while the controller reports Global mode;
/// `.alwaysShow` keeps it visible in every mode. When visible, GLOBAL is
/// placed at the end of the list (see `PolicyGroupPresentation.arrangedGroups`).
enum GlobalGroupVisibility: String, CaseIterable, Identifiable {
    case followMode
    case alwaysShow

    var id: String { rawValue }

    static func stored(_ rawValue: String?) -> GlobalGroupVisibility {
        switch rawValue {
        case GlobalGroupVisibility.alwaysShow.rawValue:
            .alwaysShow
        case GlobalGroupVisibility.followMode.rawValue:
            .followMode
        default:
            .followMode
        }
    }

    var titleKey: String {
        switch self {
        case .followMode:
            "settings.global_follow_mode"
        case .alwaysShow:
            "settings.global_always_show"
        }
    }
}

import Foundation
import MicaCore

enum CoreCompatibilitySummary: String, Equatable {
    case mihomoCompatible
    case smartCompatible
    case partialCompatible
    case unknownController
    case unsupported

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .mihomoCompatible:
            return MicaStrings.localized("compatibility.mihomo_compatible", language: language)
        case .smartCompatible:
            return MicaStrings.localized("compatibility.smart_compatible", language: language)
        case .partialCompatible:
            return MicaStrings.localized("compatibility.partial_compatible", language: language)
        case .unknownController:
            return MicaStrings.localized("compatibility.unknown_controller", language: language)
        case .unsupported:
            return MicaStrings.localized("compatibility.unsupported", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .mihomoCompatible:
            return "mihomo-compatible"
        case .smartCompatible:
            return "smart-compatible"
        case .partialCompatible:
            return "partial-compatible"
        case .unknownController:
            return "unknown-controller"
        case .unsupported:
            return "unsupported"
        }
    }
}

struct CapabilityMatrixRow: Identifiable, Equatable {
    var id: String
    var title: String
    var status: CapabilityStatus
    var evidence: String
    var operationImpact: String
}

struct DiagnosticsRuntimeOperationRow: Identifiable, Equatable {
    var id: String
    var titleKey: String
    var detailKey: String
    var sourceKey: String
    var sourceRowID: String
    var systemImage: String
    var status: CapabilityStatus
    var nextStepKey: String
    var actionButtonKey: String?
    var requiresConfirmation: Bool
    var confirmationMessageKey: String?
    var isDestructive: Bool
    var evidence: String
}

enum CapabilityStatus: String, CaseIterable, Equatable {
    case supported
    case unavailable
    case partial
    case untested
    case failed

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .supported:
            MicaStrings.localized("diagnostics.capability_status_supported", language: language)
        case .partial:
            MicaStrings.localized("diagnostics.capability_status_partial", language: language)
        case .untested:
            MicaStrings.localized("diagnostics.capability_status_untested", language: language)
        case .unavailable:
            MicaStrings.localized("diagnostics.capability_status_unavailable", language: language)
        case .failed:
            MicaStrings.localized("diagnostics.capability_status_failed", language: language)
        }
    }

    var diagnosticsLabel: String {
        rawValue
    }

    var fallbackStatus: CapabilityStatus {
        switch self {
        case .supported:
            return .supported
        case .failed:
            return .failed
        case .unavailable:
            return .unavailable
        case .partial:
            return .partial
        case .untested:
            return .untested
        }
    }

    var emptyFallback: CapabilityStatus {
        switch self {
        case .supported:
            return .partial
        case .failed:
            return .failed
        case .unavailable:
            return .unavailable
        case .partial:
            return .partial
        case .untested:
            return .untested
        }
    }
}

struct ObservabilityReadinessRow: Identifiable, Equatable {
    var id: String
    var title: String
    var category: String
    var state: ObservabilityReadinessState
    var detail: String
    var boundary: String
}

enum ObservabilityReadinessState: String, CaseIterable, Equatable {
    case ready
    case partial
    case notImplementedInUI
    case controllerCapabilityUnknown
    case futureOptionalStream
    case unavailable

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .ready:
            return MicaStrings.localized("observability.ready", language: language)
        case .partial:
            return MicaStrings.localized("observability.partial", language: language)
        case .notImplementedInUI:
            return MicaStrings.localized("observability.not_implemented", language: language)
        case .controllerCapabilityUnknown:
            return MicaStrings.localized("observability.capability_unknown", language: language)
        case .futureOptionalStream:
            return MicaStrings.localized("observability.future_optional_stream", language: language)
        case .unavailable:
            return MicaStrings.localized("observability.unavailable", language: language)
        }
    }

    var diagnosticsLabel: String {
        switch self {
        case .ready:
            return "ready"
        case .partial:
            return "partial"
        case .notImplementedInUI:
            return "not-implemented-in-ui"
        case .controllerCapabilityUnknown:
            return "controller-capability-unknown"
        case .futureOptionalStream:
            return "future-optional-stream"
        case .unavailable:
            return "unavailable"
        }
    }
}

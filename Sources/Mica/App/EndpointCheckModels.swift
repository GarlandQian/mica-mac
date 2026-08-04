import Foundation
import MicaCore

struct EndpointCheckStep: Identifiable, Equatable {
    var id: String
    var title: String
    var state: EndpointCheckState
    var detail: String
    var nextAction: String
    var primaryAction: EndpointCheckAction?
}

enum EndpointCheckState: String, Equatable {
    case ready
    case running
    case passed
    case partial
    case failed
    case skipped

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .ready:
            return MicaStrings.localized("trial.state_ready", language: language)
        case .running:
            return MicaStrings.localized("trial.state_running", language: language)
        case .passed:
            return MicaStrings.localized("trial.state_passed", language: language)
        case .partial:
            return MicaStrings.localized("trial.state_partial", language: language)
        case .failed:
            return MicaStrings.localized("trial.state_failed", language: language)
        case .skipped:
            return MicaStrings.localized("trial.state_skipped", language: language)
        }
    }
}

enum EndpointCheckAction: String, Identifiable, Equatable {
    case retryTest
    case refresh
    case reloadRules
    case reloadProviders
    case copyDiagnostics

    var id: String {
        rawValue
    }

    var title: String {
        title(language: MicaStrings.appLanguage)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .retryTest:
            return MicaStrings.localized("trial.action_retry_test", language: language)
        case .refresh:
            return MicaStrings.localized("trial.action_refresh", language: language)
        case .reloadRules:
            return MicaStrings.localized("trial.action_reload_rules", language: language)
        case .reloadProviders:
            return MicaStrings.localized("trial.action_reload_providers", language: language)
        case .copyDiagnostics:
            return MicaStrings.localized("trial.action_copy_diagnostics", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .retryTest:
            return MicaSymbols.Command.test
        case .refresh:
            return MicaSymbols.Command.refresh
        case .reloadRules:
            return MicaSymbols.Data.rules
        case .reloadProviders:
            return MicaSymbols.Data.providerItems
        case .copyDiagnostics:
            return MicaSymbols.Command.copy
        }
    }
}

enum DiagnosticsExportTarget: String, Identifiable, CaseIterable, Equatable {
    case endpointResults
    case checkResults
    case diagnosticsReport

    var id: String {
        rawValue
    }

    var title: String {
        title(language: MicaStrings.appLanguage)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .endpointResults:
            return MicaStrings.localized("export.endpoint_results", language: language)
        case .checkResults:
            return MicaStrings.localized("export.check_results", language: language)
        case .diagnosticsReport:
            return MicaStrings.localized("export.diagnostics_report", language: language)
        }
    }

    var buttonTitle: String {
        buttonTitle(language: MicaStrings.appLanguage)
    }

    func buttonTitle(language: AppLanguage) -> String {
        switch self {
        case .endpointResults:
            return MicaStrings.localized("export.copy_endpoint_results", language: language)
        case .checkResults:
            return MicaStrings.localized("export.copy_check_results", language: language)
        case .diagnosticsReport:
            return MicaStrings.localized("export.copy_diagnostics_report", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .endpointResults:
            return "checkmark.shield"
        case .checkResults:
            return "tablecells"
        case .diagnosticsReport:
            return "doc.on.doc"
        }
    }
}

struct CheckResultRow: Identifiable, Equatable {
    var id: String
    var title: String
    var state: CheckResultState
    var currentState: String
    var latestResult: String
    var lastChecked: String
    var nextAction: String
    var retryAction: String
    var reportPolicy: String
}

enum CheckResultState: Equatable {
    case ready
    case partial
    case attention
    case notChecked

    var label: String {
        label(language: MicaStrings.appLanguage)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .ready:
            return MicaStrings.localized("matrix.state_ready", language: language)
        case .partial:
            return MicaStrings.localized("matrix.state_partial", language: language)
        case .attention:
            return MicaStrings.localized("matrix.state_attention", language: language)
        case .notChecked:
            return MicaStrings.localized("matrix.state_not_checked", language: language)
        }
    }
}

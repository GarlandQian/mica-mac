import Foundation
import MicaCore

enum RouterTrialFailureCategory: Equatable {
    case authFailed
    case wrongTarget
    case malformedJSON
    case invalidURL
    case dns
    case connectionRefused
    case timeout
    case tls
    case partialEnhancedSnapshot
    case providerUpdateFailed
    case networkUnavailable
    case cancelled
    case networkFailed
    case unexpectedHTTP(Int)
    case localFailure

    var retryDisposition: RouterRetryDisposition {
        switch self {
        case .dns,
             .connectionRefused,
             .timeout,
             .partialEnhancedSnapshot,
             .providerUpdateFailed,
             .networkUnavailable,
             .networkFailed:
            .transient
        case .unexpectedHTTP(let status) where status == 408 || status == 429 || status >= 500:
            .transient
        case .cancelled:
            .cancelled
        case .localFailure:
            .retryOnce
        case .authFailed,
             .wrongTarget,
             .malformedJSON,
             .invalidURL,
             .tls,
             .unexpectedHTTP:
            .terminal
        }
    }

    init(error: Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }

        if error is RouterProfileEndpointError {
            self = .invalidURL
            return
        }

        if let surgeError = error as? SurgeHttpAPIError {
            self = Self.category(for: surgeError)
            return
        }

        if let clientError = error as? MihomoClientError {
            self = Self.category(for: clientError)
            return
        }

        if let singBoxError = error as? SingBoxGRPCError {
            self = Self.category(for: singBoxError)
            return
        }

        self = .localFailure
    }

    var shortLabel: String {
        shortLabel(language: MicaStrings.appLanguage)
    }

    func shortLabel(language: AppLanguage) -> String {
        switch self {
        case .authFailed:
            return MicaStrings.localized("failure.auth_failed_short", language: language)
        case .wrongTarget:
            return MicaStrings.localized("failure.wrong_target_short", language: language)
        case .malformedJSON:
            return MicaStrings.localized("failure.invalid_json_short", language: language)
        case .invalidURL:
            return MicaStrings.localized("failure.invalid_url_short", language: language)
        case .dns:
            return MicaStrings.localized("failure.dns_short", language: language)
        case .connectionRefused:
            return MicaStrings.localized("failure.port_refused_short", language: language)
        case .timeout:
            return MicaStrings.localized("failure.timeout_short", language: language)
        case .tls:
            return MicaStrings.localized("failure.tls_short", language: language)
        case .partialEnhancedSnapshot:
            return MicaStrings.localized("failure.partial_enhanced_short", language: language)
        case .providerUpdateFailed:
            return MicaStrings.localized("failure.provider_update_short", language: language)
        case .networkUnavailable:
            return MicaStrings.localized("failure.network_offline_short", language: language)
        case .cancelled:
            return MicaStrings.localized("failure.cancelled_short", language: language)
        case .networkFailed:
            return MicaStrings.localized("failure.network_failed_short", language: language)
        case .unexpectedHTTP(let status):
            return MicaStrings.localized("failure.http_status \(status)", language: language)
        case .localFailure:
            return MicaStrings.localized("failure.failed_short", language: language)
        }
    }

    var safeMessage: String {
        safeMessage(language: MicaStrings.appLanguage)
    }

    func safeMessage(language: AppLanguage) -> String {
        switch self {
        case .authFailed:
            return MicaStrings.localized("failure.auth_failed_message", language: language)
        case .wrongTarget:
            return MicaStrings.localized("failure.wrong_target_message", language: language)
        case .malformedJSON:
            return MicaStrings.localized("failure.invalid_json_message", language: language)
        case .invalidURL:
            return MicaStrings.localized("failure.invalid_url_message", language: language)
        case .dns:
            return MicaStrings.localized("failure.dns_message", language: language)
        case .connectionRefused:
            return MicaStrings.localized("failure.port_refused_message", language: language)
        case .timeout:
            return MicaStrings.localized("failure.timeout_message", language: language)
        case .tls:
            return MicaStrings.localized("failure.tls_message", language: language)
        case .partialEnhancedSnapshot:
            return MicaStrings.localized("failure.partial_enhanced_message", language: language)
        case .providerUpdateFailed:
            return MicaStrings.localized("failure.provider_update_message", language: language)
        case .networkUnavailable:
            return MicaStrings.localized("failure.network_offline_message", language: language)
        case .cancelled:
            return MicaStrings.localized("failure.cancelled_message", language: language)
        case .networkFailed:
            return MicaStrings.localized("failure.network_failed_message", language: language)
        case .unexpectedHTTP(let status):
            return MicaStrings.localized("failure.http_status_message \(status)", language: language)
        case .localFailure:
            return MicaStrings.localized("failure.local_message", language: language)
        }
    }

    var reportHeadline: String {
        reportHeadline(language: MicaStrings.appLanguage)
    }

    func reportHeadline(language: AppLanguage) -> String {
        switch self {
        case .authFailed:
            return MicaStrings.localized("failure.auth_failed_headline", language: language)
        case .wrongTarget:
            return MicaStrings.localized("failure.wrong_target_headline", language: language)
        case .malformedJSON:
            return MicaStrings.localized("failure.invalid_json_headline", language: language)
        case .invalidURL:
            return MicaStrings.localized("failure.invalid_url_headline", language: language)
        case .dns:
            return MicaStrings.localized("failure.dns_headline", language: language)
        case .connectionRefused:
            return MicaStrings.localized("failure.port_refused_headline", language: language)
        case .timeout:
            return MicaStrings.localized("failure.timeout_headline", language: language)
        case .tls:
            return MicaStrings.localized("failure.tls_headline", language: language)
        case .partialEnhancedSnapshot:
            return MicaStrings.localized("failure.partial_enhanced_headline", language: language)
        case .providerUpdateFailed:
            return MicaStrings.localized("failure.provider_update_headline", language: language)
        case .networkUnavailable:
            return MicaStrings.localized("failure.network_offline_headline", language: language)
        case .cancelled:
            return MicaStrings.localized("failure.cancelled_headline", language: language)
        case .networkFailed:
            return MicaStrings.localized("failure.network_failed_headline", language: language)
        case .unexpectedHTTP(let status):
            return MicaStrings.localized("failure.http_status_headline \(status)", language: language)
        case .localFailure:
            return MicaStrings.localized("failure.local_headline", language: language)
        }
    }

    var controllerJSONMessage: String {
        controllerJSONMessage(language: MicaStrings.appLanguage)
    }

    func controllerJSONMessage(language: AppLanguage) -> String {
        switch self {
        case .authFailed:
            return MicaStrings.localized("failure.json_auth_failed", language: language)
        case .wrongTarget:
            return MicaStrings.localized("failure.json_wrong_target", language: language)
        case .malformedJSON:
            return MicaStrings.localized("failure.json_malformed", language: language)
        case .invalidURL:
            return MicaStrings.localized("failure.json_invalid_url", language: language)
        case .dns, .connectionRefused, .networkUnavailable, .networkFailed:
            return MicaStrings.localized("failure.json_no_response", language: language)
        case .timeout:
            return MicaStrings.localized("failure.json_timeout", language: language)
        case .tls:
            return MicaStrings.localized("failure.json_tls", language: language)
        case .partialEnhancedSnapshot:
            return MicaStrings.localized("failure.json_partial_enhanced", language: language)
        case .providerUpdateFailed:
            return MicaStrings.localized("failure.json_provider_update", language: language)
        case .cancelled:
            return MicaStrings.localized("failure.json_cancelled", language: language)
        case .unexpectedHTTP(let status):
            return MicaStrings.localized("failure.json_http_status \(status)", language: language)
        case .localFailure:
            return MicaStrings.localized("failure.json_local", language: language)
        }
    }

    var nextStep: String {
        nextStep(language: MicaStrings.appLanguage)
    }

    func nextStep(language: AppLanguage) -> String {
        switch self {
        case .authFailed, .wrongTarget, .malformedJSON, .invalidURL, .dns, .connectionRefused, .tls:
            return MicaStrings.localized("matrix.edit_controller", language: language)
        case .partialEnhancedSnapshot:
            return MicaStrings.localized("trial.reload_rules_or_providers", language: language)
        case .providerUpdateFailed:
            return MicaStrings.localized("trial.retry_provider_update", language: language)
        case .timeout, .networkUnavailable, .networkFailed, .unexpectedHTTP, .cancelled, .localFailure:
            return MicaStrings.localized("matrix.retry_test", language: language)
        }
    }

    var summary: ControllerHealthSummary {
        switch self {
        case .authFailed:
            return .authFailed
        case .wrongTarget, .malformedJSON, .invalidURL:
            return .wrongTarget
        case .dns, .connectionRefused, .timeout, .tls, .networkUnavailable, .networkFailed:
            return .offline
        case .partialEnhancedSnapshot, .providerUpdateFailed:
            return .partial
        case .unexpectedHTTP:
            return .partial
        case .cancelled, .localFailure:
            return .unknown
        }
    }

    private static func category(for error: SurgeHttpAPIError) -> RouterTrialFailureCategory {
        switch error {
        case .unauthorized:
            return .authFailed
        case .unexpectedStatus(let status):
            return httpCategory(status)
        case .malformedResponse:
            return .malformedJSON
        case .emptyResponse, .invalidResponse:
            return .wrongTarget
        case .invalidURL:
            return .invalidURL
        case .connectionFailure(let reason):
            return category(for: reason)
        }
    }

    private static func category(for error: MihomoClientError) -> RouterTrialFailureCategory {
        switch error {
        case .unauthorized:
            return .authFailed
        case .unexpectedStatus(let status):
            return httpCategory(status)
        case .malformedResponse:
            return .malformedJSON
        case .emptyResponse, .invalidResponse:
            return .wrongTarget
        case .invalidURL:
            return .invalidURL
        case .connectionFailure(let reason):
            return category(for: reason)
        }
    }

    private static func category(for error: SingBoxGRPCError) -> RouterTrialFailureCategory {
        switch error {
        case .invalidIntervalMilliseconds:
            return .localFailure
        case .transport:
            return .networkFailed
        case .rpc(let code, _):
            switch code {
            case 1:
                return .cancelled
            case 4:
                return .timeout
            case 7, 16:
                return .authFailed
            case 14:
                return .networkUnavailable
            case 2, 8, 13:
                return .networkFailed
            default:
                return .localFailure
            }
        }
    }

    private static func httpCategory(_ status: Int) -> RouterTrialFailureCategory {
        if status == 401 || status == 403 {
            return .authFailed
        }

        if status == 404 || status == 405 {
            return .wrongTarget
        }

        return .unexpectedHTTP(status)
    }

    private static func category(for reason: ControllerConnectionFailureReason) -> RouterTrialFailureCategory {
        switch reason {
        case .hostNotFound:
            return .dns
        case .connectionRefused:
            return .connectionRefused
        case .timedOut:
            return .timeout
        case .tlsTrustFailed:
            return .tls
        case .networkUnavailable:
            return .networkUnavailable
        case .cancelled:
            return .cancelled
        case .other:
            return .networkFailed
        }
    }
}

enum RouterRetryDisposition: Equatable {
    case transient
    case terminal
    case cancelled
    case retryOnce
}

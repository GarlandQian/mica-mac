import Foundation

public enum ControllerConnectionFailureReason: Equatable, Sendable {
    case hostNotFound
    case connectionRefused
    case timedOut
    case tlsTrustFailed
    case networkUnavailable
    case cancelled
    case other

    var errorDescription: String {
        switch self {
        case .hostNotFound:
            "Could not resolve the router host. Check the hostname, mDNS name, or router IP address."
        case .connectionRefused:
            "The router is reachable, but the controller port refused the connection. Check that the external-controller is listening on the LAN address and port."
        case .timedOut:
            "The controller did not respond before the timeout. Check that the Mac and router are on the same network and that the firewall allows the controller port."
        case .tlsTrustFailed:
            "TLS trust failed. Check the router certificate, use a trusted certificate, or choose the self-signed TLS policy only for a router you control."
        case .networkUnavailable:
            "The Mac is offline or cannot reach the router network."
        case .cancelled:
            "The controller request was cancelled."
        case .other:
            "The network request failed before reaching the controller."
        }
    }

    static func classify(_ error: Error) -> Self {
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .other
        }
        switch URLError.Code(rawValue: nsError.code) {
        case .cancelled:
            return .cancelled
        case .cannotFindHost:
            return .hostNotFound
        case .cannotConnectToHost:
            return .connectionRefused
        case .timedOut:
            return .timedOut
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .tlsTrustFailed
        case .notConnectedToInternet:
            return .networkUnavailable
        default:
            return .other
        }
    }
}

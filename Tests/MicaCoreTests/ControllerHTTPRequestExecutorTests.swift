import Foundation
import XCTest
@testable import MicaCore

final class ControllerHTTPRequestExecutorTests: XCTestCase {
    func testFamilyAuthenticationHeadersDoNotLeakIntoEachOther() async throws {
        for family in HTTPFixtureFamily.allCases {
            try await family.read(credential: "fixture-credential") { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
                XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
                XCTAssertNil(request.httpBody)
                XCTAssertEqual(request.timeoutInterval, 8)
                switch family {
                case .mihomo:
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-credential")
                    XCTAssertNil(request.value(forHTTPHeaderField: "X-Key"))
                case .surge:
                    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Key"), "fixture-credential")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                }
                return try httpFixtureResponse(request, data: Data(#"{"mode":"rule"}"#.utf8))
            }
        }
    }

    func testMissingAndEmptyCredentialsOmitAuthentication() async throws {
        for family in HTTPFixtureFamily.allCases {
            for credential in [nil, ""] as [String?] {
                try await family.read(credential: credential) { request in
                    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                    XCTAssertNil(request.value(forHTTPHeaderField: "X-Key"))
                    return try httpFixtureResponse(request, data: Data(#"{"mode":"rule"}"#.utf8))
                }
            }
        }
    }

    func testHTTPStatusIsCheckedBeforeDecodingWithinEachFamily() async throws {
        for family in HTTPFixtureFamily.allCases {
            for status in [301, 401, 403, 404, 500] {
                let failure = await capturedFailure {
                    try await family.read { request in
                        try httpFixtureResponse(request, status: status, data: Data("not-json".utf8))
                    }
                }
                let expected: HTTPFixtureFailure = [401, 403].contains(status) ? .unauthorized : .status(status)
                XCTAssertEqual(family.classify(failure), expected)
            }
        }
    }

    func testReadsRejectEmptyMalformedAndNonHTTPResponses() async throws {
        for family in HTTPFixtureFamily.allCases {
            let empty = await capturedFailure {
                try await family.read { request in try httpFixtureResponse(request, status: 204) }
            }
            XCTAssertEqual(family.classify(empty), .empty)

            let malformed = await capturedFailure {
                try await family.read { request in
                    try httpFixtureResponse(request, data: Data("<html>private response</html>".utf8))
                }
            }
            XCTAssertEqual(family.classify(malformed), .malformed(family.readPath))

            let nonHTTP = await capturedFailure {
                try await family.read { request in
                    let url = try XCTUnwrap(request.url)
                    return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
                }
            }
            XCTAssertEqual(family.classify(nonHTTP), .invalidResponse)
        }
    }

    func testNetworkErrorsKeepTheSameMeaningAcrossControllerFamilies() async throws {
        let failures: [(URLError.Code, ControllerConnectionFailureReason)] = [
            (.cannotFindHost, .hostNotFound),
            (.cannotConnectToHost, .connectionRefused),
            (.timedOut, .timedOut),
            (.serverCertificateUntrusted, .tlsTrustFailed),
            (.clientCertificateRejected, .tlsTrustFailed),
            (.notConnectedToInternet, .networkUnavailable),
            (.networkConnectionLost, .other),
        ]
        for family in HTTPFixtureFamily.allCases {
            for (code, expected) in failures {
                let error = await capturedFailure {
                    try await family.read { _ in
                        throw NSError(domain: NSURLErrorDomain, code: code.rawValue)
                    }
                }
                XCTAssertEqual(family.classify(error), .connection(expected))
            }
        }
    }

    func testTransportAndFamilyCancellationRemainCancellation() async throws {
        let errors: [any Error] = [
            CancellationError(),
            URLError(.cancelled),
            NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue),
        ]
        for family in HTTPFixtureFamily.allCases {
            for error in errors + [family.cancellationError] {
                let failure = await capturedFailure {
                    try await family.read { _ in throw error }
                }
                XCTAssertTrue(failure is CancellationError)
            }
        }
    }

    func testAlreadyCancelledTasksDoNotInvokeTransport() async throws {
        for family in HTTPFixtureFamily.allCases {
            let operation = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await family.read { request in
                    XCTFail("A cancelled request must not reach the transport")
                    return try httpFixtureResponse(request, data: Data(#"{"mode":"rule"}"#.utf8))
                }
            }
            let failure = await capturedFailure { try await operation.value }
            XCTAssertTrue(failure is CancellationError)
        }
    }

    func testCancellationWinsOverLateSuccessfulResponsesAndTransportErrors() async throws {
        for family in HTTPFixtureFamily.allCases {
            for lateFailure in [false, true] {
                let operation = Task {
                    try await family.read { request in
                        withUnsafeCurrentTask { $0?.cancel() }
                        if lateFailure { throw URLError(.timedOut) }
                        return try httpFixtureResponse(request, data: Data(#"{"mode":"rule"}"#.utf8))
                    }
                }
                let failure = await capturedFailure { try await operation.value }
                XCTAssertTrue(failure is CancellationError)
            }
        }
    }

    func testCommandsAcceptEmptySuccessButRejectCancelledCompletion() async throws {
        for family in HTTPFixtureFamily.allCases {
            try await family.command { request in try httpFixtureResponse(request, status: 204) }
            let operation = Task {
                try await family.command { request in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try httpFixtureResponse(request, status: 204)
                }
            }
            let failure = await capturedFailure { try await operation.value }
            XCTAssertTrue(failure is CancellationError)
        }
    }

    private func capturedFailure(_ operation: () async throws -> Void) async -> (any Error)? {
        do {
            try await operation()
            XCTFail("Expected request failure")
            return nil
        } catch {
            return error
        }
    }
}

private enum HTTPFixtureFamily: CaseIterable, Sendable {
    case mihomo
    case surge

    var readPath: String { self == .mihomo ? "/configs" : "/v1/outbound" }

    var cancellationError: any Error {
        switch self {
        case .mihomo: MihomoClientError.connectionFailure(.cancelled)
        case .surge: SurgeHttpAPIError.connectionFailure(.cancelled)
        }
    }

    func read(
        credential: String? = nil,
        loader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws {
        let profile = RouterProfile(displayName: "HTTP fixture", host: "controller.example")
        switch self {
        case .mihomo:
            _ = try await MihomoClient(profile: profile, secret: credential, dataLoader: loader).configs()
        case .surge:
            _ = try await SurgeHttpAPIClient(profile: profile, apiKey: credential, dataLoader: loader).outbound()
        }
    }

    func command(
        loader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws {
        let profile = RouterProfile(displayName: "HTTP fixture", host: "controller.example")
        switch self {
        case .mihomo:
            try await MihomoClient(profile: profile, dataLoader: loader).flushDNSCache()
        case .surge:
            try await SurgeHttpAPIClient(profile: profile, dataLoader: loader).flushDNSCache()
        }
    }

    func classify(_ error: (any Error)?) -> HTTPFixtureFailure? {
        guard let error else { return nil }
        switch (self, error) {
        case (.mihomo, MihomoClientError.unauthorized), (.surge, SurgeHttpAPIError.unauthorized):
            return .unauthorized
        case (.mihomo, MihomoClientError.unexpectedStatus(let code)), (.surge, SurgeHttpAPIError.unexpectedStatus(let code)):
            return .status(code)
        case (.mihomo, MihomoClientError.emptyResponse), (.surge, SurgeHttpAPIError.emptyResponse):
            return .empty
        case (.mihomo, MihomoClientError.invalidResponse), (.surge, SurgeHttpAPIError.invalidResponse):
            return .invalidResponse
        case (.mihomo, MihomoClientError.malformedResponse(let path)), (.surge, SurgeHttpAPIError.malformedResponse(let path)):
            return .malformed(path)
        case (.mihomo, MihomoClientError.connectionFailure(let reason)), (.surge, SurgeHttpAPIError.connectionFailure(let reason)):
            return .connection(reason)
        default:
            return nil
        }
    }
}

private enum HTTPFixtureFailure: Equatable {
    case unauthorized
    case status(Int)
    case empty
    case invalidResponse
    case malformed(String)
    case connection(ControllerConnectionFailureReason)
}

private func httpFixtureResponse(
    _ request: URLRequest,
    status: Int = 200,
    data: Data = Data()
) throws -> (Data, URLResponse) {
    let url = try XCTUnwrap(request.url)
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
    return (data, response)
}

import XCTest
@testable import MicaCore

final class ControllerProbeResolverTests: XCTestCase {
    func testHTTPConnectionRefusedSkipsSingBoxWaitForReadyProbe() async throws {
        let recorder = ProbeInvocationRecorder()
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw MihomoClientError.connectionFailure(.connectionRefused)
            },
            singBoxProbe: { _, _ in
                await recorder.record()
                return SingBoxVersion(version: "late", apiVersion: 1)
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: nil)
            XCTFail("Expected HTTP connection failure")
        } catch MihomoClientError.connectionFailure(let reason) {
            XCTAssertEqual(reason, .connectionRefused)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testHTTPTimeoutSkipsSingBoxWaitForReadyProbe() async throws {
        let recorder = ProbeInvocationRecorder()
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw MihomoClientError.connectionFailure(.timedOut)
            },
            singBoxProbe: { _, _ in
                await recorder.record()
                return SingBoxVersion(version: "late", apiVersion: 1)
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: nil)
            XCTFail("Expected HTTP timeout")
        } catch MihomoClientError.connectionFailure(let reason) {
            XCTAssertEqual(reason, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testDetectsSingBoxWhenHTTPFamiliesDoNotMatch() async throws {
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw ControllerHTTPProbeError.unrecognizedController
            },
            singBoxProbe: { _, _ in
                SingBoxVersion(version: "1.14.0-alpha.31", apiVersion: 7)
            }
        )

        let kind = try await resolver.resolve(profile: profile(), credential: "secret")
        XCTAssertEqual(kind, .singBoxCompatible)
    }

    func testHTTPControllerIdentitySkipsSingBoxProbe() async throws {
        let recorder = ProbeInvocationRecorder()
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in .mihomoCompatible },
            singBoxProbe: { _, _ in
                await recorder.record()
                return SingBoxVersion(version: "unexpected", apiVersion: 1)
            }
        )

        let kind = try await resolver.resolve(profile: profile(), credential: nil)
        let callCount = await recorder.callCount()
        XCTAssertEqual(kind, .mihomoCompatible)
        XCTAssertEqual(callCount, 0)
    }

    func testSingBoxAuthenticationFailureIsPreserved() async throws {
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw ControllerHTTPProbeError.unrecognizedController
            },
            singBoxProbe: { _, _ in
                throw SingBoxGRPCError.rpc(code: 16, message: "unauthenticated")
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: "wrong-secret")
            XCTFail("Expected sing-box authentication failure")
        } catch let error as SingBoxGRPCError {
            XCTAssertEqual(error, .rpc(code: 16, message: "unauthenticated"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPConnectionFailureIsNotHiddenByGRPCMismatch() async throws {
        let recorder = ProbeInvocationRecorder()
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw MihomoClientError.connectionFailure(.other)
            },
            singBoxProbe: { _, _ in
                await recorder.record()
                throw SingBoxGRPCError.transport("protocol mismatch")
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: nil)
            XCTFail("Expected HTTP connection failure")
        } catch MihomoClientError.connectionFailure(let reason) {
            XCTAssertEqual(reason, .other)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testHTTPCancellationDoesNotStartSingBoxProbe() async throws {
        let recorder = ProbeInvocationRecorder()
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw CancellationError()
            },
            singBoxProbe: { _, _ in
                await recorder.record()
                return SingBoxVersion(version: "unexpected", apiVersion: 1)
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: nil)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation must terminate protocol probing.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 0)
    }

    private func profile() -> RouterProfile {
        RouterProfile(
            displayName: "Auto",
            host: "controller.example",
            port: 9090,
            controllerKind: .autoDetect
        )
    }
}

private actor ProbeInvocationRecorder {
    private var calls = 0

    func record() {
        calls += 1
    }

    func callCount() -> Int {
        calls
    }
}

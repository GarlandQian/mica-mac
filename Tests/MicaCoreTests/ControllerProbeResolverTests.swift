import XCTest
@testable import MicaCore

final class ControllerProbeResolverTests: XCTestCase {
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

    func testHTTPControllerIdentityWinsWhenBothProbesSucceed() async throws {
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in .mihomoCompatible },
            singBoxProbe: { _, _ in
                SingBoxVersion(version: "unexpected", apiVersion: 1)
            }
        )

        let kind = try await resolver.resolve(profile: profile(), credential: nil)
        XCTAssertEqual(kind, .mihomoCompatible)
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
        let resolver = ControllerProbeResolver(
            httpProbe: { _, _, _ in
                throw MihomoClientError.connectionFailure(.networkUnavailable)
            },
            singBoxProbe: { _, _ in
                throw SingBoxGRPCError.transport("protocol mismatch")
            }
        )

        do {
            _ = try await resolver.resolve(profile: profile(), credential: nil)
            XCTFail("Expected HTTP connection failure")
        } catch MihomoClientError.connectionFailure(let reason) {
            XCTAssertEqual(reason, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

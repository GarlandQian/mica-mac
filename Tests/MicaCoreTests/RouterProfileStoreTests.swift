import XCTest
@testable import MicaCore

final class RouterProfileStoreTests: XCTestCase {
    func testLoadedProfilesRemainCachedForTheStoreLifetime() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/codex/tests", isDirectory: true)
            .appendingPathComponent("mica-profile-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("routers.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = RouterProfile(
            displayName: "Cached",
            host: "controller.local"
        )
        try await JSONRouterProfileStore(fileURL: fileURL).saveProfiles([profile])

        let store = JSONRouterProfileStore(fileURL: fileURL)
        let initial = try await store.loadProfiles()
        XCTAssertEqual(initial, [profile])
        try FileManager.default.removeItem(at: fileURL)

        let cached = try await store.loadProfiles()
        XCTAssertEqual(cached, [profile])
    }

    func testInvalidPersistedEndpointIsRejectedDuringLoad() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/codex/tests", isDirectory: true)
            .appendingPathComponent("mica-profile-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("routers.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let id = UUID()
        let invalidJSON = Data(
            """
            [{
              "id": "\(id.uuidString)",
              "displayName": "Broken",
              "scheme": "http",
              "host": "bad host",
              "port": 9090,
              "tlsPolicy": "system"
            }]
            """.utf8
        )
        try invalidJSON.write(to: fileURL)

        do {
            _ = try await JSONRouterProfileStore(fileURL: fileURL).loadProfiles()
            XCTFail("Expected invalid persisted endpoint to fail decoding")
        } catch is DecodingError {
            // Persisted corruption must fail before any session can use it.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveRejectsInvalidEndpointBeforeWriting() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/codex/tests", isDirectory: true)
            .appendingPathComponent("mica-profile-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("routers.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = RouterProfile(
            displayName: "Broken",
            host: "controller.local",
            port: 70_000
        )

        do {
            try await JSONRouterProfileStore(fileURL: fileURL).saveProfiles([profile])
            XCTFail("Expected invalid endpoint to fail before persistence")
        } catch let error as RouterProfileEndpointError {
            XCTAssertEqual(error, .invalidPort(70_000))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

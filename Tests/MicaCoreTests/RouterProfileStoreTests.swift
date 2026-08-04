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
}

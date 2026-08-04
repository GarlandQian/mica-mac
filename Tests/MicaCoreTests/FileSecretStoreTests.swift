import XCTest
@testable import MicaCore

final class FileSecretStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/codex/tests", isDirectory: true)
            .appendingPathComponent("mica-secret-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("secrets.json")
    }

    override func tearDown() {
        if let directory = fileURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        fileURL = nil
        super.tearDown()
    }

    func testMissingFileReturnsNil() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let secret = try await store.secret(for: UUID())
        XCTAssertNil(secret)
    }

    func testSaveThenReadReturnsSameSecret() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let id = UUID()

        try await store.save("token-abc", for: id)

        let secret = try await store.secret(for: id)
        XCTAssertEqual(secret, "token-abc")
    }

    func testSaveOverwritesExistingSecret() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let id = UUID()

        try await store.save("first", for: id)
        try await store.save("second", for: id)

        let secret = try await store.secret(for: id)
        XCTAssertEqual(secret, "second")
    }

    func testDistinctProfilesKeepSeparateSecrets() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let first = UUID()
        let second = UUID()

        try await store.save("one", for: first)
        try await store.save("two", for: second)

        let firstSecret = try await store.secret(for: first)
        let secondSecret = try await store.secret(for: second)
        XCTAssertEqual(firstSecret, "one")
        XCTAssertEqual(secondSecret, "two")
    }

    func testRemoveSecretDeletesOnlyThatEntry() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let kept = UUID()
        let removed = UUID()
        try await store.save("keep", for: kept)
        try await store.save("drop", for: removed)

        try await store.removeSecret(for: removed)

        let removedSecret = try await store.secret(for: removed)
        let keptSecret = try await store.secret(for: kept)
        XCTAssertNil(removedSecret)
        XCTAssertEqual(keptSecret, "keep")
    }

    func testRemoveMissingSecretIsNoOp() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        try await store.removeSecret(for: UUID())
        let secret = try await store.secret(for: UUID())
        XCTAssertNil(secret)
    }

    func testSecretsPersistAcrossStoreInstances() async throws {
        let id = UUID()
        try await FileSecretStore(fileURL: fileURL).save("persisted", for: id)

        let reopened = FileSecretStore(fileURL: fileURL)
        let secret = try await reopened.secret(for: id)
        XCTAssertEqual(secret, "persisted")
    }

    func testLoadedSecretsRemainCachedForTheStoreLifetime() async throws {
        let id = UUID()
        try await FileSecretStore(fileURL: fileURL).save("persisted", for: id)

        let store = FileSecretStore(fileURL: fileURL)
        let initial = try await store.secret(for: id)
        XCTAssertEqual(initial, "persisted")
        try FileManager.default.removeItem(at: fileURL)

        let cached = try await store.secret(for: id)
        XCTAssertEqual(cached, "persisted")
    }

    func testFileIsPlaintextKeyedByProfileUUIDString() async throws {
        let store = FileSecretStore(fileURL: fileURL)
        let id = UUID()
        try await store.save("visible-token", for: id)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(id.uuidString))
        XCTAssertTrue(contents.contains("visible-token"))
    }
}

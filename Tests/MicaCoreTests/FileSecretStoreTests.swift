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

    func testNewStoreDirectoryAndFileHavePrivatePermissions() async throws {
        let store = FileSecretStore(fileURL: fileURL)

        try await store.save("private-token", for: UUID())

        XCTAssertEqual(try permissions(of: fileURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
    }

    func testCustomStoreLeavesExistingSharedParentPermissionsUnchanged() async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
        let store = FileSecretStore(fileURL: fileURL)

        try await store.save("private-token", for: UUID())

        XCTAssertEqual(try permissions(of: directoryURL), 0o755)
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
    }

    func testNestedNewDirectoryDoesNotChangeExistingAncestorPermissions() async throws {
        let ancestorURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: ancestorURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ancestorURL.path)
        let privateDirectory = ancestorURL.appendingPathComponent("private/nested", isDirectory: true)
        let nestedFile = privateDirectory.appendingPathComponent("secrets.json")
        let store = FileSecretStore(fileURL: nestedFile)

        try await store.save("private-token", for: UUID())

        XCTAssertEqual(try permissions(of: ancestorURL), 0o755)
        XCTAssertEqual(try permissions(of: privateDirectory.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(of: privateDirectory), 0o700)
        XCTAssertEqual(try permissions(of: nestedFile), 0o600)
    }

    func testOwnedExistingStoreDirectoryIsHardenedWithoutChangingItsParent() async throws {
        let parentURL = fileURL.deletingLastPathComponent()
        let ownedDirectory = parentURL.appendingPathComponent("Mica", isDirectory: true)
        let ownedFile = ownedDirectory.appendingPathComponent("secrets.json")
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        for directory in [parentURL, ownedDirectory] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        let store = FileSecretStore(fileURL: ownedFile, ownsDirectory: true)

        try await store.save("private-token", for: UUID())

        XCTAssertEqual(try permissions(of: parentURL), 0o755)
        XCTAssertEqual(try permissions(of: ownedDirectory), 0o700)
        XCTAssertEqual(try permissions(of: ownedFile), 0o600)
    }

    func testLoadingExistingWeakPermissionFilePreservesContentsAndHardensIt() async throws {
        let id = UUID()
        try writeWeakPermissionFile(Data("{\"\(id.uuidString)\":\"existing-token\"}".utf8))
        let store = FileSecretStore(fileURL: fileURL)

        let secret = try await store.secret(for: id)

        XCTAssertEqual(secret, "existing-token")
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
        XCTAssertEqual(try permissions(of: fileURL.deletingLastPathComponent()), 0o755)
    }

    func testEmptyExistingFileIsHardenedBeforeReturningNoSecret() async throws {
        try writeWeakPermissionFile(Data())
        let store = FileSecretStore(fileURL: fileURL)

        let secret = try await store.secret(for: UUID())

        XCTAssertNil(secret)
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
    }

    func testAtomicReplacementsAndRemovalKeepFilePrivate() async throws {
        let id = UUID()
        let store = FileSecretStore(fileURL: fileURL)
        for value in ["first", "second", "third"] {
            try await store.save(value, for: id)
            XCTAssertEqual(try permissions(of: fileURL), 0o600)
            let reopened = FileSecretStore(fileURL: fileURL)
            let persisted = try await reopened.secret(for: id)
            XCTAssertEqual(persisted, value)
            // A later write must also repair an existing weak-permission file.
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }
        try await store.removeSecret(for: id)

        XCTAssertEqual(try permissions(of: fileURL), 0o600)
        let remainingFiles = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(remainingFiles.map(\.lastPathComponent), ["secrets.json"])
    }

    func testCachedReadAlsoRepairsChangedFilePermissions() async throws {
        let id = UUID()
        let store = FileSecretStore(fileURL: fileURL)
        try await store.save("cached-token", for: id)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let secret = try await store.secret(for: id)

        XCTAssertEqual(secret, "cached-token")
        XCTAssertEqual(try permissions(of: fileURL), 0o600)
    }

    private func writeWeakPermissionFile(_ data: Data) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
        try data.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}

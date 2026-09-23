import Darwin
import Foundation

/// Stores controller secrets as a plaintext JSON map on disk, keyed by profile
/// ID. Chosen over `KeychainSecretStore` to avoid the Keychain authorization
/// prompt that reappears whenever the app is re-signed during development.
///
/// Secrets live in their own file (default `~/Library/Application
/// Support/Mica/secrets.json`), separate from `routers.json`. Keeping them out
/// of `RouterProfile` preserves the invariant that exported/diagnostic reports
/// never carry credentials: profiles only ever hold a `secretReference`.
public actor FileSecretStore: SecretStore {
    private let fileURL: URL
    private let ownsDirectory: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedSecrets: [String: String]?

    public init(fileURL: URL? = nil) {
        self.init(fileURL: fileURL ?? Self.defaultFileURL(), ownsDirectory: fileURL == nil)
    }

    // The default Mica directory belongs to this app. A caller-provided URL may
    // live in a shared directory whose existing permissions must stay untouched.
    init(fileURL: URL, ownsDirectory: Bool) {
        self.fileURL = fileURL
        self.ownsDirectory = ownsDirectory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    public func secret(for profileID: UUID) async throws -> String? {
        try load()[profileID.uuidString]
    }

    public func save(_ secret: String, for profileID: UUID) async throws {
        var secrets = try load()
        secrets[profileID.uuidString] = secret
        try persist(secrets)
    }

    public func removeSecret(for profileID: UUID) async throws {
        var secrets = try load()
        guard secrets.removeValue(forKey: profileID.uuidString) != nil else {
            return
        }
        try persist(secrets)
    }

    private func load() throws -> [String: String] {
        try protectExistingStore()
        if let cachedSecrets {
            return cachedSecrets
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedSecrets = [:]
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            cachedSecrets = [:]
            return [:]
        }

        let secrets = try decoder.decode([String: String].self, from: data)
        cachedSecrets = secrets
        return secrets
    }

    private func persist(_ secrets: [String: String]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try createPrivateDirectoriesIfNeeded(at: directoryURL)
        try protectExistingStore()
        let data = try encoder.encode(secrets)
        let temporaryURL = directoryURL.appendingPathComponent(".mica-secrets-\(UUID().uuidString).tmp")
        // Create the staging file with 0600 from its first instant, including
        // when a custom destination has a world-searchable parent directory.
        let descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Self.posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        // A restrictive process umask may also strip owner access at creation.
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw Self.posixError()
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporaryURL.path, fileURL.path) == 0 else {
            throw Self.posixError()
        }
        cachedSecrets = secrets
    }

    private func protectExistingStore() throws {
        let manager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if ownsDirectory, manager.fileExists(atPath: directoryURL.path) {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }
        if manager.fileExists(atPath: fileURL.path) {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    private func createPrivateDirectoriesIfNeeded(at directoryURL: URL) throws {
        let manager = FileManager.default
        var missingDirectories: [URL] = []
        var ancestorURL = directoryURL
        while !manager.fileExists(atPath: ancestorURL.path) {
            missingDirectories.append(ancestorURL)
            let parentURL = ancestorURL.deletingLastPathComponent()
            guard parentURL.path != ancestorURL.path else {
                throw CocoaError(.fileNoSuchFile)
            }
            ancestorURL = parentURL
        }
        for missingURL in missingDirectories.reversed() {
            try manager.createDirectory(
                at: missingURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("Mica", isDirectory: true)
            .appendingPathComponent("secrets.json")
    }
}

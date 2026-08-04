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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedSecrets: [String: String]?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()

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
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(secrets)
        try data.write(to: fileURL, options: [.atomic])
        cachedSecrets = secrets
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

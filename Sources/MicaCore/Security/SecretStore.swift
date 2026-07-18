import Foundation

public protocol SecretStore: Sendable {
    func secret(for profileID: UUID) async throws -> String?
    func save(_ secret: String, for profileID: UUID) async throws
    func removeSecret(for profileID: UUID) async throws
}

public actor InMemorySecretStore: SecretStore {
    private var secrets: [UUID: String] = [:]

    public init() {}

    public func secret(for profileID: UUID) async throws -> String? {
        secrets[profileID]
    }

    public func save(_ secret: String, for profileID: UUID) async throws {
        secrets[profileID] = secret
    }

    public func removeSecret(for profileID: UUID) async throws {
        secrets.removeValue(forKey: profileID)
    }
}

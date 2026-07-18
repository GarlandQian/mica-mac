import Foundation
import Security

public actor KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "dev.mica.router-controller") {
        self.service = service
    }

    public func secret(for profileID: UUID) async throws -> String? {
        var query = baseQuery(for: profileID)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainSecretStoreError.invalidData
            }

            guard let secret = String(data: data, encoding: .utf8) else {
                throw KeychainSecretStoreError.invalidData
            }

            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
    }

    public func save(_ secret: String, for profileID: UUID) async throws {
        let data = Data(secret.utf8)
        var query = baseQuery(for: profileID)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw KeychainSecretStoreError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainSecretStoreError.unhandledStatus(updateStatus)
        }
    }

    public func removeSecret(for profileID: UUID) async throws {
        let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
    }
}

public enum KeychainSecretStoreError: Error, LocalizedError, Equatable {
    case invalidData
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            "The saved controller secret could not be decoded."
        case .unhandledStatus(let status):
            "Keychain returned status \(status)."
        }
    }
}

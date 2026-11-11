import Foundation
import CryptoKit
import Security

protocol PangguaiPersisting {
    func credentials() throws -> PGCredentials?
    func saveCredentials(_ value: PGCredentials) throws
    func snapshot(accountID: String) throws -> PGSnapshot?
    func saveSnapshot(_ snapshot: PGSnapshot, accountID: String) throws
    func logout() throws
}

/// Tokens are device-only Keychain items. Cached records have hashed account names and AES-GCM protection.
final class PangguaiStorage: PangguaiPersisting {
    private let storage: ProtectedStorage
    private let service = "org.handancampus.ios.native.pangguai.session"
    init() throws { storage = try ProtectedStorage() }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current", kSecAttrSynchronizable as String: false] }
    static func scope(_ accountID: String) -> String { "pangguai-" + SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined() }
    func credentials() throws -> PGCredentials? {
        var q = query; q[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data, bytes.count <= 16384 else { throw PGFailure.storage }
        let result = try JSONDecoder().decode(PGCredentials.self, from: bytes)
        guard !result.id.isEmpty, result.id.count <= 256, !result.token.isEmpty, result.token.count <= 4096,
              (try? PangguaiProtocol.phone(result.phone)) == result.phone else { throw PGFailure.storage }
        return result
    }
    func saveCredentials(_ value: PGCredentials) throws {
        let bytes = try JSONEncoder().encode(value)
        let changes: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(changes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) }
        guard status == errSecSuccess else { throw PGFailure.storage }
    }
    func snapshot(accountID: String) throws -> PGSnapshot? { try storage.read(Self.scope(accountID), as: PGSnapshot.self) }
    func saveSnapshot(_ snapshot: PGSnapshot, accountID: String) throws { try storage.write(snapshot, name: Self.scope(accountID)) }
    /// Preserve encrypted transaction intents for this account so relogin cannot accidentally replay them.
    /// Other accounts never see these records. No credentials or account list remain after disconnect.
    func logout() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PGFailure.storage }
    }
}

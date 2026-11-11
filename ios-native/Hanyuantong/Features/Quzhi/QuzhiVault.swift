import Foundation
import Security

@MainActor
protocol QuzhiPersistence {
    func restore() throws -> QuzhiState?
    func save(_ state: QuzhiState) throws
    func clear() throws
}

/// Credentials are stored only in device-only Keychain. Encrypted, versioned cache files contain no credentials.
/// A Keychain pointer is the commit point so failed account switches cannot pair a new session with old data.
@MainActor
final class QuzhiVault: QuzhiPersistence {
    private struct Pointer: Codable {
        let session: QuzhiSession
        let expired: Bool
        let cacheID: String
        var valid: Bool {
            QuzhiProtocol.matches(cacheID, "^quzhi-[a-f0-9]{64}-[A-Fa-f0-9-]{36}\\z") &&
                cacheID.hasPrefix("quzhi-" + session.scope + "-") &&
                (try? QuzhiProtocol.phone(session.telephone)) == session.telephone &&
                !session.loginCode.isEmpty && !session.userID.isEmpty && !session.projectID.isEmpty
        }
    }
    private struct Cache: Codable { let scope: String; let snapshot: QuzhiSnapshot }
    private let service: String
    private let directory: URL?
    private var storage: ProtectedStorage?
    init(service: String = "org.handancampus.ios.native.quzhi", directory: URL? = nil) {
        self.service = service; self.directory = directory
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session-v1", kSecAttrSynchronizable as String: false]
    }
    private func cache() throws -> ProtectedStorage {
        if let storage { return storage }
        let value = try ProtectedStorage(directory: directory); storage = value; return value
    }
    private func pointer() throws -> Pointer? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data, bytes.count <= 16_384,
              let pointer = try? JSONDecoder().decode(Pointer.self, from: bytes), pointer.valid else { throw QuzhiFailure.storage }
        return pointer
    }
    func restore() throws -> QuzhiState? {
        do {
            guard let pointer = try pointer() else { return nil }
            guard let cached = try cache().read(pointer.cacheID, as: Cache.self), cached.scope == pointer.session.scope,
                  cached.snapshot.bills.count <= 200 else { throw QuzhiFailure.storage }
            return QuzhiState(session: pointer.session, snapshot: cached.snapshot, expired: pointer.expired)
        } catch { throw QuzhiFailure.storage }
    }
    func save(_ state: QuzhiState) throws {
        let id = "quzhi-" + state.session.scope + "-" + UUID().uuidString
        do {
            let previous = try pointer()
            let next = Pointer(session: state.session, expired: state.expired, cacheID: id)
            guard next.valid, state.snapshot.bills.count <= 200 else { throw QuzhiFailure.storage }
            let cache = try cache()
            try cache.write(Cache(scope: state.session.scope, snapshot: state.snapshot), name: id)
            let bytes = try JSONEncoder().encode(next)
            let attributes: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var insert = query; insert.merge(attributes) { _, new in new }
                status = SecItemAdd(insert as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw QuzhiFailure.storage }
            if let previous { try? cache.remove(previous.cacheID) }
        } catch {
            try? storage?.remove(id)
            throw QuzhiFailure.storage
        }
    }
    func clear() throws {
        // Do not require decodable cache data to remove a damaged session.
        let old = try? pointer()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QuzhiFailure.storage }
        if let old { try cache().remove(old.cacheID) }
    }
}

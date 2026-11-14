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
            QuzhiVault.validCacheID(cacheID) &&
                cacheID.hasPrefix("quzhi-" + session.scope + "-") &&
                (try? QuzhiProtocol.phone(session.telephone)) == session.telephone &&
                !session.loginCode.isEmpty && !session.userID.isEmpty && !session.projectID.isEmpty
        }
    }
    private struct Cache: Codable { let scope: String; let snapshot: QuzhiSnapshot }
    private let service: String
    private let directory: URL?
    private var storage: ProtectedStorage?
    private let removeFile: (URL) throws -> Void
    init(service: String = "org.handancampus.ios.native.quzhi", directory: URL? = nil,
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.service = service; self.directory = directory; self.removeFile = removeFile
    }
    private nonisolated static func validCacheID(_ value: String) -> Bool {
        QuzhiProtocol.matches(value, "^quzhi-[a-f0-9]{64}-[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\\z")
    }
    private func cacheDirectory() throws -> URL {
        try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
            .appendingPathComponent("Hanyuantong", isDirectory: true)
    }
    /// Filenames are durable cleanup identifiers, independent of the Keychain pointer. This also
    /// finds old-version and interrupted-write caches after restart. Never recurse or delete files
    /// outside the exact Quzhi cache namespace; reject a matching directory/symlink rather than follow it.
    private func cleanup(excluding retainedID: String? = nil) throws {
        let root = try cacheDirectory()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return
        }
        for file in files {
            guard file.pathExtension == "sealed" else { continue }
            let id = file.deletingPathExtension().lastPathComponent
            guard Self.validCacheID(id), id != retainedID else { continue }
            try removeCache(id)
        }
    }
    private func removeCache(_ id: String) throws {
        guard Self.validCacheID(id) else { throw QuzhiFailure.storage }
        let file = try cacheDirectory().appendingPathComponent(id + ".sealed")
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw QuzhiFailure.storage }
            try removeFile(file)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) {
            return
        }
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session-v1", kSecAttrSynchronizable as String: false]
    }
    private func cache() throws -> ProtectedStorage {
        if let storage { return storage }
        let value = try ProtectedStorage(directory: cacheDirectory()); storage = value; return value
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
            guard let pointer = try pointer() else {
                // A failed prior logout may already have removed the Keychain entry.
                try cleanup()
                return nil
            }
            try cleanup(excluding: pointer.cacheID)
            guard let cached = try cache().read(pointer.cacheID, as: Cache.self), cached.scope == pointer.session.scope,
                  cached.snapshot.bills.count <= 200 else { throw QuzhiFailure.storage }
            return QuzhiState(session: pointer.session, snapshot: cached.snapshot, expired: pointer.expired)
        } catch { throw QuzhiFailure.storage }
    }
    func save(_ state: QuzhiState) throws {
        let id = "quzhi-" + state.session.scope + "-" + UUID().uuidString
        var committed = false
        do {
            let previous = try pointer()
            try cleanup(excluding: previous?.cacheID)
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
            committed = true
            // The new pointer is committed. Cleanup cannot roll it back or remove its cache. If an
            // OS deletion fails, the validated filename remains the durable retry record. Every
            // subsequent restore/save/clear retries the sweep, including after process restart.
            try? cleanup(excluding: id)
        } catch {
            if !committed { try? removeCache(id) }
            throw QuzhiFailure.storage
        }
    }
    func clear() throws {
        // Revoke credentials first, even if cached files cannot currently be removed. Enumeration
        // is independent of this pointer, so a failed deletion remains retryable after restart.
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QuzhiFailure.storage }
        do { try cleanup() }
        catch { throw QuzhiFailure.storage }
    }
}

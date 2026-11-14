import Foundation
import Security

@MainActor protocol AnalyticsPersisting {
    func load() throws -> AnalyticsRecord?
    func save(_ record: AnalyticsRecord) throws
}

/// The entire small record lives encrypted in Keychain, never in defaults, a backup or a shared App Group.
/// Reading a missing record does not create a key, installation identity or any analytics storage.
@MainActor final class AnalyticsKeychainStorage: AnalyticsPersisting {
    private let service: String
    private let installationMarker: URL?
    init(service: String = "org.handancampus.ios.native.analytics", installationMarker: URL? = nil) {
        self.service = service; self.installationMarker = installationMarker
    }
    private func markerURL() throws -> URL {
        if let installationMarker { return installationMarker }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Hanyuantong/Analytics/installation.marker")
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "anonymous-analytics-v1", kSecAttrSynchronizable as String: false]
    }
    func load() throws -> AnalyticsRecord? {
        // Keychain may survive uninstall. An app-container marker prevents restoring old consent after reinstall.
        // The marker contains only a format byte, is excluded from backups, and is created only on a user choice.
        let marker = try markerURL()
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        guard try Data(contentsOf: marker) == Data([1]) else { throw AnalyticsFailure.storage }
        var query = self.query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data, bytes.count <= 8192 else { throw AnalyticsFailure.storage }
        let record = try JSONDecoder().decode(AnalyticsRecord.self, from: bytes)
        guard record.isValid else { throw AnalyticsFailure.storage }
        return record
    }
    func save(_ record: AnalyticsRecord) throws {
        guard record.isValid else { throw AnalyticsFailure.invalid }
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 8192 else { throw AnalyticsFailure.invalid }
        let values: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status != errSecSuccess {
            guard status == errSecItemNotFound else { throw AnalyticsFailure.storage }
            guard SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw AnalyticsFailure.storage }
        }
        let marker = try markerURL()
        if !FileManager.default.fileExists(atPath: marker.path) {
            var directory = marker.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try ProtectedStorage.writeAtomically(Data([1]), to: marker)
        }
    }
    static func makeIdentity() throws -> AnalyticsIdentity {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AnalyticsFailure.storage }
        return AnalyticsIdentity(id: UUID().uuidString.lowercased(), token: bytes.map { String(format: "%02x", $0) }.joined())
    }
}

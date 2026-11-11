import Foundation
import CryptoKit
import Security
import Darwin

/// App-local records are encrypted with a device-only Keychain key, never synced to iCloud.
/// Academic and personal data have independent files and independent deletion lifecycles.
final class ProtectedStorage {
    enum Failure: Error { case keychain(OSStatus), unavailable }
    private let directory: URL
    private let service = "org.handancampus.ios.native.data"
    init(directory: URL? = nil) throws {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Hanyuantong", isDirectory: true)
        self.directory = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var url = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "cache-key", kSecAttrSynchronizable as String: false]
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        guard status == errSecItemNotFound, create else { throw Failure.keychain(status) }
        let key = SymmetricKey(size: .bits256)
        var add = query
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        return key
    }
    func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        let url = directory.appendingPathComponent(name + ".sealed")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(sealed, using: key(create: false))
        return try JSONDecoder().decode(type, from: data)
    }
    func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        guard let sealed = try AES.GCM.seal(data, using: key(create: true)).combined else { throw Failure.unavailable }
        let url = directory.appendingPathComponent(name + ".sealed")
        try Self.writeAtomically(sealed, to: url)
    }

    /// Prepare a new inode in the same directory; the rename is the sole commit point.
    /// All throwing work (including metadata) happens before the destination changes.
    /// The hook is an internal test seam to simulate failure at the last pre-commit step.
    static func writeAtomically(_ sealed: Data, to destination: URL,
                                beforeCommit: ((URL) throws -> Void)? = nil) throws {
        var staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".pending-" + UUID().uuidString + ".sealed")
        defer { try? FileManager.default.removeItem(at: staged) }
        try sealed.write(to: staged, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try staged.setResourceValues(values)
        try beforeCommit?(staged)
        // Apple rename(2): same-filesystem replacement; a failure leaves both files unchanged.
        // No Foundation metadata or other throwing operation may follow a successful rename.
        let status = staged.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target -> Int32 in
                guard let source, let target else { return EINVAL }
                if Darwin.rename(source, target) == 0 { return 0 }
                return errno
            }
        }
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(status))
        }
    }
    func remove(_ name: String) throws {
        let url = directory.appendingPathComponent(name + ".sealed")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

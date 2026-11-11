import Foundation
import CryptoKit
import Security

struct WidgetCourse: Codable, Identifiable {
    let id: String
    let title: String
    let room: String
    let day: Int
    let start: String
    let end: String
    let weeks: [Int]
}
struct WidgetSnapshot: Codable {
    let version: Int
    let generatedAt: Date
    let semesterStart: Date
    let courses: [WidgetCourse]
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }
    func today(_ date: Date) -> [WidgetCourse] {
        let calendar = Self.calendar
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: semesterStart), to: calendar.startOfDay(for: date)).day ?? 0
        let week = Int(floor(Double(offset) / 7)) + 1
        let day = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        return courses.filter { $0.day == day && $0.weeks.contains(week) }.sorted { $0.start < $1.start }
    }
}
enum WidgetSnapshotFile {
    static let group = "group.org.handancampus.ios.native"
    static let name = "widget-snapshot.sealed"
    enum Failure: Error { case unavailable, invalid, keychain(OSStatus) }
    private static func directory() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw Failure.unavailable }
        return url
    }
    private static func key(create: Bool) throws -> SymmetricKey {
        guard let access = Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String, !access.isEmpty, !access.contains("$(") else { throw Failure.unavailable }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.handancampus.ios.widget", kSecAttrAccount as String: "snapshot-key", kSecAttrAccessGroup as String: access, kSecAttrSynchronizable as String: false]
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard create, status == errSecItemNotFound else { throw Failure.keychain(status) }
        let value = SymmetricKey(size: .bits256)
        var add = query; add[kSecValueData as String] = value.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        return value
    }
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard snapshot.version == 1, snapshot.courses.count <= 3000 else { throw Failure.invalid }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 2 * 1024 * 1024, let sealed = try AES.GCM.seal(data, using: key(create: true)).combined else { throw Failure.invalid }
        var url = try directory().appendingPathComponent(name)
        try sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func read() throws -> WidgetSnapshot {
        let url = try directory().appendingPathComponent(name)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * 1024 * 1024 else { throw Failure.invalid }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let value = try JSONDecoder().decode(WidgetSnapshot.self, from: AES.GCM.open(box, using: key(create: false)))
        guard value.version == 1, value.courses.count <= 3000 else { throw Failure.invalid }
        return value
    }
    static func remove() throws {
        let url = try directory().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

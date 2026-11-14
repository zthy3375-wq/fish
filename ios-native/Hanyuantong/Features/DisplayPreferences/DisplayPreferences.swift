import Foundation

enum CampusDisplayTheme: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self { case .light: return "浅色"; case .dark: return "深色"; case .system: return "系统" }
    }
    var symbol: String {
        switch self { case .light: return "sun.max"; case .dark: return "moon"; case .system: return "iphone" }
    }
}

/// Only local presentation data. Notification permission and analytics consent have independent stores.
struct DisplayPreferences: Codable, Equatable {
    static let currentVersion = 1
    static let defaults = DisplayPreferences()
    var version = currentVersion
    var name = "同学"
    var major = ""
    var theme: CampusDisplayTheme = .light
    var compact = false

    func validated() throws -> Self {
        guard version == Self.currentVersion else { throw DisplayPreferencesFailure.unsupportedVersion }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf16.count <= 20, major.utf16.count <= 50,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !major.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw DisplayPreferencesFailure.invalidProfile
        }
        return self
    }

    func editingProfile(name: String, major: String) throws -> Self {
        var changed = self
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.name = name.isEmpty ? Self.defaults.name : name
        changed.major = major.trimmingCharacters(in: .whitespacesAndNewlines)
        return try changed.validated()
    }
}

enum DisplayPreferencesFailure: LocalizedError, Equatable {
    case unsupportedVersion, invalidProfile, unavailable, saveFailed, confirmationRequired
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "本机设置版本暂不兼容，原设置已保留。"
        case .invalidProfile: return "请填写不超过20字的昵称和不超过50字的专业 / 年级，不要使用换行或控制字符；表情可能占多个字。"
        case .unavailable: return "本机设置暂时无法读取。原设置已保留，请解锁设备后重试；读取成功前不会覆盖或重置。"
        case .saveFailed: return "设置未能安全保存，仍保留上次成功保存的设置，请稍后重试。"
        case .confirmationRequired: return "请先确认是否恢复默认昵称、专业 / 年级、主题与紧凑布局。"
        }
    }
}

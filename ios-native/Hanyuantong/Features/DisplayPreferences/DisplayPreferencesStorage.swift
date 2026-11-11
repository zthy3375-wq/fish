import Foundation

@MainActor protocol DisplayPreferencesPersisting {
    func load() throws -> DisplayPreferences?
    func save(_ preferences: DisplayPreferences) throws
}

/// This independent encrypted record never enters personal backups, widgets, analytics or school requests.
@MainActor final class ProtectedDisplayPreferencesStorage: DisplayPreferencesPersisting {
    static let recordName = "display-preferences-v1"
    private let storage: ProtectedStorage
    init(storage: ProtectedStorage) { self.storage = storage }
    convenience init() throws { self.init(storage: try ProtectedStorage()) }

    func load() throws -> DisplayPreferences? {
        try storage.read(Self.recordName, as: DisplayPreferences.self)?.validated()
    }

    func save(_ preferences: DisplayPreferences) throws {
        try storage.write(preferences.validated(), name: Self.recordName)
    }
}

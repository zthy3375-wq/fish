import Foundation
import Combine

@MainActor final class DisplayPreferencesStore: ObservableObject {
    @Published private(set) var preferences = DisplayPreferences.defaults
    @Published private(set) var canEdit = false
    @Published private(set) var error: String?
    private var storage: DisplayPreferencesPersisting?
    private let makeStorage: @MainActor () throws -> DisplayPreferencesPersisting

    init(makeStorage: (@MainActor () throws -> DisplayPreferencesPersisting)? = nil) {
        self.makeStorage = makeStorage ?? { try ProtectedDisplayPreferencesStorage() }
        reload()
    }

    convenience init(storage: DisplayPreferencesPersisting) { self.init(makeStorage: { storage }) }

    /// A failed load is not an absent record. Never use safe display defaults to overwrite unreadable data.
    func reload() {
        do {
            let candidateStorage = try storage ?? makeStorage()
            let candidate = try (candidateStorage.load() ?? .defaults).validated()
            storage = candidateStorage
            preferences = candidate
            canEdit = true
            error = nil
        } catch {
            canEdit = false
            self.error = (error as? DisplayPreferencesFailure)?.localizedDescription ?? DisplayPreferencesFailure.unavailable.localizedDescription
        }
    }

    func updateTheme(_ theme: CampusDisplayTheme) throws {
        var candidate = preferences; candidate.theme = theme
        try commit(candidate)
    }

    func updateCompact(_ compact: Bool) throws {
        var candidate = preferences; candidate.compact = compact
        try commit(candidate)
    }

    func updateProfile(name: String, major: String) throws {
        try commit(preferences.editingProfile(name: name, major: major))
    }

    /// Writes a complete default record atomically, instead of deleting an unreadable or partially replaced file.
    func reset(confirmed: Bool) throws {
        guard confirmed else { throw DisplayPreferencesFailure.confirmationRequired }
        try commit(.defaults)
    }

    private func commit(_ candidate: DisplayPreferences) throws {
        guard canEdit, let storage else { throw DisplayPreferencesFailure.unavailable }
        let candidate = try candidate.validated()
        guard candidate != preferences else { error = nil; return }
        do { try storage.save(candidate) }
        catch {
            self.error = DisplayPreferencesFailure.saveFailed.localizedDescription
            throw DisplayPreferencesFailure.saveFailed
        }
        // Publication follows the encrypted storage commit. A failed save never changes the live display.
        preferences = candidate
        error = nil
    }
}

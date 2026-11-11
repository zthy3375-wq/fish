import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Hanyuantong

final class DisplayPreferencesTests: XCTestCase {
    @MainActor private final class MemoryStorage: DisplayPreferencesPersisting {
        var saved: DisplayPreferences?
        var loadFailure: Error?
        var saveFailure: Error?
        var writes = 0
        var beforeSave: ((DisplayPreferences) -> Void)?
        init(_ saved: DisplayPreferences? = nil) { self.saved = saved }
        func load() throws -> DisplayPreferences? {
            if let loadFailure { throw loadFailure }
            return saved
        }
        func save(_ preferences: DisplayPreferences) throws {
            beforeSave?(preferences)
            if let saveFailure { throw saveFailure }
            writes += 1; saved = preferences
        }
    }

    func testDefaultsMatchCurrentAndroidLightDisplayAndLocalProfile() throws {
        let defaults = try DisplayPreferences.defaults.validated()
        XCTAssertEqual(defaults.version, 1)
        XCTAssertEqual(defaults.name, "同学"); XCTAssertEqual(defaults.major, "")
        XCTAssertEqual(defaults.theme, .light); XCTAssertFalse(defaults.compact)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "name", "major", "theme", "compact"])
        XCTAssertNil(json["notifications"]); XCTAssertNil(json["analytics"])
    }

    func testProfileTrimsWhitespaceAndEmptyNicknameUsesExistingDefault() throws {
        let changed = try DisplayPreferences.defaults.editingProfile(name: "  合成同学  ", major: "  示例专业 / 大一\n")
        XCTAssertEqual(changed.name, "合成同学"); XCTAssertEqual(changed.major, "示例专业 / 大一")
        XCTAssertEqual(try changed.editingProfile(name: " \n ", major: "").name, "同学")
    }

    func testProfileLengthIsBoundedWithoutSplittingEmojiOrSilentlyTruncating() throws {
        XCTAssertEqual(try DisplayPreferences.defaults.editingProfile(name: String(repeating: "测", count: 20), major: String(repeating: "试", count: 50)).name.count, 20)
        XCTAssertThrowsError(try DisplayPreferences.defaults.editingProfile(name: String(repeating: "测", count: 21), major: ""))
        XCTAssertThrowsError(try DisplayPreferences.defaults.editingProfile(name: "合成", major: String(repeating: "试", count: 51)))
        XCTAssertNoThrow(try DisplayPreferences.defaults.editingProfile(name: String(repeating: "🐟", count: 10), major: ""))
        XCTAssertThrowsError(try DisplayPreferences.defaults.editingProfile(name: String(repeating: "🐟", count: 11), major: ""))
        XCTAssertThrowsError(try DisplayPreferences.defaults.editingProfile(name: "合成\n同学", major: ""))
        XCTAssertThrowsError(try DisplayPreferences.defaults.editingProfile(name: "合成", major: "示例\0专业"))
    }

    func testUnsupportedVersionAndUnknownThemeDoNotSilentlyDefault() throws {
        var future = DisplayPreferences.defaults; future.version = 2
        XCTAssertThrowsError(try future.validated())
        let invalidTheme = Data(#"{"version":1,"name":"同学","major":"","theme":"future","compact":false}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DisplayPreferences.self, from: invalidTheme))
        let invalidBoolean = Data(#"{"version":1,"name":"同学","major":"","theme":"light","compact":"true"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DisplayPreferences.self, from: invalidBoolean))
        XCTAssertThrowsError(try JSONDecoder().decode(DisplayPreferences.self, from: Data("{}".utf8)))
    }

    @MainActor func testMissingRecordUsesDefaultsWithoutWritingOrMakingOtherChoices() {
        let storage = MemoryStorage()
        let store = DisplayPreferencesStore(storage: storage)
        XCTAssertTrue(store.canEdit); XCTAssertEqual(store.preferences, .defaults)
        XCTAssertNil(storage.saved); XCTAssertEqual(storage.writes, 0)
    }

    @MainActor func testAllEditsPersistAcrossNewStoreInstance() throws {
        let storage = MemoryStorage()
        let first = DisplayPreferencesStore(storage: storage)
        try first.updateProfile(name: "合成昵称", major: "示例专业 / 二年级")
        try first.updateTheme(.dark); try first.updateCompact(true)
        let second = DisplayPreferencesStore(storage: storage)
        XCTAssertEqual(second.preferences, first.preferences)
        XCTAssertEqual(second.preferences.theme, .dark); XCTAssertTrue(second.preferences.compact)
        try second.updateTheme(.system)
        XCTAssertEqual(DisplayPreferencesStore(storage: storage).preferences.theme, .system)
    }

    @MainActor func testWritesFinishBeforeNewPreferencesArePublished() throws {
        let storage = MemoryStorage()
        let store = DisplayPreferencesStore(storage: storage)
        var checkedCommit = false
        storage.beforeSave = { candidate in
            XCTAssertEqual(store.preferences.theme, .light)
            XCTAssertEqual(candidate.theme, .dark)
            checkedCommit = true
        }
        var values = [DisplayPreferences]()
        let subscription = store.$preferences.dropFirst().sink { candidate in
            XCTAssertEqual(storage.saved, candidate)
            values.append(candidate)
        }
        try store.updateTheme(.dark)
        XCTAssertTrue(checkedCommit); XCTAssertEqual(values.count, 1)
        withExtendedLifetime(subscription) { }
    }

    @MainActor func testEveryFailedSaveRetainsPublishedPreferencesAndDiskRecord() throws {
        let old = try DisplayPreferences.defaults.editingProfile(name: "保留昵称", major: "保留专业")
        let storage = MemoryStorage(old)
        let store = DisplayPreferencesStore(storage: storage)
        storage.saveFailure = DisplayPreferencesFailure.saveFailed
        var publications = 0
        let subscription = store.$preferences.dropFirst().sink { _ in publications += 1 }
        XCTAssertThrowsError(try store.updateTheme(.dark))
        XCTAssertThrowsError(try store.updateCompact(true))
        XCTAssertThrowsError(try store.updateProfile(name: "未保存昵称", major: ""))
        XCTAssertThrowsError(try store.reset(confirmed: true))
        XCTAssertEqual(store.preferences, old); XCTAssertEqual(storage.saved, old)
        XCTAssertEqual(storage.writes, 0); XCTAssertEqual(publications, 0)
        XCTAssertNotNil(store.error)
        storage.saveFailure = nil
        try store.updateTheme(.dark)
        XCTAssertEqual(store.preferences.theme, .dark); XCTAssertNil(store.error)
        withExtendedLifetime(subscription) { }
    }

    @MainActor func testUnreadableRecordBlocksAllMutationIncludingResetUntilReload() throws {
        var original = DisplayPreferences.defaults; original.theme = .dark
        let storage = MemoryStorage(original); storage.loadFailure = DisplayPreferencesFailure.unavailable
        let store = DisplayPreferencesStore(storage: storage)
        XCTAssertFalse(store.canEdit); XCTAssertEqual(store.preferences, .defaults)
        XCTAssertThrowsError(try store.updateTheme(.system))
        XCTAssertThrowsError(try store.updateCompact(true))
        XCTAssertThrowsError(try store.updateProfile(name: "不能覆盖", major: ""))
        XCTAssertThrowsError(try store.reset(confirmed: true))
        XCTAssertEqual(storage.saved, original); XCTAssertEqual(storage.writes, 0)
        storage.loadFailure = nil; store.reload()
        XCTAssertTrue(store.canEdit); XCTAssertEqual(store.preferences, original); XCTAssertNil(store.error)
        try store.updateCompact(true)
        XCTAssertEqual(storage.saved?.theme, .dark); XCTAssertEqual(storage.saved?.compact, true)
    }

    @MainActor func testFailedReloadRetainsLastSuccessfulDisplayAndCanRecover() throws {
        var original = DisplayPreferences.defaults; original.theme = .dark; original.compact = true
        let storage = MemoryStorage(original)
        let store = DisplayPreferencesStore(storage: storage)
        storage.loadFailure = DisplayPreferencesFailure.unavailable; store.reload()
        XCTAssertEqual(store.preferences, original); XCTAssertFalse(store.canEdit)
        XCTAssertThrowsError(try store.reset(confirmed: true))
        storage.loadFailure = nil; store.reload()
        XCTAssertEqual(store.preferences, original); XCTAssertTrue(store.canEdit)
    }

    @MainActor func testStorageConstructionFailureDoesNotBlockLaterRetry() {
        let storage = MemoryStorage()
        var unavailable = true
        let store = DisplayPreferencesStore(makeStorage: {
            if unavailable { throw DisplayPreferencesFailure.unavailable }
            return storage
        })
        XCTAssertFalse(store.canEdit); XCTAssertEqual(storage.writes, 0)
        unavailable = false; store.reload()
        XCTAssertTrue(store.canEdit); XCTAssertEqual(store.preferences, .defaults)
    }

    @MainActor func testUnsupportedSavedVersionBlocksResetAndRetainsRecord() {
        var original = DisplayPreferences.defaults; original.version = 9
        let storage = MemoryStorage(original)
        let store = DisplayPreferencesStore(storage: storage)
        XCTAssertFalse(store.canEdit)
        XCTAssertThrowsError(try store.reset(confirmed: true))
        XCTAssertEqual(storage.saved, original); XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(store.error, DisplayPreferencesFailure.unsupportedVersion.localizedDescription)
    }

    @MainActor func testResetNeedsConfirmationAndOnlyRestoresDisplayFields() throws {
        var original = try DisplayPreferences.defaults.editingProfile(name: "合成昵称", major: "示例专业")
        original.theme = .system; original.compact = true
        let storage = MemoryStorage(original)
        let store = DisplayPreferencesStore(storage: storage)
        XCTAssertThrowsError(try store.reset(confirmed: false))
        XCTAssertEqual(store.preferences, original); XCTAssertEqual(storage.writes, 0)
        try store.reset(confirmed: true)
        XCTAssertEqual(store.preferences, .defaults); XCTAssertEqual(storage.saved, .defaults)
        try store.reset(confirmed: true)
        XCTAssertEqual(storage.writes, 1)
    }

    @MainActor func testInvalidProfileDoesNotSaveOrChangeOtherFields() throws {
        var original = DisplayPreferences.defaults; original.theme = .system; original.compact = true
        let storage = MemoryStorage(original)
        let store = DisplayPreferencesStore(storage: storage)
        XCTAssertThrowsError(try store.updateProfile(name: String(repeating: "鱼", count: 21), major: ""))
        XCTAssertEqual(store.preferences, original); XCTAssertEqual(storage.writes, 0)
        try store.updateProfile(name: "测试昵称", major: "")
        XCTAssertEqual(store.preferences.theme, .system); XCTAssertTrue(store.preferences.compact)
    }

    @MainActor func testEncryptedPersistenceAndResetLeaveOtherRecordsUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let protected = try ProtectedStorage(directory: directory)
        try protected.write(["synthetic": "personal"], name: "personal")
        try protected.write(["synthetic": "academic"], name: "academic")
        let personalFile = directory.appendingPathComponent("personal.sealed")
        let academicFile = directory.appendingPathComponent("academic.sealed")
        let personal = try Data(contentsOf: personalFile); let academic = try Data(contentsOf: academicFile)
        let first = DisplayPreferencesStore(storage: ProtectedDisplayPreferencesStorage(storage: protected))
        try first.updateProfile(name: "synthetic-local", major: "synthetic-major")
        try first.updateTheme(.dark); try first.updateCompact(true)
        let file = directory.appendingPathComponent(ProtectedDisplayPreferencesStorage.recordName + ".sealed")
        let sealed = try Data(contentsOf: file)
        XCTAssertNil(sealed.range(of: Data("synthetic-local".utf8)))
        XCTAssertNil(sealed.range(of: Data("synthetic-major".utf8)))
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        let reopened = DisplayPreferencesStore(storage: ProtectedDisplayPreferencesStorage(storage: try ProtectedStorage(directory: directory)))
        XCTAssertEqual(reopened.preferences, first.preferences)
        try reopened.reset(confirmed: true)
        XCTAssertEqual(try protected.read(ProtectedDisplayPreferencesStorage.recordName, as: DisplayPreferences.self), .defaults)
        XCTAssertEqual(try Data(contentsOf: personalFile), personal)
        XCTAssertEqual(try Data(contentsOf: academicFile), academic)
    }

    @MainActor func testCorruptCiphertextIsPreservedAndCannotBeReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let protected = try ProtectedStorage(directory: directory)
        let file = directory.appendingPathComponent(ProtectedDisplayPreferencesStorage.recordName + ".sealed")
        let original = Data("synthetic-invalid-ciphertext".utf8)
        try original.write(to: file)
        let store = DisplayPreferencesStore(storage: ProtectedDisplayPreferencesStorage(storage: protected))
        XCTAssertFalse(store.canEdit)
        XCTAssertThrowsError(try store.updateTheme(.dark))
        XCTAssertThrowsError(try store.reset(confirmed: true))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testThemeSelectionDistinguishesExplicitLightDarkAndSystem() {
        XCTAssertEqual(CampusDisplayTheme.light.colorScheme, .light)
        XCTAssertEqual(CampusDisplayTheme.dark.colorScheme, .dark)
        XCTAssertNil(CampusDisplayTheme.system.colorScheme)
        XCTAssertEqual(CampusDisplayTheme.allCases.map(\.rawValue), ["light", "dark", "system"])
    }

    func testDynamicColorsResolveNormalAndIncreasedContrastWithoutCachedAppearance() {
        let color = CampusTheme.dynamicUIColor(light: 0x283445, dark: 0xe1e7ef, highLight: 0x131f30, highDark: 0xffffff)
        assertColor(color, hex: 0x283445, style: .light)
        assertColor(color, hex: 0xe1e7ef, style: .dark)
        assertColor(color, hex: 0x131f30, style: .light, contrast: .high)
        assertColor(color, hex: 0xffffff, style: .dark, contrast: .high)
        assertColor(color, hex: 0x283445, style: .light)
    }

    func testCurrentLightAndDarkSemanticPaletteIsPreserved() {
        let values: [(Color, UInt32, UInt32)] = [
            (CampusTheme.background, 0xf7f8fb, 0x171c24), (CampusTheme.surface, 0xfdfdff, 0x1e2530),
            (CampusTheme.text, 0x283445, 0xe1e7ef), (CampusTheme.muted, 0x6d7889, 0xa6b1c2),
            (CampusTheme.primary, 0x4f6f94, 0xa4bbd9), (CampusTheme.tint, 0xeaf0f8, 0x303e53),
            (CampusTheme.border, 0xdce1e9, 0x3a4556)
        ]
        for (color, light, dark) in values {
            assertColor(UIColor(color), hex: light, style: .light)
            assertColor(UIColor(color), hex: dark, style: .dark)
        }
    }

    func testCompactChangesSpacingAndDoesNotCompressAccessibilitySizes() {
        XCTAssertEqual(EnvironmentValues().campusCompactLayout, false)
        XCTAssertEqual(CampusLayoutMetrics.cardPadding(compact: false, accessibilitySize: false), 16)
        XCTAssertEqual(CampusLayoutMetrics.cardPadding(compact: true, accessibilitySize: false), 12)
        XCTAssertEqual(CampusLayoutMetrics.cardPadding(compact: false, accessibilitySize: true), 16)
        XCTAssertEqual(CampusLayoutMetrics.cardPadding(compact: true, accessibilitySize: true), 16)
    }

    private func assertColor(_ color: UIColor, hex: UInt32, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast = .normal, file: StaticString = #filePath, line: UInt = #line) {
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
        let resolved = color.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(r, CGFloat((hex >> 16) & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(g, CGFloat((hex >> 8) & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(b, CGFloat(hex & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 0.001, file: file, line: line)
    }
}

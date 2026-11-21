import XCTest
@testable import Hanyuantong

final class ProtectedStorageTests: XCTestCase {
    private struct Record: Codable, Equatable { let title: String }
    func testEncryptedRecordSurvivesNewStoreInstance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try ProtectedStorage(directory: directory)
        let value = Record(title: "synthetic-persistence-check")
        try first.write(value, name: "personal")
        let sealed = try Data(contentsOf: directory.appendingPathComponent("personal.sealed"))
        XCTAssertNil(String(data: sealed, encoding: .utf8)?.range(of: value.title))
        let second = try ProtectedStorage(directory: directory)
        XCTAssertEqual(try second.read("personal", as: Record.self), value)
    }
    func testCorruptRecordIsRejectedWithoutReplacingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        let file = directory.appendingPathComponent("personal.sealed")
        let corrupt = Data("invalid sealed data".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try storage.read("personal", as: Record.self))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    func testReplacementSurvivesReopenWithProtectionAndBackupExclusion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        let file = directory.appendingPathComponent("personal.sealed")
        try storage.write(Record(title: "original"), name: "personal")
        let original = try Data(contentsOf: file)
        let replacement = Record(title: "replacement")
        try storage.write(replacement, name: "personal")
        XCTAssertNotEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try ProtectedStorage(directory: directory).read("personal", as: Record.self), replacement)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try assertFirstUnlockProtectionWhenObservable(at: file)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["personal.sealed"])
    }

    /// Simulator cannot validate the physical device's Data Protection classes/lock lifecycle.
    /// Keep this separately visible as skipped in simulator CI, never as a security pass.
    func testPhysicalDeviceProtectionBeforeAndAfterAtomicReplacement() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required: Simulator does not validate device Data Protection. Real-device verification remains pending.")
        #else
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        let file = directory.appendingPathComponent("personal.sealed")
        try storage.write(Record(title: "original"), name: "personal")
        try assertFirstUnlockProtectionWhenObservable(at: file)
        try storage.write(Record(title: "replacement"), name: "personal")
        try assertFirstUnlockProtectionWhenObservable(at: file)
        #endif
    }

    func testFailureBeforeCommitPreservesOriginalCiphertextAndReadableRecord() throws {
        enum InjectedFailure: Error { case metadataPreparation }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        let original = Record(title: "keep-original")
        try storage.write(original, name: "personal")
        let file = directory.appendingPathComponent("personal.sealed")
        let originalCiphertext = try Data(contentsOf: file)
        var visitedPreparedFile = false
        XCTAssertThrowsError(try ProtectedStorage.writeAtomically(Data("synthetic-staged-bytes".utf8), to: file) { staged in
            visitedPreparedFile = true
            XCTAssertNotEqual(staged, file)
            XCTAssertEqual(try Data(contentsOf: file), originalCiphertext)
            XCTAssertEqual(try staged.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            throw InjectedFailure.metadataPreparation
        }) { error in
            XCTAssertTrue(error is InjectedFailure)
        }
        XCTAssertTrue(visitedPreparedFile)
        XCTAssertEqual(try Data(contentsOf: file), originalCiphertext)
        XCTAssertEqual(try storage.read("personal", as: Record.self), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["personal.sealed"])
    }

    func testFailedFirstWriteDoesNotCreateDestinationOrLeaveStagedFile() throws {
        enum InjectedFailure: Error { case preparation }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try ProtectedStorage(directory: directory)
        let file = directory.appendingPathComponent("personal.sealed")
        XCTAssertThrowsError(try ProtectedStorage.writeAtomically(Data([1, 2, 3]), to: file) { _ in
            throw InjectedFailure.preparation
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testRenameFailureDoesNotRemoveDestinationAndCleansStagedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try ProtectedStorage(directory: directory)
        let target = directory.appendingPathComponent("personal.sealed", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let sentinel = target.appendingPathComponent("keep")
        try Data([42]).write(to: sentinel)
        XCTAssertThrowsError(try ProtectedStorage.writeAtomically(Data([1, 2, 3]), to: target)) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([42]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["personal.sealed"])
    }

    func testReplacingPersonalRecordDoesNotAlterAcademicFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        let school = Record(title: "synthetic-school-cache")
        try storage.write(school, name: "academic")
        let schoolFile = directory.appendingPathComponent("academic.sealed")
        let schoolCiphertext = try Data(contentsOf: schoolFile)
        try storage.write(Record(title: "first"), name: "personal")
        try storage.write(Record(title: "second"), name: "personal")
        XCTAssertEqual(try Data(contentsOf: schoolFile), schoolCiphertext)
        XCTAssertEqual(try storage.read("academic", as: Record.self), school)
    }

}

/// The FileManager protection attribute may be absent in Simulator even when protection
/// was requested. Apple DTS reproduced this: https://developer.apple.com/forums/thread/780632
/// Never tolerate a missing attribute on device or a wrong non-nil value on either target.
/// This helper deliberately does not skip its caller's encryption/reset/isolation assertions.
func assertFirstUnlockProtectionWhenObservable(at url: URL,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #if targetEnvironment(simulator)
    if attributes[.protectionKey] == nil {
        XCTContext.runActivity(named: "Simulator omits FileManager protection metadata; physical-device validation is still required") { activity in
            let note = XCTAttachment(string: "No device protection claim: .protectionKey is unavailable in this simulator. Encryption, backup exclusion, persistence and isolation assertions continue. See https://developer.apple.com/forums/thread/780632")
            note.lifetime = .keepAlways
            activity.add(note)
        }
        return
    }
    #endif
    XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType,
                   .completeUntilFirstUserAuthentication, file: file, line: line)
}

private final class InMemoryAchievementPersistence: CampusAchievementPersisting {
    var journal: CampusAchievementJournal?
    var failWrites = false
    var failReads = false
    var writes = 0
    func load() throws -> CampusAchievementJournal? {
        if failReads { throw CampusAchievementFailure.unavailable }
        return journal
    }
    func save(_ value: CampusAchievementJournal) throws {
        if failWrites { throw CampusAchievementFailure.unavailable }
        journal = value
        writes += 1
    }
}

final class CampusAchievementTests: XCTestCase {
    @MainActor func testDeviceAwardsAreIdempotentAndLifeNeedsAllThreeActivities() throws {
        let disk = InMemoryAchievementPersistence()
        let store = CampusAchievementStore(persistence: disk)
        XCTAssertNil(store.date(for: "life"))
        store.record("bath")
        store.record("laundry")
        XCTAssertNil(store.date(for: "life"))
        store.record("map")
        XCTAssertNotNil(store.date(for: "life"))
        XCTAssertEqual(disk.writes, 3)
        let saved = disk.journal
        store.record("map")
        store.record("firstpost") // Community achievements require server evidence.
        store.record("grade") // School achievements require current verified connection.
        XCTAssertEqual(disk.writes, 3)
        XCTAssertEqual(disk.journal, saved)
        XCTAssertNil(store.date(for: "firstpost"))
    }

    @MainActor func testShowcaseCanHoldThreeOnlyAndPersistsAfterRecreate() {
        let disk = InMemoryAchievementPersistence()
        let store = CampusAchievementStore(persistence: disk)
        for code in ["welcome", "bath", "laundry", "map"] { store.record(code) }
        for code in ["welcome", "bath", "laundry"] { store.togglePin(code) }
        store.togglePin("map")
        XCTAssertEqual(store.journal.pins, ["welcome", "bath", "laundry"])
        let reopened = CampusAchievementStore(persistence: disk)
        XCTAssertEqual(reopened.journal.pins, store.journal.pins)
        reopened.togglePin("bath")
        reopened.togglePin("map")
        XCTAssertEqual(reopened.journal.pins, ["welcome", "laundry", "map"])
    }

    @MainActor func testSaveFailureNeverPublishesUncommittedUnlocksOrPins() throws {
        let disk = InMemoryAchievementPersistence()
        let store = CampusAchievementStore(persistence: disk)
        store.record("welcome")
        let saved = try XCTUnwrap(disk.journal)
        disk.failWrites = true
        store.record("bath")
        store.togglePin("welcome")
        XCTAssertNil(store.date(for: "bath"))
        XCTAssertEqual(store.journal.pins, [])
        XCTAssertEqual(disk.journal, saved)
        XCTAssertNotNil(store.error)
        disk.failWrites = false
        store.togglePin("welcome")
        XCTAssertEqual(store.journal.pins, ["welcome"])
    }

    @MainActor func testDeviceMigrationRemovesOldRecordsOnlyAfterTheSecureSave() throws {
        let domain = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(["device": ["welcome": legacyDate, "firstpost": legacyDate]], forKey: "campus.medals.v1")
        defaults.set(["device": ["welcome", "firstpost"]], forKey: "campus.medal-pins.v1")
        let disk = InMemoryAchievementPersistence()
        let store = CampusAchievementStore(persistence: disk)
        disk.failWrites = true
        _ = MedalJournal(defaults: defaults, device: store)
        XCTAssertNotNil(defaults.dictionary(forKey: "campus.medals.v1")?["device"])
        XCTAssertNil(store.date(for: "welcome"))
        disk.failWrites = false
        _ = MedalJournal(defaults: defaults, device: store)
        XCTAssertEqual(store.date(for: "welcome"), legacyDate)
        XCTAssertNil(store.date(for: "firstpost"))
        XCTAssertEqual(store.journal.pins, ["welcome"])
        XCTAssertNil(defaults.dictionary(forKey: "campus.medals.v1")?["device"])
    }

    @MainActor func testAllPrivateCatalogAwardsPersistWithTheRightOwner() throws {
        let key = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let disk = InMemoryAchievementPersistence()
        let journal = MedalJournal(defaults: defaults, device: CampusAchievementStore(persistence: disk))
        let local = CampusMedal.catalog.filter { $0.source != "community" }
        XCTAssertEqual(local.count, 22)
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        for medal in local where medal.code != "life" {
            journal.unlock(medal.code, scope: "owner", at: date)
        }
        let reopened = MedalJournal(defaults: defaults, device: CampusAchievementStore(persistence: disk))
        for medal in local {
            XCTAssertEqual(reopened.stamp(medal, scope: "owner"), date, medal.code)
            if medal.source != "device" { XCTAssertNil(reopened.stamp(medal, scope: "other"), medal.code) }
        }
        for medal in CampusMedal.catalog where medal.source == "community" {
            reopened.unlock(medal.code, scope: "owner", at: date)
            XCTAssertNil(reopened.stamp(medal, scope: "owner"), medal.code)
        }
    }

    @MainActor func testRestoreVerifiedCompletedTaskKeepsDateAndDoesNotReplayBanner() throws {
        let key = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let disk = InMemoryAchievementPersistence()
        let device = CampusAchievementStore(persistence: disk)
        let journal = MedalJournal(defaults: defaults, device: device)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        var task = CampusTask(title: "旧版个人待办", date: completed, completed: true)
        task.completedAt = completed
        task.updatedAt = completed.addingTimeInterval(120)
        task.steps = [TaskStep(title: "一", completed: true), TaskStep(title: "二", completed: false)]
        XCTAssertNil(TaskRules.stepsMedalEvidence(task))
        task.steps[1].completed = true
        let verified = try XCTUnwrap(TaskRules.stepsMedalEvidence(task))
        XCTAssertEqual(verified, task.updatedAt)
        journal.unlock("tasks", at: verified, historical: true)
        journal.unlock("tasks")
        XCTAssertEqual(CampusAchievementStore(persistence: disk).date(for: "tasks"), verified)
        XCTAssertNil(journal.notice)
        XCTAssertEqual(disk.writes, 1)
    }

    @MainActor func testTemporaryReadFailureRetriesWithExistingJournal() {
        let disk = InMemoryAchievementPersistence()
        let earned = Date()
        disk.journal = CampusAchievementJournal(stamps: ["welcome": earned])
        disk.failReads = true
        let store = CampusAchievementStore(persistence: disk)
        store.record("bath")
        XCTAssertEqual(disk.writes, 0)
        disk.failReads = false
        store.record("bath")
        XCTAssertNotNil(store.date(for: "bath"))
        XCTAssertEqual(store.date(for: "welcome"), earned)
        XCTAssertEqual(disk.writes, 1)
    }

    @MainActor func testInvalidDeviceJournalCannotOverwriteUnreadableStoredAwards() {
        let disk = InMemoryAchievementPersistence()
        disk.journal = CampusAchievementJournal(version: 1, stamps: ["firstpost": Date()], pins: [])
        let store = CampusAchievementStore(persistence: disk)
        XCTAssertNotNil(store.error)
        let original = disk.journal
        store.record("welcome")
        XCTAssertEqual(disk.journal, original)
        XCTAssertEqual(disk.writes, 0)
    }
}

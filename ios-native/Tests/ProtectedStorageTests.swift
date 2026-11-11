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
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["personal.sealed"])
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

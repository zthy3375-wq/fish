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
}

import XCTest
@testable import Hanyuantong

final class PersonalBackupTests: XCTestCase {
    private func sample() -> PersonalBackup {
        PersonalBackup(courses: [Course(name: "个人课程", day: 1, start: "08:00", end: "09:30", weeks: [1, 2])],
                       tasks: [CampusTask(title: "完成作业", date: Date(timeIntervalSince1970: 1800000000))],
                       semesterStart: Date(timeIntervalSince1970: 1790000000))
    }
    func testRoundTripKeepsPersonalFields() throws {
        var value = sample()
        value.courses[0].notes = "带好教材"
        value.tasks[0].completed = true
        let decoded = try PersonalBackup.decode(value.encode())
        XCTAssertEqual(decoded.courses, value.courses)
        XCTAssertEqual(decoded.tasks, value.tasks)
        XCTAssertEqual(decoded.semesterStart, value.semesterStart)
    }
    func testRejectsSchoolSourcesAndExternalIDs() {
        var value = sample()
        value.courses[0].source = "school"
        XCTAssertThrowsError(try value.encode())
        value.courses[0].source = "personal"
        value.courses[0].externalID = "school-page-example"
        XCTAssertThrowsError(try value.encode())
    }
    func testRejectsMalformedTimesAndRanges() {
        for time in ["8:00", "24:00", "08:60", "aa:bb", "０８:００", "09:30", "10:00"] {
            var value = sample(); value.courses[0].start = time
            XCTAssertThrowsError(try value.validate(), time)
        }
        for weeks in [[], [0], [61], [1, 1]] {
            var value = sample(); value.courses[0].weeks = weeks
            XCTAssertThrowsError(try value.validate())
        }
        var value = sample(); value.courses[0].day = 8
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses[0].startPeriod = 4; value.courses[0].endPeriod = 2
        XCTAssertThrowsError(try value.validate())
    }
    func testDuplicateIDsAreRejectedAcrossAndWithinCollections() {
        var value = sample(); value.courses.append(value.courses[0])
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.tasks.append(value.tasks[0])
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.tasks[0].id = value.courses[0].id
        XCTAssertThrowsError(try value.validate())
    }
    func testUnknownVersionAndForeignFieldsRejected() throws {
        var value = sample(); value.version = 2
        XCTAssertThrowsError(try value.validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample().encode()) as? [String: Any])
        object["cookies"] = "synthetic-not-a-real-cookie"
        XCTAssertThrowsError(try PersonalBackup.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "cookies")
        var courses = try XCTUnwrap(object["courses"] as? [[String: Any]])
        courses[0]["token"] = "synthetic"
        object["courses"] = courses
        XCTAssertThrowsError(try PersonalBackup.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try PersonalBackup.decode(Data("{\"version\":1}".utf8)))
    }
    func testSizeAndContentLimits() {
        XCTAssertThrowsError(try PersonalBackup.decode(Data(repeating: 32, count: PersonalBackup.maximumBytes + 1)))
        var value = sample(); value.tasks[0].title = " \n "
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses[0].notes = String(repeating: "a", count: 4001)
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.semesterStart = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses = (0..<2001).map { _ in Course(name: "课程", day: 1, start: "08:00", end: "09:00", weeks: [1]) }
        XCTAssertThrowsError(try value.validate())
    }
    func testEmptyPersonalBackupIsValidForExplicitReplacement() throws {
        let value = PersonalBackup(courses: [], tasks: [], semesterStart: sample().semesterStart)
        XCTAssertNoThrow(try PersonalBackup.decode(value.encode()))
    }
    func testFileReadUsesSameStrictValidation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try sample().encode().write(to: url)
        XCTAssertEqual(try PersonalBackup.read(from: url).courses.count, 1)
        try Data(repeating: 32, count: PersonalBackup.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try PersonalBackup.read(from: url))
    }
}

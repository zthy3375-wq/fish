import Foundation

/// Native iPhone schema v1. This is not the Android backup format.
struct PersonalBackup: Codable {
    static let maximumBytes = 2 * 1024 * 1024
    static let currentVersion = 1
    var version: Int = PersonalBackup.currentVersion
    var courses: [Course]
    var tasks: [CampusTask]
    var semesterStart: Date

    enum Failure: LocalizedError {
        case unsupported, tooLarge, invalid
        var errorDescription: String? {
            switch self {
            case .unsupported: return "请选择本应用 iPhone 原生版导出的 JSON 备份（版本 1）。不支持 Android 备份。"
            case .tooLarge: return "备份超过大小或记录数量限制（2 MB、2000 门课程、5000 条待办）。"
            case .invalid: return "备份内容无效，未恢复任何数据。请检查课程时间、周次、重复编号或数据来源。"
            }
        }
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw Failure.unsupported }
        guard courses.count <= 2000, tasks.count <= 5000 else { throw Failure.tooLarge }
        guard Self.validDate(semesterStart), Set(courses.map(\.id)).count == courses.count,
              Set(tasks.map(\.id)).count == tasks.count,
              Set(courses.map(\.id)).isDisjoint(with: Set(tasks.map(\.id))) else { throw Failure.invalid }
        for course in courses {
            guard course.source == "personal", course.externalID == nil,
                  Self.validText(course.name, limit: 200, required: true),
                  Self.validText(course.teacher, limit: 200), Self.validText(course.room, limit: 200),
                  Self.validText(course.period, limit: 200), Self.validText(course.notes, limit: 4000),
                  Self.validText(course.color, limit: 40), (1...7).contains(course.day),
                  let start = Self.minutes(course.start), let end = Self.minutes(course.end), start < end,
                  !course.weeks.isEmpty, course.weeks.count <= 60,
                  Set(course.weeks).count == course.weeks.count,
                  course.weeks.allSatisfy({ (1...60).contains($0) }) else { throw Failure.invalid }
            switch (course.startPeriod, course.endPeriod) {
            case (nil, nil): break
            case let (first?, last?) where (1...24).contains(first) && (first...24).contains(last): break
            default: throw Failure.invalid
            }
        }
        for task in tasks {
            guard Self.validText(task.title, limit: 200, required: true),
                  Self.validText(task.notes, limit: 4000), Self.validDate(task.date) else { throw Failure.invalid }
        }
    }

    func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> PersonalBackup {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        do {
            // Reject unrecognized fields rather than silently accepting login material or another schema.
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(root.keys) == Set(["version", "courses", "tasks", "semesterStart"]),
                  let courses = root["courses"] as? [[String: Any]],
                  let tasks = root["tasks"] as? [[String: Any]] else { throw Failure.unsupported }
            guard courses.count <= 2000, tasks.count <= 5000 else { throw Failure.tooLarge }
            let courseKeys: Set<String> = ["id", "name", "teacher", "room", "day", "start", "end", "period", "weeks", "color", "startPeriod", "endPeriod", "notes", "source", "externalID"]
            let taskKeys: Set<String> = ["id", "title", "date", "completed", "notes"]
            guard courses.allSatisfy({ Set($0.keys).isSubset(of: courseKeys) }),
                  tasks.allSatisfy({ Set($0.keys).isSubset(of: taskKeys) }) else { throw Failure.unsupported }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(Self.self, from: data)
            try backup.validate()
            return backup
        } catch let error as Failure { throw error }
        catch { throw Failure.invalid }
    }

    /// Bounded reads also protect against an incorrectly reported file size.
    static func read(from url: URL) throws -> PersonalBackup {
        guard url.pathExtension.lowercased() == "json" else { throw Failure.unsupported }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.invalid }
        guard (values.fileSize ?? 0) <= maximumBytes else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw Failure.tooLarge }
        }
        return try decode(data)
    }

    private static func validText(_ value: String, limit: Int, required: Bool = false) -> Bool {
        value.count <= limit && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private static func validDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (-2208988800...7289654400).contains(seconds)
    }
    private static func minutes(_ value: String) -> Int? {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }) else { return nil }
        let hour = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minute = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        guard hour < 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }
}

import Foundation

struct SchoolCourseTimeChange: Codable, Equatable, Hashable {
    var day: Int
    var room: String
    var start: String
    var end: String
    var startPeriod: Int?
    var endPeriod: Int?
    var usesPeriods: Bool

    init(course: Course) {
        day = course.day; room = course.room; start = course.start; end = course.end
        startPeriod = course.startPeriod; endPeriod = course.endPeriod; usesPeriods = course.startPeriod != nil
    }
    func validated(periods: [AcademicPeriod]? = nil) throws -> Self {
        var next = self; next.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...7).contains(day), next.room.count <= 150 else { throw BackupCompatibilityFailure("请检查星期和教室。") }
        if usesPeriods {
            guard let first = startPeriod, let last = endPeriod, (1...24).contains(first), (first...24).contains(last) else { throw BackupCompatibilityFailure("请检查上课节次。") }
            if let periods {
                guard let firstTime = periods.first(where: { $0.number == first }), let lastTime = periods.first(where: { $0.number == last }) else { throw BackupCompatibilityFailure("学校作息已更新，请重新选择节次。") }
                next.start = firstTime.start; next.end = lastTime.end
            }
        } else { next.startPeriod = nil; next.endPeriod = nil }
        guard [next.start, next.end].allSatisfy({ $0.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil }), next.end > next.start else { throw BackupCompatibilityFailure("结束时间需晚于开始时间。") }
        return next
    }
}
struct SchoolCourseAdjustment: Codable, Equatable {
    let term: AcademicTerm
    let sourceKey: String
    let week: Int
    let change: SchoolCourseTimeChange
}
struct SchoolCourseAdjustmentContext: Identifiable {
    let scope: String
    let term: AcademicTerm
    let source: Course
    let current: Course
    let week: Int
    let periods: [AcademicPeriod]
    var id: UUID { current.id }
}
enum SchoolCourseAdjustments {
    static func key(_ course: Course) -> String {
        // A length-prefixed encoding avoids ambiguity even in unusual course names.
        [course.name, course.teacher, course.room, String(course.day), course.start, course.end,
         String(course.startPeriod ?? 0), String(course.endPeriod ?? 0)].map { "\($0.utf8.count):\($0)" }.joined()
    }
    static func periods(_ snapshot: AcademicSnapshot) -> [AcademicPeriod] {
        snapshot.periods ?? ScheduleMath.starts.enumerated().map { AcademicPeriod(number: $0.offset + 1, start: $0.element, end: ScheduleMath.ends[$0.offset]) }
    }
    static func originals(_ snapshot: AcademicSnapshot) -> [Course] {
        let times = periods(snapshot)
        var occurrences: [String: Int] = [:]
        return (snapshot.courses ?? []).compactMap { row in
            let slots = ScheduleMath.parseRange(row.periods, limit: 24), weeks = ScheduleMath.parseRange(row.weeks, limit: 60)
            guard let first = slots.first, let last = slots.last, !weeks.isEmpty,
                  let start = times.first(where: { $0.number == first })?.start,
                  let end = times.first(where: { $0.number == last })?.end else { return nil }
            var course = Course(name: row.name, teacher: row.teacher, room: row.room, day: row.weekday, start: start, end: end, period: row.periods + "节", weeks: weeks, color: "purple", startPeriod: first, endPeriod: last, notes: "学校同步", source: "school", externalID: row.id)
            let sourceKey = key(course)
            let occurrence = occurrences[sourceKey, default: 0]; occurrences[sourceKey] = occurrence + 1
            course.id = BackupValue.stableID(sourceKey + "/\(occurrence)", namespace: "school/\(snapshot.scope)/\(snapshot.term?.xnm ?? "")/\(snapshot.term?.xqm ?? "")")
            course.adjustmentSourceKey = sourceKey
            return course
        }
    }
    static func validated(_ records: [SchoolCourseAdjustment]) throws -> [SchoolCourseAdjustment] {
        guard records.count <= 4000 else { throw BackupCompatibilityFailure("本地调课记录过多，请先恢复不再需要的调整。") }
        var identities = Set<String>()
        for record in records {
            guard record.term.isValid, !record.sourceKey.isEmpty, record.sourceKey.count <= 2000, (1...60).contains(record.week),
                  identities.insert("\(record.term.xnm)/\(record.term.xqm)/\(record.week)/\(record.sourceKey)").inserted else { throw BackupCompatibilityFailure("本地调课记录无法识别。") }
            _ = try record.change.validated()
        }
        return records
    }
    static func project(_ originals: [Course], term: AcademicTerm?, records: [SchoolCourseAdjustment], periods: [AcademicPeriod]) -> [Course] {
        originals.flatMap { source -> [Course] in
            let sourceKey = key(source)
            let unique = originals.filter { key($0) == sourceKey }.count == 1
            let active = unique ? records.filter { $0.term == term && $0.sourceKey == sourceKey && source.weeks.contains($0.week) } : []
            var groups: [SchoolCourseTimeChange: [Int]] = [:]
            for record in active {
                guard let change = try? record.change.validated(periods: periods) else { continue }
                groups[change, default: []].append(record.week)
            }
            let changed = Set(groups.values.flatMap { $0 })
            var original = source; original.weeks.removeAll { changed.contains($0) }; original.adjustmentSourceKey = sourceKey
            var result: [Course] = original.weeks.isEmpty ? [] : [original]
            for (change, weeks) in groups.sorted(by: { ($0.value.min() ?? 0) < ($1.value.min() ?? 0) }) {
                var course = source
                course.id = BackupValue.stableID("\(source.id)/\(weeks.min() ?? 0)", namespace: "school-adjusted")
                course.day = change.day; course.room = change.room; course.start = change.start; course.end = change.end
                course.startPeriod = change.startPeriod; course.endPeriod = change.endPeriod; course.weeks = weeks.sorted()
                course.period = change.usesPeriods ? "\(change.startPeriod!)–\(change.endPeriod!) 节" : "自定义时间"
                course.adjustmentSourceKey = sourceKey; course.locallyAdjusted = true
                result.append(course)
            }
            return result
        }
    }
    static func updating(_ records: [SchoolCourseAdjustment], term: AcademicTerm, source: Course, weeks: [Int], change: SchoolCourseTimeChange, periods: [AcademicPeriod]) throws -> [SchoolCourseAdjustment] {
        guard !weeks.isEmpty, Set(weeks).count == weeks.count, weeks.allSatisfy(source.weeks.contains) else { throw BackupCompatibilityFailure("请选择原课程实际有课的教学周。") }
        let value = try change.validated(periods: periods), sourceKey = key(source)
        var next = records.filter { !($0.term == term && $0.sourceKey == sourceKey && weeks.contains($0.week)) }
        let restoring = value.day == source.day && value.room == source.room && value.start == source.start && value.end == source.end
        if !restoring { next += weeks.map { SchoolCourseAdjustment(term: term, sourceKey: sourceKey, week: $0, change: value) } }
        return try validated(next)
    }
    static func conflicts(_ courses: [Course], sourceKey: String, weeks: [Int]) -> [String] {
        var names = Set<String>()
        for a in courses where a.adjustmentSourceKey == sourceKey && a.weeks.contains(where: weeks.contains) {
            for b in courses where a.id != b.id && a.day == b.day && a.start < b.end && b.start < a.end && a.weeks.contains(where: { weeks.contains($0) && b.weeks.contains($0) }) { names.insert(b.name) }
        }
        return names.sorted()
    }
    static func inactiveCount(_ originals: [Course], term: AcademicTerm?, records: [SchoolCourseAdjustment], periods: [AcademicPeriod]) -> Int {
        records.filter { record in
            record.term == term && (originals.filter { key($0) == record.sourceKey && $0.weeks.contains(record.week) }.count != 1 || (try? record.change.validated(periods: periods)) == nil)
        }.count
    }
}

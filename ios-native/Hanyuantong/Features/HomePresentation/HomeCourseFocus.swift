import Foundation

struct HomeCourseFocus {
    let course: Course
    let start: Date
    let end: Date
    func isCurrent(at now: Date) -> Bool { start <= now && now < end }
    func progress(at now: Date) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
    func remainingMinutes(at now: Date) -> Int { max(0, Int(ceil(end.timeIntervalSince(now) / 60))) }
    static func select(courses: [Course], personalStart: Date, schoolStart: Date, now: Date) -> HomeCourseFocus? {
        let calendar = ScheduleMath.calendar
        var candidates: [HomeCourseFocus] = []
        for course in courses {
            let base = course.source == "school" ? schoolStart : personalStart
            let currentWeek = max(1, ScheduleMath.week(on: now, start: base))
            guard (1...7).contains(course.day), let first = minutes(course.start), let last = minutes(course.end), first < last else { continue }
            for week in Set(course.weeks).sorted() where week >= currentWeek && (1...60).contains(week) {
                guard let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + course.day - 1, to: calendar.startOfDay(for: base)),
                      let start = calendar.date(bySettingHour: first / 60, minute: first % 60, second: 0, of: day),
                      let end = calendar.date(bySettingHour: last / 60, minute: last % 60, second: 0, of: day), end > now else { continue }
                candidates.append(HomeCourseFocus(course: course, start: start, end: end)); break
            }
        }
        return candidates.sorted {
            if $0.isCurrent(at: now) != $1.isCurrent(at: now) { return $0.isCurrent(at: now) }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.course.id.uuidString < $1.course.id.uuidString
        }.first
    }
    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

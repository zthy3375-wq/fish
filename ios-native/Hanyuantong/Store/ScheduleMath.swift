import Foundation

/// Calendar calculations intentionally use the campus timezone, independent of travel/device timezone.
enum ScheduleMath {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }
    static let starts = ["08:00", "08:45", "09:45", "10:30", "11:15", "14:30", "15:15", "16:15", "17:00", "17:45", "19:00", "19:45", "20:30"]
    static let ends = ["08:40", "09:25", "10:25", "11:10", "11:55", "15:10", "15:55", "16:55", "17:40", "18:25", "19:40", "20:25", "21:10"]
    static func week(on date: Date, start: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }
    static func weekday(on date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 + 1 }
    static func parseRange(_ raw: String, limit: Int) -> [Int] {
        let value = raw.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",").replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-").replacingOccurrences(of: "－", with: "-").replacingOccurrences(of: "—", with: "-")
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)(?:\s*-\s*(\d+))?"#) else { return [] }
        var values = Set<Int>()
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range(at: 1), in: value), let first = Int(value[range]), (1...limit).contains(first) else { continue }
            let last = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) } ?? first
            guard last >= first && last <= limit else { continue }
            let remainder = Range(NSRange(location: NSMaxRange(match.range), length: (value as NSString).length - NSMaxRange(match.range)), in: value).map { String(value[$0]) } ?? ""
            let modifier = remainder.prefix { !$0.isNumber && $0 != "," }
            for number in first...last {
                if modifier.contains("单") && number % 2 == 0 { continue }
                if modifier.contains("双") && number % 2 != 0 { continue }
                values.insert(number)
            }
        }
        return values.sorted()
    }
}

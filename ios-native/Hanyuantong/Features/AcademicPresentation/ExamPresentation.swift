import Foundation

enum NativeExamPresentation {
    /// Dates use Asia/Shanghai. Unknown dates remain visible separately, never guessed.
    static func day(_ exam: ExamRecord) -> Date? {
        let text = exam.date.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard NativeGradeReport.matches(text, "^20[0-9]{2}-[0-9]{2}-[0-9]{2}$") else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = ScheduleMath.calendar; formatter.timeZone = ScheduleMath.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    /// Includes today's exams even when the school supplies no parseable start/end time.
    static func upcoming(_ exams: [ExamRecord], now: Date = Date()) -> [ExamRecord] {
        let today = ScheduleMath.calendar.startOfDay(for: now)
        return exams.filter { day($0).map { $0 >= today } ?? false }.sorted {
            let a = day($0)!, b = day($1)!
            return a == b ? $0.time < $1.time : a < b
        }
    }
    static func unknownDates(_ exams: [ExamRecord]) -> [ExamRecord] { exams.filter { day($0) == nil } }
    static func dayLabel(_ exam: ExamRecord, now: Date = Date()) -> String {
        guard let day = day(exam) else { return "日期待核对" }
        let distance = ScheduleMath.calendar.dateComponents([.day], from: ScheduleMath.calendar.startOfDay(for: now), to: day).day ?? 0
        return distance == 0 ? "今天" : distance > 0 ? "\(distance) 天后" : "已过日期"
    }
}

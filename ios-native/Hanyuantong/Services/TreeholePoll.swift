import Foundation

struct TreeholePollOption: Codable, Equatable, Identifiable { let id: String; let text: String; let count: Int }
struct TreeholePoll: Codable, Equatable {
    let version: Int
    let question: String
    let closesAt: String
    var closed: Bool
    let total: Int
    let myOptionId: String?
    let options: [TreeholePollOption]
    var deadline: Date? {
        let reader = ISO8601DateFormatter(); reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = reader.date(from: closesAt) { return date }
        reader.formatOptions = [.withInternetDateTime]; return reader.date(from: closesAt)
    }
    func ended(at date: Date = Date()) -> Bool { closed || (deadline.map { $0 <= date } ?? true) }
    var deadlineLabel: String {
        guard let deadline else { return "已结束" }
        let writer = DateFormatter(); writer.locale = Locale(identifier: "zh_CN"); writer.timeZone = TimeZone(identifier: "Asia/Shanghai"); writer.dateFormat = "M月d日 HH:mm"
        return writer.string(from: deadline) + " 截止"
    }
}
struct TreeholePollDraft: Codable, Equatable {
    var question = ""
    var options = ["", ""]
    var durationHours = 72
    var valid: Bool {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !question.isEmpty && question.count <= 80 && (2...6).contains(options.count) && options.allSatisfy { !$0.isEmpty && $0.count <= 40 } && Set(options.map { $0.lowercased() }).count == options.count && [24,72,168].contains(durationHours)
    }
    var payload: [String: Any] { ["question": question, "options": options, "durationHours": durationHours] }
}

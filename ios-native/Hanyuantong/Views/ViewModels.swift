import Foundation

enum AppTab: String, CaseIterable { case home, schedule, tasks, profile }

struct Course: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var teacher: String = ""
    var room: String = ""
    /// Monday = 1, Sunday = 7, matching the existing Android data contract.
    var day: Int
    var start: String
    var end: String
    var period: String = ""
    var weeks: [Int]
    var color: String = "purple"
    var startPeriod: Int? = nil
    var endPeriod: Int? = nil
    var notes: String = ""
    var source: String = "personal"
    var externalID: String? = nil
}

struct CampusTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var date: Date
    var completed: Bool = false
    var notes: String = ""
}

struct GradeRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var score: String
    var credit: String = ""
    var term: String = ""
    var kind: String = ""
}

struct ExamRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var date: String
    var time: String = ""
    var room: String = ""
    var seat: String = ""
}

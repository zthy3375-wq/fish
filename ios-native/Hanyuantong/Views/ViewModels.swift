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

/// Personal tasks only. Official learning items remain in LearningStore and cannot be completed here.
struct CampusTask: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    /// Compatibility projection for older native readers; use plannedAt/plannedDay/deadline for meaning.
    var date: Date
    var completed: Bool
    var notes: String
    var schemaVersion: Int = 2
    var course: String = ""
    var plannedAt: Date?
    var plannedDay: String?
    var deadline: Date?
    var prepared: Bool = false
    var durationMinutes: Int = 30
    var priority: Int = 0
    var pinned: Bool = false
    var steps: [TaskStep] = []
    var repeatRule: TaskRepeatRule?
    var reminders: [TaskReminder] = []
    var completedAt: Date?
    var generatedFrom: UUID?
    var seriesID: UUID?
    var snoozedUntil: Date?
    var createdAt: Date
    var updatedAt: Date
    /// Only old native tasks retain the global planned-time reminder behavior.
    var legacyReminder: Bool = true
    var originalID: String?
    var generatedFromOriginalID: String?
    var seriesOriginalID: String?

    init(id: UUID = UUID(), title: String, date: Date, completed: Bool = false, notes: String = "") {
        self.id = id; self.title = title; self.date = date; self.completed = completed; self.notes = notes
        plannedAt = date; createdAt = date; updatedAt = date
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, date, completed, notes, schemaVersion, course, plannedAt, plannedDay, deadline
        case prepared, durationMinutes, priority, pinned, steps, repeatRule, reminders, completedAt
        case generatedFrom, seriesID, snoozedUntil, createdAt, updatedAt, legacyReminder
        case originalID, generatedFromOriginalID, seriesOriginalID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        completed = try c.decode(Bool.self, forKey: .completed)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...2).contains(version) else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "Unsupported task version")
        }
        schemaVersion = 2
        course = try c.decodeIfPresent(String.self, forKey: .course) ?? ""
        // An absent rich schema denotes the original native planned date, never a deadline.
        plannedAt = try c.decodeIfPresent(Date.self, forKey: .plannedAt)
        plannedDay = try c.decodeIfPresent(String.self, forKey: .plannedDay)
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        if version == 1 && !c.contains(.plannedAt) && !c.contains(.plannedDay) { plannedAt = date }
        prepared = try c.decodeIfPresent(Bool.self, forKey: .prepared) ?? false
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        steps = try c.decodeIfPresent([TaskStep].self, forKey: .steps) ?? []
        repeatRule = try c.decodeIfPresent(TaskRepeatRule.self, forKey: .repeatRule)
        reminders = try c.decodeIfPresent([TaskReminder].self, forKey: .reminders) ?? []
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        generatedFrom = try c.decodeIfPresent(UUID.self, forKey: .generatedFrom)
        seriesID = try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        legacyReminder = try c.decodeIfPresent(Bool.self, forKey: .legacyReminder) ?? (version == 1)
        originalID = try c.decodeIfPresent(String.self, forKey: .originalID)
        generatedFromOriginalID = try c.decodeIfPresent(String.self, forKey: .generatedFromOriginalID)
        seriesOriginalID = try c.decodeIfPresent(String.self, forKey: .seriesOriginalID)
    }
}

struct GradeRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var score: String
    var credit: String = ""
    var term: String = ""
    var kind: String = ""
    var schoolGPA: Double? = nil
    var courseCode: String = ""
    var recordId: String = ""
    var year: String = ""
    var termCode: String = ""
    var examType: String = ""
}

struct ExamRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var date: String
    var time: String = ""
    var room: String = ""
    var seat: String = ""
}

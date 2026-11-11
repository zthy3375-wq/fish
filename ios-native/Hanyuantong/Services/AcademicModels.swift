import Foundation

struct AcademicTerm: Codable, Equatable, Hashable {
    let xnm: String
    let xqm: String
    var isValid: Bool {
        xnm.range(of: "^20[0-9]{2}$", options: .regularExpression) != nil && ["3", "12"].contains(xqm)
    }
    var title: String { "\(xnm)–\((Int(xnm) ?? 0) + 1) \(xqm == "3" ? "第一学期" : "第二学期")" }
}

struct AcademicCourse: Codable, Equatable, Identifiable {
    let name: String
    let teacher: String
    let room: String
    let weekday: Int
    let periods: String
    let weeks: String
    static func validPeriods(_ value: String) -> Bool {
        guard value.range(of: "^[0-9]{1,2}(-[0-9]{1,2})?$", options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard let first = parts.first, let last = parts.last else { return false }
        return (1...24).contains(first) && (first...24).contains(last)
    }
    var id: String { [name, teacher, room, String(weekday), periods, weeks].joined(separator: "\u{1f}") }
}
struct AcademicPractice: Codable, Equatable, Identifiable {
    let name: String
    let teacher: String
    let weeks: String
    var id: String { [name, teacher, weeks].joined(separator: "\u{1f}") }
}
struct AcademicGrade: Codable, Equatable, Identifiable {
    let name: String
    let scoreText: String
    let credit: Double?
    let gpa: Double?
    let term: String
    let kind: String
    let courseCode: String
    let recordId: String
    let year: String
    let termCode: String
    let examType: String
    var id: String { [recordId, courseCode, name, year, termCode, examType].joined(separator: "\u{1f}") }
}
struct AcademicExam: Codable, Equatable, Identifiable {
    let name: String
    let date: String
    let time: String
    let room: String
    let seat: String
    var id: String { [name, date, time, room, seat].joined(separator: "\u{1f}") }
}
struct AcademicPeriod: Codable, Equatable {
    let number: Int
    let start: String
    let end: String
}
struct AcademicError: Error, LocalizedError, Equatable {
    let code: String
    var errorDescription: String? {
        switch code {
        case "EXPIRED": return "学校会话已过期，请重新连接。"
        case "CANCELLED": return "已取消学校连接。"
        case "BUSY": return "正在查询学校数据，请稍候。"
        case "TERM": return "学期信息不匹配，请重新选择学期。"
        case "STORAGE": return "无法安全保存或清除学校会话，请稍后重试。"
        case "NETWORK", "HTTP": return "暂时无法连接学校，请稍后重试。"
        case "CAPTCHA": return "请在学校官方页面完成验证码后重试。"
        case "PRESENTATION": return "请先关闭当前页面，再连接学校。"
        default: return "学校数据暂未完整读取，请重试（\(code)）。"
        }
    }
}

/// Partial results preserve previous success, but never cross accounts or terms.
/// Nil means unavailable; [] only means the server confirmed a complete empty module.
struct AcademicSnapshot: Codable, Equatable {
    let scope: String
    let term: AcademicTerm?
    let courses: [AcademicCourse]?
    let practice: [AcademicPractice]?
    let grades: [AcademicGrade]?
    let exams: [AcademicExam]?
    let semesters: [AcademicTerm]
    let moduleErrors: [String: String]
    let updatedAt: Date
    var periods: [AcademicPeriod]? = nil
    var gradeScope: String? = nil
    var moduleUpdatedAt: [String: Date] = [:]

    func merging(previous: AcademicSnapshot?) -> AcademicSnapshot {
        guard let previous, previous.scope == scope, (term == nil || previous.term == term) else { return self }
        var merged = AcademicSnapshot(scope: scope, term: term ?? previous.term, courses: courses ?? previous.courses,
            practice: practice ?? previous.practice, grades: grades ?? previous.grades,
            exams: exams ?? previous.exams, semesters: semesters.isEmpty ? previous.semesters : semesters,
            moduleErrors: moduleErrors, updatedAt: updatedAt)
        merged.periods = periods ?? previous.periods
        merged.gradeScope = grades == nil ? previous.gradeScope : gradeScope
        merged.moduleUpdatedAt = previous.moduleUpdatedAt.merging(moduleUpdatedAt) { _, new in new }
        return merged
    }

    static func decode(_ payload: [String: Any], now: Date = Date()) throws -> AcademicSnapshot {
        guard payload["session"] as? String == "valid" else {
            throw AcademicError(code: payload["session"] as? String == "expired" ? "EXPIRED" : (payload["code"] as? String ?? payload["error"] as? String ?? "SCHEMA"))
        }
        guard let scope = payload["sessionScope"] as? String, UUID(uuidString: scope) != nil,
              let modules = payload["modules"] as? [String: Any] else { throw AcademicError(code: "SCHEMA") }
        var errors: [String: String] = [:]
        var dates: [String: Date] = [:]
        func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            guard let module = modules[name] as? [String: Any] else { return nil }
            guard module["status"] as? String == "ok", let value = module["data"],
                  JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value), data.count <= 700_000,
                  let decoded = try? JSONDecoder().decode(type, from: data) else {
                errors[name] = module["code"] as? String ?? "SCHEMA"; return nil
            }
            dates[name] = now
            return decoded
        }
        struct Row: Decodable { let kcmc: String; let xm: String; let cdmc: String; let xqj: String; let jcs: String; let zcd: String }
        struct Timetable: Decodable { let term: AcademicTerm; let kbList: [Row]; let practice: [AcademicPractice]; let periods: [AcademicPeriod]? }
        let timetable = read("timetable", as: Timetable.self)
        var courses: [AcademicCourse]?
        var practice: [AcademicPractice]?
        var term: AcademicTerm?
        if let requested = payload["requestedTerm"] as? [String: String], let year = requested["xnm"], let code = requested["xqm"] {
            let selected = AcademicTerm(xnm: year, xqm: code)
            guard selected.isValid else { throw AcademicError(code: "TERM") }
            term = selected
        }
        if let resolved = payload["resolvedTerm"] as? [String: String], let year = resolved["xnm"], let code = resolved["xqm"] {
            let actual = AcademicTerm(xnm: year, xqm: code)
            guard actual.isValid, term == nil || term == actual else { throw AcademicError(code: "TERM") }
            term = actual
        }
        if let timetable {
            if let term, term != timetable.term { throw AcademicError(code: "TERM") }
            term = timetable.term
            if timetable.term.isValid, timetable.kbList.count <= 500, timetable.practice.count <= 500,
               !timetable.kbList.isEmpty || !timetable.practice.isEmpty,
               timetable.kbList.allSatisfy({ !$0.kcmc.isEmpty && !ScheduleMath.parseRange($0.zcd, limit: 60).isEmpty && (1...7).contains(Int($0.xqj) ?? 0) && AcademicCourse.validPeriods($0.jcs) }) {
                courses = timetable.kbList.map { AcademicCourse(name: $0.kcmc, teacher: $0.xm, room: $0.cdmc, weekday: Int($0.xqj)!, periods: $0.jcs, weeks: $0.zcd) }
                practice = timetable.practice
            } else { errors["timetable"] = "SCHEMA"; dates.removeValue(forKey: "timetable") }
        }
        var grades = read("grades", as: [AcademicGrade].self)
        var exams = read("exams", as: [AcademicExam].self)
        if let rows = grades, rows.count > 2000 || rows.contains(where: { $0.name.isEmpty }) {
            grades = nil; errors["grades"] = "SCHEMA"; dates.removeValue(forKey: "grades")
        }
        if let rows = exams, rows.count > 2000 || rows.contains(where: { $0.name.isEmpty }) {
            exams = nil; errors["exams"] = "SCHEMA"; dates.removeValue(forKey: "exams")
        }
        let semesters = (read("semesters", as: [AcademicTerm].self) ?? []).filter(\.isValid)
        var snapshot = AcademicSnapshot(scope: scope, term: term, courses: courses, practice: practice,
            grades: grades, exams: exams, semesters: semesters, moduleErrors: errors, updatedAt: now)
        snapshot.periods = courses == nil ? nil : timetable?.periods
        snapshot.gradeScope = (modules["grades"] as? [String: Any])?["scope"] as? String
        snapshot.moduleUpdatedAt = dates
        return snapshot
    }
}

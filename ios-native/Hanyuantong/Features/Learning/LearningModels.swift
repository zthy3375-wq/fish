import Foundation

/// Native-only learning data. Signed URLs must never be copied into diagnostics or analytics.
struct LearningCourse: Codable, Identifiable, Equatable {
    var courseId: String
    var classId: String
    var cpi: String
    var name: String
    var teacher: String
    var url: String
    var key: String { "\(courseId)/\(classId)" }
    var id: String { key }

    func validated() throws -> Self {
        guard [courseId, classId, cpi].allSatisfy(LearningPolicy.numeric),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200, teacher.count <= 150,
              url.count <= 16_384, LearningPolicy.safeRead(url) else {
            throw LearningError(code: "COURSES_SCHEMA")
        }
        return self
    }
}

struct LearningItem: Codable, Identifiable, Equatable {
    var id: String
    var courseId: String
    var classId: String
    var workId: String
    var kind: String
    var title: String
    var course: String
    var status: String
    var statusText: String
    /// Local wall-clock minute in Asia/Shanghai, never an inferred year.
    var deadline: String?
    var startAt: String?
    var timeText: String
    var description: String
    var url: String
    var stale: Bool = false
    var updatedAt: String?
    var firstSeenAt: String?
    var seenAt: String?
    var courseKey: String { "\(courseId)/\(classId)" }
    var hasLink: Bool { LearningPolicy.allowed(url) }

    init(id: String, courseId: String, classId: String, workId: String, kind: String,
         title: String, course: String, status: String, statusText: String,
         deadline: String? = nil, startAt: String? = nil, timeText: String = "",
         description: String = "", url: String = "", stale: Bool = false,
         updatedAt: String? = nil, firstSeenAt: String? = nil, seenAt: String? = nil) {
        self.id = id; self.courseId = courseId; self.classId = classId; self.workId = workId
        self.kind = kind; self.title = title; self.course = course; self.status = status
        self.statusText = statusText; self.deadline = deadline; self.startAt = startAt
        self.timeText = timeText; self.description = description; self.url = url; self.stale = stale
        self.updatedAt = updatedAt; self.firstSeenAt = firstSeenAt; self.seenAt = seenAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, courseId, classId, workId, kind, title, course, status, statusText
        case deadline, startAt, timeText, description, url, stale, updatedAt, firstSeenAt, seenAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        courseId = try c.decode(String.self, forKey: .courseId)
        classId = try c.decode(String.self, forKey: .classId)
        workId = try c.decode(String.self, forKey: .workId)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        course = try c.decode(String.self, forKey: .course)
        status = try c.decode(String.self, forKey: .status)
        statusText = try c.decode(String.self, forKey: .statusText)
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
        startAt = try c.decodeIfPresent(String.self, forKey: .startAt)
        timeText = try c.decodeIfPresent(String.self, forKey: .timeText) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        firstSeenAt = try c.decodeIfPresent(String.self, forKey: .firstSeenAt)
        seenAt = try c.decodeIfPresent(String.self, forKey: .seenAt)
        _ = try validated()
    }

    func validated() throws -> Self {
        guard [courseId, classId, workId].allSatisfy(LearningPolicy.numeric),
              ["homework", "exam"].contains(kind),
              ["pending", "submitted", "closed", "unknown"].contains(status),
              id == "\(courseId)/\(classId)/\(kind)/\(workId)",
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, course.count <= 200, statusText.count <= 100,
              timeText.count <= 1_000, description.count <= 4_000, url.count <= 16_384,
              url.isEmpty || LearningPolicy.allowed(url),
              [deadline, startAt].allSatisfy({ value in
                  guard let value else { return true }
                  return value.count == 16 && LearningHTML.dates(value).first == value
              }) else { throw LearningError(code: "WORK_SCHEMA") }
        return self
    }
}

struct LearningNotice: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    var sender: String
    var publishedText: String
}

struct LearningParsedWork: Codable, Equatable {
    var records: [LearningItem]
    var recognized: Bool
    var complete: Bool
    var rejected: Int
    var nextURL: String? = nil
    var total: Int? = nil
}

struct LearningParsedCourses: Codable, Equatable {
    var courses: [LearningCourse]
    var complete: Bool
    var rejected: Int
}

struct LearningNavigation: Codable, Equatable {
    var menu: String?
    var workFrame: String?
    var courseFrames: [String]
    var workEnc: String
    var openc: String
    var stuenc: String
    var auth: Bool
    var challenge: Bool
    var accessDenied: Bool
    var emptyCourses: Bool
    var fid: String?
}

struct LearningPage {
    var url: URL
    var body: String
}

struct LearningError: Error, LocalizedError, Equatable {
    let code: String
    var message: String {
        switch code {
        case "AUTH", "ACCOUNT_CHANGED": return "学习通登录已过期，请在官方页面重新登录。"
        case "VERIFY": return "学习通需要完成官方验证，请验证后继续。"
        case "RATE_LIMIT": return "学习通访问较频繁，请稍后继续。"
        case "CANCELLED": return "已暂停更新，已读取的数据已保留。"
        case "LIMIT": return "本次学习数据超过处理上限，原有数据已保留。"
        case "WORK_ACCESS": return "当前账号没有此课程的访问权限。"
        case "WORK_ENC": return "暂未找到这门课程的作业入口。"
        case "COURSES_SCHEMA": return "暂时无法识别学习通课程列表。"
        case "WORK_SCHEMA": return "暂时无法识别学习通作业列表。"
        case "EXAMS_SCHEMA": return "暂时无法识别学习通考试列表。"
        case "NOTICES_SCHEMA": return "暂时无法识别学习通通知列表。"
        case "URL", "METHOD", "REDIRECT": return "学习通返回的页面暂不支持安全读取。"
        default: return "学习通更新未完成，原有数据已保留，请稍后重试。"
        }
    }
    var errorDescription: String? { message }
}

/// Exact official HTTPS origins and the existing Android read-only protocol contract.
enum LearningPolicy {
    static let home = "https://i.chaoxing.com/base"
    static let login = "https://passport2.chaoxing.com/login?refer=https%3A%2F%2Fi.chaoxing.com"
    static let courses = "https://mooc1-api.chaoxing.com/mycourse/backclazzdata"
    static let allWork = "https://mooc1-api.chaoxing.com/mooc-ans/mooc2/work/all-task"
    static let exams = "https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist"
    static let notices = "https://notice.chaoxing.com/pc/notice/getNoticeList"
    static let homeURL = URL(string: home)!
    static let loginURL = URL(string: login)!
    static let coursesURL = URL(string: courses)!
    static let allWorkURL = URL(string: allWork)!
    static let examsURL = URL(string: exams)!
    static let noticesURL = URL(string: notices)!
    static let readUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"
    static let maxPageBytes = 1_500_000
    static let maxCourses = 200
    static let maxBatchItems = 1_000
    static let origins = ["https://chaoxing.com", "https://passport2.chaoxing.com", "https://i.chaoxing.com", "https://mooc1-api.chaoxing.com", "https://mooc1.chaoxing.com", "https://mooc1-1.chaoxing.com", "https://mooc1-2.chaoxing.com", "https://mooc2-ans.chaoxing.com", "https://notice.chaoxing.com", "https://sso.chaoxing.com"]
    private static let readPaths: Set<String> = [
        "/base", "/mycourse/studentcourse", "/mycourse/stu", "/mycourse/backclazzdata",
        "/visit/courselistdata", "/mooc2-ans/visit/courselistdata", "/visit/stucoursemiddle",
        "/mooc-ans/visit/stucoursemiddle", "/mooc2/work/all-task", "/mooc-ans/mooc2/work/all-task",
        "/mooc2/work/list", "/mooc-ans/mooc2/work/list", "/work/getallwork", "/mooc-ans/work/getallwork",
        "/mooc2/work/task", "/mooc-ans/mooc2/work/task", "/exam-ans/exam/test/examcode/examlist",
        "/pc/notice/getnoticelist"
    ]
    private static let workPaths: Set<String> = ["/mooc2/work/list", "/mooc-ans/mooc2/work/list", "/work/getallwork", "/mooc-ans/work/getallwork"]

    static func numeric(_ value: String) -> Bool {
        (1...24).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func allowed(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 16_384,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !value.contains("\\"), let c = URLComponents(string: value),
              c.scheme?.lowercased() == "https", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, let host = c.host?.lowercased(),
              host == "chaoxing.com" || host.hasSuffix(".chaoxing.com"),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else { return false }
        return c.url != nil
    }
    static func allowed(_ url: URL?) -> Bool { allowed(url?.absoluteString) }
    static func origin(_ value: String) -> String? {
        guard allowed(value), let host = URLComponents(string: value)?.host?.lowercased() else { return nil }
        return "https://\(host)"
    }
    static func origin(_ url: URL) -> String? { origin(url.absoluteString) }
    static func safeRead(_ value: String) -> Bool {
        guard allowed(value), let path = URLComponents(string: value)?.path.lowercased() else { return false }
        return readPaths.contains(path) || path.hasPrefix("/mooc2-ans/mycourse/") || path.hasPrefix("/mooc-ans/mycourse/")
    }
    static func safeRead(_ url: URL) -> Bool { safeRead(url.absoluteString) }
    static func workList(_ value: String) -> Bool {
        allowed(value) && workPaths.contains(URLComponents(string: value)?.path.lowercased() ?? "")
    }
    static func workList(_ url: URL) -> Bool { workList(url.absoluteString) }
    static func loginPage(_ value: String) -> Bool {
        guard allowed(value), let c = URLComponents(string: value) else { return true }
        return c.host?.lowercased().hasPrefix("passport") == true || c.path.lowercased().contains("/login")
    }
    static func loginPage(_ url: URL) -> Bool { loginPage(url.absoluteString) }
    static func challenge(_ url: String, body: String) -> Bool {
        url.localizedCaseInsensitiveContains("antispider") || body.contains("访问过于频繁") || (body.contains("9010") && body.contains("验证码"))
    }
    static func query(_ value: String) -> [String: String] {
        guard let raw = URLComponents(string: value)?.percentEncodedQuery else { return [:] }
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let name = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                  let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { continue }
            let key = name.lowercased()
            if let existing = result[key], existing != value { result[key] = "\0" }
            else { result[key] = value }
        }
        return result
    }
    static func query(_ url: URL) -> [String: String] { query(url.absoluteString) }
    static func sameCourse(_ value: String, course: LearningCourse?) -> Bool {
        guard let course else { return true }
        let q = query(value)
        return (q["courseid"] == nil || q["courseid"] == course.courseId)
            && (q["classid"] == nil || q["classid"] == course.classId)
            && (q["clazzid"] == nil || q["clazzid"] == course.classId)
    }
    static func sameCourse(_ url: URL, course: LearningCourse?) -> Bool { sameCourse(url.absoluteString, course: course) }
    static func absolute(_ raw: String, base: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !trimmed.contains("\\"), allowed(base), let baseURL = URL(string: base),
              let value = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL.absoluteString,
              allowed(value) else { return nil }
        return value
    }
    static func params(_ base: String, _ values: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = values.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        let pieces = base.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0]); let fragment = pieces.count > 1 ? "#\(pieces[1])" : ""
        return path + (path.contains("?") ? "&" : "?") + encoded + fragment
    }
    static func params(_ base: String, values: [String: String]) -> URL {
        // URL construction is used only for fixed official endpoint constants.
        URL(string: params(base, values)) ?? homeURL
    }
    static func params(_ base: URL, values: [String: String]) -> URL { params(base.absoluteString, values: values) }
    static func itemDestination(_ item: LearningItem, courses: [LearningCourse]) -> String {
        guard (try? item.validated()) != nil else { return home }
        if allowed(item.url) { return item.url }
        return courses.first(where: { $0.key == item.courseKey && safeRead($0.url) })?.url ?? home
    }
}

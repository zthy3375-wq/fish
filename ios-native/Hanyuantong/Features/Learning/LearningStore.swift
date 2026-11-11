import Foundation
import Combine
import UIKit

struct LearningCourseSync: Codable, Equatable {
    var status: String
    var count: Int
    var at: Date
    var code: String?
}
struct LearningPlan: Codable, Equatable {
    var plannedDay: String?
    var notes = ""
    var durationMinutes = 30
    var prepared = false
}
struct LearningCache: Codable {
    var version = 1
    var account = ""
    var session = "disconnected"
    var courses: [LearningCourse] = []
    var items: [LearningItem] = []
    var notices: [LearningNotice] = []
    var selectedCourses: [String] = []
    var courseSync: [String: LearningCourseSync] = [:]
    var plans: [String: LearningPlan] = [:]
    var issues: [String: String] = [:]
    var activeCourses: [String] = []
    var activeExtras = true
    var cursor: Int?
    var updatedAt: Date?
    var examUpdatedAt: Date?
    var noticeUpdatedAt: Date?
    var lastAttempt: Date?
    var connected: Bool { !account.isEmpty && session != "disconnected" }
    var remaining: Int { cursor.map { max(0, activeCourses.count - $0) } ?? 0 }

    /// Unknown, empty and partial observations never remove successful records or infer submission.
    mutating func merge(_ incoming: [LearningItem], completeCourse: String? = nil) throws {
        guard incoming.count <= 1000 else { throw LearningError(code: "LIMIT") }
        var map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let found = Set(incoming.map(\.id))
        if let completeCourse {
            for (id, var old) in map where old.courseKey == completeCourse && old.kind == "homework" && !found.contains(id) {
                old.stale = true; map[id] = old
            }
        }
        for var value in incoming {
            _ = try value.validated()
            guard value.id == "\(value.courseId)/\(value.classId)/\(value.kind)/\(value.workId)", [value.courseId, value.classId, value.workId].allSatisfy(LearningPolicy.numeric), ["homework", "exam"].contains(value.kind), ["pending", "submitted", "closed", "unknown"].contains(value.status), value.title.count <= 200, value.timeText.count <= 1000 else { throw LearningError(code: "SCHEMA") }
            if let old = map[value.id] {
                let uncertain = (value.status == "unknown" && old.status != "unknown") || (value.deadline == nil && old.deadline != nil)
                if value.status == "unknown" { value.status = old.status; value.statusText = old.statusText }
                if value.deadline == nil { value.deadline = old.deadline }
                if value.course.isEmpty { value.course = old.course }
                if value.url.isEmpty { value.url = old.url }
                value.stale = uncertain
            }
            map[value.id] = value
        }
        guard map.count <= 2000 else { throw LearningError(code: "LIMIT") }
        items = map.values.sorted { $0.id < $1.id }
    }
    func validated(account expected: String) throws -> Self {
        guard version == 1, account == expected, account.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil, courses.count <= 200, items.count <= 2000, notices.count <= 100, plans.count <= 2000, activeCourses.count <= 200, Set(items.map(\.id)).count == items.count, Set(courses.map(\.key)).count == courses.count, cursor.map({ $0 >= 0 && $0 <= activeCourses.count }) ?? true else { throw LearningError(code: "STORAGE") }
        guard ["disconnected", "valid", "expired", "unknown"].contains(session), selectedCourses.count <= 200,
              selectedCourses.allSatisfy({ $0.range(of: "^[0-9]{1,24}/[0-9]{1,24}$", options: .regularExpression) != nil }),
              activeCourses.allSatisfy({ $0.range(of: "^[0-9]{1,24}/[0-9]{1,24}$", options: .regularExpression) != nil }),
              plans.values.allSatisfy({ $0.notes.count <= 4000 && (5...480).contains($0.durationMinutes) }),
              notices.allSatisfy({ $0.id.count <= 100 && $0.title.count <= 200 && $0.content.count <= 6000 && $0.sender.count <= 100 && $0.publishedText.count <= 100 }) else { throw LearningError(code: "STORAGE") }
        for course in courses {
            _ = try course.validated()
            guard [course.courseId, course.classId, course.cpi].allSatisfy(LearningPolicy.numeric), LearningPolicy.safeRead(course.url), course.name.count <= 200, course.teacher.count <= 150 else { throw LearningError(code: "STORAGE") }
        }
        for item in items {
            _ = try item.validated()
            guard item.id == "\(item.courseId)/\(item.classId)/\(item.kind)/\(item.workId)", [item.courseId, item.classId, item.workId].allSatisfy(LearningPolicy.numeric), ["homework", "exam"].contains(item.kind), ["pending", "submitted", "closed", "unknown"].contains(item.status), item.url.isEmpty || LearningPolicy.allowed(item.url), item.title.count <= 200, item.description.count <= 4000, item.timeText.count <= 1000 else { throw LearningError(code: "STORAGE") }
        }
        return self
    }
}

@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var cache = LearningCache()
    @Published private(set) var isBusy = false
    @Published private(set) var isOpening = false
    @Published private(set) var pauseRequested = false
    @Published var message: String?
    private var storage: ProtectedStorage?
    private let session = LearningSession()
    private var task: Task<Void, Never>?
    private var epoch = 0
    private var storageReady = false
    private var pendingCleanupAccount: String?
    var needsCleanup: Bool { pendingCleanupAccount != nil }
    var connected: Bool { cache.connected }
    /// Export only aggregate health/error codes; never identifiers, signed URLs, cookies or task content.
    var feedbackText: String {
        let payload: [String: Any] = ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "at": ISO8601DateFormatter().string(from: Date()), "session": cache.session,
            "courseCount": cache.courses.count, "taskCount": cache.items.count,
            "errorCodes": Array(Set(cache.issues.values)).sorted(),
            "syncProgress": ["planned": cache.activeCourses.count, "processed": cache.cursor ?? cache.activeCourses.count, "remaining": cache.remaining]]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    var pendingCount: Int { cache.items.filter { LearningDisplay.state($0).key == "pending" }.count }
    var blocked: Bool { isBusy || isOpening }
    var needsLogin: Bool { !connected || cache.session == "expired" || cache.issues["connection"] == "VERIFY" }
    var status: String {
        if isBusy { return "正在更新 \(cache.cursor ?? 0)/\(cache.activeCourses.count) 门课程" }
        if !connected { return "连接后查看课程作业" }
        if cache.session == "expired" { return "登录已过期，请重新连接" }
        if cache.issues["connection"] == "VERIFY" { return "需要完成官方验证，已有作业保留" }
        if cache.remaining > 0 { return "还有 \(cache.remaining) 门课程待更新" }
        if !cache.issues.isEmpty { return "部分内容未更新，已读记录保留" }
        if let updated = cache.updatedAt { return "上次更新 " + CampusTheme.date(updated, format: "MM-dd HH:mm") }
        return "选择关注课程开始同步"
    }
    init(storage: ProtectedStorage? = nil) {
        do {
            let storage = try storage ?? ProtectedStorage()
            self.storage = storage
            if let account = try session.savedAccount(), let value = try storage.read(Self.filename(account), as: LearningCache.self) {
                cache = try value.validated(account: account)
            }
            storageReady = true
        } catch { message = "本机学习通加密数据暂时无法读取。请解锁设备后重试，原记录不会被覆盖。" }
    }
    func attachPresenter(_ controller: UIViewController) { session.attachPresenter(controller) }
    private static func filename(_ account: String) -> String { "learning-" + account }
    private func persist(_ next: LearningCache) throws {
        guard storageReady, let storage, !next.account.isEmpty else { throw LearningError(code: "STORAGE") }
        _ = try next.validated(account: next.account)
        try storage.write(next, name: Self.filename(next.account))
        cache = next
    }
    private func accept(_ result: LearningSession.CourseList) throws {
        var next = cache
        if next.account != result.account {
            let oldAccount = next.account
            cache = LearningCache()
            if !oldAccount.isEmpty { try storage?.remove(Self.filename(oldAccount)) }
            next = LearningCache(); next.account = result.account
        }
        if result.complete { next.courses = result.courses; next.issues.removeValue(forKey: "courses") }
        else {
            var courses = Dictionary(uniqueKeysWithValues: next.courses.map { ($0.key, $0) })
            for course in result.courses { courses[course.key] = course }
            next.courses = courses.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            next.issues["courses"] = "COURSES_PARTIAL"
        }
        next.session = "valid"; next.lastAttempt = Date(); next.issues.removeValue(forKey: "connection")
        try persist(next)
    }
    private func ensureStorage() -> Bool {
        if storageReady { return true }
        do {
            let storage = try self.storage ?? ProtectedStorage(); self.storage = storage
            if let account = try session.savedAccount(), let saved = try storage.read(Self.filename(account), as: LearningCache.self) { cache = try saved.validated(account: account) }
            storageReady = true; return true
        } catch { message = "本机学习通加密数据暂时无法读取。请解锁设备后重试。"; return false }
    }
    private func start(_ operation: @escaping (Int) async throws -> Void) {
        guard !blocked, ensureStorage(), !needsCleanup else { return }
        epoch += 1; let token = epoch
        isBusy = true; pauseRequested = false; message = nil
        task = Task { [weak self] in
            guard let self else { return }
            do { try await operation(token) }
            catch { if token == self.epoch { self.failed(error) } }
            if token == self.epoch { self.isBusy = false; self.pauseRequested = false; self.task = nil }
        }
    }
    private func current(_ token: Int) throws { try Task.checkCancellation(); guard token == epoch else { throw LearningError(code: "CANCELLED") } }
    private func failed(_ error: Error) {
        let code = (error as? LearningError)?.code ?? (error as? LearningPartialFailure)?.code ?? (error is CancellationError ? "CANCELLED" : "NETWORK")
        let changedAccount = !cache.account.isEmpty && (try? session.account()).map { $0 != cache.account } == true
        guard code != "CANCELLED" || changedAccount else { return }
        message = LearningError(code: changedAccount ? "ACCOUNT_CHANGED" : code).localizedDescription
        if code == "ACCOUNT_CHANGED" || changedAccount {
            pendingCleanupAccount = cache.account.isEmpty ? nil : cache.account
            cache = LearningCache()
            do {
                try session.logout()
                if let account = pendingCleanupAccount { try storage?.remove(Self.filename(account)) }
                pendingCleanupAccount = nil
            } catch { message = "账号已变更，旧记录已隐藏。本机清理尚未完成，请解锁设备后重试清理。" }
            return
        }
        if !cache.account.isEmpty {
            var next = cache; next.issues["connection"] = code; next.lastAttempt = Date()
            if code == "AUTH" { next.session = "expired" }
            do { try persist(next) } catch { message = LearningError(code: "STORAGE").localizedDescription }
        }
    }
    func login() {
        start { [weak self] token in
            guard let self else { return }
            let oldAccount = self.cache.account
            let result = try await self.session.login()
            try self.current(token); try self.accept(result)
            self.message = "已连接学习通。请选择需要关注的课程。"
            if oldAccount == result.account, self.cache.cursor != nil { self.message = "验证已完成，可继续原来的更新范围。" }
        }
    }
    /// Refresh starts a new full plan; continue preserves the exact earlier scope and extras mode.
    func sync(courseKeys: [String]? = nil, resume: Bool = false) {
        guard !needsLogin else { message = "请先连接学习通或完成官方验证。"; return }
        if cache.issues["connection"] == "RATE_LIMIT", let last = cache.lastAttempt, Date().timeIntervalSince(last) < 300 { message = "平台请求较多，请稍等五分钟再试。"; return }
        start { [weak self] token in
            guard let self else { return }
            if !(resume && self.cache.cursor != nil) {
                let result = try await self.session.fetchCourses()
                try self.current(token); try self.accept(result)
                var next = self.cache
                let keys = courseKeys ?? next.selectedCourses
                let present = Set(next.courses.map(\.key))
                next.activeCourses = Array(Set(keys)).filter { present.contains($0) }.sorted()
                next.activeExtras = courseKeys == nil
                next.cursor = 0; next.lastAttempt = Date()
                try self.persist(next)
            }
            guard !self.cache.activeCourses.isEmpty else { self.message = "请先在课程管理中选择关注课程。"; return }
            while let index = self.cache.cursor, index < self.cache.activeCourses.count {
                try self.current(token)
                if self.pauseRequested { self.message = "更新已暂停，已读取记录保留。"; return }
                let key = self.cache.activeCourses[index]
                guard let course = self.cache.courses.first(where: { $0.key == key }) else { throw LearningError(code: "PLAN_EXPIRED") }
                do {
                    let parsed = try await self.session.courseWork(course)
                    try self.current(token)
                    var next = self.cache
                    try next.merge(parsed.records, completeCourse: parsed.complete ? key : nil)
                    next.courseSync[key] = LearningCourseSync(status: parsed.complete ? "ok" : "partial", count: parsed.records.count, at: Date(), code: parsed.complete ? nil : "PARTIAL")
                    if parsed.complete { next.issues.removeValue(forKey: key) } else { next.issues[key] = "PARTIAL" }
                    next.cursor = index + 1; next.updatedAt = Date(); next.issues.removeValue(forKey: "connection"); next.session = "valid"
                    try self.persist(next)
                } catch {
                    try self.current(token)
                    let code = (error as? LearningError)?.code ?? (error as? LearningPartialFailure)?.code ?? (error is CancellationError ? "CANCELLED" : "NETWORK")
                    var next = self.cache
                    if let partial = error as? LearningPartialFailure { try next.merge(partial.items) }
                    next.courseSync[key] = LearningCourseSync(status: "error", count: next.items.filter { $0.courseKey == key && $0.kind == "homework" }.count, at: Date(), code: code)
                    next.issues[key] = code
                    if ["AUTH", "ACCOUNT_CHANGED", "VERIFY", "RATE_LIMIT", "CANCELLED", "STORAGE"].contains(code) { try self.persist(next); throw LearningError(code: code) }
                    next.cursor = index + 1; try self.persist(next)
                }
                if self.cache.remaining > 0 { try await Task.sleep(nanoseconds: 4_000_000_000) }
            }
            if self.pauseRequested { self.message = "更新已暂停，已读取记录保留。"; return }
            if self.cache.activeExtras {
                do {
                    let parsed = try await self.session.exams(); try self.current(token)
                    var next = self.cache; try next.merge(parsed.records)
                    if parsed.complete { next.examUpdatedAt = Date(); next.issues.removeValue(forKey: "exams") } else { next.issues["exams"] = "EXAMS_PARTIAL" }
                    try self.persist(next)
                } catch { try self.handleExtra(error, key: "exams", token: token) }
                if self.pauseRequested { self.message = "更新已暂停，已读取记录保留。"; return }
                do {
                    let notices = try await self.session.notices(); try self.current(token)
                    var next = self.cache
                    if !notices.isEmpty || next.notices.isEmpty { next.notices = notices; next.noticeUpdatedAt = Date(); next.issues.removeValue(forKey: "notices") }
                    else { next.issues["notices"] = "EMPTY_RETAINED" }
                    try self.persist(next)
                } catch { try self.handleExtra(error, key: "notices", token: token) }
            }
            var next = self.cache; next.cursor = nil; try self.persist(next)
            self.message = next.issues.isEmpty ? "更新完成，提交状态以学习通官方页面为准。" : "本轮更新结束，未读完整的内容和原记录已保留。"
        }
    }
    private func handleExtra(_ error: Error, key: String, token: Int) throws {
        try current(token)
        let code = (error as? LearningError)?.code ?? (error is CancellationError ? "CANCELLED" : "NETWORK")
        if ["AUTH", "ACCOUNT_CHANGED", "VERIFY", "RATE_LIMIT", "CANCELLED", "STORAGE"].contains(code) { throw LearningError(code: code) }
        var next = cache; next.issues[key] = code; try persist(next)
    }
    func pause() { pauseRequested = true; message = "将在当前课程读取后暂停。" }
    func follow(_ course: LearningCourse) {
        guard !blocked else { return }
        var next = cache
        let removing = next.selectedCourses.contains(course.key)
        if removing { next.selectedCourses.removeAll { $0 == course.key } } else { next.selectedCourses.append(course.key) }
        do { try persist(next); if !removing { sync(courseKeys: [course.key]) } } catch { failed(error) }
    }
    func plan(_ item: LearningItem, value: LearningPlan) {
        guard connected, cache.items.contains(where: { $0.id == item.id }), value.notes.count <= 4000, (5...480).contains(value.durationMinutes) else { return }
        var next = cache; next.plans[item.id] = value
        do { try persist(next); message = "本机计划已保存，平台截止时间与提交状态不变。" } catch { failed(error) }
    }
    func today(_ item: LearningItem) {
        var value = cache.plans[item.id] ?? LearningPlan(); value.plannedDay = CampusTheme.date(Date(), format: "yyyy-MM-dd"); plan(item, value: value)
    }
    func openCourse(_ course: LearningCourse) {
        guard cache.courses.contains(where: { $0 == course }), let url = URL(string: course.url), LearningPolicy.safeRead(url) else { return }
        open(url, refresh: [course.key])
    }
    func openItem(_ item: LearningItem) {
        guard cache.items.contains(where: { $0.id == item.id && $0.url == item.url }) else { return }
        let detail = URL(string: item.url)
        let course = cache.courses.first { $0.key == item.courseKey }
        let target = detail.flatMap { LearningPolicy.allowed($0) ? $0 : nil } ?? course.flatMap { URL(string: $0.url) } ?? LearningPolicy.homeURL
        open(target, refresh: [item.courseKey])
    }
    func openPortal() { open(LearningPolicy.homeURL, refresh: nil) }
    private func open(_ url: URL, refresh: [String]?) {
        guard !blocked, ensureStorage(), !needsCleanup else { return }
        epoch += 1; let token = epoch; isOpening = true; message = nil
        task = Task { [weak self] in
            guard let self else { return }
            var success = false
            do { try await self.session.open(url); try self.current(token); success = true }
            catch { if token == self.epoch { self.failed(error) } }
            guard token == self.epoch else { return }
            self.isOpening = false; self.task = nil
            if success, self.connected { self.sync(courseKeys: refresh) }
        }
    }
    func logout() {
        epoch += 1; task?.cancel(); task = nil; session.cancel(); isBusy = false; isOpening = false; pauseRequested = false
        pendingCleanupAccount = pendingCleanupAccount ?? (cache.account.isEmpty ? nil : cache.account)
        cache = LearningCache()
        do {
            try session.logout()
            if let account = pendingCleanupAccount { try storage?.remove(Self.filename(account)) }
            pendingCleanupAccount = nil; message = "已退出学习通，本机学习通缓存与计划已清除。"
        } catch { message = "连接已停止，但本机清理未完成。请解锁设备后重试清理。" }
    }
}

enum LearningDisplay {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"; formatter.isLenient = false
        return formatter.date(from: value)
    }
    static func state(_ item: LearningItem, now: Date = Date()) -> (key: String, label: String) {
        let past = (date(item.deadline).map { $0 < now } ?? false) || item.statusText.range(of: "已截止|已过期|已关闭|已结束", options: .regularExpression) != nil
        switch item.status {
        case "submitted": return ("submitted", item.statusText.contains("待批阅") ? "已提交 · 待批阅" : "已提交")
        case "closed": return ("closed", item.statusText.range(of: "未交|未提交", options: .regularExpression) != nil ? "已截止 · 未提交" : "已截止 · 提交状态待核对")
        case "pending": return (past ? "closed" : "pending", past ? "未提交 · 已逾期" : (item.statusText.contains("未开始") ? "未开始" : "未提交"))
        default: return ("unknown", past ? "已截止 · 提交状态未知" : "提交状态未知")
        }
    }
    static func deadline(_ item: LearningItem) -> String {
        guard let date = date(item.deadline) else { return "截止时间待核对" }
        return CampusTheme.date(date, format: "M月d日 HH:mm") + " 截止"
    }
}

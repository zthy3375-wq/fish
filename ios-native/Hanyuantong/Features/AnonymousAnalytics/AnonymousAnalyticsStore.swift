import Foundation
import Combine

/// Opt-in state machine. New counts and identity creation occur only after a successful explicit choice.
/// Shutdown/disable never starts a replacement request. Deletes run behind the current bounded request.
@MainActor final class AnonymousAnalyticsStore: ObservableObject {
    @Published private(set) var state = AnalyticsState()
    @Published private(set) var isSending = false
    @Published private(set) var error: String?
    let unavailableReason: String?
    private let storage: AnalyticsPersisting
    private let transport: AnalyticsTransporting
    private let build: AnalyticsBuild
    private let now: () -> Date
    private let makeIdentity: () throws -> AnalyticsIdentity
    private var record = AnalyticsRecord()
    private var loaded = false
    private var deletionPersisted = false
    private var suspended = false
    private var generation = 0
    private var lastAttempt: Date?
    private var sending: Task<Void, Never>?

    init(storage: AnalyticsPersisting? = nil, transport: AnalyticsTransporting? = nil,
         build: AnalyticsBuild = .current, now: @escaping () -> Date = Date.init,
         makeIdentity: (() throws -> AnalyticsIdentity)? = nil) {
        self.storage = storage ?? AnalyticsKeychainStorage()
        self.transport = transport ?? AnalyticsHTTPTransport()
        self.build = build; self.now = now
        self.makeIdentity = makeIdentity ?? { try AnalyticsKeychainStorage.makeIdentity() }
        unavailableReason = build.unavailableReason
        do {
            if var saved = try self.storage.load() {
                guard saved.isValid else { throw AnalyticsFailure.storage }
                if saved.enrollmentInFlight { saved.enrollmentInFlight = false; saved.enrollmentUncertain = true }
                record = saved; deletionPersisted = saved.deletePending
            }
            loaded = true; publish()
        } catch {
            self.error = "统计设置暂无法安全读取，已停止采集和上报；原记录未覆盖。"
        }
        // No identity creation, writes or network access at initialization.
    }

    var canEnable: Bool { loaded && unavailableReason == nil && !record.deletePending }
    func setEnabled(_ enabled: Bool) {
        guard loaded else { return }
        if enabled {
            guard unavailableReason == nil else { self.error = unavailableReason; return }
            guard !record.deletePending else { self.error = "请先完成历史记录删除。"; return }
            do {
                var next = record
                if next.identity == nil { next.identity = try makeIdentity() }
                guard next.identity?.isValid == true else { throw AnalyticsFailure.invalid }
                next.choice = .on; next.dirty = true
                try commit(next)
                generation += 1; suspended = false; self.error = nil
                flush(force: true)
            } catch { self.error = "设置未保存，统计未开启，请重试。" }
        } else {
            // Stop immediately even if Keychain is unavailable; do not claim the preference was saved.
            generation += 1; suspended = true
            var next = record; next.choice = .off; next.dirty = false
            do { try commit(next); self.error = nil }
            catch {
                record = next; publish()
                self.error = "当前会话已停止统计，但关闭设置未能保存；请在退出 App 前重试。"
            }
        }
    }

    func recordFeature(_ feature: AnalyticsFeature) {
        guard loaded, unavailableReason == nil, !suspended, record.choice == .on, !record.deletePending else { return }
        var next = record
        let day = AnalyticsContract.day(now())
        var counters = next.counters ?? AnalyticsCounters(day: day)
        counters.increment(feature, on: day); next.counters = counters; next.dirty = true
        do { try commit(next); flush() }
        catch { suspended = true; self.error = "统计本机保存失败，已暂停采集；校园功能不受影响。" }
    }

    func deleteData() {
        guard loaded else { return }
        generation += 1; suspended = true
        var next = record
        next.choice = .off; next.counters = nil; next.dirty = false
        next.deletePending = next.identity != nil
        do {
            // Persist intent before touching the network so relaunch can retry without re-enrolling.
            try commit(next); self.error = nil
            if next.deletePending { flush(force: true) }
        } catch {
            record = next; publish()
            self.error = "已停止新采集，但删除请求未能安全保存，尚未发送；请重试。"
        }
    }

    /// Foreground retries only; no background scheduler, reachability collection or pre-consent heartbeat.
    func flush(force: Bool = false) {
        guard loaded, sending == nil else { return }
        if record.deletePending && !deletionPersisted { return }
        if !record.deletePending {
            guard unavailableReason == nil, !suspended, record.choice == .on, record.identity != nil else { return }
        }
        let timestamp = now()
        if !force, let lastAttempt, timestamp.timeIntervalSince(lastAttempt) >= 0,
           timestamp.timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = timestamp; isSending = true
        sending = Task { [weak self] in
            guard let self else { return }
            let startedForDeletion = self.record.deletePending
            await self.runOnce()
            // A delete requested during enrollment/record must not be lost to a busy flag.
            if !startedForDeletion && self.record.deletePending && self.deletionPersisted && !Task.isCancelled { await self.performDelete() }
            self.isSending = false; self.sending = nil
        }
    }

    /// Used for explicit cancellation/teardown. It cannot retract a request already accepted by the server.
    func cancelSending() { suspended = true; generation += 1; sending?.cancel() }
    func waitForIdle() async { await sending?.value }

    private func runOnce() async {
        if record.deletePending { await performDelete(); return }
        guard record.choice == .on, unavailableReason == nil, !suspended, !Task.isCancelled,
              let identity = record.identity else { return }
        let revision = generation
        let day = AnalyticsContract.day(now())
        if !record.dirty && record.sentDay == day && record.sentBuild == build.number { return }
        do {
            if !record.enrolled {
                var next = record; next.enrollmentInFlight = true
                try commit(next)
                let response: AnalyticsResponse
                do { response = try await send(.enroll, identity: identity) }
                catch {
                    markEnrollmentUncertain(identity)
                    throw error
                }
                guard record.identity == identity else { return }
                next = record; next.enrollmentInFlight = false
                if response.status == 200 && response.ok { next.enrolled = true }
                // Preserve an earlier ambiguous attempt. This endpoint has no server-side revocation tombstone.
                try commit(next)
                guard response.status == 200 && response.ok else { throw AnalyticsFailure.response }
            }
            guard revision == generation, record.choice == .on, !record.deletePending, !suspended, !Task.isCancelled else { return }
            let today = AnalyticsContract.day(now())
            let snapshot = record.counters?.day == today ? record.counters! : AnalyticsCounters(day: today)
            let response = try await send(.record, identity: identity, counters: snapshot)
            guard revision == generation, record.identity == identity, record.choice == .on, !record.deletePending, !Task.isCancelled else { return }
            if response.status == 401 || response.status == 430 {
                var next = record; next.enrolled = false; try commit(next)
                throw AnalyticsFailure.response
            }
            guard response.status == 200 && response.ok else { throw AnalyticsFailure.response }
            var next = record
            let currentDay = AnalyticsContract.day(now())
            let currentCounters = record.counters?.day == currentDay ? record.counters! : AnalyticsCounters(day: currentDay)
            next.dirty = snapshot != currentCounters
            next.sentDay = snapshot.day; next.sentBuild = build.number; next.lastSent = now()
            try commit(next); self.error = nil
        } catch {
            if !record.deletePending && record.choice == .on && !suspended {
                self.error = "统计暂未上报，已保留本机汇总；可稍后重试，校园功能不受影响。"
            }
        }
    }

    private func performDelete() async {
        guard record.deletePending, deletionPersisted, let identity = record.identity, !Task.isCancelled else { return }
        do {
            let response = try await send(.delete, identity: identity)
            guard record.identity == identity, record.deletePending, !Task.isCancelled else { return }
            guard response.status == 200 && response.ok else { throw AnalyticsFailure.response }
            if record.enrollmentUncertain || record.enrollmentInFlight {
                self.error = "删除请求已被接受，但早前连接结果不明，暂不能确认全部删除。已关闭统计并保留删除凭证，请稍后重试；不会重新注册。"
                return
            }
            var next = AnalyticsRecord(); next.choice = .off
            try commit(next); self.error = nil
        } catch {
            self.error = "已关闭统计，删除尚未确认。请求已保留，可联网后重试；不会重新注册。"
        }
    }
    private func markEnrollmentUncertain(_ identity: AnalyticsIdentity) {
        guard record.identity == identity else { return }
        var next = record; next.enrollmentInFlight = false; next.enrollmentUncertain = true
        do { try commit(next) }
        catch { record = next; publish(); suspended = true }
        // If saving failed, the previously persisted enrollmentInFlight marker still protects the next launch.
    }
    private func send(_ action: AnalyticsAction, identity: AnalyticsIdentity, counters: AnalyticsCounters? = nil) async throws -> AnalyticsResponse {
        try Task.checkCancellation()
        return try await transport.send(AnalyticsContract.request(action, identity: identity, build: build, counters: counters, now: now()))
    }
    private func commit(_ next: AnalyticsRecord) throws {
        guard next.isValid else { throw AnalyticsFailure.invalid }
        try storage.save(next); record = next; deletionPersisted = next.deletePending; publish()
    }
    private func publish() {
        state = AnalyticsState(choice: unavailableReason != nil && record.choice == .on ? .off : record.choice,
                               deletePending: record.deletePending, deletionUncertain: record.enrollmentUncertain,
                               lastSent: record.lastSent, hasIdentity: record.identity != nil)
    }
}

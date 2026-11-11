import Foundation
import Combine

/// One app-owned instance should be shared by home, profile and the wallet screen.
/// Public operations are invoked by UI actions. Initialization restores local data and retries
/// obsolete-cache cleanup; it never makes network requests.
@MainActor
final class QuzhiStore: ObservableObject {
    @Published private(set) var snapshot = QuzhiSnapshot()
    @Published private(set) var connected = false
    @Published private(set) var expired = false
    @Published private(set) var phone = ""
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published private(set) var cleanupRequired = false
    @Published private(set) var error = ""
    @Published private(set) var loginMessage = ""
    @Published private(set) var bathCode: QuzhiBathCode?
    @Published private(set) var returnedFromRecharge = false
    private var state: QuzhiState?
    private let transport: QuzhiTransport
    private let persistence: QuzhiPersistence
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let owner = UUID()
    private var generation = 0
    private var bathGeneration = 0
    private var operation: Task<Bool, Never>?
    private var rechargeScope: String?
    private static var currentOwner: UUID?
    private static var smsNext: [String: TimeInterval] = [:]
    var valid: Bool { connected && !expired }
    var balanceText: String { QuzhiProtocol.money(snapshot.wallet?.total) }

    init(transport: QuzhiTransport = QuzhiClient(), persistence: QuzhiPersistence? = nil,
         now: @escaping () -> Date = Date.init, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport; self.persistence = persistence ?? QuzhiVault(); self.now = now; self.uptime = uptime
        Self.currentOwner = owner
        restore()
    }
    deinit { operation?.cancel() }

    func restore() {
        guard !ready, !cleanupRequired, Self.currentOwner == owner else { return }
        do { publish(try persistence.restore()); ready = true; self.error = "" }
        catch { self.error = QuzhiFailure.storage.localizedDescription }
    }
    private func publish(_ next: QuzhiState?) {
        state = next; snapshot = next?.snapshot ?? QuzhiSnapshot()
        connected = next != nil; expired = next?.expired ?? false; phone = next?.session.maskedPhone ?? ""
    }
    private func check(_ token: Int) throws {
        try Task.checkCancellation()
        guard token == generation, Self.currentOwner == owner else { throw CancellationError() }
    }
    private func commit(_ next: QuzhiState, token: Int) throws {
        try check(token)
        try persistence.save(next)
        publish(next)
    }
    private func execute(_ work: @escaping @MainActor (Int) async throws -> Void) async -> Bool {
        guard Self.currentOwner == owner else { return false }
        if !ready { restore() }
        guard ready, !cleanupRequired, !busy else { return false }
        busy = true; error = ""; generation &+= 1
        let token = generation
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            var success = false
            do { try await work(token); try self.check(token); success = true }
            catch {
                if token == self.generation, Self.currentOwner == self.owner, !(error is CancellationError), !Task.isCancelled {
                    self.error = QuzhiFailure.classify(error).localizedDescription
                }
            }
            if token == self.generation, Self.currentOwner == self.owner {
                self.busy = false; self.operation = nil
            }
            return success
        }
        operation = task
        return await task.value
    }
    private func request(_ path: String, _ values: [String: String], post: Bool = false, token: Int) async throws -> Any {
        try check(token)
        let bytes = try await transport.request(path: path, values: values, post: post)
        try check(token)
        return try QuzhiProtocol.payload(bytes)
    }
    func cancel() {
        generation &+= 1; operation?.cancel(); operation = nil; busy = false
        loginMessage = ""; concealBathCode()
    }
    func concealBathCode() { bathGeneration &+= 1; bathCode = nil }
    func suspend() { cancel() }

    @discardableResult
    func sendSMS(phone: String, consent: Bool) async -> Bool {
        loginMessage = ""
        return await execute { [self] token in
            guard consent else { throw QuzhiFailure.consent }
            let phone = try QuzhiProtocol.phone(phone), time = uptime()
            Self.smsNext = Self.smsNext.filter { $0.value > time }
            if let next = Self.smsNext[phone], next > time {
                loginMessage = "请在 \(Int(ceil(next - time))) 秒后重新发送"
                throw QuzhiFailure.verify
            }
            // Reserve before the request. Failure, cancellation and reopening never reset the cooldown.
            Self.smsNext[phone] = time + 60
            var values = QuzhiProtocol.common
            values.merge(["telephone": phone, "secret": try QuzhiProtocol.smsSecret(phone), "typeId": "3", "platform": "1"]) { _, new in new }
            _ = try await request("user/verification/code/get", values, token: token)
            loginMessage = "验证码已发送，请查看短信"
        }
    }
    @discardableResult
    func login(phone: String, secret: String, mode: QuzhiLoginMode, consent: Bool) async -> Bool {
        concealBathCode(); rechargeScope = nil; returnedFromRecharge = false; loginMessage = ""
        return await execute { [self] token in
            let phone = try QuzhiProtocol.phone(phone)
            var values = QuzhiProtocol.common; values["telephone"] = phone
            if mode == .sms {
                guard consent else { throw QuzhiFailure.consent }
                guard QuzhiProtocol.matches(secret, "^[0-9]{4,8}\\z") else { throw QuzhiFailure.credentials }
                values["smsCode"] = secret; values["type"] = "5"
            } else {
                values["password"] = try QuzhiProtocol.password(secret); values["type"] = "0"; values["identifier"] = ""
            }
            let raw = try await request(mode == .sms ? "user/registerAndLogin" : "user/login", values, post: true, token: token)
            let candidate = try QuzhiProtocol.session(raw, phone: phone)
            let wallet = try QuzhiProtocol.wallet(await request("account/wallet", candidate.auth, token: token))
            var snapshot = state?.session.scope == candidate.scope ? state!.snapshot : QuzhiSnapshot()
            snapshot.wallet = wallet; snapshot.walletUpdatedAt = now(); snapshot.issues = [:]
            try commit(QuzhiState(session: candidate, snapshot: snapshot), token: token)
        }
    }
    @discardableResult
    func refresh(month requestedMonth: String) async -> Bool {
        guard valid else { return false }
        return await execute { [self] token in
            let month = try QuzhiProtocol.month(requestedMonth.isEmpty ? QuzhiProtocol.currentMonth(now()) : requestedMonth)
            guard var next = state else { throw QuzhiFailure.auth }
            next.snapshot.issues = [:]
            let auth = next.session.auth
            @MainActor func failure(_ error: Error, part: String) throws {
                try check(token)
                if error is CancellationError { throw error }
                let reason = QuzhiFailure.classify(error)
                next.snapshot.issues[part] = reason
                if reason == .auth { next.expired = true }
            }
            do {
                next.snapshot.wallet = try QuzhiProtocol.wallet(await request("account/wallet", auth, token: token))
                next.snapshot.walletUpdatedAt = now()
            } catch { try failure(error, part: "wallet") }
            if next.snapshot.school.isEmpty {
                if next.expired { next.snapshot.issues["school"] = .auth }
                else {
                    do {
                        guard let object = try await request("project/info/triple", auth, token: token) as? [String: Any] else { throw QuzhiFailure.format }
                        let name = QuzhiProtocol.text(object, "projectName")
                        guard !name.isEmpty else { throw QuzhiFailure.format }
                        next.snapshot.school = name
                    } catch { try failure(error, part: "school") }
                }
            }
            if next.expired { next.snapshot.issues["bills"] = .auth }
            else {
                do {
                    var values = auth; values["month"] = month; values["billRequestType"] = "2"
                    let bills = try QuzhiProtocol.bills(await request("order/query/account/bill/list", values, token: token))
                    next.snapshot.bills = bills.items; next.snapshot.billsTruncated = bills.truncated
                    next.snapshot.billsMonth = month; next.snapshot.billsUpdatedAt = now()
                } catch { try failure(error, part: "bills") }
            }
            if next.expired { concealBathCode(); rechargeScope = nil; publish(next) }
            try commit(next, token: token)
        }
    }
    @discardableResult
    func revealBathCode() async -> Bool {
        guard valid else { return false }
        concealBathCode(); let reveal = bathGeneration
        return await execute { [self] token in
            guard let current = state, !current.expired else { throw QuzhiFailure.auth }
            guard !current.session.accountID.isEmpty else { throw QuzhiFailure.account }
            do {
                let result = try QuzhiProtocol.bathCode(await request("account/useCode/new", current.session.auth, token: token), now: now())
                try check(token)
                guard reveal == bathGeneration else { throw CancellationError() }
                bathCode = result
            } catch {
                try check(token)
                if error as? QuzhiFailure == .auth {
                    var next = current; next.expired = true; concealBathCode(); rechargeScope = nil
                    // Do not keep showing an active session when secure persistence is unavailable.
                    publish(next)
                    try commit(next, token: token)
                }
                throw error
            }
        }
    }
    @discardableResult
    func logout() -> Bool {
        cancel(); rechargeScope = nil; returnedFromRecharge = false
        guard Self.currentOwner == owner else { return false }
        do {
            try persistence.clear(); publish(nil); ready = true; cleanupRequired = false; error = ""; return true
        } catch {
            // Hide all account data even if the OS refuses deletion; do not claim logout completed.
            publish(nil); ready = false; cleanupRequired = true
            self.error = "趣智退出尚未完成，无法清除本机数据。请解锁设备后重试清除。"
            return false
        }
    }
    /// Call only after the user accepts the account-check confirmation. This URL does not initiate payment.
    func beginRechargeHandoff() -> URL? {
        guard ready, valid, !busy, Self.currentOwner == owner else { return nil }
        concealBathCode(); returnedFromRecharge = false; error = ""
        rechargeScope = state?.session.scope
        return QuzhiProtocol.recharge
    }
    func finishRechargeHandoff(opened: Bool) {
        guard Self.currentOwner == owner else { return }
        if !opened { rechargeScope = nil; error = QuzhiFailure.noAlipay.localizedDescription }
    }
    func resumeAfterRecharge(month: String) async {
        guard let scope = rechargeScope, !busy else { return }
        rechargeScope = nil
        guard valid, state?.session.scope == scope else { return }
        returnedFromRecharge = true
        _ = await refresh(month: month)
    }
}

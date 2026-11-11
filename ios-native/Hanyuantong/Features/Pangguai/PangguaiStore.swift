import Foundation
import Combine

@MainActor
final class PangguaiStore: ObservableObject {
    @Published private(set) var snapshot = PGSnapshot()
    @Published private(set) var connected = false
    @Published private(set) var expired = false
    @Published private(set) var maskedPhone = ""
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var device: PGDevice?
    @Published var laundryQuote: PGLaundryQuote?
    @Published var waterQuote: PGWaterQuote?
    @Published var settlementQuote: PGWaterSettlement?
    @Published private(set) var smsRetryAt: Date?
    let api: PangguaiRequesting
    let persistence: PangguaiPersisting?
    let now: () -> Date
    var credentials: PGCredentials?
    var generation = UUID()
    var operation: Task<Bool, Never>?
    private var smsReservations: [String: Date] = [:]
    init(api: PangguaiRequesting = PangguaiClient(), persistence: PangguaiPersisting? = nil, now: @escaping () -> Date = Date.init) {
        self.api = api; self.now = now
        self.persistence = persistence ?? (try? PangguaiStorage())
        do {
            guard let vault = self.persistence else { throw PGFailure.storage }
            if let c = try vault.credentials() {
                let cached = try vault.snapshot(accountID: c.id) ?? PGSnapshot()
                credentials = c; snapshot = cached; publishIdentity()
            }
        } catch { message = PGFailure.storage.message }
    }
    private func publishIdentity() {
        connected = credentials != nil; expired = credentials?.expired ?? false
        maskedPhone = credentials.map { String($0.phone.prefix(3)) + "****" + String($0.phone.suffix(4)) } ?? ""
    }
    func cancelPending() {
        generation = UUID(); operation?.cancel(); operation = nil; busy = false
        laundryQuote = nil; waterQuote = nil; settlementQuote = nil
    }
    func dismissDevice() { cancelPending(); device = nil }
    func logout() {
        cancelPending()
        do { guard let p = persistence else { throw PGFailure.storage }; try p.logout(); credentials = nil; snapshot = PGSnapshot(); device = nil; publishIdentity(); message = nil }
        catch { message = PGFailure.storage.message }
    }
    func alive(_ epoch: UUID) throws {
        try Task.checkCancellation(); guard generation == epoch else { throw CancellationError() }
    }
    func authenticated() throws -> PGCredentials { guard let c = credentials, !c.expired else { throw PGFailure.auth }; return c }
    func post(_ path: String, _ fields: [String: String] = [:], epoch: UUID, token: String? = nil) async throws -> PGJSON {
        try alive(epoch)
        let auth = try token ?? authenticated().token
        let result = try await api.request(path, fields: fields, token: auth)
        try alive(epoch); return result
    }
    @discardableResult
    func perform(_ work: @escaping (UUID) async throws -> Void) async -> Bool {
        guard !busy else { return false }
        let epoch = generation; busy = true; message = nil
        let task = Task { @MainActor () -> Bool in
            do { try self.alive(epoch); try await work(epoch); try self.alive(epoch); return true }
            catch {
                guard self.generation == epoch else { return false }
                let failure = PGFailure.mapped(error)
                if [.auth, .account].contains(failure), var c = self.credentials {
                    c.expired = true
                    do { try self.persistence?.saveCredentials(c) } catch { self.message = PGFailure.storage.message }
                    self.credentials = c; self.publishIdentity()
                    self.laundryQuote = nil; self.waterQuote = nil; self.settlementQuote = nil
                }
                self.message = failure.message; return false
            }
        }
        operation = task
        let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        if generation == epoch { busy = false; operation = nil }
        return result
    }
    func save(_ next: PGSnapshot, epoch: UUID) throws {
        try alive(epoch); let c = try authenticated()
        guard let p = persistence else { throw PGFailure.storage }
        do { try p.saveSnapshot(next, accountID: c.id) } catch { throw PGFailure.storage }
        snapshot = next
    }
    func saveLaundry(_ session: PGLaundrySession, epoch: UUID) throws { var next = snapshot; next.laundry = session; try save(next, epoch: epoch) }
    func saveWater(_ session: PGWaterSession, epoch: UUID) throws { var next = snapshot; next.water = session; try save(next, epoch: epoch) }
    func sendCode(phone: String, consent: Bool) async -> Bool {
        await perform { epoch in
            guard consent else { throw PGFailure.consent }
            let number = try PangguaiProtocol.phone(phone)
            if let until = self.smsReservations[number], until > self.now() { self.smsRetryAt = until; throw PGFailure.busy }
            let until = self.now().addingTimeInterval(60)
            self.smsReservations[number] = until; self.smsRetryAt = until
            _ = try await self.post("common/sms/sendCode", ["phone":number, "template":"reg"], epoch: epoch, token: "")
            self.message = "验证码已发送。"
        }
    }
    func login(phone: String, code: String, consent: Bool) async -> Bool {
        await perform { epoch in
            guard consent else { throw PGFailure.consent }
            let number = try PangguaiProtocol.phone(phone)
            guard PangguaiProtocol.matches(code, "^[0-9]{4,8}$") else { throw PGFailure.phone }
            let result = try await self.post("user/reg", ["phone":number, "verify":code, "channel":PangguaiProtocol.channel], epoch: epoch, token: "")
            let token = try result.required("token")
            let info = try await self.post("user/info", epoch: epoch, token: token)
            let identity = try PangguaiProtocol.profile(info, expectedPhone: number)
            guard let p = self.persistence else { throw PGFailure.storage }
            var next = try p.snapshot(accountID: identity.id) ?? PGSnapshot()
            if let balance = identity.balance { next.balance = balance; next.walletUpdatedAt = self.now() }
            let c = PGCredentials(id: identity.id, phone: number, token: token)
            try self.alive(epoch)
            do { try p.saveSnapshot(next, accountID: c.id); try p.saveCredentials(c) } catch { throw PGFailure.storage }
            self.credentials = c; self.snapshot = next; self.device = nil; self.laundryQuote = nil; self.waterQuote = nil; self.settlementQuote = nil; self.publishIdentity()
        }
    }
    func refresh() async {
        await perform { epoch in
            let c = try self.authenticated(); var next = self.snapshot; next.issues = [:]
            for section in ["wallet", "tickets", "orders"] {
                do {
                    switch section {
                    case "wallet":
                        let info = try await self.post("user/info", epoch: epoch)
                        let profile = try PangguaiProtocol.profile(info, expectedPhone: c.phone)
                        guard profile.id == c.id else { throw PGFailure.account }
                        guard let balance = profile.balance else { throw PGFailure.format }
                        next.balance = balance; next.walletUpdatedAt = self.now()
                    case "tickets":
                        var tickets: [PGTicket] = []; var ids = Set<String>(); var expectedTotal: Int?
                        for page in 1...10 {
                            let data = try await self.post("tokenCoin/userTokenCoins", ["page":String(page), "pageSize":"20"], epoch: epoch)
                            let rows = try data["items"].rows()
                            guard rows.count <= 20, let total = Int(data["total"].text), total >= 0, total <= 200,
                                  expectedTotal == nil || total == expectedTotal else { throw PGFailure.partial }
                            expectedTotal = total
                            if rows.isEmpty && tickets.count < total { throw PGFailure.partial }
                            for row in rows {
                                let id = try row.required("shopId")
                                guard ids.insert(id).inserted else { throw PGFailure.partial }
                                tickets.append(PGTicket(id: id, name: try row.required("shopName"), balance: PangguaiProtocol.money(row["totalAmount"]), principal: PangguaiProtocol.money(row["principalAmount"]), gift: PangguaiProtocol.money(row["presentAmount"])))
                            }
                            if tickets.count >= total { break }
                        }
                        guard tickets.count == expectedTotal else { throw PGFailure.partial }
                        next.tickets = tickets; next.ticketsUpdatedAt = self.now()
                    default:
                        let data = try await self.post("order/list", ["page":"1", "pageSize":"20"], epoch: epoch)
                        let rows = try data["items"].rows(); guard rows.count <= 20 else { throw PGFailure.format }
                        let orders = try rows.map { row -> PGOrder in
                            let name = row["machineName"].text.isEmpty ? row["goodsName"].text : row["machineName"].text
                            let status = row["orderStatusName"].text.isEmpty ? (["0":"待支付", "1":"订单已关闭", "2":"已支付", "3":"已完成"][row["orderStatus"].text] ?? "状态待核对") : String(row["orderStatusName"].text.prefix(40))
                            return PGOrder(id: try row.required("id"), name: String(name.prefix(100)), amount: PangguaiProtocol.money(row["payPrice"]), status: status, time: String(row["createTime"].text.prefix(40)))
                        }
                        guard Set(orders.map(\.id)).count == orders.count else { throw PGFailure.partial }
                        next.orders = orders; next.ordersUpdatedAt = self.now()
                    }
                } catch {
                    try self.alive(epoch)
                    let failure = PGFailure.mapped(error); next.issues[section] = failure
                    if [.auth, .account].contains(failure) { try self.save(next, epoch: epoch); throw failure }
                }
            }
            try self.save(next, epoch: epoch)
            if !next.issues.isEmpty { self.message = PGFailure.partial.message }
        }
    }
    func readDevice(_ raw: String) async {
        await perform { epoch in
            self.device = nil; self.laundryQuote = nil; self.waterQuote = nil; self.settlementQuote = nil
            let fields = try PangguaiProtocol.deviceCode(raw)
            let scan = try await self.post("goods/scan/v2", fields, epoch: epoch)
            let id = try scan.required("id")
            let details = try await self.post("goods/normal/details", ["goodsId":id], epoch: epoch)
            let skus = try await self.post("goods/normal/skus", ["goodsId":id], epoch: epoch)
            self.device = try PGDevice.parse(scan: scan, details: details, skus: skus)
        }
    }
    /// Polling is deliberately read-only. It must never create, pay, end or start a device.
    func pollSessions() async {
        await perform { epoch in
            if let s = self.snapshot.laundry, !s.terminal { _ = try await self.readLaundry(s, epoch: epoch) }
            if let s = self.snapshot.water { _ = try await self.readWater(s, epoch: epoch) }
        }
    }
    func officialURL(merchantID: String? = nil) throws -> URL {
        var components = URLComponents(); components.scheme = "alipays"; components.host = "platformapi"; components.path = "/startapp"
        var items = [URLQueryItem(name: "appId", value: "2018072460764274")]
        if let merchantID {
            _ = try authenticated()
            guard snapshot.tickets.contains(where: { $0.id == merchantID }), PangguaiProtocol.matches(merchantID, "^[A-Za-z0-9_-]{1,128}$") else { throw PGFailure.account }
            items.append(URLQueryItem(name: "page", value: "user/recharge/buyGold/buyGold?shopId=\(merchantID)"))
        }
        components.queryItems = items
        guard let url = components.url else { throw PGFailure.format }; return url
    }
}

struct PGWaterSettlement: Identifiable, Equatable {
    var id = UUID(); var sessionID: UUID; var expiresAt: Date; var amount: String; var deviceName: String; var paymentName: String
}

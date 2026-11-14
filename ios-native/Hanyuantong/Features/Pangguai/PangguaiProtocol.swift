import Foundation
import CryptoKit

/// Value types keep credentials and server payloads inside the native boundary.
indirect enum PGJSON: Codable, Equatable, Sendable {
    case object([String: PGJSON]), array([PGJSON]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode([String: PGJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([PGJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String {
        switch self { case .string(let v): return v; case .number(let v): return NSDecimalNumber(decimal: v).stringValue
        case .bool(let v): return v ? "true" : "false"; default: return "" }
    }
    var object: [String: PGJSON]? { if case .object(let v) = self { return v }; return nil }
    var array: [PGJSON]? { if case .array(let v) = self { return v }; return nil }
    subscript(_ key: String) -> PGJSON { object?[key] ?? .null }
    var yes: Bool { ["true", "1"].contains(text) }
    func required(_ key: String) throws -> String {
        let v = self[key].text
        guard !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, v.count <= 256,
              !v.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw PGFailure.format }
        return v
    }
    func rows() throws -> [PGJSON] { guard let values = array else { throw PGFailure.format }; return values }
    func record() throws -> PGJSON { guard object != nil else { throw PGFailure.format }; return self }
}

enum PGFailure: String, Error, LocalizedError, Codable {
    case auth, account, verify, service, network, format, partial, phone, qr, device, price, priceChanged
    case busy, cancelled, quoteExpired, payChannel, deviceBusy, orderActive, orderMismatch, createUnknown
    case waterActive, waterChannel, waterUnknown, waterWait, waterOwnership, waterPhysicalEnd, waterStillActive, waterBill
    case officialRequired, storage, consent
    var errorDescription: String? { message }
    var message: String {
        switch self {
        case .auth, .account: return "胖乖登录已失效或账户不匹配，请重新连接。"
        case .verify: return "平台要求验证或稍后重试，请到官方端完成验证。"
        case .phone: return "请输入正确的手机号和短信验证码。"
        case .consent: return "请先阅读并同意胖乖用户协议与隐私政策。"
        case .qr: return "请扫描胖乖机身设备二维码。"
        case .device: return "设备信息不匹配或暂不支持，请在官方端使用。"
        case .price: return "费用信息不完整，请重新查询。"
        case .priceChanged: return "费用或计费说明发生变化，请重新核对并确认。"
        case .quoteExpired: return "确认信息已过期，请重新查询。"
        case .payChannel, .waterChannel: return "付款方式不可用或尚未开通，请在官方端核对。"
        case .deviceBusy: return "设备尚未确认就绪，请检查机门和机身提示。"
        case .orderActive: return "请先处理当前洗衣订单。"
        case .orderMismatch: return "订单与设备不一致，已停止操作，请在官方端核对。"
        case .createUnknown: return "下单结果未知，不会重复下单。请查询原订单或在官方端核对。"
        case .waterActive: return "请先处理当前接水记录。"
        case .waterUnknown: return "启动结果未知，不会重复开水。请查看机身，若已出水请按机身「结算」。"
        case .waterWait: return "设备尚未返回确定状态，请查看机身并稍后查询。"
        case .waterOwnership: return "设备会话与本次订单不一致，已停止远程操作。请核对机身。"
        case .waterPhysicalEnd: return "请按机身「结算」，确认已经停止出水后再核对。"
        case .waterStillActive: return "设备仍返回本次接水记录。请先按机身「结算」并确认停止。"
        case .waterBill: return "用水已结束，账单仍需在最近消费或官方端核对。"
        case .officialRequired: return "此步骤需要支付宝或胖乖官方端完成，返回不代表支付或设备启动成功。"
        case .format, .partial: return "本次信息不完整，已保留上次有效结果。"
        case .busy: return "正在处理，请稍候。"
        case .cancelled: return "已取消，未确认的操作请在原订单中核对。"
        case .storage: return "本机安全存储不可用，未继续操作，请稍后重试。"
        case .network: return "网络请求未完成，已保留记录。请稍后查询，勿重复付款或启动设备。"
        case .service: return "平台暂未完成请求，请稍后重试。"
        }
    }
    static func mapped(_ error: Error) -> PGFailure { (error as? PGFailure) ?? (error is CancellationError ? .cancelled : .network) }
}

enum PangguaiProtocol {
    static let version = "1.109.1"
    // Public compatibility protocol used by the existing Android client. Do not invent an iOS signature contract.
    static let channel = "android_app"
    static let paths: Set<String> = ["common/sms/sendCode", "user/reg", "user/info", "user/astrict/list", "tokenCoin/userTokenCoins", "order/list", "goods/scan/v2", "goods/normal/details", "goods/normal/skus", "trade/preview/v4", "payChannelRoute/prePay", "trade/check_device_status", "machine/sync", "trade/create", "pay/unify/pay", "order/pay_status", "machine/device_is_start", "order/detail", "payChannelRoute/againPay", "order/cancel", "payChannelRoute/afterPay", "payChannelRoute/addUserAfterPayChannel", "goods/water/unlock", "goods/water/sync", "goods/endWater", "order/afterPay/creating", "order/sync"]
    static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    static func phone(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(value, "^1[0-9]{10}$") else { throw PGFailure.phone }; return value
    }
    static func money(_ value: PGJSON) -> String? {
        guard matches(value.text, "^[0-9]{1,10}(\\.[0-9]{1,4})?$"), let n = Decimal(string: value.text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: n).stringValue
    }
    static func price(_ value: PGJSON) throws -> String {
        guard let v = money(value), let n = Decimal(string: v), n.exponent >= -2 else { throw PGFailure.price }; return v
    }
    static func amount(_ raw: String?) -> String {
        guard let raw, let value = money(.string(raw)), let n = Decimal(string: value) else { return "—" }
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN"); f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: n)) ?? "—"
    }
    static func signature(path: String, token: String, timestamp: String) throws -> String {
        guard paths.contains(path) else { throw PGFailure.format }
        let input = "appSecret=nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o=&channel=\(channel)&timestamp=\(timestamp)&token=\(token)&version=\(version)&/\(path)"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func payload(_ envelope: PGJSON) throws -> PGJSON {
        let code = envelope["code"].text
        guard ["0", "200"].contains(code) else {
            let msg = envelope["msg"].text + envelope["message"].text
            if ["2", "401"].contains(code) || matches(msg.lowercased(), "未登[录陆]|登录.*(失效|过期)|token.*(invalid|expired|过期|无效)") { throw PGFailure.auth }
            if matches(msg.lowercased(), "验证码|验证|频繁|风控|captcha|risk") { throw PGFailure.verify }
            throw PGFailure.service
        }
        return envelope["data"]
    }
    static func profile(_ data: PGJSON, expectedPhone: String? = nil) throws -> (id: String, phone: String, balance: String?) {
        let number = try phone(data.required("phone"))
        guard expectedPhone == nil || number == expectedPhone else { throw PGFailure.account }
        return (try data.required("id"), number, money(data["balance"]))
    }
    /// Decode once and never navigate the QR URL. HTTP is accepted only as inert legacy QR text.
    static func deviceCode(_ raw: String) throws -> [String: String] {
        guard (1...2048).contains(raw.utf8.count), !raw.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 || $0 == "\\" }),
              let u = URLComponents(string: raw), ["http", "https"].contains(u.scheme ?? ""), u.host == "h5.qiekj.com", u.user == nil, u.password == nil,
              u.port == nil || [80,443].contains(u.port!), ["/skip", "/pages/skip/skip"].contains(u.percentEncodedPath), u.fragment == nil else { throw PGFailure.qr }
        var fields: [String: String] = [:]
        for part in (u.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: true) {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, let k = String(pair[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                  let v = String(pair[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding, fields[k] == nil else { throw PGFailure.qr }
            fields[k] = v
        }
        let selected = fields.filter { ["NQT", "SN"].contains($0.key) }
        guard selected.count == 1, !fields.keys.contains(where: { $0.uppercased() == "IMEI" }), let value = selected.values.first,
              matches(value, "^[A-Za-z0-9_-]{4,128}$") else { throw PGFailure.qr }
        return selected
    }
    static func items(device: String, sku: String) throws -> String {
        let rows = [["goodsId": device, "skuId": sku, "amount": "1", "num": "1", "soldType": "1"]]
        return String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
    }
    static func timestamp(_ raw: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.isLenient = false
        return f.date(from: raw)
    }
}

struct PGTicket: Codable, Identifiable, Equatable { var id: String; var name: String; var balance: String?; var principal: String?; var gift: String? }
struct PGOrder: Codable, Identifiable, Equatable { var id: String; var name: String; var amount: String?; var status: String; var time: String }
struct PGSKU: Codable, Identifiable, Equatable { var id: String; var name: String; var price: String?; var feature: String; var available: Bool }
struct PGDevice: Codable, Identifiable, Equatable {
    var id: String; var name: String; var category: String; var operatorName: String; var payment: String; var issue: String
    var imei: String; var routeShopID: String; var shopID: String; var isBluetooth: String; var skus: [PGSKU]
    static func parse(scan: PGJSON, details d: PGJSON, skus: PGJSON) throws -> PGDevice {
        let id = try scan.required("id"), category = try scan.required("categoryCode")
        guard scan["type"].text == "goods", ["00", "04", "08"].contains(category), d["goodsId"].text == id, d["categoryCode"].text == category else { throw PGFailure.device }
        let rows = try skus.rows(); guard rows.count <= 40 else { throw PGFailure.format }
        let choices = try rows.map { s in PGSKU(id: try s.required("skuId"), name: String(s["name"].text.prefix(100)), price: PangguaiProtocol.money(s["price"]), feature: String(s["feature"].text.prefix(300)), available: s["scanAvailable"].yes && s["stockState"].text == "1") }
        guard Set(choices.map(\.id)).count == choices.count else { throw PGFailure.format }
        return PGDevice(id: id, name: try d.required("name"), category: category, operatorName: String(d["orgName"].text.prefix(100)), payment: d["payment"].text, issue: String(d["deviceErrorMsg"].text.prefix(150)), imei: d["imei"].text, routeShopID: scan["shopId"].text, shopID: d["shopId"].text, isBluetooth: d["isBluetooth"].text, skus: choices)
    }
}
struct PGChannel: Codable, Identifiable, Equatable { var id: String; var name: String; var available: Bool; var reason: String }
struct PGLaundryQuote: Identifiable, Equatable {
    var id = UUID(); var expiresAt: Date; var deviceID: String; var deviceName: String; var skuID: String; var program: String; var amount: String; var channels: [PGChannel]; var sessionID: UUID?
}
struct PGWaterQuote: Identifiable, Equatable {
    var id = UUID(); var expiresAt: Date; var deviceID: String; var deviceName: String; var skuID: String; var outlet: String; var feature: String; var price: String?; var paymentName: String; var remoteEnd: Bool; var canStart: Bool; var reason: String
}
struct PGLaundrySession: Codable, Identifiable, Equatable {
    var id = UUID(); var deviceID: String; var deviceName: String; var skuID: String; var program: String; var shopID: String; var amount: String
    var phase = "creating"; var orderID: String?; var orderNo: String?; var paySent = false; var cancelSent = false; var method: String?
    var updatedAt = Date(); var createSentAt = Date(); var knownOrders: [String] = []; var expectedEnd: Date?; var finishedAt: Date?; var error: PGFailure?
    var terminal: Bool { ["completed", "closed", "refunded"].contains(phase) }
    var title: String { ["creating":"下单结果待核对", "pending":"等待付款", "checking":"正在核对付款结果", "paid":"已付款，等待启动确认", "running":"洗衣中", "completed":"洗衣已完成", "closed":"订单已关闭", "refunding":"退款处理中", "refunded":"已退款"][phase] ?? "订单状态待核对" }
}
struct PGWaterSession: Codable, Identifiable, Equatable {
    var id = UUID(); var deviceID: String; var deviceName: String; var skuID: String; var outlet: String; var feature: String; var paymentName: String
    var remoteEnd: Bool; var phase = "starting"; var orderNo: String?; var orderID: String?; var updatedAt = Date(); var startedAt: Date?; var endedAt: Date?
    var amount: String?; var billPayable = false; var endSent = false; var afterPaySent = false; var settleSent = false; var deviceEnded = false; var emptyReads = 0; var endBasis: String?; var error: PGFailure?
    var terminal: Bool { ["settled", "ended_zero", "closed_unknown"].contains(phase) }
    var title: String { ["starting":"正在确认设备启动", "using":"接水中", "ending":"等待设备结束", "ended":"用水已结束，账单待核对", "settling":"用水已结束，账单待核对", "settled":"本次接水已结算", "ended_zero":"用水已结束", "closed_unknown":"接水记录已结束，账单待核对"][phase] ?? "用水状态待核对" }
}
struct PGSnapshot: Codable, Equatable {
    var balance: String?; var walletUpdatedAt: Date?; var tickets: [PGTicket] = []; var ticketsUpdatedAt: Date?
    var orders: [PGOrder] = []; var ordersUpdatedAt: Date?; var issues: [String: PGFailure] = [:]
    var laundry: PGLaundrySession?; var water: PGWaterSession?
}
struct PGCredentials: Codable, Equatable { var id: String; var phone: String; var token: String; var expired = false }

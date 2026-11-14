import Foundation
import CryptoKit
import CoreFoundation

/// Protocol parity with the shipped Android adapter. No device-control or payment endpoints.
enum QuzhiFailure: String, Error, Codable, LocalizedError {
    case phone, password, credentials, auth, verify, format, unverifiedUnits, service, month, account, network, storage, busy, request, consent, noAlipay
    var errorDescription: String? {
        switch self {
        case .phone: return "请输入正确的手机号"
        case .password: return "请输入趣智校园密码"
        case .credentials: return "账号、密码或验证码未通过验证，请检查后重试"
        case .auth: return "趣智登录已失效，请重新连接"
        case .verify: return "平台要求验证或稍后重试，请勿连续提交"
        case .format: return "平台返回的信息暂时无法识别，已保留上次数据"
        case .unverifiedUnits: return "余额单位暂无法核对，已保留上次数据"
        case .service: return "趣智未完成这次请求，请稍后重试"
        case .month: return "请选择有效月份"
        case .account: return "账号信息不完整，请重新连接趣智校园"
        case .network: return "连接趣智失败，请检查网络后重试。已保留上次数据"
        case .storage: return "无法安全读取或保存趣智数据，请解锁设备后重试"
        case .busy: return "趣智操作正在进行，请稍候"
        case .request: return "请求不受支持"
        case .consent: return "请先确认短信登录可能创建账户的提示"
        case .noAlipay: return "无法打开支付宝，请安装支付宝后重试，或在趣智官方应用中充值"
        }
    }
    static func classify(_ error: Error) -> QuzhiFailure { error as? QuzhiFailure ?? .network }
}

struct QuzhiSession: Codable, Equatable {
    let loginCode: String
    let userID: String
    let accountID: String
    let projectID: String
    let telephone: String
    var maskedPhone: String { String(telephone.prefix(3)) + "****" + telephone.suffix(4) }
    /// Token refresh must not change account ownership; delimiter ambiguity is avoided with JSON.
    var scope: String {
        let bytes = (try? JSONEncoder().encode([userID, accountID, projectID, telephone])) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    var auth: [String: String] {
        var result = QuzhiProtocol.common
        result.merge(["loginCode": loginCode, "userId": userID, "accountId": accountID,
                      "projectId": projectID, "telephone": telephone, "telPhone": telephone]) { _, new in new }
        return result.filter { !$0.value.isEmpty }
    }
}
struct QuzhiWallet: Codable, Equatable { let total: String }
struct QuzhiBill: Codable, Equatable {
    let id: String
    let date: String
    let amount: String?
    let description: String
}
struct QuzhiSnapshot: Codable, Equatable {
    var school = ""
    var wallet: QuzhiWallet?
    var walletUpdatedAt: Date?
    var bills: [QuzhiBill] = []
    var billsMonth: String?
    var billsUpdatedAt: Date?
    var billsTruncated = false
    var issues: [String: QuzhiFailure] = [:]
}
/// This value is deliberately not Codable. A use code must never enter the persistent snapshot.
struct QuzhiBathCode: Equatable {
    let code: String?
    let enabled: Bool
    let queriedAt: Date
}
struct QuzhiState {
    var session: QuzhiSession
    var snapshot: QuzhiSnapshot
    var expired = false
}
enum QuzhiLoginMode: String, CaseIterable { case password = "密码登录", sms = "短信登录" }

enum QuzhiProtocol {
    static let base = URL(string: "https://v3-api.china-qzxy.cn/")!
    static let recharge = URL(string: "alipays://platformapi/startapp?appId=2018090661238647&page=pages%2Frecharge%2Frecharge")!
    // Preserve the verified wire-contract discriminator, not the app's operating-system identity.
    // There is no verified alternate iOS API contract; the HTTP User-Agent correctly identifies iOS.
    static let common = ["phoneSystem": "android", "version": "6.5.28"]
    static let paths: Set<String> = ["user/login", "user/verification/code/get", "user/registerAndLogin", "account/wallet", "project/info/triple", "order/query/account/bill/list", "account/useCode/new"]
    static let responseLimit = 1_048_576
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    static func text(_ object: [String: Any], _ key: String) -> String {
        if let value = object[key] as? String { return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)) }
        if let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
        return ""
    }
    static func phone(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(value, "^1[3-9][0-9]{9}\\z") else { throw QuzhiFailure.phone }
        return value
    }
    static func month(_ value: String) throws -> String {
        guard matches(value, "^20[0-9]{2}-(0[1-9]|1[0-2])\\z") else { throw QuzhiFailure.month }
        return value
    }
    static func currentMonth(_ date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func password(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf16.count <= 128 else { throw QuzhiFailure.password }
        return String(md5(value).suffix(10)).uppercased()
    }
    static func smsSecret(_ value: String) throws -> String {
        let value = try phone(value)
        return md5(String(value.prefix(3)) + value.suffix(4) + "klcx")
    }
    static func payload(_ bytes: Data) throws -> Any {
        guard bytes.count <= responseLimit else { throw QuzhiFailure.format }
        var body = bytes
        if body.starts(with: [0xef, 0xbb, 0xbf]) { body.removeFirst(3) }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw QuzhiFailure.format }
        let code = text(object, "errorCode")
        let success = object["success"] as? NSNumber
        if let success, CFGetTypeID(success) == CFBooleanGetTypeID(), success.boolValue, code == "0" {
            return object["data"] ?? NSNull()
        }
        let message = text(object, "message") + text(object, "errorMessage")
        if !message.contains("签名") && (["401", "403"].contains(code) || matches(message, "未登[录陆]|请先登[录陆]|请重新登[录陆]|登录.{0,12}(过期|失效)|loginCode.{0,12}失效")) { throw QuzhiFailure.auth }
        if matches(message, "频繁|稍后|次数|验证码|验证失败") { throw QuzhiFailure.verify }
        if matches(message, "密码|账号不存在|用户不存在") { throw QuzhiFailure.credentials }
        throw QuzhiFailure.service
    }
    static func session(_ data: Any, phone input: String) throws -> QuzhiSession {
        guard let object = data as? [String: Any] else { throw QuzhiFailure.format }
        let nested = object["userAccount"] as? [String: Any]
        let account = nested ?? object
        func first(_ values: String...) -> String { values.first { !$0.isEmpty } ?? "" }
        let token = nested != nil ? text(object, "loginCode") : first(text(object, "v3LoginCode"), text(object, "loginCode"))
        let result = QuzhiSession(loginCode: token, userID: first(text(object, "userId"), text(object, "v3UserId"), text(account, "userId")),
                                  accountID: first(text(account, "accountId"), text(object, "accountId")),
                                  projectID: first(text(account, "projectId"), text(object, "projectId")), telephone: try phone(input))
        guard !result.loginCode.isEmpty, !result.userID.isEmpty, !result.projectID.isEmpty else { throw QuzhiFailure.format }
        return result
    }
    private static func amount(_ object: [String: Any], _ key: String) throws -> Decimal? {
        let raw = text(object, key)
        if raw.isEmpty { return nil }
        guard matches(raw, "^-?[0-9]{1,12}(\\.[0-9]{1,6})?\\z"), let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { throw QuzhiFailure.format }
        return amount
    }
    static func wallet(_ data: Any) throws -> QuzhiWallet {
        guard let object = data as? [String: Any] else { throw QuzhiFailure.format }
        let yuan = try amount(object, "money")
        let raw = text(object, "accountMoney")
        var milli: Decimal?
        if !raw.isEmpty {
            guard matches(raw, "^-?[0-9]{1,15}\\z"), let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { throw QuzhiFailure.format }
            milli = value / 1000
        }
        if let yuan, let milli, yuan != milli { throw QuzhiFailure.unverifiedUnits }
        guard let total = yuan ?? milli else { throw QuzhiFailure.unverifiedUnits }
        return QuzhiWallet(total: NSDecimalNumber(decimal: total).stringValue)
    }
    static func bills(_ data: Any) throws -> (items: [QuzhiBill], truncated: Bool) {
        guard let rows = data as? [Any] else { throw QuzhiFailure.format }
        let items = try rows.prefix(200).map { item -> QuzhiBill in
            guard let wrapper = item as? [String: Any], let bill = wrapper["consumeBillDTO"] as? [String: Any] else { throw QuzhiFailure.format }
            let description = [text(bill, "deviceDescription"), text(bill, "description"), "用水消费"].first { !$0.isEmpty }!
            return QuzhiBill(id: text(bill, "orderNo"), date: text(bill, "consumeDate"),
                             amount: try amount(bill, "consumeMoney").map { NSDecimalNumber(decimal: $0).stringValue }, description: description)
        }
        return (items, rows.count > 200)
    }
    static func bathCode(_ data: Any, now: Date) throws -> QuzhiBathCode {
        guard let object = data as? [String: Any] else { throw QuzhiFailure.format }
        let status = text(object, "useCodeStatus"), code = text(object, "useCode")
        guard ["0", "1"].contains(status), code.isEmpty || matches(code, "^[0-9]{8}\\z"), status != "1" || !code.isEmpty else { throw QuzhiFailure.format }
        return QuzhiBathCode(code: code.isEmpty ? nil : code, enabled: status == "1", queriedAt: now)
    }
    static func money(_ value: String?) -> String {
        guard let value, matches(value, "^-?[0-9]{1,12}(\\.[0-9]{1,6})?\\z"), let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return "—" }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 3; formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "—"
    }
}

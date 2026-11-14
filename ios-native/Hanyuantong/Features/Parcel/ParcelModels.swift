import Foundation
import CryptoKit

/// Only these fixed official destinations are offered. Android schemes are deliberately not reused.
enum ParcelProvider: String, Codable, CaseIterable, Identifiable {
    case taobao, pinduoduo
    var id: String { rawValue }
    var title: String { self == .taobao ? "淘宝 / 菜鸟" : "拼多多" }
    var parcelURL: URL {
        URL(string: self == .taobao
            ? "https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home"
            : "https://m.pinduoduo.net/mdkd/package?tab=ID_CODE")!
    }
    var identityURL: URL {
        self == .taobao ? URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")! : parcelURL
    }
    var fallbackURL: URL { self == .taobao ? identityURL : URL(string: "https://mobile.yangkeduo.com/")! }
    var accountURL: URL { URL(string: self == .taobao ? "https://m.taobao.com/" : "https://m.pinduoduo.net/")! }
}

enum ParcelFailure: Error, LocalizedError, Equatable {
    case origin, unavailable, cancelled, timeout, login, verification, unrecognized, account, storage, limit
    var errorDescription: String? {
        switch self {
        case .origin: return "这个页面不在已核验的快递范围内。请使用固定官方入口。"
        case .unavailable: return "官方页面暂时无法打开，请稍后重试或使用官方 App。"
        case .cancelled: return "已停止读取，原有取件记录未被覆盖。"
        case .timeout: return "官方页面加载超时，尚未读取到新取件码。"
        case .login: return "请在官方页面登录，再打开待取包裹页。旧登录的本机记录已隐藏。"
        case .verification: return "请在官方页面自行完成验证。不会自动处理验证码或绕过验证。"
        case .unrecognized: return "当前页面没有可安全识别的取件码。请直接在官方页面查看，不代表没有包裹。"
        case .account: return "暂时无法确认当前账号，未保存或合并取件码。可继续使用官方页面。"
        case .storage: return "本机加密存储暂时不可用，未保存新记录。请解锁设备后重试。"
        case .limit: return "页面数据超出读取限制，未替换已有记录。请在官方页面查看。"
        }
    }
}

enum ParcelPolicy {
    static func allowed(_ url: URL?, provider: ParcelProvider) -> Bool {
        guard let url else { return false }
        let raw = url.absoluteString
        guard raw.utf8.count <= 8192, !raw.contains("\\"),
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, let host = c.host?.lowercased() else { return false }
        let hosts: Set<String> = provider == .taobao
            ? ["pages-fast.m.taobao.com", "login.m.taobao.com", "login.taobao.com", "passport.taobao.com", "m.taobao.com", "h5.m.taobao.com"]
            : ["m.pinduoduo.net"]
        return hosts.contains(host)
    }
    static func readable(_ url: URL?, provider: ParcelProvider) -> Bool {
        guard allowed(url, provider: provider), let url else { return false }
        let target = provider.parcelURL
        return url.host?.lowercased() == target.host && url.path == target.path
            && !url.path.contains("%") && !url.path.contains("..")
    }
    static func authPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let text = (url.host ?? "") + url.path
        return text.range(of: "login|passport|captcha|punish|verify", options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func bounded(_ value: String, max: Int, empty: Bool = true) -> Bool {
        (empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && value.utf8.count <= max
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    static func code(_ value: String) -> Bool {
        bounded(value, max: 72, empty: false) && (2...24).contains(value.count)
            && value.range(of: "^(?=.*[0-9])[A-Za-z0-9]+(?:[-—–－ ][A-Za-z0-9]+)*$", options: .regularExpression) != nil
            && value.range(of: "^[0-9]{10,}$", options: .regularExpression) == nil
    }
    static func cookieAllowed(_ cookie: HTTPCookie, provider: ParcelProvider, now: Date = Date()) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let root = provider == .taobao ? "taobao.com" : "pinduoduo.net"
        return (domain == root || domain.hasSuffix("." + root)) && !domain.hasSuffix(".")
            && cookie.path.hasPrefix("/") && bounded(cookie.path, max: 1024)
            && bounded(cookie.name, max: 256, empty: false) && bounded(cookie.value, max: 8192)
            && (cookie.expiresDate.map { $0 > now } ?? true)
    }
    /// Stable numeric account identifiers only; never use a nickname, phone, or rotating token as a principal.
    static func account(_ cookies: [HTTPCookie], provider: ParcelProvider, now: Date = Date()) throws -> String {
        let name = provider == .taobao ? "unb" : "pdd_user_id"
        let host = provider.accountURL.host!
        let values = Set(cookies.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cookieAllowed($0, provider: provider, now: now) && $0.name == name && $0.path == "/"
                && (domain == host || ($0.domain.hasPrefix(".") && host.hasSuffix("." + domain)))
        }.map(\.value))
        guard values.count == 1, let id = values.first,
              id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil else { throw ParcelFailure.account }
        return digest(provider.rawValue + ":" + id)
    }
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func validScope(_ scope: String) -> Bool { scope.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
}

struct ParcelPickup: Codable, Equatable, Identifiable {
    var station: String
    var code: String
    var observedAt: Date
    var locallyTakenAt: Date?
    // Provisional shelf identity. This is not an order/tracking ID, and never merges across providers/accounts.
    var id: String { ParcelPolicy.digest(station + "\n" + code) }
    func validated() throws -> Self {
        guard ParcelPolicy.bounded(station, max: 360), ParcelPolicy.code(code),
              observedAt.timeIntervalSince1970.isFinite, observedAt.timeIntervalSince1970 > 0,
              locallyTakenAt.map({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 }) ?? true else { throw ParcelFailure.unrecognized }
        return self
    }
}
struct ParcelReadBatch: Decodable {
    enum Phase: String, Decodable { case partial, empty, loading, login, verify, unrecognized }
    struct Field: Decodable { let station: String; let code: String }
    let version: Int
    let provider: ParcelProvider
    let phase: Phase
    let items: [Field]
    static func decode(_ raw: String, provider: ParcelProvider) throws -> Self {
        guard raw.utf8.count <= 100_000 else { throw ParcelFailure.limit }
        let batch = try JSONDecoder().decode(Self.self, from: Data(raw.utf8))
        guard batch.version == 1, batch.provider == provider, batch.items.count <= 100,
              (batch.phase == .partial) == !batch.items.isEmpty else { throw ParcelFailure.unrecognized }
        for item in batch.items {
            guard ParcelPolicy.bounded(item.station, max: 360), ParcelPolicy.code(item.code) else { throw ParcelFailure.unrecognized }
        }
        guard Set(batch.items.map { $0.station + "\n" + $0.code }).count == batch.items.count else { throw ParcelFailure.unrecognized }
        return batch
    }
}

struct ParcelCache: Codable, Equatable {
    var provider: ParcelProvider
    var account: String
    var items: [ParcelPickup] = []
    var lastReadAt: Date?
    var lastReadWasEmpty = false
    /// A DOM view is never a full snapshot. Missing records are retained and visibly dated.
    mutating func merge(_ batch: ParcelReadBatch, account expected: String, now: Date = Date()) throws {
        guard account == expected, provider == batch.provider, ParcelPolicy.validScope(account) else { throw ParcelFailure.account }
        guard batch.phase == .partial || batch.phase == .empty else { throw ParcelFailure.unrecognized }
        _ = try validated(provider: provider, account: account)
        var next = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for field in batch.items {
            var value = ParcelPickup(station: field.station, code: field.code, observedAt: now)
            value.locallyTakenAt = next[value.id]?.locallyTakenAt
            _ = try value.validated()
            next[value.id] = value
        }
        guard next.count <= 300 else { throw ParcelFailure.limit }
        items = next.values.sorted { $0.id < $1.id }
        lastReadAt = now; lastReadWasEmpty = batch.phase == .empty
    }
    func validated(provider expectedProvider: ParcelProvider, account expected: String) throws -> Self {
        guard provider == expectedProvider, account == expected, ParcelPolicy.validScope(account), items.count <= 300,
              Set(items.map(\.id)).count == items.count,
              lastReadAt.map({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 }) ?? true else { throw ParcelFailure.storage }
        for item in items { _ = try item.validated() }
        return self
    }
}

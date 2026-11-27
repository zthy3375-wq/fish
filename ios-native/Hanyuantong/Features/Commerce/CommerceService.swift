import Foundation

struct CommerceShop: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let description: String
    let hours: String
    let phone: String
    let address: String
    let images: [String]
    let latitude: Double?
    let longitude: Double?

    var mapURL: URL? {
        let hasLocation = latitude != nil && longitude != nil
        var parts = URLComponents(string: "https://uri.amap.com/" + (hasLocation ? "marker" : "search"))
        var items = [URLQueryItem(name: "name", value: hasLocation ? name : address), URLQueryItem(name: "city", value: "邯郸")]
        if let latitude, let longitude { items.append(.init(name: "position", value: "\(longitude),\(latitude)")) }
        parts?.queryItems = items
        return parts?.url
    }
    var phoneURL: URL? {
        URL(string: "tel:" + phone.filter { $0.isASCII && ($0.isNumber || $0 == "+") })
    }
}

struct CommerceCategory: Decodable, Identifiable { let id: String; let name: String }
struct CommerceAd: Decodable, Identifiable {
    let id: String; let shopId: String; let title: String; let subtitle: String; let image: String; let endsAt: String
    var displayUntil: Date { CommerceAPI.timestamp(endsAt) ?? .distantPast }
}
struct CommerceOffer: Decodable, Identifiable {
    let id: String; let title: String; let terms: String; let endsAt: String; let soldOut: Bool
}
struct CommerceCoupon: Decodable, Identifiable {
    let id: String; let title: String; let terms: String; let shopName: String; let state: String
    let code: String?; let endsAt: String; let claimedAt: String; let usedAt: String?
    var stateLabel: String { state == "used" ? "已核销" : state == "expired" ? "已失效" : "待使用" }
}
struct CommerceCatalog: Decodable {
    let items: [CommerceShop]; let next: String?; let categories: [CommerceCategory]; let ads: [CommerceAd]; let media: [String: URL]?
}
struct CommercePage<Item: Decodable>: Decodable { let items: [Item]; let next: String?; let media: [String: URL]? }
struct CommerceProfile: Decodable {
    let role: String; let memberId: String; let verifiedStudent: Bool; let adminUrl: URL?
}
struct CommerceDetail: Decodable { let shop: CommerceShop; let offers: [CommerceOffer]; let media: [String: URL]? }
struct CommercePlacements: Decodable { let ads: [CommerceAd]; let media: [String: URL]? }
struct CommerceClaim: Decodable { let id: String }
struct CommerceFavorite: Decodable { let favorited: Bool }
struct CommerceCouponDetail: Decodable { let coupon: CommerceCoupon }
struct CommerceEmpty: Decodable {}

struct CommerceFailure: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "commerce_unavailable": return "校园周边暂未开放"
        case "not_found": return "这项内容已下架或暂不可用"
        case "session_expired": return "请先登录邯院通账号"
        case "student_verification_required": return "领取前需核验邯郸学院学生身份"
        case "sold_out": return "这张优惠券已经领完"
        case "offer_unavailable": return "这张优惠券已过期或暂停领取"
        case "too_many_requests": return "操作较频繁，请稍后重试"
        case "invalid_request": return "请核对填写内容"
        default: return "服务暂时无法连接，请稍后重试"
        }
    }
}

private final class CommerceRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct CommerceAPI {
    static let shared = CommerceAPI()
    static var serviceBase: String {
        #if DEBUG
        if let value = Bundle.main.object(forInfoDictionaryKey: "CommerceTestService") as? String,
           let url = URLComponents(string: value), url.scheme == "https", url.host != nil, url.user == nil,
           url.password == nil, url.query == nil, url.fragment == nil, url.path.hasSuffix("/v1/") {
            return value
        }
        #endif
        return "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/"
    }
    private static let publicActions: Set<String> = ["home", "catalog", "shop", "report"]
    private static let privateActions: Set<String> = ["access", "wallet", "favorites", "favorite", "shop.status", "coupon", "claim", "metrics"]
    private let vault: TreeholeTokenVault
    private let session: URLSession

    init(vault: TreeholeTokenVault = TreeholeKeychain(), session: URLSession? = nil) {
        self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: config, delegate: CommerceRedirectGuard(), delegateQueue: nil)
    }

    func request<T: Decodable>(_ action: String, _ values: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let isPublic = Self.publicActions.contains(action)
        guard isPublic || Self.privateActions.contains(action) else { throw CommerceFailure(code: "invalid_request") }
        let endpoint = Self.serviceBase + "commerce."
        guard let url = URL(string: endpoint + action) else { throw CommerceFailure(code: "invalid_request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: values.merging(["platform": "ios"]) { _, platform in platform })
        if !isPublic {
            guard let token = try vault.read(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw CommerceFailure(code: "session_expired")
            }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            throw CommerceFailure(code: body?["error"] ?? "temporarily_unavailable")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func label(_ value: String) -> String {
        guard let time = timestamp(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: time)
    }
}

@MainActor final class CommerceMetrics {
    static let shared = CommerceMetrics()
    private var events: [String: [String: String]] = [:]
    private var sent: Set<String> = []
    private var day = ""
    private var pending: Task<Void, Never>?

    func add(_ kind: String, _ id: String) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if today != day { day = today; sent.removeAll(); events.removeAll() }
        let key = kind + id
        guard !sent.contains(key), events[key] == nil, events.count < 36 else { return }
        events[key] = ["kind": kind, "id": id]
        if pending == nil { schedule() }
    }
    private func schedule() {
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            let batch = Array(events.prefix(12))
            for (key, _) in batch { events.removeValue(forKey: key); sent.insert(key) }
            if sent.count > 256 { sent.removeAll(keepingCapacity: true) }
            pending = nil
            if !events.isEmpty { schedule() }
            guard !batch.isEmpty else { return }
            let _: CommerceEmpty? = try? await CommerceAPI.shared.request("metrics", ["events": batch.map { $0.value }])
        }
    }
}

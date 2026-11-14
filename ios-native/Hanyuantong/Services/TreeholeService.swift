import Foundation
import Security

struct TreeholeMember: Codable, Equatable {
    let id: String, username: String, nickname: String, role: String
    let bannedUntil: String?
}
struct TreeholeAuthor: Codable, Equatable { let name: String; let anonymous: Bool, mine: Bool }
struct TreeholePost: Codable, Identifiable, Equatable {
    let id: String, body: String, createdAt: String
    let anonymous: Bool, locked: Bool, liked: Bool, saved: Bool
    let author: TreeholeAuthor
    let commentCount: Int, likeCount: Int
}
struct TreeholeComment: Codable, Identifiable, Equatable {
    let id: String, postId: String, body: String, createdAt: String
    let replyTo: String?
    let author: TreeholeAuthor
    let deleted: Bool, isOriginalPoster: Bool
}
struct TreeholeReport: Codable, Identifiable {
    let id: String, postId: String, reason: String, body: String, createdAt: String
    let commentId: String?
}
struct TreeholeEnvelope: Decodable {
    var user: TreeholeMember?; var post: TreeholePost?; var comment: TreeholeComment?
    var posts: [TreeholePost]?; var comments: [TreeholeComment]?; var reports: [TreeholeReport]?
    var next: [String: String]?; var recoveryCode: String?
    var registrationEnabled: Bool?; var requiresInvite: Bool?
    // Native transport strips this before returning to the view model.
    var sessionToken: String?; var error: String?
}
struct TreeholeError: LocalizedError {
    let code: String
    var errorDescription: String? {
        ["session_expired": "请登录邯院通账号", "invalid_credentials": "账号、密码或恢复码不正确",
         "username_unavailable": "这个登录账号已被使用，请换一个", "invalid_username": "账号需以字母开头，使用 4–24 位字母、数字或下划线",
         "password_length": "密码需为 10–128 位", "invalid_request": "请检查填写内容和字数", "agreement_required": "请先同意树洞规则",
         "registration_closed": "树洞注册暂未开放", "invite_invalid": "内测邀请码不正确", "too_many_requests": "操作较频繁，请稍后重试",
         "posting_too_fast": "发言较频繁，请休息一会儿", "account_muted": "账号暂时禁言，可以继续浏览", "not_found": "内容已删除、已隐藏或暂时不可用",
         "forbidden": "你没有这项操作权限", "post_locked": "这条讨论已暂停回复", "reply_unavailable": "回复目标已删除，请重新选择",
         "request_conflict": "这次提交的内容已变化，请重新打开编辑", "secure_storage_failed": "无法安全保存登录状态，请重试"] [code]
        ?? "树洞连接暂时不可用，请稍后重试"
    }
}
protocol TreeholeTokenVault { func read() throws -> String?; func save(_ value: String) throws; func clear() throws }
final class TreeholeKeychain: TreeholeTokenVault {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.handancampus.treehole.v1", kSecAttrAccount as String: "session"] }
    func read() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw TreeholeError(code: "secure_storage_failed") }
        return value
    }
    func save(_ value: String) throws {
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound, SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw TreeholeError(code: "secure_storage_failed") }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TreeholeError(code: "secure_storage_failed") }
    }
}
private final class TreeholeRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor TreeholeService {
    static let actions: Set<String> = ["config", "register", "login", "recover", "me", "logout", "profile.update", "password.change", "account.delete", "posts.list", "posts.get", "posts.create", "posts.delete", "comments.create", "comments.delete", "reactions.set", "reports.create", "blocks.set", "blocks.clear", "admin.reports", "admin.resolve"]
    private let vault: TreeholeTokenVault
    private let session: URLSession
    private var generation = 0
    init(vault: TreeholeTokenVault = TreeholeKeychain(), session: URLSession? = nil) {
        self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: config, delegate: TreeholeRedirectGuard(), delegateQueue: nil)
    }
    static func validToken(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil }
    func request(_ action: String, _ body: [String: Any] = [:]) async throws -> TreeholeEnvelope {
        guard Self.actions.contains(action) else { throw TreeholeError(code: "invalid_request") }
        let authenticating = ["register", "login", "recover"].contains(action)
        if authenticating || action == "logout" { generation += 1 }
        let expected = generation
        let token = try vault.read().flatMap { Self.validToken($0) ? $0 : nil }
        if action == "logout" { try vault.clear() }
        if !authenticating && action != "config" && action != "logout" && token == nil { throw TreeholeError(code: "session_expired") }
        let endpoint = URL(string: "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/\(action)")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = action == "config" ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !authenticating { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if action != "config" {
            let data = try JSONSerialization.data(withJSONObject: body)
            guard data.count <= 20000 else { throw TreeholeError(code: "invalid_request") }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard generation == expected else { throw CancellationError() }
            guard data.count <= 2_000_000, let http = response as? HTTPURLResponse else { throw TreeholeError(code: "invalid_response") }
            var result = try JSONDecoder().decode(TreeholeEnvelope.self, from: data)
            guard (200..<300).contains(http.statusCode) else {
                if result.error == "session_expired" { try vault.clear() }
                throw TreeholeError(code: result.error ?? "temporarily_unavailable")
            }
            if authenticating {
                guard let next = result.sessionToken, Self.validToken(next), result.user != nil else { throw TreeholeError(code: "invalid_response") }
                try vault.save(next)
            }
            if action == "account.delete" { generation += 1; try vault.clear() }
            result.sessionToken = nil
            return result
        } catch {
            if action == "logout" { return TreeholeEnvelope() }
            throw error
        }
    }
}

// UTC API timestamps are displayed in campus time; cursor strings remain unmodified.
enum TreeholePresentation {
    static func date(_ value: String) -> String {
        let reader = ISO8601DateFormatter(); reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = reader.date(from: value)
        if parsed == nil { reader.formatOptions = [.withInternetDateTime]; parsed = reader.date(from: value) }
        guard let parsed else { return "时间未知" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: parsed)
    }
}

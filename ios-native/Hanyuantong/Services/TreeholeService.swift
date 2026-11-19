import Foundation
import Security
import CryptoKit

struct ContestIdentity: Codable, Equatable {
    struct Badge: Codable, Equatable { let code: String }
    let official: Badge?
}
struct TreeholeMember: Codable, Equatable {
    var badges: ContestIdentity? = nil
    let id: String, username: String, nickname: String, role: String
    let bannedUntil: String?
    var bio: String? = nil
    var avatar: TreeholeImage? = nil
}
struct TreeholeAuthor: Codable, Equatable { let name: String; let anonymous: Bool, mine: Bool; var id: String? = nil; var avatar: TreeholeImage? = nil }
struct TreeholeImage: Codable, Identifiable, Equatable { let id: String; var url: String? = nil; let width: Int; let height: Int }
struct TreeholePost: Codable, Identifiable, Equatable {
    let id: String, body: String, createdAt: String
    let anonymous: Bool, locked: Bool
    var liked: Bool, saved: Bool
    var author: TreeholeAuthor
    let commentCount: Int
    var likeCount: Int
    var title: String? = nil
    var category: String? = nil
    var interest: String? = nil
    var images: [TreeholeImage]? = nil
    var watching: Bool? = nil
    var newReplyCount: Int? = nil
    var myResponse: String? = nil
    var responseCounts: [String: Int]? = nil
    var buddy: TreeholeBuddy? = nil
    var poll: TreeholePoll? = nil
    var displayBody: String { poll != nil && body == "[投票] " + poll!.question ? "" : body }
}
struct TreeholeComment: Codable, Identifiable, Equatable {
    let id: String, postId: String, body: String, createdAt: String
    let replyTo: String?
    var author: TreeholeAuthor
    let deleted: Bool, isOriginalPoster: Bool
    var rootId: String? = nil
    var likeCount: Int? = nil
    var liked: Bool? = nil
    var replyCount: Int? = nil
    var replies: [TreeholeComment]? = nil
    var images: [TreeholeImage]? = nil
    var displayBody: String { body == "[图片]" && !(images ?? []).isEmpty ? "" : body }
}
struct TreeholeReport: Codable, Identifiable {
    let id: String, postId: String, reason: String, body: String, createdAt: String
    let commentId: String?
}
struct TreeholeNotification: Codable, Identifiable, Equatable {
    let id: String, kind: String, postId: String, postTitle: String, excerpt: String, createdAt: String
    let commentId: String?, rootId: String?
    let actor: TreeholeAuthor
    var readAt: String?
    var label: String { ["buddy": "招募状态有更新", "reply": "回复了你", "post_reply": "评论了你的帖子", "thread_reply": "更新了你关注的讨论", "post_like": "赞了你的帖子", "comment_like": "赞了你的回复", "post_response": "回应了你的帖子"][kind] ?? "有新的互动" }
}
struct TreeholePublicProfile: Codable, Equatable { let id: String, nickname: String, bio: String; let postCount: Int; var following: Bool? = nil; var avatar: TreeholeImage? = nil }
struct TreeholeFollow: Codable, Identifiable, Equatable { let id: String, nickname: String, bio: String, followedAt: String; var avatar: TreeholeImage? = nil }
struct TreeholeEnvelope: Decodable {
    var schema: Int?
    var myEntries: [NativeContestEntry]?
    var contestsEnabled: Bool?
    var contests: [NativeContest]?
    var contest: NativeContest?
    var entries: [NativeContestEntry]?
    var entry: NativeContestEntry?
    var serverTime: String?
    var votesUsed: Int?
    var stats: NativeContestStats?
    var awards: [NativeContestAward]?
    var worn: String?
    var annual: [Int]?
    var themes: [NativeContestTheme]?
    var solicitation: Bool?
    var leaders: [NativeContestLeader]?
    var votes: [NativeContestVote]?
    var audit: [NativeContestAudit]?
    var metrics: [String: Int]?
    var contestReports: [NativeContestReport]?

    var buddiesEnabled: Bool?; var participants: [TreeholeBuddyMember]?
    var pollsEnabled: Bool?; var commentImagesEnabled: Bool?
    var followingEnabled: Bool?; var following: [TreeholeFollow]?
    var image: TreeholeImage?; var imagesEnabled: Bool?
    var user: TreeholeMember?; var post: TreeholePost?; var comment: TreeholeComment?
    var posts: [TreeholePost]?; var comments: [TreeholeComment]?; var reports: [TreeholeReport]?
    var next: [String: String]?; var recoveryCode: String?
    var registrationEnabled: Bool?; var requiresInvite: Bool?
    var discoveryEnabled: Bool?
    var avatarsEnabled: Bool?; var responsesEnabled: Bool?
    var engagementEnabled: Bool?; var unreadCount: Int?; var notifications: [TreeholeNotification]?
    var context: TreeholeComment?; var focusCommentId: String?; var profile: TreeholePublicProfile?
    // Native transport strips this before returning to the view model.
    var sessionToken: String?; var error: String?
}
struct TreeholeError: LocalizedError {
    let code: String
    var errorDescription: String? {
        ["contest_conflict":"作品或赛事已有更新，请重新打开后编辑", "contests_unavailable":"主题赛事尚未启用", "contest_closed":"当前阶段已关闭或已暂停，请刷新赛事", "contest_entry_limit":"已达到本场投稿数量上限", "contest_vote_limit":"票数已用完，可先撤回其他作品的票", "contest_self_vote":"请给其他同学的作品投票", "contest_ineligible":"账号注册时间未达到投票要求", "contest_review_pending":"请先复核异常票", "contest_format":"作品类型不符合本场规则", "contest_rules_locked":"规则已固定，可延长尚未结束的阶段", "buddy_time": "请选择未来 90 天内的活动时间", "buddy_full": "已经招满了，可以稍后再看看", "buddy_closed": "已停止报名，仍可在帖子下继续交流", "buddy_host": "发起人不占报名名额", "poll_closed": "投票已结束", "following_limit": "关注已达到上限，请先整理关注名单", "invalid_image": "图片暂不支持，请换一张照片或截图", "image_too_large": "图片较大，请缩小后重试", "image_unavailable": "图片已过期，请重新添加", "upload_limit": "今天上传的图片较多，请明天再试", "images_unavailable": "图片服务暂不可用", "session_expired": "请登录邯院通账号", "invalid_credentials": "账号、密码或恢复码不正确",
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
    static let actions: Set<String> = ["contests.image", "contests.list", "contests.get", "contests.entries", "contests.submit", "contests.withdraw", "contests.vote", "contests.profile", "contests.wear", "contests.year", "contests.themes", "contests.suggest", "contests.themevote", "contests.report", "contests.admin", "contests.save", "contests.manage", "contests.review", "config", "register", "login", "recover", "me", "logout", "profile.update", "password.change", "account.delete", "posts.list", "posts.get", "posts.create", "posts.delete", "comments.create", "comments.delete", "reactions.set", "reports.create", "blocks.set", "blocks.clear", "admin.reports", "admin.resolve", "media.upload", "media.discard", "media.url", "comments.replies", "comments.like", "comments.context", "threads.watch", "notifications.list", "notifications.unread", "notifications.read", "profile.get", "avatar.set", "responses.set", "follows.set", "follows.list", "polls.vote", "buddies.join", "buddies.close", "buddies.members"]
    private let vault: TreeholeTokenVault
    private let session: URLSession
    private var generation = 0
    private var contestRevision = 0
    private var contestListCache: [String: (at: Date, result: TreeholeEnvelope)] = [:]
    init(vault: TreeholeTokenVault = TreeholeKeychain(), session: URLSession? = nil) {
        self.vault = vault
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: config, delegate: TreeholeRedirectGuard(), delegateQueue: nil)
    }
    static func validToken(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil }
    func request(_ action: String, _ body: [String: Any] = [:]) async throws -> TreeholeEnvelope {
        try Task.checkCancellation()
        guard Self.actions.contains(action) else { throw TreeholeError(code: "invalid_request") }
        let authenticating = ["register", "login", "recover"].contains(action)
        if authenticating || action == "logout" { generation += 1; contestListCache.removeAll() }
        let expected = generation
        let token = try vault.read().flatMap { Self.validToken($0) ? $0 : nil }
        if action == "logout" { try vault.clear() }
        if !authenticating && action != "config" && action != "logout" && token == nil { throw TreeholeError(code: "session_expired") }
        let contestRead = ["contests.list","contests.get","contests.entries","contests.profile","contests.year","contests.themes","contests.admin"].contains(action)
        let contestWrite = action.hasPrefix("contests.") && !contestRead && action != "contests.image"
        if contestWrite { contestRevision += 1; contestListCache.removeAll() }
        let expectedRevision = contestRevision
        var cacheKey = ""
        if contestRead {
            let fingerprint = SHA256.hash(data: Data((token ?? "").utf8)).map { String(format: "%02x", $0) }.joined()
            let cacheBody = body.filter { $0.key != "_fresh" }
            cacheKey = String(generation) + action + String(contestRevision) + fingerprint + (try JSONSerialization.data(withJSONObject: cacheBody, options: [.sortedKeys])).base64EncodedString()
            if body["_fresh"] as? Bool != true, let cached = contestListCache[cacheKey] {
                let age = Date().timeIntervalSince(cached.at)
                if age >= 0 && age < (["contests.list","contests.profile","contests.year"].contains(action) ? 120 : 15) {
                    var result = cached.result
                    if let time = result.serverTime.flatMap(NativeContest.date) { result.serverTime = ISO8601DateFormatter().string(from: time.addingTimeInterval(age)) }
                    return result
                }
            }
        }
        let endpoint = URL(string: "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/\(action)")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = action == "config" ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !authenticating { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if action != "config" {
            let data = try JSONSerialization.data(withJSONObject: body)
            guard data.count <= (action == "media.upload" ? 1_650_000 : 20000) else { throw TreeholeError(code: "invalid_request") }
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
            if contestRead {
                guard expectedRevision == contestRevision else { throw CancellationError() }
                if contestListCache.count >= 16 { contestListCache.removeAll() }
                contestListCache[cacheKey] = (Date(), result)
            } else if ["contests.submit","contests.withdraw","contests.vote","contests.save","contests.manage","contests.review","contests.wear","contests.suggest","contests.themevote","contests.report"].contains(action) || authenticating || action == "logout" || action == "account.delete" {
                if contestWrite { contestRevision += 1 }; contestListCache.removeAll()
            }
            return result
        } catch {
            if action == "logout" { return TreeholeEnvelope() }
            throw error
        }
    }
}

// UTC API timestamps are displayed in campus time; cursor strings remain unmodified.
enum TreeholePresentation {
    static func date(_ value: String, now: Date = Date()) -> String {
        let reader = ISO8601DateFormatter(); reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = reader.date(from: value)
        if parsed == nil { reader.formatOptions = [.withInternetDateTime]; parsed = reader.date(from: value) }
        guard let parsed else { return "时间未知" }
        let elapsed = now.timeIntervalSince(parsed)
        if elapsed >= 0 && elapsed < 60 { return "刚刚" }
        if elapsed >= 60 && elapsed < 3600 { return "\(Int(elapsed / 60)) 分钟前" }
        if elapsed >= 3600 && elapsed < 86400 { return "\(Int(elapsed / 3600)) 小时前" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: parsed)
    }
}

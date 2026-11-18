import Foundation
import Combine

@MainActor final class TreeholeStore: ObservableObject {
    @Published var honorsEnabled=false
    @Published var messageUnread:Int?
    @Published var messagesEnabled=false
    @Published var boardsEnabled=false
    @Published var responseKinds=["same","hug","useful"]
    @Published var moderationEnabled=false
    @Published var user: TreeholeMember?
    @Published var posts: [TreeholePost] = []
    @Published var current: TreeholePost?
    @Published var detailLoading = false
    @Published var detailError: String?
    private var detailRequest = 0
    @Published var comments: [TreeholeComment] = []
    @Published var reports: [TreeholeReport] = []
    @Published var busy = false
    @Published var ready = false
    @Published var registration = false
    @Published var requiresInvite = false
    @Published var message: String?
    @Published var recovery: String?
    @Published var category = "all"
    @Published var interest = ""
    @Published var followingEnabled = false
    @Published var following: [TreeholeFollow] = []
    @Published var followingNext: [String: String]?
    @Published var followingLoading = false
    @Published var followingError: String?
    @Published var pendingFollows: Set<String> = []
    var followingRetryMore = false
    private var followingRevision = 0
    private var followStates: [String: Bool] = [:]
    @Published var discoveryEnabled = false
    @Published var sort = "latest"
    @Published var imagesEnabled = false
    @Published var avatarsEnabled = false
    @Published var buddiesEnabled = false
    @Published var pendingBuddies: Set<String> = []
    private var buddySnapshots: [String: TreeholeBuddy] = [:]
    @Published var pollsEnabled = false
    @Published var commentImagesEnabled = false
    @Published var pendingVotes: Set<String> = []
    private var pollSnapshots: [String: TreeholePoll] = [:]
    @Published var responsesEnabled = false
    @Published var pendingResponses: Set<String> = []
    private var responseSnapshots: [String: TreeholePost] = [:]
    @Published var engagementEnabled = false
    @Published var unreadCount = 0
    @Published var notifications: [TreeholeNotification] = []
    @Published var inboxFilter = "all"
    @Published var inboxLoading = false
    @Published var inboxError: String?
    @Published var inboxNext: [String: String]?
    @Published var publicProfile: TreeholePublicProfile?
    @Published var profilePosts: [TreeholePost] = []
    @Published var profileNext: [String: String]?
    @Published var focusedThread: TreeholeComment?
    @Published var watchPending = false
    private var inboxRevision = 0
    private var unreadBusy = false
    @Published var expandedReplies: Set<String> = []
    @Published var replyPages: [String: [String: String]] = [:]
    @Published var scope = "all"
    @Published var query = ""
    @Published var feedLoadingMore = false
    @Published var feedPageError: String?
    @Published var feedRevision = 0
    var feedNeedsRefresh = false
    private var loadedFeedIdentity: [String: String]?
    private var lastAutomaticCursor = ""
    @Published var feedNext: [String: String]?
    @Published var commentNext: [String: String]?
    @Published var pendingReactions: Set<String> = []
    @Published var pendingCommentLikes: Set<String> = []
    @Published var loadingThreads: Set<String> = []
    private var loadedThreads: Set<String> = []
    private var epoch = 0
    private var discussion = 0
    let api: TreeholeService
    init(api: TreeholeService = TreeholeService()) { self.api = api }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; message = nil
        Task { defer { busy = false }; do { try await work() } catch is CancellationError { } catch {
            if let e = error as? TreeholeError, e.code == "session_expired" { clear() }
            message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
        } }
    }
    func applyIdentity(_ h: NativeHonorHall) {
        applyBadges(h.id,h.badges,h.showcase)
    }
    func applyBadges(_ id:String,_ badges:MemberBadges,_ pins:[String]) {
        if user?.id == id { user?.badges=badges; user?.showcase=pins }
        if publicProfile?.id == id { publicProfile?.badges=badges; publicProfile?.showcase=pins }
        func update(_ a: inout TreeholeAuthor) { if !a.anonymous && a.id == id { a.badges=badges } }
        for i in posts.indices { update(&posts[i].author) }; for i in profilePosts.indices { update(&profilePosts[i].author) }
        if current != nil { update(&current!.author) }; for i in comments.indices { update(&comments[i].author) }
        feedNeedsRefresh=true
    }
    func clear() { messageUnread=nil; MedalJournal.shared.clearCommunityNotices(); pendingBuddies = []; buddySnapshots = [:]; pendingVotes = []; pollSnapshots = [:]; followingRevision += 1; following = []; followingNext = nil; followingLoading = false; followingError = nil; pendingFollows = []; followStates = [:]; followingRetryMore = false; pendingResponses = []; responseSnapshots = [:]; leaveDetail(); epoch += 1; inboxRevision += 1; notifications = []; unreadCount = 0; inboxNext = nil; inboxLoading = false; inboxError = nil; publicProfile = nil; profilePosts = []; profileNext = nil; watchPending = false; feedRevision += 1; feedLoadingMore = false; feedPageError = nil; loadedFeedIdentity = nil; lastAutomaticCursor = ""; feedNeedsRefresh = false; pendingReactions = []; pendingCommentLikes = []; loadingThreads = []; loadedThreads = []; user = nil; posts = []; current = nil; comments = []; reports = []; recovery = nil; scope = "all"; query = ""; category = "all"; interest = ""; sort = "latest"; expandedReplies = []; replyPages = [:]; feedNext = nil; commentNext = nil }
    func restoreCachedIdentity() async {
        guard !ready, !busy, user == nil else { return }
        let old=epoch
        if let cached=await api.cachedIdentity(), old == epoch, !ready, !busy, user == nil { user=cached }
    }
    func enter() {
        perform {
            do {
                let entry=try await self.api.request("me",["entry":true])
                if let config=entry.config?.value { self.applyConfiguration(config) }
                else { self.applyConfiguration(try await self.api.request("config")) }
                self.user=entry.user
                if let firstPage=entry.posts {
                    self.rememberResponses(firstPage); self.posts=firstPage.map(self.restorePoll)
                    self.feedNext=entry.next; self.loadedFeedIdentity=self.feedIdentity; self.feedNeedsRefresh=false
                } else { try await self.feed() }
            } catch let failure as TreeholeError where failure.code == "session_expired" {
                self.clear()
                self.applyConfiguration(try await self.api.request("config"))
            }
            self.ready = true
            await self.refreshUnread()
        }
    }
    private func applyConfiguration(_ config:TreeholeEnvelope) {
        self.boardsEnabled=config.boardsEnabled == true; self.responseKinds=config.responseKinds ?? ["same","hug","useful"]
        self.honorsEnabled = config.honorsEnabled == true; self.messagesEnabled = config.messagesEnabled == true; self.moderationEnabled = config.moderationEnabled == true
        self.registration = config.registrationEnabled == true; self.requiresInvite = config.requiresInvite == true; self.imagesEnabled = config.imagesEnabled == true
        self.engagementEnabled = config.engagementEnabled == true; self.pollsEnabled = config.pollsEnabled == true; self.buddiesEnabled = config.buddiesEnabled == true; self.commentImagesEnabled = config.commentImagesEnabled == true
        self.followingEnabled = config.followingEnabled == true; self.discoveryEnabled = config.discoveryEnabled == true; self.avatarsEnabled = config.avatarsEnabled == true; self.responsesEnabled = config.responsesEnabled == true
    }
    private var feedIdentity: [String: String] { ["scope": scope, "query": query, "sort": sort].merging(TreeholeCategories.filters(category, interest: interest, enabled: discoveryEnabled)) { _, new in new } }
    func selectDiscovery(_ selected: String, interest selectedInterest: String = "") async throws {
        let old = (category, interest, scope), generation = epoch
        category = selected; interest = selectedInterest; if scope != "following" { scope = "all" }
        let requested = feedIdentity
        do { try await feed() } catch {
            if generation == epoch, feedIdentity == requested { category = old.0; interest = old.1; scope = old.2 }
            throw error
        }
    }
    func selectScope(_ selected: String) async throws {
        let old = (scope, query, category, interest, sort), generation = epoch
        scope = selected; query = ""; category = "all"; interest = ""; sort = "latest"
        let requested = feedIdentity
        do { try await feed() } catch {
            if generation == epoch, feedIdentity == requested { scope = old.0; query = old.1; category = old.2; interest = old.3; sort = old.4 }
            throw error
        }
    }
    func didBlockPublicAuthor(_ id: String) {
        followStates[id] = false; followingRevision += 1; followingLoading = false
        following.removeAll { $0.id == id }
        if publicProfile?.id == id { publicProfile?.following = false }
    }
    func restoreProfile(_ profile: TreeholePublicProfile) -> TreeholePublicProfile {
        var result = profile
        if let state = followStates[profile.id] { result.following = state }
        return result
    }
    func loadFollowing(more: Bool = false) async {
        guard followingEnabled, !followingLoading, !more || followingNext != nil else { return }
        let generation = epoch; followingRevision += 1; let revision = followingRevision
        followingLoading = true; followingError = nil; followingRetryMore = more
        defer { if generation == epoch, revision == followingRevision { followingLoading = false } }
        do {
            let r = try await api.request("follows.list", more ? followingNext ?? [:] : [:])
            guard generation == epoch, revision == followingRevision else { return }
            var ids = Set(following.map(\.id))
            following = more ? following + (r.following ?? []).filter { ids.insert($0.id).inserted } : r.following ?? []
            followingNext = r.next
        } catch {
            guard generation == epoch, revision == followingRevision else { return }
            if let e = error as? TreeholeError, e.code == "session_expired" { clear(); message = e.errorDescription }
            else { followingError = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试" }
        }
    }
    func setFollow(_ id: String, enabled: Bool) async {
        guard followingEnabled, !pendingFollows.contains(id), id != user?.id else { return }
        let generation = epoch; message = nil; pendingFollows.insert(id)
        defer { if generation == epoch { pendingFollows.remove(id) } }
        do {
            let r = try await api.request("follows.set", ["memberId": id, "enabled": enabled])
            guard generation == epoch else { return }
            followStates[id] = enabled
            if publicProfile?.id == id { if let profile = r.profile { publicProfile = profile }; publicProfile?.following = enabled }
            followingRevision += 1; followingLoading = false
            if !enabled { following.removeAll { $0.id == id } }
            if scope == "following" {
                feedRevision += 1; feedLoadingMore = false; feedNext = nil; feedNeedsRefresh = true
                if !enabled { posts.removeAll { $0.author.id == id } }
            }
        } catch {
            guard generation == epoch else { return }
            if let e = error as? TreeholeError, e.code == "session_expired" { clear() }
            message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
        }
    }
    private func cursorKey(_ cursor: [String: String]) -> String { cursor.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "|") }
    func feed() async throws {
        feedRevision += 1
        let revision = feedRevision, generation = epoch, identity = feedIdentity
        feedLoadingMore = false; feedPageError = nil; lastAutomaticCursor = ""
        let result = try await api.request("posts.list", identity)
        guard revision == feedRevision, generation == epoch else { return }
        rememberResponses(result.posts ?? []); posts = (result.posts ?? []).map(restorePoll); feedNext = result.next; loadedFeedIdentity = identity; feedNeedsRefresh = false
    }
    func loadMoreFeed(automatic: Bool = true) async {
        guard !busy, !feedLoadingMore, let cursor = feedNext, loadedFeedIdentity == feedIdentity else { return }
        let key = cursorKey(cursor), generation = epoch, revision = feedRevision, identity = feedIdentity
        if automatic && (feedPageError != nil || lastAutomaticCursor == key) { return }
        lastAutomaticCursor = key; feedLoadingMore = true; feedPageError = nil
        var body: [String: Any] = identity; cursor.forEach { body[$0.key] = $0.value }
        defer { if revision == feedRevision && generation == epoch { feedLoadingMore = false } }
        do {
            let result = try await api.request("posts.list", body)
            guard revision == feedRevision, generation == epoch, identity == feedIdentity else { return }
            rememberResponses(result.posts ?? [])
            var ids = Set(posts.map(\.id))
            posts += (result.posts ?? []).map(restorePoll).filter { ids.insert($0.id).inserted }; feedNext = result.next
            if let next = result.next, cursorKey(next) == key { feedPageError = "暂时无法继续加载，请刷新后重试" }
        } catch {
            guard revision == feedRevision, generation == epoch, identity == feedIdentity else { return }
            if let failure = error as? TreeholeError, failure.code == "session_expired" { clear(); message = failure.errorDescription }
            else { feedPageError = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试" }
        }
    }
    private func syncFeedPost(_ fresh: TreeholePost) {
        guard let index = posts.firstIndex(where: { $0.id == fresh.id }) else { return }
        var updated = fresh
        if pendingReactions.contains(fresh.id + ":like") { updated.liked = posts[index].liked; updated.likeCount = posts[index].likeCount }
        if pendingReactions.contains(fresh.id + ":save") { updated.saved = posts[index].saved }
        if pendingResponses.contains(fresh.id) { updated.myResponse = posts[index].myResponse; updated.responseCounts = posts[index].responseCounts }
        posts[index] = updated
    }
    func leaveDetail() {
        detailRequest += 1; discussion += 1; detailLoading = false; detailError = nil
        current = nil; comments = []; commentNext = nil; expandedReplies = []; replyPages = [:]; loadedThreads = []; focusedThread = nil
    }
    func refreshUnread() async {
        guard engagementEnabled, user != nil, !unreadBusy else { return }
        let generation = epoch; unreadBusy = true; defer { unreadBusy = false }
        do { let r = try await api.request("notifications.unread"); guard generation == epoch else { return }; unreadCount = r.unreadCount ?? 0; messageUnread=r.messageUnreadCount }
        catch { if generation == epoch, let e = error as? TreeholeError, e.code == "session_expired" { clear() } }
    }
    func loadInbox(more: Bool = false) async {
        guard user != nil, engagementEnabled, !inboxLoading else { return }
        inboxRevision += 1; let revision = inboxRevision, generation = epoch
        inboxLoading = true; inboxError = nil
        defer { if generation == epoch && revision == inboxRevision { inboxLoading = false } }
        var body: [String: Any] = ["filter": inboxFilter]
        if more { inboxNext?.forEach { body[$0.key] = $0.value } }
        do {
            let r = try await api.request("notifications.list", body)
            guard generation == epoch, revision == inboxRevision else { return }
            var ids = Set(notifications.map(\.id))
            notifications = more ? notifications + (r.notifications ?? []).filter { ids.insert($0.id).inserted } : r.notifications ?? []
            inboxNext = r.next; unreadCount = r.unreadCount ?? 0
        } catch {
            guard generation == epoch, revision == inboxRevision else { return }
            if let e = error as? TreeholeError, e.code == "session_expired" { clear() }
            else { inboxError = (error as? TreeholeError)?.errorDescription ?? "连接失败，请重试" }
        }
    }
    func readNotifications(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }; let generation = epoch
        let r = try await api.request("notifications.read", ["ids": Array(ids.prefix(50))])
        guard generation == epoch else { return }
        let read = Set(ids.prefix(50)); let now = ISO8601DateFormatter().string(from: Date())
        for index in notifications.indices where read.contains(notifications[index].id) { if notifications[index].readAt == nil { notifications[index].readAt = now } }
        unreadCount = r.unreadCount ?? unreadCount
    }
    func notificationDetail(_ item: TreeholeNotification) async throws {
        let generation = epoch
        let r = try await api.request("posts.get", ["postId": item.postId, "threaded": true])
        guard let post = r.post else { throw TreeholeError(code: "not_found") }
        var context: TreeholeComment?
        if let id = item.commentId {
            do { context = try await api.request("comments.context", ["postId": item.postId, "commentId": id]).context }
            catch let e as TreeholeError where e.code == "not_found" { message = "这条回复已不可用，可以继续查看讨论" }
        }
        guard generation == epoch else { throw CancellationError() }
        rememberResponses([post]); leaveDetail(); current = restorePoll(post); syncFeedPost(restorePoll(post)); comments = r.comments ?? []; commentNext = r.next; focusedThread = context
        do { try await readNotifications([item.id]) } catch { message = "已打开讨论，消息已读状态暂未同步" }
    }
    func profile(_ id: String, more: Bool = false) async throws {
        let generation = epoch
        var body: [String: Any] = ["scope": "author", "memberId": id]
        if more { profileNext?.forEach { body[$0.key] = $0.value } }
        var person = publicProfile
        if !more { person = try await api.request("profile.get", ["memberId": id]).profile }
        let r = try await api.request("posts.list", body)
        guard generation == epoch else { throw CancellationError() }
        if more && publicProfile?.id != id { return }
        publicProfile = person; if let person { followStates[person.id] = person.following }; rememberResponses(r.posts ?? [])
        var ids = Set(profilePosts.map(\.id))
        profilePosts = more ? profilePosts + (r.posts ?? []).map(restorePoll).filter { ids.insert($0.id).inserted } : (r.posts ?? []).map(restorePoll); profileNext = r.next
    }
    func toggleWatch(_ post: TreeholePost) async {
        guard !watchPending else { return }; let generation = epoch; watchPending = true
        defer { if generation == epoch { watchPending = false } }
        do {
            let r = try await api.request("threads.watch", ["postId": post.id, "enabled": post.watching != true])
            guard generation == epoch, let updated = r.post else { return }
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index].watching = updated.watching }
            if current?.id == post.id { current?.watching = updated.watching }
            if scope == "watching" { feedNeedsRefresh = true }; await refreshUnread()
        } catch {
            guard generation == epoch else { return }
            if let e = error as? TreeholeError, e.code == "session_expired" { clear() }
            message = (error as? TreeholeError)?.errorDescription ?? "关注状态未更新，请重试"
        }
    }
    @discardableResult func openDetail(_ post: TreeholePost) -> Task<Void, Never> {
        leaveDetail(); current = post; detailLoading = true
        let ticket = detailRequest
        return Task {
            guard ticket == detailRequest, current?.id == post.id else { return }
            do { try await detail(post) } catch { /* Inline error preserves the cached reading surface. */ }
        }
    }
    func detail(_ post: TreeholePost, more: Bool = false) async throws {
        if current?.id != post.id { leaveDetail(); current = post }
        detailRequest += 1
        let ticket = detailRequest, generation = epoch, conversation = discussion
        detailLoading = true; detailError = nil
        var body: [String: Any] = ["postId": post.id, "threaded": true]
        if more { commentNext?.forEach { body[$0.key] = $0.value } }
        defer { if ticket == detailRequest && generation == epoch { detailLoading = false } }
        do {
            let r = try await api.request("posts.get", body)
            guard ticket == detailRequest, generation == epoch, conversation == discussion, current?.id == post.id else { return }
            guard var fresh = r.post else { throw TreeholeError(code: "post_not_found") }
            if pendingReactions.contains(post.id + ":like"), let cached = current { fresh.liked = cached.liked; fresh.likeCount = cached.likeCount }
            if pendingReactions.contains(post.id + ":save"), let cached = current { fresh.saved = cached.saved }
            if !more { discussion += 1; expandedReplies = []; replyPages = [:]; loadedThreads = [] }
            if pendingResponses.contains(post.id), let cached = current { fresh.myResponse = cached.myResponse; fresh.responseCounts = cached.responseCounts }
            rememberResponses([fresh]); fresh = restorePoll(fresh); current = fresh; syncFeedPost(fresh)
            var ids = Set(comments.map(\.id))
            comments = more ? comments + (r.comments ?? []).filter { ids.insert($0.id).inserted } : r.comments ?? []; commentNext = r.next
        } catch {
            guard ticket == detailRequest, generation == epoch, conversation == discussion else { return }
            if let failure = error as? TreeholeError, failure.code == "session_expired" { clear(); message = failure.errorDescription }
            else { detailError = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试" }
            throw error
        }
    }
    func expand(_ comment: TreeholeComment, post: TreeholePost) {
        guard !busy, !loadingThreads.contains(comment.id) else { return }
        if loadedThreads.contains(comment.id), !expandedReplies.contains(comment.id) { expandedReplies.insert(comment.id); return }
        let more = expandedReplies.contains(comment.id), generation = epoch, conversation = discussion
        if more && replyPages[comment.id] == nil { return }
        loadingThreads.insert(comment.id); message = nil
        Task {
            defer { if generation == epoch { loadingThreads.remove(comment.id) } }
            do {
                var body: [String: Any] = ["postId": post.id, "rootId": comment.id]
                if more { replyPages[comment.id]?.forEach { body[$0.key] = $0.value } }
                let r = try await api.request("comments.replies", body)
                guard generation == epoch, conversation == discussion, current?.id == post.id else { return }
                let index = comments.firstIndex(where: { $0.id == comment.id })
                guard index != nil || focusedThread?.id == comment.id else { return }
                let previous = more ? (index.map { comments[$0].replies ?? [] } ?? focusedThread?.replies ?? []) : []
                var ids = Set(previous.map(\.id))
                let replies = previous + (r.comments ?? []).filter { ids.insert($0.id).inserted }
                if let index { comments[index].replies = replies }
                if focusedThread?.id == comment.id { focusedThread?.replies = replies }
                expandedReplies.insert(comment.id); loadedThreads.insert(comment.id); replyPages[comment.id] = r.next
            } catch { actionError(error, generation: generation) }
        }
    }
    func collapse(_ comment: TreeholeComment) { expandedReplies.remove(comment.id) }
    private func updateComment(_ id: String, liked: Bool, count: Int) {
        if focusedThread?.id == id { focusedThread?.liked = liked; focusedThread?.likeCount = count }
        if let index = focusedThread?.replies?.firstIndex(where: { $0.id == id }) { focusedThread?.replies?[index].liked = liked; focusedThread?.replies?[index].likeCount = count }
        for i in comments.indices {
            if comments[i].id == id { comments[i].liked = liked; comments[i].likeCount = count }
            if let j = comments[i].replies?.firstIndex(where: { $0.id == id }) { comments[i].replies?[j].liked = liked; comments[i].replies?[j].likeCount = count }
        }
    }
    func likeComment(_ comment: TreeholeComment, post: TreeholePost) {
        guard !busy, !pendingCommentLikes.contains(comment.id) else { return }
        let generation = epoch, enabled = !(comment.liked ?? false)
        pendingCommentLikes.insert(comment.id); message = nil
        updateComment(comment.id, liked: enabled, count: max(0, (comment.likeCount ?? 0) + (enabled ? 1 : -1)))
        Task {
            defer { if generation == epoch { pendingCommentLikes.remove(comment.id) } }
            do {
                let r = try await api.request("comments.like", ["postId": post.id, "commentId": comment.id, "enabled": enabled])
                guard generation == epoch, current?.id == post.id, let fresh = r.comment else { return }
                updateComment(comment.id, liked: fresh.liked ?? false, count: fresh.likeCount ?? 0)
            } catch {
                if generation == epoch, current?.id == post.id { updateComment(comment.id, liked: comment.liked ?? false, count: comment.likeCount ?? 0) }
                actionError(error, generation: generation)
            }
        }
    }
    private func updatePost(_ id: String, kind: String, enabled: Bool, count: Int) {
        func apply(_ post: inout TreeholePost) { if kind == "like" { post.liked = enabled; post.likeCount = count } else { post.saved = enabled } }
        if let index = posts.firstIndex(where: { $0.id == id }) { apply(&posts[index]) }
        if let index = profilePosts.firstIndex(where: { $0.id == id }) { apply(&profilePosts[index]) }
        if var post = current, post.id == id { apply(&post); current = post }
    }
    private func rememberResponses(_ fresh: [TreeholePost]) {
        for post in fresh { if let buddy = post.buddy, buddy.version >= (buddySnapshots[post.id]?.version ?? -1) { buddySnapshots[post.id] = buddy } }
        for post in fresh { if let poll = post.poll, poll.version >= (pollSnapshots[post.id]?.version ?? -1) { pollSnapshots[post.id] = poll } }
        for post in fresh where responseSnapshots[post.id] != nil && !pendingResponses.contains(post.id) { responseSnapshots[post.id] = post }
    }
    func restoreResponse(_ post: TreeholePost) -> TreeholePost {
        guard let response = responseSnapshots[post.id] else { return restorePoll(post) }; var restored = restorePoll(post)
        restored.myResponse = response.myResponse; restored.responseCounts = response.responseCounts; return restored
    }
    func restorePoll(_ post: TreeholePost) -> TreeholePost {
        var result = post
        if let buddy = buddySnapshots[post.id], buddy.version >= (post.buddy?.version ?? -1) { result.buddy = buddy }
        if let poll = pollSnapshots[post.id], poll.version >= (post.poll?.version ?? -1) { result.poll = poll }
        return result
    }
    func applyBuddy(_ id: String, buddy: TreeholeBuddy) {
        guard buddy.version >= (buddySnapshots[id]?.version ?? -1) else { return }
        buddySnapshots[id] = buddy
        if let index = posts.firstIndex(where: { $0.id == id }) { posts[index].buddy = buddy }
        if let index = profilePosts.firstIndex(where: { $0.id == id }) { profilePosts[index].buddy = buddy }
        if current?.id == id { current?.buddy = buddy }
    }
    func buddyAction(_ post: TreeholePost, action: String, enabled: Bool) async {
        guard buddiesEnabled, ["join", "close"].contains(action), !pendingBuddies.contains(post.id) else { return }
        let generation = epoch; pendingBuddies.insert(post.id); message = nil
        defer { if generation == epoch { pendingBuddies.remove(post.id) } }
        do {
            let result = try await api.request("buddies." + action, ["postId": post.id, action == "join" ? "enabled" : "closed": enabled])
            guard generation == epoch, let fresh = result.post?.buddy else { return }
            applyBuddy(post.id, buddy: fresh); feedNeedsRefresh = true
            message = action == "join" ? (enabled ? "报名成功，可在「我报名的」找到这条讨论" : "已退出报名") : (enabled ? "已结束招募" : "已重新开放招募")
        } catch {
            if generation == epoch, let failure = error as? TreeholeError, ["buddy_full", "buddy_closed", "post_locked"].contains(failure.code) {
                if let fresh = try? await api.request("posts.get", ["postId": post.id]).post?.buddy, generation == epoch { applyBuddy(post.id, buddy: fresh) }
            }
            actionError(error, generation: generation)
        }
    }
    private func applyPoll(_ id: String, poll: TreeholePoll) {
        guard poll.version >= (pollSnapshots[id]?.version ?? -1) else { return }
        pollSnapshots[id] = poll
        if let index = posts.firstIndex(where: { $0.id == id }) { posts[index].poll = poll }
        if let index = profilePosts.firstIndex(where: { $0.id == id }) { profilePosts[index].poll = poll }
        if current?.id == id { current?.poll = poll }
    }
    func vote(_ post: TreeholePost, optionId: String?) async {
        guard pollsEnabled, !post.locked, let poll = post.poll, !poll.ended(), !pendingVotes.contains(post.id) else { return }
        let generation = epoch; pendingVotes.insert(post.id); message = nil
        defer { if generation == epoch { pendingVotes.remove(post.id) } }
        do {
            let response = try await api.request("polls.vote", ["postId": post.id, "optionId": optionId as Any? ?? NSNull()])
            guard generation == epoch, let fresh = response.post?.poll else { return }
            applyPoll(post.id, poll: fresh)
        } catch {
            if generation == epoch, let e = error as? TreeholeError, e.code == "poll_closed" { var closed = poll; closed.closed = true; applyPoll(post.id, poll: closed) }
            actionError(error, generation: generation)
        }
    }
    private func updateResponse(_ id: String, kind: String?, counts: [String: Int], source: TreeholePost) {
        var snapshot = source; snapshot.myResponse = kind; snapshot.responseCounts = counts; responseSnapshots[id] = snapshot
        if let i = posts.firstIndex(where: { $0.id == id }) { posts[i].myResponse = kind; posts[i].responseCounts = counts }
        if let i = profilePosts.firstIndex(where: { $0.id == id }) { profilePosts[i].myResponse = kind; profilePosts[i].responseCounts = counts }
        if current?.id == id { current?.myResponse = kind; current?.responseCounts = counts }
    }
    func respond(_ post: TreeholePost, kind: String) {
        guard responsesEnabled, !busy, responseKinds.contains(kind), !pendingResponses.contains(post.id) else { return }
        let generation = epoch, next: String? = post.myResponse == kind ? nil : kind
        var counts = post.responseCounts ?? [:]
        if let old = post.myResponse { counts[old] = max(0, (counts[old] ?? 0) - 1) }; if let next { counts[next, default: 0] += 1 }
        pendingResponses.insert(post.id); message = nil; updateResponse(post.id, kind: next, counts: counts, source: post)
        Task {
            defer { if generation == epoch { pendingResponses.remove(post.id) } }
            do {
                let result = try await api.request("responses.set", ["postId": post.id, "kind": next as Any? ?? NSNull()])
                guard generation == epoch, let fresh = result.post else { return }
                updateResponse(post.id, kind: fresh.myResponse, counts: fresh.responseCounts ?? [:], source: fresh)
            } catch {
                if generation == epoch { updateResponse(post.id, kind: post.myResponse, counts: post.responseCounts ?? [:], source: post) }
                actionError(error, generation: generation)
            }
        }
    }
    func setAvatar(_ photo: TreeholeDraftPhoto?) async throws {
        guard avatarsEnabled, user != nil else { return }
        let generation = epoch
        var imageId: String?
        if let photo {
            let uploaded = try await api.request("media.upload", ["data": photo.data.base64EncodedString(), "requestId": photo.id, "purpose": "avatar"])
            guard generation == epoch else { throw CancellationError() }
            guard let image = uploaded.image else { throw TreeholeError(code: "invalid_response") }; imageId = image.id
        }
        let result = try await api.request("avatar.set", ["imageId": imageId as Any? ?? NSNull()])
        guard generation == epoch else { throw CancellationError() }
        guard let updated = result.user else { throw TreeholeError(code: "invalid_response") }
        user = updated; feedNeedsRefresh = true
        func author(_ value: TreeholeAuthor) -> TreeholeAuthor { var value = value; if !value.anonymous && value.id == updated.id { value.avatar = updated.avatar }; return value }
        for i in posts.indices { posts[i].author = author(posts[i].author) }
        for i in profilePosts.indices { profilePosts[i].author = author(profilePosts[i].author) }
        if let value = current { current?.author = author(value.author) }
        for i in comments.indices { comments[i].author = author(comments[i].author); for j in comments[i].replies?.indices ?? 0..<0 { if let value = comments[i].replies?[j].author { comments[i].replies?[j].author = author(value) } } }
        if publicProfile?.id == updated.id { publicProfile?.avatar = updated.avatar }
    }
    func react(_ post: TreeholePost, kind: String) {
        let key = post.id + ":" + kind
        guard !busy, ["like", "save"].contains(kind), !pendingReactions.contains(key) else { return }
        let generation = epoch, enabled = kind == "like" ? !post.liked : !post.saved
        pendingReactions.insert(key); message = nil
        updatePost(post.id, kind: kind, enabled: enabled, count: max(0, post.likeCount + (enabled ? 1 : -1)))
        Task {
            defer { if generation == epoch { pendingReactions.remove(key) } }
            do {
                let r = try await api.request("reactions.set", ["postId": post.id, "kind": kind, "enabled": enabled])
                guard generation == epoch, let fresh = r.post else { return }
                updatePost(post.id, kind: kind, enabled: kind == "like" ? fresh.liked : fresh.saved, count: fresh.likeCount)
                if kind == "save", !fresh.saved, scope == "saved" { posts.removeAll { $0.id == post.id } }
            } catch {
                if generation == epoch { updatePost(post.id, kind: kind, enabled: kind == "like" ? post.liked : post.saved, count: post.likeCount) }
                actionError(error, generation: generation)
            }
        }
    }
    private func actionError(_ error: Error, generation: Int) {
        guard generation == epoch else { return }
        if let failure = error as? TreeholeError, failure.code == "session_expired" { clear() }
        message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
    }
}

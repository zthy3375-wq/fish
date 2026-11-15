import Foundation
import Combine

@MainActor final class TreeholeStore: ObservableObject {
    @Published var user: TreeholeMember?
    @Published var posts: [TreeholePost] = []
    @Published var current: TreeholePost?
    @Published var comments: [TreeholeComment] = []
    @Published var reports: [TreeholeReport] = []
    @Published var busy = false
    @Published var ready = false
    @Published var registration = false
    @Published var requiresInvite = false
    @Published var message: String?
    @Published var recovery: String?
    @Published var category = "all"
    @Published var sort = "latest"
    @Published var imagesEnabled = false
    @Published var expandedReplies: Set<String> = []
    @Published var replyPages: [String: [String: String]] = [:]
    @Published var scope = "all"
    @Published var query = ""
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
    func clear() { epoch += 1; pendingReactions = []; pendingCommentLikes = []; loadingThreads = []; loadedThreads = []; user = nil; posts = []; current = nil; comments = []; reports = []; recovery = nil; scope = "all"; query = ""; category = "all"; sort = "latest"; expandedReplies = []; replyPages = [:]; feedNext = nil; commentNext = nil }
    func enter() {
        perform {
            let config = try await self.api.request("config")
            self.registration = config.registrationEnabled == true; self.requiresInvite = config.requiresInvite == true; self.imagesEnabled = config.imagesEnabled == true
            do { self.user = try await self.api.request("me").user; try await self.feed() }
            catch let error as TreeholeError where error.code == "session_expired" { self.clear() }
            self.ready = true
        }
    }
    func feed(more: Bool = false) async throws {
        var body: [String: Any] = ["scope": scope, "query": query, "category": category, "sort": sort]
        if more { feedNext?.forEach { body[$0.key] = $0.value } }
        let r = try await api.request("posts.list", body)
        posts = more ? posts + (r.posts ?? []).filter { fresh in !posts.contains { $0.id == fresh.id } } : r.posts ?? []; feedNext = r.next
    }
    func detail(_ post: TreeholePost, more: Bool = false) async throws {
        var body: [String: Any] = ["postId": post.id, "threaded": true]
        if more { commentNext?.forEach { body[$0.key] = $0.value } }
        let r = try await api.request("posts.get", body)
        if !more { discussion += 1; expandedReplies = []; replyPages = [:]; loadedThreads = [] }
        current = r.post; comments = more ? comments + (r.comments ?? []) : r.comments ?? []; commentNext = r.next
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
                guard generation == epoch, conversation == discussion, current?.id == post.id, let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
                let previous = more ? comments[index].replies ?? [] : []
                var ids = Set(previous.map(\.id))
                comments[index].replies = previous + (r.comments ?? []).filter { ids.insert($0.id).inserted }
                expandedReplies.insert(comment.id); loadedThreads.insert(comment.id); replyPages[comment.id] = r.next
            } catch { actionError(error, generation: generation) }
        }
    }
    func collapse(_ comment: TreeholeComment) { expandedReplies.remove(comment.id) }
    private func updateComment(_ id: String, liked: Bool, count: Int) {
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
        if var post = current, post.id == id { apply(&post); current = post }
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

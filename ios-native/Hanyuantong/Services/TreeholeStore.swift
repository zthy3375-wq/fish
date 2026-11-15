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
    let api: TreeholeService
    init(api: TreeholeService = TreeholeService()) { self.api = api }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; message = nil
        Task { defer { busy = false }; do { try await work() } catch is CancellationError { } catch {
            if let e = error as? TreeholeError, e.code == "session_expired" { clear() }
            message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
        } }
    }
    func clear() { user = nil; posts = []; current = nil; comments = []; reports = []; recovery = nil; scope = "all"; query = ""; category = "all"; sort = "latest"; expandedReplies = []; replyPages = [:]; feedNext = nil; commentNext = nil }
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
        if !more { expandedReplies = []; replyPages = [:] }
        current = r.post; comments = more ? comments + (r.comments ?? []) : r.comments ?? []; commentNext = r.next
    }
    func expand(_ comment: TreeholeComment, post: TreeholePost) {
        perform {
            let more = self.expandedReplies.contains(comment.id)
            var body: [String: Any] = ["postId": post.id, "rootId": comment.id]
            if more { self.replyPages[comment.id]?.forEach { body[$0.key] = $0.value } }
            let r = try await self.api.request("comments.replies", body)
            if let index = self.comments.firstIndex(where: { $0.id == comment.id }) {
                self.comments[index].replies = more ? (self.comments[index].replies ?? []) + (r.comments ?? []) : r.comments ?? []
                self.expandedReplies.insert(comment.id); self.replyPages[comment.id] = r.next
            }
        }
    }
    func likeComment(_ comment: TreeholeComment, post: TreeholePost) {
        perform {
            guard let fresh = try await self.api.request("comments.like", ["postId": post.id, "commentId": comment.id, "enabled": !(comment.liked ?? false)]).comment else { return }
            for i in self.comments.indices {
                if self.comments[i].id == fresh.id { self.comments[i].liked = fresh.liked; self.comments[i].likeCount = fresh.likeCount }
                if let j = self.comments[i].replies?.firstIndex(where: { $0.id == fresh.id }) { self.comments[i].replies?[j].liked = fresh.liked; self.comments[i].replies?[j].likeCount = fresh.likeCount }
            }
        }
    }
    func react(_ post: TreeholePost, kind: String) {
        perform {
            let r = try await self.api.request("reactions.set", ["postId": post.id, "kind": kind, "enabled": kind == "like" ? !post.liked : !post.saved])
            guard let fresh = r.post else { return }
            self.posts = self.posts.map { $0.id == post.id ? fresh : $0 }
            if self.current?.id == post.id { self.current = fresh }
        }
    }
}

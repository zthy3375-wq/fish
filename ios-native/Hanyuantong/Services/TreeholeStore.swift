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
    func clear() { user = nil; posts = []; current = nil; comments = []; reports = []; recovery = nil; scope = "all"; query = ""; feedNext = nil; commentNext = nil }
    func enter() {
        perform {
            let config = try await self.api.request("config")
            self.registration = config.registrationEnabled == true; self.requiresInvite = config.requiresInvite == true
            do { self.user = try await self.api.request("me").user; try await self.feed() }
            catch let error as TreeholeError where error.code == "session_expired" { self.clear() }
            self.ready = true
        }
    }
    func feed(more: Bool = false) async throws {
        var body: [String: Any] = ["scope": scope, "query": query]
        if more { feedNext?.forEach { body[$0.key] = $0.value } }
        let r = try await api.request("posts.list", body)
        posts = more ? posts + (r.posts ?? []) : r.posts ?? []; feedNext = r.next
    }
    func detail(_ post: TreeholePost, more: Bool = false) async throws {
        var body: [String: Any] = ["postId": post.id]
        if more { commentNext?.forEach { body[$0.key] = $0.value } }
        let r = try await api.request("posts.get", body)
        current = r.post; comments = more ? comments + (r.comments ?? []) : r.comments ?? []; commentNext = r.next
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

import XCTest
import UIKit
@testable import Hanyuantong

private final class TreeholeMemoryVault: TreeholeTokenVault {
    var token: String?
    func read() throws -> String? { token }
    func save(_ value: String) throws { token = value }
    func clear() throws { token = nil }
}
private final class TreeholeTestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var pauseNext = false
    static var resume: (() -> Void)?
    static var paused: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let (code, data) = handler(request)
        let deliver: () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
        if Self.pauseNext { Self.pauseNext = false; Self.resume = deliver; Self.paused?() } else { deliver() }
    }
    override func stopLoading() { }
}
final class TreeholeTests: XCTestCase {
    private func service(_ vault: TreeholeMemoryVault) -> TreeholeService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TreeholeTestProtocol.self]
        return TreeholeService(vault: vault, session: URLSession(configuration: config))
    }
    override func tearDown() { TreeholeTestProtocol.handler = nil; TreeholeTestProtocol.pauseNext = false; TreeholeTestProtocol.resume = nil; TreeholeTestProtocol.paused = nil }
    func testNativeLoginStoresTokenAndRemovesItFromEnvelope() async throws {
        let vault = TreeholeMemoryVault(), token = String(repeating: "a", count: 43)
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/hyt-community/v1/login"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data("{\"sessionToken\":\"\(token)\",\"user\":{\"id\":\"test-id\",\"username\":\"app_user\",\"nickname\":\"同学\",\"role\":\"member\"}}".utf8))
        }
        let r = try await service(vault).request("login", ["username": "app_user", "password": "synthetic-password"])
        XCTAssertEqual(vault.token, token); XCTAssertNil(r.sessionToken); XCTAssertEqual(r.user?.nickname, "同学")
    }
    func testExpiredSessionClearsVault() async {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 43))
            return (401, Data("{\"error\":\"session_expired\"}".utf8))
        }
        do { _ = try await service(vault).request("me"); XCTFail() } catch { XCTAssertEqual((error as? TreeholeError)?.code, "session_expired") }
        XCTAssertNil(vault.token)
    }
    func testOfflineLogoutAndActionAllowlist() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let api = service(vault); _ = try await api.request("logout"); XCTAssertNil(vault.token)
        for action in ["credentials", "session", "../login", "https://evil.invalid"] {
            do { _ = try await api.request(action); XCTFail() } catch { XCTAssertEqual((error as? TreeholeError)?.code, "invalid_request") }
        }
    }
    func testAnonymousPayloadDecodesWithoutAccountIdentity() throws {
        let data = Data("{\"id\":\"post-id\",\"body\":\"匿名文字\",\"createdAt\":\"2026-11-14T00:00:00Z\",\"anonymous\":true,\"locked\":false,\"liked\":false,\"saved\":false,\"author\":{\"name\":\"匿名同学 · abc\",\"anonymous\":true,\"mine\":false},\"commentCount\":0,\"likeCount\":0}".utf8)
        let post = try JSONDecoder().decode(TreeholePost.self, from: data)
        XCTAssertTrue(post.anonymous); XCTAssertFalse(post.author.mine)
        let encoded = String(data: try JSONEncoder().encode(post), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("username")); XCTAssertFalse(encoded.contains("authorId"))
    }
    func testTimestampBoundariesAndCampusTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-15T01:00:00Z"))
        XCTAssertEqual(TreeholePresentation.date("2026-11-15T00:59:01Z", now: now), "刚刚")
        XCTAssertEqual(TreeholePresentation.date("2026-11-15T00:59:00Z", now: now), "1 分钟前")
        XCTAssertEqual(TreeholePresentation.date("2026-11-15T00:00:00.000Z", now: now), "1 小时前")
        XCTAssertEqual(TreeholePresentation.date("2026-11-14T01:00:00Z", now: now), "11月14日 09:00")
        XCTAssertEqual(TreeholePresentation.date("2026-11-15T02:00:00Z", now: now), "11月15日 10:00")
        XCTAssertEqual(TreeholePresentation.date("invalid", now: now), "时间未知")
    }

    func testUploadSizeLimitDoesNotRelaxPostBodyLimit() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        TreeholeTestProtocol.handler = { request in XCTAssertEqual(request.url?.lastPathComponent, "media.upload"); return (200, Data("{}".utf8)) }
        let api = service(vault), body = ["data": String(repeating: "a", count: 1_600_000)]
        _ = try await api.request("media.upload", body)
        for (action, payload) in [("posts.create", body), ("media.upload", ["data": String(repeating: "a", count: 1_650_001)])] {
            do { _ = try await api.request(action, payload); XCTFail() } catch { XCTAssertEqual((error as? TreeholeError)?.code, "invalid_request") }
        }
    }
    @MainActor func testDraftPersistsImagesAndIsolatesAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory), first = UUID().uuidString, second = UUID().uuidString
        let draft = TreeholeDraftStore(storage: storage); draft.bind(first); draft.value.title = "草稿标题"; draft.value.body = "草稿正文"; draft.value.anonymous = true
        draft.value.photos = [TreeholeDraftPhoto(id: UUID().uuidString, data: Data([1,2,3]), remote: TreeholeImage(id: "uploaded", width: 4, height: 3))]
        let request = draft.value.requestId; draft.flush(); draft.bind(second); XCTAssertFalse(draft.value.hasContent)
        draft.value.body = "另一账号"; draft.flush(); draft.bind(first); XCTAssertEqual(draft.value.requestId, request); XCTAssertEqual(draft.value.photos.first?.remote?.id, "uploaded"); XCTAssertTrue(draft.value.anonymous)
        draft.clear(); draft.bind(second); XCTAssertEqual(draft.value.body, "另一账号")
    }
    @MainActor func testPickedImageIsResizedAndConvertedToJPEG() throws {
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200)).image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200)) }.pngData()!
        let photo = try TreeholeDraftStore.prepare(bytes), decoded = try XCTUnwrap(UIImage(data: photo.data))
        XCTAssertEqual(decoded.size.width, 1600); XCTAssertEqual(decoded.size.height, 800); XCTAssertLessThanOrEqual(photo.data.count, 1_200_000); XCTAssertEqual(Array(photo.data.prefix(2)), [255,216])
    }

    private func samplePost(_ id: String = "post-id", comments: Int = 1) -> TreeholePost {
        TreeholePost(id: id, body: "校园日常", createdAt: "2026-11-15T00:00:00Z", anonymous: false, locked: false, liked: false, saved: false, author: TreeholeAuthor(name: "同学", anonymous: false, mine: false), commentCount: comments, likeCount: 2)
    }
    @MainActor private func settle(_ store: TreeholeStore) async throws {
        for _ in 0..<200 {
            if store.pendingReactions.isEmpty && store.pendingCommentLikes.isEmpty { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Interaction did not settle")
    }
    @MainActor func testFailedReactionsRollBackWithoutBlockingReading() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        TreeholeTestProtocol.handler = { _ in (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        let store = TreeholeStore(api: service(vault)), post = samplePost()
        store.posts = [post]; store.current = post
        let comment = TreeholeComment(id: "comment", postId: post.id, body: "回复", createdAt: post.createdAt, replyTo: nil, author: post.author, deleted: false, isOriginalPoster: false, likeCount: 4, liked: false)
        store.comments = [comment]
        store.react(post, kind: "like"); store.likeComment(comment, post: post)
        XCTAssertFalse(store.busy); XCTAssertEqual(store.current?.likeCount, 3); XCTAssertEqual(store.comments.first?.likeCount, 5)
        XCTAssertTrue(store.pendingReactions.contains(post.id + ":like"))
        try await settle(store)
        XCTAssertEqual(store.current?.liked, false); XCTAssertEqual(store.posts.first?.likeCount, 2)
        XCTAssertEqual(store.comments.first?.liked, false); XCTAssertEqual(store.comments.first?.likeCount, 4)
        XCTAssertNotNil(store.message)
    }
    @MainActor func testConcurrentLikeAndSaveKeepIndependentFields() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let post = samplePost()
        TreeholeTestProtocol.handler = { request in
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var chunk = [UInt8](repeating: 0, count: 1024); while stream.hasBytesAvailable { let n = stream.read(&chunk, maxLength: chunk.count); if n <= 0 { break }; bytes.append(contentsOf: chunk.prefix(n)) } }
            let payload = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            var fresh = post
            if payload?["kind"] as? String == "like" { fresh.liked = true; fresh.likeCount = 3 } else { fresh.saved = true }
            return (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(fresh)) + Data("}".utf8))
        }
        let store = TreeholeStore(api: service(vault)); store.posts = [post]; store.current = post
        store.react(post, kind: "like"); store.react(post, kind: "save")
        XCTAssertFalse(store.busy); XCTAssertEqual(store.pendingReactions.count, 2)
        try await settle(store)
        XCTAssertEqual(store.current?.liked, true); XCTAssertEqual(store.current?.saved, true); XCTAssertEqual(store.current?.likeCount, 3)
        XCTAssertEqual(store.posts.first?.liked, true); XCTAssertEqual(store.posts.first?.saved, true)
    }
    @MainActor func testOldInteractionCannotRestoreClearedAccount() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        var post = samplePost(); post.liked = true
        let finished = expectation(description: "old request completes")
        TreeholeTestProtocol.handler = { _ in defer { finished.fulfill() }; return (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(post)) + Data("}".utf8)) }
        let store = TreeholeStore(api: service(vault)); store.posts = [samplePost()]; store.current = samplePost()
        store.react(samplePost(), kind: "like"); store.clear()
        await fulfillment(of: [finished], timeout: 3)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(store.current); XCTAssertTrue(store.posts.isEmpty); XCTAssertTrue(store.pendingReactions.isEmpty); XCTAssertNil(store.message)
    }


    private func page(_ posts: [TreeholePost], next: [String: String]? = nil) -> Data {
        var value: [String: Any] = ["posts": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(posts))]
        if let next { value["next"] = next }
        return try! JSONSerialization.data(withJSONObject: value)
    }
    @MainActor func testFeedPaginationRetainsPagesOnFailureAndRetriesWithoutBlockingReading() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), cursor = ["beforeId": "one", "snapshotTime": "2026-11-15T00:00:00Z"]
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("one")], next: cursor)) }
        try await store.feed()
        var calls = 0
        TreeholeTestProtocol.handler = { _ in calls += 1; return (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        await store.loadMoreFeed(); await store.loadMoreFeed()
        XCTAssertEqual(calls, 1); XCTAssertEqual(store.posts.map(\.id), ["one"]); XCTAssertEqual(store.feedNext, cursor)
        XCTAssertNotNil(store.feedPageError); XCTAssertFalse(store.busy); XCTAssertFalse(store.feedLoadingMore)
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("one"), self.samplePost("two"), self.samplePost("two")])) }
        await store.loadMoreFeed(automatic: false)
        XCTAssertEqual(store.posts.map(\.id), ["one", "two"]); XCTAssertNil(store.feedNext); XCTAssertNil(store.feedPageError)
    }
    @MainActor func testLateFeedPageCannotRestoreOldCategoryOrClearedAccount() async throws {
        for clearsAccount in [false, true] {
            let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
            let store = TreeholeStore(api: service(vault))
            TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("one")], next: ["beforeId": "one"])) }
            try await store.feed()
            let delayed = expectation(description: "page response held")
            TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("old-page")])) }
            TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
            let loading = Task { await store.loadMoreFeed() }
            await fulfillment(of: [delayed], timeout: 3)
            XCTAssertTrue(store.feedLoadingMore); XCTAssertFalse(store.busy)
            if clearsAccount { store.clear() }
            else {
                store.category = "help"
                TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("help-post")])) }
                try await store.feed()
            }
            TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
            XCTAssertEqual(store.posts.map(\.id), clearsAccount ? [] : ["help-post"])
            XCTAssertFalse(store.feedLoadingMore); XCTAssertNil(store.feedPageError)
        }
    }
    @MainActor func testNonAdvancingCursorDoesNotAutomaticallyLoop() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), cursor = ["beforeId": "one"]
        var calls = 0
        TreeholeTestProtocol.handler = { _ in calls += 1; return (200, self.page([self.samplePost("one")], next: cursor)) }
        try await store.feed(); await store.loadMoreFeed(); await store.loadMoreFeed()
        XCTAssertEqual(calls, 2); XCTAssertNotNil(store.feedPageError); XCTAssertEqual(store.posts.count, 1)
    }
    @MainActor func testDetailUpdatesCachedCountsWithoutDroppingPagesOrPendingReactions() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), cursor = ["beforeId": "two"]
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("one"), self.samplePost("two")], next: cursor)) }
        try await store.feed()
        store.posts[1].liked = true; store.posts[1].likeCount = 3; store.pendingReactions = ["two:like"]
        TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(self.samplePost("two", comments: 9))) + Data("}".utf8)) }
        try await store.detail(store.posts[1])
        XCTAssertEqual(store.posts.map(\.id), ["one", "two"]); XCTAssertEqual(store.feedNext, cursor)
        XCTAssertEqual(store.posts[1].commentCount, 9); XCTAssertTrue(store.posts[1].liked); XCTAssertEqual(store.posts[1].likeCount, 3)
    }
    @MainActor func testRemovingSavedPostKeepsOtherCachedCards() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.scope = "saved"
        var saved = samplePost("one"); saved.saved = true
        store.posts = [saved, samplePost("two")]; store.current = saved
        TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(self.samplePost("one"))) + Data("}".utf8)) }
        store.react(saved, kind: "save"); try await settle(store)
        XCTAssertEqual(store.posts.map(\.id), ["two"]); XCTAssertEqual(store.current?.saved, false)
    }

    @MainActor func testCachedDetailAppearsBeforeNetworkAndBackInvalidatesResponse() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), post = samplePost("cached")
        TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(post)) + Data("}".utf8)) }
        let delayed = expectation(description: "detail response held")
        TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
        let loading = store.openDetail(post)
        XCTAssertEqual(store.current?.id, "cached"); XCTAssertTrue(store.detailLoading); XCTAssertFalse(store.busy)
        await fulfillment(of: [delayed], timeout: 3)
        store.leaveDetail(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
        XCTAssertNil(store.current); XCTAssertFalse(store.detailLoading); XCTAssertNil(store.detailError)
    }
    @MainActor func testLateDetailCannotReplaceNewPostOrRestoreAccount() async throws {
        for clears in [false, true] {
            let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
            let store = TreeholeStore(api: service(vault)), old = samplePost("old"), next = samplePost("next")
            TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(old)) + Data("}".utf8)) }
            let delayed = expectation(description: "old detail held")
            TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
            let loading = store.openDetail(old); await fulfillment(of: [delayed], timeout: 3)
            if clears { store.clear() }
            else {
                TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(next)) + Data("}".utf8)) }
                await store.openDetail(next).value
            }
            TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
            XCTAssertEqual(store.current?.id, clears ? nil : "next"); XCTAssertNil(store.detailError); XCTAssertFalse(store.detailLoading)
        }
    }
    @MainActor func testDetailFailureKeepsBodyAndRetryRecovers() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), post = samplePost("cached")
        TreeholeTestProtocol.handler = { _ in (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        await store.openDetail(post).value
        XCTAssertEqual(store.current?.id, post.id); XCTAssertNotNil(store.detailError); XCTAssertFalse(store.busy); XCTAssertFalse(store.detailLoading)
        TreeholeTestProtocol.handler = { _ in (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(post)) + Data("}".utf8)) }
        try await store.detail(post); XCTAssertNil(store.detailError); XCTAssertEqual(store.current?.id, post.id)
    }

}

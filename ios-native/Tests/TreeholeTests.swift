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
    func testWearableCollectionMatchesAndroidForBothServerVersions() throws {
        func item(_ code: String, _ category: String = "contribution", _ kind: String? = nil) -> CampusHonorItem {
            CampusHonorItem(id: "definition-" + code, code: code, name: code, category: category,
                rarity: "rare", year: nil, archived: false, criteria: nil, awardId: "grant-" + code,
                at: nil, story: nil, publicHidden: true, memberId: nil, nickname: nil, displayKind: kind)
        }
        let rows = [item("early-resident"), item("first-hundred"), item("before-dawn","hidden"),
                    item("campus-legend"), item("person-of-year-2026","limited"), item("custom","contribution","achievement")]
        var json: [String: Any] = ["id":"viewer","nickname":"同学","items":[],"badges":["worn":["code":"seed"]],
            "identities":["contributor"],"legacyHonors":[["code":"seed"]],"useTitle":false,"total":0,
            "rarities":[:],"unseen":[],"showcase":["firstpost"],"layoutVersion":3]
        func decode() throws -> CampusCollectionProfile {
            try JSONDecoder().decode(CampusCollectionProfile.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let profile = try decode()
        let cards = profile.wearableItems(in: rows, own: true, complete: true)
        XCTAssertEqual(cards.map(\.code), ["seed","creator","contributor","early-resident","person-of-year-2026","creator-of-year","photo-of-year","warmth-of-year"])
        XCTAssertEqual(profile.wearableItems(in: rows, own: false, complete: true).map(\.code), ["seed","contributor","early-resident","person-of-year-2026"])
        XCTAssertFalse(profile.wearableItems(in: rows, own: true, complete: false).contains(where: \.isAnnualTemplate))
        let seed = try XCTUnwrap(cards.first)
        let (action, wear) = try XCTUnwrap(profile.wearRequest(for: seed, remove: false, useTitle: true))
        XCTAssertEqual(action, "collection.wear"); XCTAssertEqual(wear["legacyCode"] as? String, "seed")
        XCTAssertTrue(wear["awardId"] is NSNull); XCTAssertEqual(wear["organized"] as? Bool, true)
        XCTAssertTrue(try XCTUnwrap(profile.wearRequest(for: seed, remove: true, useTitle: false)).1["legacyCode"] is NSNull)
        XCTAssertEqual(profile.wearRequest(for: rows[0], remove: false, useTitle: true)?.1["awardId"] as? String, rows[0].awardId)
        for item in [cards[1], rows[1], rows[2], rows[3], rows[5], cards.last!] {
            XCTAssertNil(profile.wearRequest(for: item, remove: false, useTitle: false), item.code)
        }
        json.removeValue(forKey: "layoutVersion")
        let legacy = try decode()
        let (oldAction, oldBody) = try XCTUnwrap(legacy.wearRequest(for: seed, remove: false, useTitle: false))
        XCTAssertEqual(oldAction, "honors.wear"); XCTAssertEqual(oldBody["showcase"] as? [String], ["firstpost"])
    }

    @MainActor func testPhotoZoomRefitsAndPreservesMagnificationWhenRotated() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400)).image { _ in }
        let widths: [CGFloat] = [320, 375, 390, 430]
        for width in widths {
            let view = CommunityPhotoScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 740))
            view.display(photo); view.layoutIfNeeded()
            XCTAssertEqual(view.minimumZoomScale, CGFloat(width)/800, accuracy: 0.001)
            XCTAssertEqual(view.contentSize.width, CGFloat(width), accuracy: 1)
            XCTAssertGreaterThan(view.contentInset.top, 0)
            view.setZoomScale(view.minimumZoomScale * 2.5, animated: false)
            view.frame = CGRect(x: 0, y: 0, width: 740, height: width); view.layoutIfNeeded()
            XCTAssertEqual(view.minimumZoomScale, min(740/800, CGFloat(width)/400), accuracy: 0.001)
            XCTAssertEqual(view.zoomScale / view.minimumZoomScale, 2.5, accuracy: 0.001)
            view.setZoomScale(view.minimumZoomScale, animated: false)
            XCTAssertLessThanOrEqual(view.contentSize.width, 741)
            XCTAssertLessThanOrEqual(view.contentSize.height, CGFloat(width)+1)
        }
    }

    func testLegacyDeletedThreadsHideAuthorsAndKeepLiveDescendants() {
        func comment(_ id: String, deleted: Bool = false, replyTo: String? = nil) -> TreeholeComment {
            TreeholeComment(id: id, postId: "post", body: id, createdAt: "", replyTo: replyTo,
                author: TreeholeAuthor(name: id, anonymous: false, mine: false), deleted: deleted, isOriginalPoster: false)
        }
        var root = comment("old root", deleted: true)
        let removed = comment("old reply", deleted: true, replyTo: root.id)
        let live = comment("still readable", replyTo: removed.id)
        root.replies = [removed, live]
        XCTAssertEqual(root.liveReplies.map(\.id), [live.id])
        XCTAssertNil(root.replyRecipient(for: live))
        XCTAssertEqual(root.visibleReplyCount(complete: false), 1)
        root.replyCount = 6
        XCTAssertEqual(root.visibleReplyCount(complete: false), 6)
        XCTAssertEqual(root.visibleReplyCount(complete: true), 1)
        root.replies = [removed]
        XCTAssertEqual(root.visibleReplyCount(complete: true), 0)
    }

    func testQuickReplyLimitMatchesAndroidUTF16WithoutBreakingEmoji() {
        let prefix = String(repeating: "学", count: 999)
        XCTAssertEqual(TreeholePresentation.boundedReply(prefix + "🙂"), prefix)
        let fits = String(repeating: "🙂", count: 500)
        XCTAssertEqual(TreeholePresentation.boundedReply(fits + "a"), fits)
        XCTAssertEqual(TreeholePresentation.boundedReply("一起上课"), "一起上课")
    }

    func testQuickReplyIdentityPreservesAnonymousBoardAndPostAuthor() {
        func post(category: String, anonymous: Bool, mine: Bool) -> TreeholePost {
            TreeholePost(id: "fixture", body: "", createdAt: "", anonymous: anonymous, locked: false, liked: false, saved: false,
                         author: TreeholeAuthor(name: "同学", anonymous: anonymous, mine: mine), commentCount: 0, likeCount: 0, category: category)
        }
        let daily = post(category: "daily", anonymous: true, mine: false)
        XCTAssertFalse(TreeholeReplyIdentity(post: daily, preferredAnonymous: false).isAnonymous)
        XCTAssertTrue(TreeholeReplyIdentity(post: daily, preferredAnonymous: true).isAnonymous)
        XCTAssertTrue(TreeholeReplyIdentity(post: post(category: "treehole", anonymous: false, mine: false), preferredAnonymous: false).isRequired)
        let author = TreeholeReplyIdentity(post: post(category: "daily", anonymous: true, mine: true), preferredAnonymous: false)
        XCTAssertTrue(author.isAnonymous)
        XCTAssertEqual(author.label, "保持楼主匿名身份")
    }

    func testCompactWeekGroupsOnlyOverlappingIntervals() {
        func course(_ start: String, _ end: String) -> Course {
            Course(name: start, day: 1, start: start, end: end, weeks: [1])
        }
        let day = TimetableDay([course("10:00", "10:30"), course("08:40", "09:20"),
                                course("09:15", "10:00"), course("08:00", "09:00")])
        XCTAssertEqual(day.clusters.map(\.count), [3, 1])
        XCTAssertEqual(day.clusters.first?.end, 600)
        XCTAssertEqual(day.laneCount, 2)
        XCTAssertTrue(TimetableDay([]).clusters.isEmpty)
    }

    private func service(_ vault: TreeholeMemoryVault) -> TreeholeService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TreeholeTestProtocol.self]
        return TreeholeService(vault: vault, session: URLSession(configuration: config))
    }
    override func tearDown() { TreeholeTestProtocol.handler = nil; TreeholeTestProtocol.pauseNext = false; TreeholeTestProtocol.resume = nil; TreeholeTestProtocol.paused = nil }
    @MainActor func testColdGalleryReadsAuthenticatedIdentityWithoutFetchingFeed() async throws {
        let vault=TreeholeMemoryVault(); vault.token=String(repeating:"z",count:43)
        let api=service(vault)
        var count=0
        TreeholeTestProtocol.handler={req in
            count+=1; XCTAssertEqual(req.url?.lastPathComponent,"me")
            let data=Data(#"{"user":{"id":"16C4C633-9417-4C1D-981E-6269A16DAE89","username":"测试","nickname":"同学","role":"member"}}"#.utf8)
            return (200,data)
        }
        let store=TreeholeStore(api:api)
        try await store.restoreGalleryIdentity()
        XCTAssertEqual(store.user?.username,"测试")
        XCTAssertLessThanOrEqual(count,1)
        vault.token=String(repeating:"y",count:43)
        let other=await api.cachedIdentity()
        XCTAssertNil(other)
    }
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
        XCTAssertEqual(TreeholePresentation.date("2026-11-14T01:00:00Z", now: now), "11/14 09:00")
        XCTAssertEqual(TreeholePresentation.date("2026-11-15T02:00:00Z", now: now), "11/15 10:00")
        XCTAssertEqual(TreeholePresentation.date("2026-11-12T16:10:00Z", now: now), "11/13 00:10")
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

    @MainActor func testAvatarPreparationCropsSquareAndPreservesOldPhotoPreparation() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 400)).image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400)) }
        let source = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let avatar = try TreeholeDraftStore.prepare(source, avatar: true), photo = try TreeholeDraftStore.prepare(source)
        let cropped = try XCTUnwrap(UIImage(data: avatar.data)), original = try XCTUnwrap(UIImage(data: photo.data))
        XCTAssertEqual(cropped.size.width, cropped.size.height); XCTAssertLessThanOrEqual(cropped.size.width, 512); XCTAssertLessThanOrEqual(avatar.data.count, 1_200_000)
        XCTAssertGreaterThan(original.size.width, original.size.height)
    }
    @MainActor func testResponsesRollBackAndClearLateAccountChanges() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.responsesEnabled = true
        let post = samplePost(); store.posts = [post]; store.current = post
        TreeholeTestProtocol.handler = { request in XCTAssertEqual(request.url?.lastPathComponent, "responses.set"); return (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        store.respond(post, kind: "hug"); XCTAssertEqual(store.current?.myResponse, "hug"); XCTAssertFalse(store.busy); try await settle(store)
        XCTAssertNil(store.current?.myResponse); XCTAssertEqual(store.current?.responseCounts, [:])
        var fresh = post; fresh.myResponse = "same"; fresh.responseCounts = ["same": 1]
        let response = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { _ in (200, response) }
        let delayed = expectation(description: "response held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
        store.respond(post, kind: "same"); await fulfillment(of: [delayed], timeout: 3); store.clear(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil
        try await Task.sleep(nanoseconds: 30_000_000); XCTAssertNil(store.current); XCTAssertTrue(store.posts.isEmpty); XCTAssertNil(store.restoreResponse(post).myResponse)
    }
    @MainActor func testResponseSwitchUpdatesOnlyResponseFieldsAndRouteSnapshot() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.responsesEnabled = true
        var post = samplePost(); post.myResponse = "same"; post.responseCounts = ["same": 1]; store.posts = [post]; store.current = post; store.profilePosts = [post]
        var result = post; result.myResponse = "hug"; result.responseCounts = ["hug": 1]
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(result))])
        TreeholeTestProtocol.handler = { _ in (200, data) }
        store.respond(post, kind: "hug"); store.current?.saved = true; try await settle(store)
        XCTAssertEqual(store.posts[0].responseCounts, ["hug": 1]); XCTAssertEqual(store.profilePosts[0].myResponse, "hug"); XCTAssertEqual(store.restoreResponse(post).myResponse, "hug"); XCTAssertEqual(store.current?.saved, true)
        result.responseCounts = ["hug": 3]; let refreshed = page([result]); TreeholeTestProtocol.handler = { _ in (200, refreshed) }; try await store.feed(); XCTAssertEqual(store.restoreResponse(post).responseCounts, ["hug": 3])
    }
    @MainActor func testLateAvatarResultDoesNotRestoreClearedUser() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.avatarsEnabled = true
        let member = TreeholeMember(id: "member", username: "test", nickname: "测试", role: "member", bannedUntil: nil)
        store.user = member
        let data = try JSONSerialization.data(withJSONObject: ["user": JSONSerialization.jsonObject(with: JSONEncoder().encode(member))])
        TreeholeTestProtocol.handler = { request in XCTAssertEqual(request.url?.lastPathComponent, "avatar.set"); return (200, data) }
        let delayed = expectation(description: "avatar held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
        let update = Task { try await store.setAvatar(nil) }; await fulfillment(of: [delayed], timeout: 3); store.clear(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil
        do { try await update.value; XCTFail("must discard previous account response") } catch is CancellationError { }
        XCTAssertNil(store.user)
    }
    func testDiscoveryLegacyDraftAndSectionMapping() throws {
        let old = Data("{\"title\":\"旧草稿\",\"body\":\"保留文字\",\"category\":\"study\",\"anonymous\":true,\"requestId\":\"old-key\",\"photos\":[]}".utf8)
        let draft = try JSONDecoder().decode(TreeholeDraft.self, from: old)
        XCTAssertEqual(draft.category, "study"); XCTAssertTrue(draft.anonymous); XCTAssertNil(draft.interest)
        XCTAssertEqual(TreeholeCategories.filters("study", interest: "games", enabled: true), ["section": "daily", "category": "study", "interest": ""])
        XCTAssertEqual(TreeholeCategories.filters("study", interest: "graduate", enabled: true)["interest"], "graduate")
        XCTAssertEqual(TreeholeCategories.filters("daily", interest: "games", enabled: true), ["section": "daily", "category": "daily", "interest": ""])
        XCTAssertEqual(TreeholeCategories.filters("daily", interest: "", enabled: false), ["category": "daily"])
        XCTAssertEqual(TreeholeCategories.filters("entertainment", interest: "music", enabled: true)["interest"], "music")
    }
    @MainActor func testDiscoveryFailureRestoresSelectionAndRetainsPreviousPosts() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.discoveryEnabled = true
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("kept")])) }
        try await store.selectDiscovery("study")
        TreeholeTestProtocol.handler = { _ in (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        do { try await store.selectDiscovery("entertainment", interest: "games"); XCTFail() } catch { }
        XCTAssertEqual(store.category, "study"); XCTAssertEqual(store.interest, ""); XCTAssertEqual(store.posts.map(\.id), ["kept"])
        store.clear(); XCTAssertEqual(store.category, "all"); XCTAssertEqual(store.interest, "")
    }
    @MainActor func testLateInterestPageCannotEnterAnotherTag() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.discoveryEnabled = true
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("games")], next: ["beforeId": "games"])) }
        try await store.selectDiscovery("entertainment", interest: "games")
        let held = expectation(description: "interest page held")
        TreeholeTestProtocol.handler = { _ in (200, self.page([self.samplePost("old-games-page")])) }
        TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { held.fulfill() }
        let loading = Task { await store.loadMoreFeed() }; await fulfillment(of: [held], timeout: 3)
        TreeholeTestProtocol.handler = { request in
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var chunk = [UInt8](repeating: 0, count: 1024); while stream.hasBytesAvailable { let n = stream.read(&chunk, maxLength: chunk.count); if n <= 0 { break }; bytes.append(contentsOf: chunk.prefix(n)) } }
            let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            XCTAssertEqual(body?["section"] as? String, "entertainment")
            XCTAssertEqual(body?["interest"] as? String, "music")
            XCTAssertEqual(body?["boardTopics"] as? Bool, true)
            return (200, self.page([self.samplePost("music")]))
        }
        try await store.selectDiscovery("entertainment", interest: "music")
        TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
        XCTAssertEqual(store.posts.map(\.id), ["music"]); XCTAssertNil(store.feedNext)
    }

    private func samplePost(_ id: String = "post-id", comments: Int = 1) -> TreeholePost {
        TreeholePost(id: id, body: "校园日常", createdAt: "2026-11-15T00:00:00Z", anonymous: false, locked: false, liked: false, saved: false, author: TreeholeAuthor(name: "同学", anonymous: false, mine: false), commentCount: comments, likeCount: 2)
    }
    @MainActor private func settle(_ store: TreeholeStore) async throws {
        for _ in 0..<200 {
            if store.pendingReactions.isEmpty && store.pendingCommentLikes.isEmpty && store.pendingResponses.isEmpty { return }
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
    @MainActor func testUnreadRefreshCoalescesForegroundSignalsAndAllowsExplicitRefreshAndNewSession() async {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        var instant = Date(timeIntervalSince1970: 1_000), calls = 0
        let store = TreeholeStore(api: service(vault), now: { instant })
        let member = TreeholeMember(id: "viewer", username: "viewer", nickname: "同学", role: "member", bannedUntil: nil)
        store.user = member; store.engagementEnabled = true
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "notifications.unread")
            calls += 1; return (200, Data("{\"unreadCount\":7}".utf8))
        }
        await store.refreshUnread(); await store.refreshUnread()
        XCTAssertEqual(calls, 1); XCTAssertEqual(store.unreadCount, 7)
        instant = instant.addingTimeInterval(31); await store.refreshUnread()
        XCTAssertEqual(calls, 1)
        instant = instant.addingTimeInterval(150); await store.refreshUnread()
        XCTAssertEqual(calls, 2)
        await store.refreshUnread(force: true); XCTAssertEqual(calls, 3)
        store.clear(); store.user = member; await store.refreshUnread()
        XCTAssertEqual(calls, 4); XCTAssertEqual(store.unreadCount, 7)
    }
    @MainActor func testInboxSurvivesReadFailureAndDoesNotRestoreClearedAccount() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault))
        store.user = TreeholeMember(id: "viewer", username: "viewer", nickname: "同学", role: "member", bannedUntil: nil); store.engagementEnabled = true
        let item = TreeholeNotification(id: "notice", kind: "reply", postId: "post", postTitle: "讨论", excerpt: "回复", createdAt: "2026-11-16T00:00:00Z", commentId: "comment", rootId: "root", actor: TreeholeAuthor(name: "匿名同学 · abc", anonymous: true, mine: false), readAt: nil)
        let payload = Data("{\"unreadCount\":1,\"notifications\":[".utf8) + (try JSONEncoder().encode(item)) + Data("]}".utf8)
        TreeholeTestProtocol.handler = { _ in (200, payload) }; await store.loadInbox()
        XCTAssertEqual(store.notifications.map(\.id), ["notice"]); XCTAssertEqual(store.unreadCount, 1)
        TreeholeTestProtocol.handler = { _ in (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        do { try await store.readNotifications([item.id]); XCTFail("Expected read failure") } catch { }
        XCTAssertNil(store.notifications.first?.readAt); XCTAssertEqual(store.unreadCount, 1)
        TreeholeTestProtocol.handler = { _ in (200, payload) }
        let delayed = expectation(description: "inbox response held")
        TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { delayed.fulfill() }
        let loading = Task { await store.loadInbox() }; await fulfillment(of: [delayed], timeout: 3)
        store.clear(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
        XCTAssertTrue(store.notifications.isEmpty); XCTAssertEqual(store.unreadCount, 0); XCTAssertFalse(store.inboxLoading)
    }
    @MainActor func testNotificationNavigationLoadsExactContextAndMarksOnlySelectedId() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)), post = samplePost()
        let comment = TreeholeComment(id: "late-reply", postId: post.id, body: "通知目标", createdAt: post.createdAt, replyTo: nil, author: post.author, deleted: false, isOriginalPoster: false)
        let item = TreeholeNotification(id: "notice", kind: "reply", postId: post.id, postTitle: "讨论", excerpt: "通知目标", createdAt: post.createdAt, commentId: comment.id, rootId: comment.id, actor: comment.author, readAt: nil)
        var actions: [String] = []
        TreeholeTestProtocol.handler = { request in
            let action = request.url!.lastPathComponent; actions.append(action)
            if action == "posts.get" { return (200, Data("{\"post\":".utf8) + (try! JSONEncoder().encode(post)) + Data(",\"comments\":[]}".utf8)) }
            if action == "comments.context" { return (200, Data("{\"context\":".utf8) + (try! JSONEncoder().encode(comment)) + Data("}".utf8)) }
            return (200, Data("{\"unreadCount\":0}".utf8))
        }
        store.notifications = [item]; store.unreadCount = 1
        try await store.notificationDetail(item)
        XCTAssertEqual(actions, ["posts.get", "comments.context", "notifications.read"])
        XCTAssertEqual(store.focusedThread?.id, comment.id); XCTAssertEqual(store.current?.id, post.id)
        XCTAssertNotNil(store.notifications.first?.readAt); XCTAssertEqual(store.unreadCount, 0)
    }
    @MainActor func testWatchFailurePreservesStatusAndPublicProfileClearsOnLogout() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); var post = samplePost(); post.watching = true
        store.current = post; store.posts = [post]
        TreeholeTestProtocol.handler = { _ in (503, Data("{\"error\":\"network_unavailable\"}".utf8)) }
        await store.toggleWatch(post); XCTAssertEqual(store.current?.watching, true); XCTAssertFalse(store.watchPending)
        store.publicProfile = TreeholePublicProfile(id: "public", nickname: "同学", bio: "简介", postCount: 1); store.profilePosts = [post]
        store.clear(); XCTAssertNil(store.publicProfile); XCTAssertTrue(store.profilePosts.isEmpty)
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

    @MainActor func testFollowingFailureRetainsStateAndSuccessUpdatesReturnSnapshotAndFeed() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.followingEnabled = true; store.scope = "following"
        let profile = TreeholePublicProfile(id: "author", nickname: "公开同学", bio: "", postCount: 1, following: true)
        store.publicProfile = profile; var post = samplePost(); post.author.id = "author"; store.posts = [post]
        store.following = [TreeholeFollow(id: "author", nickname: "公开同学", bio: "", followedAt: post.createdAt)]
        TreeholeTestProtocol.handler = { _ in (503, Data(#"{"error":"network_unavailable"}"#.utf8)) }
        await store.setFollow("author", enabled: false)
        XCTAssertEqual(store.publicProfile?.following, true); XCTAssertEqual(store.posts.count, 1); XCTAssertTrue(store.pendingFollows.isEmpty)
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "follows.set")
            return (200, Data(#"{"profile":{"id":"author","nickname":"公开同学","bio":"","postCount":1,"following":false}}"#.utf8))
        }
        await store.setFollow("author", enabled: false)
        XCTAssertEqual(store.publicProfile?.following, false); XCTAssertEqual(store.restoreProfile(profile).following, false)
        XCTAssertTrue(store.following.isEmpty); XCTAssertTrue(store.posts.isEmpty); XCTAssertTrue(store.feedNeedsRefresh)
    }
    @MainActor func testLateFollowResponseCannotRestorePreviousAccountState() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.followingEnabled = true
        store.publicProfile = TreeholePublicProfile(id: "author", nickname: "公开同学", bio: "", postCount: 0, following: false)
        TreeholeTestProtocol.handler = { _ in (200, Data(#"{"profile":{"id":"author","nickname":"公开同学","bio":"","postCount":0,"following":true}}"#.utf8)) }
        let held = expectation(description: "follow response held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { held.fulfill() }
        let task = Task { await store.setFollow("author", enabled: true) }; await fulfillment(of: [held], timeout: 3)
        store.clear(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await task.value
        XCTAssertNil(store.publicProfile); XCTAssertTrue(store.pendingFollows.isEmpty); XCTAssertTrue(store.following.isEmpty)
        XCTAssertNil(store.restoreProfile(TreeholePublicProfile(id: "author", nickname: "同学", bio: "", postCount: 0)).following)
    }
    @MainActor func testFollowingListFailureRetryDeduplicationAndLogoutIsolation() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.followingEnabled = true
        let one = TreeholeFollow(id: "one", nickname: "同学一", bio: "", followedAt: "2026-01-01"), two = TreeholeFollow(id: "two", nickname: "同学二", bio: "", followedAt: "2026-01-01")
        let initial = Data(#"{"following":[{"id":"one","nickname":"同学一","bio":"","followedAt":"2026-01-01"}],"next":{"beforeTime":"2026-01-01","beforeId":"one"}}"#.utf8)
        TreeholeTestProtocol.handler = { _ in (200, initial) }; await store.loadFollowing(); XCTAssertEqual(store.following, [one])
        TreeholeTestProtocol.handler = { _ in (503, Data(#"{"error":"network_unavailable"}"#.utf8)) }; await store.loadFollowing(more: true)
        XCTAssertEqual(store.following, [one]); XCTAssertNotNil(store.followingError); XCTAssertTrue(store.followingRetryMore)
        let page = Data("{\"following\":".utf8) + (try JSONEncoder().encode([one, two])) + Data("}".utf8)
        TreeholeTestProtocol.handler = { _ in (200, page) }; await store.loadFollowing(more: true)
        XCTAssertEqual(store.following, [one, two]); XCTAssertNil(store.followingNext); XCTAssertNil(store.followingError)
        let held = expectation(description: "following list held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { held.fulfill() }
        let loading = Task { await store.loadFollowing() }; await fulfillment(of: [held], timeout: 3)
        store.clear(); TreeholeTestProtocol.resume?(); TreeholeTestProtocol.resume = nil; await loading.value
        XCTAssertTrue(store.following.isEmpty); XCTAssertFalse(store.followingLoading)
    }
    @MainActor func testFollowingScopeFailureRestoresCriteriaAndDiscoveryKeepsFollowingScope() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.discoveryEnabled = true; store.scope = "saved"; store.query = "保留"; store.category = "study"; store.posts = [samplePost()]
        TreeholeTestProtocol.handler = { _ in (503, Data(#"{"error":"network_unavailable"}"#.utf8)) }
        do { try await store.selectScope("following"); XCTFail() } catch { }
        XCTAssertEqual(store.scope, "saved"); XCTAssertEqual(store.query, "保留"); XCTAssertEqual(store.category, "study"); XCTAssertEqual(store.posts.count, 1)
        TreeholeTestProtocol.handler = { _ in (200, Data(#"{"posts":[]}"#.utf8)) }; try await store.selectScope("following"); try await store.selectDiscovery("entertainment", interest: "games")
        XCTAssertEqual(store.scope, "following"); XCTAssertEqual(store.interest, "games"); XCTAssertEqual(store.query, "")
    }

    func testPollDraftValidationAndLegacyDraftDecoding() throws {
        var draft = TreeholePollDraft(); XCTAssertFalse(draft.valid)
        draft.question = "今天吃什么"; draft.options = ["面", "饭"]; XCTAssertTrue(draft.valid)
        draft.options = [" a ", "A"]; XCTAssertFalse(draft.valid)
        draft.options = ["面", "饭"]; draft.durationHours = 2; XCTAssertFalse(draft.valid)
        let legacy = Data(#"{"title":"旧草稿","body":"","category":"daily","anonymous":false,"requestId":"old","photos":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(TreeholeDraft.self, from: legacy); XCTAssertNil(decoded.poll); XCTAssertEqual(decoded.title, "旧草稿")
        var value = TreeholeDraft(); value.poll = draft; XCTAssertTrue(value.hasContent)
        XCTAssertEqual(try JSONDecoder().decode(TreeholeDraft.self, from: JSONEncoder().encode(value)).poll, draft)
    }
    func testPollDeadlineAndLegacyPlaceholders() throws {
        let poll = samplePoll(); XCTAssertFalse(poll.ended(at: Date(timeIntervalSince1970: 0))); XCTAssertTrue(poll.ended(at: .distantFuture))
        var post = samplePost(); post.poll = poll; XCTAssertEqual(post.displayBody, post.body)
        let data = Data(#"{"id":"c","postId":"p","body":"[图片]","createdAt":"now","replyTo":null,"author":{"name":"匿名同学","anonymous":true,"mine":false},"deleted":false,"isOriginalPoster":false,"images":[{"id":"i","width":1,"height":1}]}"#.utf8)
        let comment = try JSONDecoder().decode(TreeholeComment.self, from: data); XCTAssertEqual(comment.displayBody, ""); XCTAssertEqual(comment.images?.count, 1)
        let old = try JSONDecoder().decode(TreeholeComment.self, from: Data(#"{"id":"c","postId":"p","body":"文字","createdAt":"now","replyTo":null,"author":{"name":"同学","anonymous":false,"mine":false},"deleted":false,"isOriginalPoster":false}"#.utf8))
        XCTAssertNil(old.images); XCTAssertEqual(old.displayBody, "文字")
    }
    private func samplePoll(version: Int = 0, choice: String? = nil) -> TreeholePoll {
        TreeholePoll(version: version, question: "吃什么？", closesAt: "2099-01-01T00:00:00.000Z", closed: false, total: choice == nil ? 0 : 1, myOptionId: choice, options: [TreeholePollOption(id: "0", text: "面", count: choice == "0" ? 1 : 0), TreeholePollOption(id: "1", text: "饭", count: choice == "1" ? 1 : 0)])
    }
    @MainActor func testPollVoteFailureKeepsCommittedCountsAndSwitchUpdatesRoutes() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.pollsEnabled = true
        var post = samplePost(); post.poll = samplePoll(); store.posts = [post]; store.profilePosts = [post]; store.current = post
        TreeholeTestProtocol.handler = { request in XCTAssertEqual(request.url?.lastPathComponent, "polls.vote"); return (503, Data(#"{"error":"network_unavailable"}"#.utf8)) }
        await store.vote(post, optionId: "0"); XCTAssertEqual(store.current?.poll?.total, 0); XCTAssertNotNil(store.message)
        var fresh = post; fresh.poll = samplePoll(version: 1, choice: "1")
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { _ in (200, data) }; store.current?.saved = true
        await store.vote(post, optionId: "1"); XCTAssertEqual(store.current?.poll?.myOptionId, "1"); XCTAssertEqual(store.posts[0].poll, fresh.poll); XCTAssertEqual(store.profilePosts[0].poll, fresh.poll); XCTAssertEqual(store.restoreResponse(post).poll, fresh.poll); XCTAssertEqual(store.current?.saved, true)
        let stale = page([post]); TreeholeTestProtocol.handler = { _ in (200, stale) }; try await store.feed(); XCTAssertEqual(store.posts[0].poll?.version, 1)
    }
    @MainActor func testPollLateVoteCannotRestoreExpiredAccount() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.pollsEnabled = true
        var post = samplePost(); post.poll = samplePoll(); store.current = post
        var fresh = post; fresh.poll = samplePoll(version: 1, choice: "0")
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { _ in (200, data) }
        let paused = expectation(description: "vote held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { paused.fulfill() }
        let task = Task { await store.vote(post, optionId: "0") }; await fulfillment(of: [paused], timeout: 3)
        XCTAssertEqual(store.current?.poll?.total, 0); store.clear(); TreeholeTestProtocol.resume?(); await task.value
        XCTAssertNil(store.current); XCTAssertTrue(store.pendingVotes.isEmpty); XCTAssertEqual(store.restorePoll(post).poll?.version, 0)
    }
    @MainActor func testPollCloseErrorAndNullCancellationNativeTransport() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let api = service(vault), store = TreeholeStore(api: service(vault)); store.pollsEnabled = true
        var post = samplePost(); post.poll = samplePoll(); store.current = post
        TreeholeTestProtocol.handler = { _ in (409, Data(#"{"error":"poll_closed"}"#.utf8)) }
        await store.vote(post, optionId: "0"); XCTAssertEqual(store.current?.poll?.closed, true)
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 43))
            return (200, Data(#"{"sessionToken":"private"}"#.utf8))
        }
        let r = try await api.request("polls.vote", ["postId":"p", "optionId":NSNull()]); XCTAssertNil(r.sessionToken)
    }

    private func sampleBuddy(version: Int = 0, joined: Bool = false, closed: Bool = false) -> TreeholeBuddy {
        TreeholeBuddy(version: version, location: "东操场", startsAt: "2099-01-01T12:00:00Z", capacity: 2, count: joined ? 1 : 0, joined: joined, closed: closed, expired: false)
    }
    func testBuddyDateValidationCampusTimeAndLegacyDraft() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        var buddy = TreeholeBuddyDraft(location: "东操场", startsAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(3600)), capacity: 1)
        XCTAssertTrue(buddy.valid(at: now)); buddy.capacity = 0; XCTAssertFalse(buddy.valid(at: now)); buddy.capacity = 20; XCTAssertTrue(buddy.valid(at: now))
        buddy.startsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(91 * 86400)); XCTAssertFalse(buddy.valid(at: now))
        buddy.startsAt = "invalid"; XCTAssertFalse(buddy.valid(at: now))
        XCTAssertTrue(sampleBuddy().timeLabel.contains("2099-01-01 20:00")); XCTAssertFalse(sampleBuddy().ended(at: now)); XCTAssertTrue(sampleBuddy().ended(at: .distantFuture))
        let legacy = Data(#"{"title":"旧草稿","body":"","category":"buddies","anonymous":false,"requestId":"old","photos":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(TreeholeDraft.self, from: legacy).buddy)
        var draft = TreeholeDraft(); draft.buddy = buddy; XCTAssertTrue(draft.hasContent); XCTAssertEqual(try JSONDecoder().decode(TreeholeDraft.self, from: JSONEncoder().encode(draft)).buddy, buddy)
    }
    @MainActor func testBuddyJoinFailureAndRevisionMergeKeepUnrelatedPostState() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.buddiesEnabled = true
        var post = samplePost(); post.buddy = sampleBuddy(); store.posts = [post]; store.profilePosts = [post]; store.current = post
        TreeholeTestProtocol.handler = { _ in (503, Data(#"{"error":"network_unavailable"}"#.utf8)) }
        await store.buddyAction(post, action: "join", enabled: true); XCTAssertEqual(store.current?.buddy?.count, 0); XCTAssertNotNil(store.message)
        var fresh = post; fresh.buddy = sampleBuddy(version: 2, joined: true)
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { request in XCTAssertEqual(request.url?.lastPathComponent, "buddies.join"); return (200, data) }; store.current?.saved = true
        await store.buddyAction(post, action: "join", enabled: true)
        XCTAssertEqual(store.current?.saved, true); XCTAssertEqual(store.posts[0].buddy, fresh.buddy); XCTAssertEqual(store.profilePosts[0].buddy, fresh.buddy); XCTAssertEqual(store.restoreResponse(post).buddy, fresh.buddy)
        let stale = page([post]); TreeholeTestProtocol.handler = { _ in (200, stale) }; try await store.feed(); XCTAssertEqual(store.posts[0].buddy?.version, 2)
    }
    @MainActor func testBuddyLateJoinCannotRestoreExpiredAccount() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let store = TreeholeStore(api: service(vault)); store.buddiesEnabled = true
        var post = samplePost(); post.buddy = sampleBuddy(); store.current = post
        var fresh = post; fresh.buddy = sampleBuddy(version: 1, joined: true)
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { _ in (200, data) }
        let paused = expectation(description: "join held"); TreeholeTestProtocol.pauseNext = true; TreeholeTestProtocol.paused = { paused.fulfill() }
        let task = Task { await store.buddyAction(post, action: "join", enabled: true) }; await fulfillment(of: [paused], timeout: 3)
        store.clear(); TreeholeTestProtocol.resume?(); await task.value
        XCTAssertNil(store.current); XCTAssertTrue(store.pendingBuddies.isEmpty); XCTAssertEqual(store.restorePoll(post).buddy?.version, 0)
    }
    @MainActor func testBuddyFullRefreshAndNativeRosterPrivacy() async throws {
        let vault = TreeholeMemoryVault(); vault.token = String(repeating: "a", count: 43)
        let api = service(vault), store = TreeholeStore(api: service(vault)); store.buddiesEnabled = true
        var post = samplePost(); post.buddy = sampleBuddy(); store.current = post
        var fresh = post; fresh.buddy = sampleBuddy(version: 3, closed: true)
        let data = try JSONSerialization.data(withJSONObject: ["post": JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh))])
        TreeholeTestProtocol.handler = { request in request.url?.lastPathComponent == "buddies.join" ? (409, Data(#"{"error":"buddy_full"}"#.utf8)) : (200, data) }
        await store.buddyAction(post, action: "join", enabled: true); XCTAssertEqual(store.current?.buddy?.closed, true); XCTAssertNotNil(store.message)
        TreeholeTestProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "a", count: 43))
            return (200, Data(#"{"sessionToken":"private","participants":[{"id":"public-id","nickname":"同学","joinedAt":"now","avatar":null}]}"#.utf8))
        }
        let response = try await api.request("buddies.members", ["postId":"p"]); XCTAssertNil(response.sessionToken); XCTAssertEqual(response.participants?.first?.nickname, "同学")
        _ = try await api.request("buddies.close", ["postId":"p", "closed":false])
    }

}

// Only the test URLSession installs this protocol. Its only destination is the local CI database.
private final class CommunityLoopbackProtocol:URLProtocol {
    private var transfer:URLSessionDataTask?
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        var outgoing=request
        guard let action=outgoing.url?.lastPathComponent,TreeholeService.actions.contains(action) else {
            client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return
        }
        outgoing.url=URL(string:"http://127.0.0.1:18642/v1/")!.appendingPathComponent(action)
        if outgoing.httpBody == nil,let stream=outgoing.httpBodyStream {
            stream.open(); defer {stream.close()}
            var data=Data(),buf=[UInt8](repeating:0,count:4096)
            while true {let length=stream.read(&buf,maxLength:buf.count);if length<=0{break};data.append(buf,count:length)}
            outgoing.httpBodyStream=nil;outgoing.httpBody=data
        }
        transfer=URLSession.shared.dataTask(with:outgoing){ [weak self] data,response,error in
            guard let self else{return}
            if let error {self.client?.urlProtocol(self,didFailWithError:error);return}
            if let response {self.client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)}
            if let data {self.client?.urlProtocol(self,didLoad:data)}
            self.client?.urlProtocolDidFinishLoading(self)
        }
        transfer?.resume()
    }
    override func stopLoading(){transfer?.cancel()}
}

extension TreeholeTests {
    @MainActor func testIsolatedCommunityRegistrationPostingHonorsAndMessages() async throws {
        let cfg=URLSessionConfiguration.ephemeral
        cfg.protocolClasses=[CommunityLoopbackProtocol.self]
        let session=URLSession(configuration:cfg)
        let a=TreeholeService(vault:TreeholeMemoryVault(),session:session)
        let b=TreeholeService(vault:TreeholeMemoryVault(),session:session)
        let pass=UUID().uuidString
        let name="7同学"+String(UUID().uuidString.prefix(8))
        let ar=try await a.request("register",["username":name,"nickname":"测试同学","password":pass,"agreed":true])
        let br=try await b.request("register",["username":"乙"+String(UUID().uuidString.prefix(8)),"nickname":"测试伙伴","password":pass,"agreed":true])
        XCTAssertEqual(ar.user?.nickname, "测试同学")
        let sender=try XCTUnwrap(ar.user?.id), peer=try XCTUnwrap(br.user?.id)
        _=try await a.request("logout")
        let login=try await a.request("login",["username":name,"password":pass])
        XCTAssertEqual(login.user?.id,sender)
        let r=try await a.request("posts.create",["body":"校园测试中的第一篇有效帖子","category":"help","anonymous":false,"requestId":UUID().uuidString])
        let post=try XCTUnwrap(r.post?.id)
        let response = try await b.request("comments.create", ["body": "来自另一账号的有效评论", "anonymous": false, "postId": post, "requestId": UUID().uuidString])
        let commentID = try XCTUnwrap(response.comment?.id)
        let accepted = try await a.request("comments.accept", ["postId": post, "commentId": commentID, "enabled": true])
        XCTAssertEqual(accepted.post?.acceptedAnswerId, commentID)
        let removed = try await a.request("comments.accept", ["postId": post, "commentId": commentID, "enabled": false])
        XCTAssertNil(removed.post?.acceptedAnswerId)
        let collection = try await a.request("collection.profile", ["memberId": sender])
        XCTAssertEqual(collection.collection?.id, sender)
        do {
            _ = try await a.request("admin.members")
            XCTFail("A regular member received the private directory")
        } catch let failure as TreeholeError {
            XCTAssertEqual(failure.code, "forbidden")
        }
        for _ in 0..<2 { _=try await b.request("reactions.set",["postId":post,"kind":"like","enabled":true]) }
        let hall=try await a.request("honors.hall")
        XCTAssertNotNil(hall.hall?.awards["firstpost"]);XCTAssertEqual(hall.hall?.progress?["likes"],1)
        do{_=try await b.request("honors.manage");XCTFail("Member received management data")}catch let e as TreeholeError{XCTAssertEqual(e.code,"forbidden")}
        let opened=try await a.request("messages.open",["memberId":peer])
        let thread=try XCTUnwrap(opened.conversation?.id)
        let body=["conversationId":thread,"requestId":UUID().uuidString,"body":"你好，这是本地测试私信。"]
        let first=try await a.request("messages.send",body)
        let retry=try await a.request("messages.send",body)
        XCTAssertEqual(try XCTUnwrap(first.message?.id),retry.message?.id)
        let history=try await b.request("messages.list",["conversationId":thread])
        XCTAssertEqual(history.messages?.count,1);XCTAssertEqual(history.messages?.first?.mine,false)
    }
}

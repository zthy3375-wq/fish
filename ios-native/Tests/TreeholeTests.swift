import XCTest
@testable import Hanyuantong

private final class TreeholeMemoryVault: TreeholeTokenVault {
    var token: String?
    func read() throws -> String? { token }
    func save(_ value: String) throws { token = value }
    func clear() throws { token = nil }
}
private final class TreeholeTestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let (code, data) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
final class TreeholeTests: XCTestCase {
    private func service(_ vault: TreeholeMemoryVault) -> TreeholeService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TreeholeTestProtocol.self]
        return TreeholeService(vault: vault, session: URLSession(configuration: config))
    }
    override func tearDown() { TreeholeTestProtocol.handler = nil }
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

}

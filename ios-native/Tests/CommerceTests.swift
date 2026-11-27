import XCTest
@testable import Hanyuantong

private final class CommerceTestVault: TreeholeTokenVault {
    private var token: String?
    init(_ token: String?) { self.token = token }
    func read() throws -> String? { token }
    func save(_ value: String) throws { token = value }
    func clear() throws { token = nil }
}

private final class CommerceTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let authenticated = request.value(forHTTPHeaderField: "Authorization") != nil
        let isHome = url.path.hasSuffix(".home")
        let accepted = isHome ? !authenticated : authenticated
        let body = isHome ? #"{"ads":[]}"# : #"{"role":"student","memberId":"fixture","verifiedStudent":true}"#
        let response = HTTPURLResponse(url: url, statusCode: accepted ? 200 : 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CommerceTests: XCTestCase {
    func testPublicPlacementOmitsSessionAndProfileUsesIt() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommerceTestProtocol.self]
        let api = CommerceAPI(vault: CommerceTestVault(String(repeating: "a", count: 43)), session: URLSession(configuration: config))
        let home: CommercePlacements = try await api.request("home")
        XCTAssertTrue(home.ads.isEmpty)
        let profile: CommerceProfile = try await api.request("access")
        XCTAssertTrue(profile.verifiedStudent)
    }

    func testPrivateRequestWithoutTokenStopsBeforeNetwork() async throws {
        let api = CommerceAPI(vault: CommerceTestVault(nil))
        do {
            let _: CommercePage<CommerceCoupon> = try await api.request("wallet")
            XCTFail("Expected missing session to be rejected")
        } catch let error as CommerceFailure {
            XCTAssertEqual(error.code, "session_expired")
        }
    }

    func testCloudbaseDatesAndEncodedMapAddress() throws {
        XCTAssertEqual(CommerceAPI.timestamp("2026-11-27T01:00:00.12345+00:00")?.timeIntervalSince1970 ?? 0, 1795741200.123, accuracy: 0.01)
        let shop = try JSONDecoder().decode(CommerceShop.self, from: Data("""
        {"id":"f","name":"校园门店","category":"food","description":"介绍","hours":"10:00","phone":"0310-1234567","address":"邯郸 A&B","images":[]}
        """.utf8))
        let url = try XCTUnwrap(shop.mapURL)
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(parts?.queryItems?.first(where: { $0.name == "name" })?.value, shop.address)
        XCTAssertEqual(shop.phoneURL?.absoluteString, "tel:03101234567")
    }
}

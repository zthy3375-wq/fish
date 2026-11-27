#if DEBUG
import Foundation
import XCTest
@testable import Hanyuantong

final class ParcelDirectoryTests: XCTestCase {
    @MainActor
    func testAuthorizationDirectoryPaginationAndRestoration() async throws {
        let harness = Harness()
        let engine = harness.engine()
        harness.add(#"{"device_code":"synthetic-device","user_code":"ABCD","verification_uri":"https://example.test/authorize","expires_in":120}"#)
        await engine.begin()
        XCTAssertEqual(engine.userCode, "ABCD")
        await engine.poll()
        XCTAssertEqual(harness.paths, ["/oauth/device/code"])
        harness.time += 5
        harness.add(#"{"token_type":"Bearer","access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":3600}"#)
        harness.add(#"""
        {"items":[
          {"source":"taobao","carrier":" SF ","trackingNumber":" sf123 ","state":"ready","updatedAt":1000,"pickupCode":"001-2"},
          {"source":"taobao","carrier":"sf","trackingNumber":"SF456","state":"ready","updatedAt":1000}],"nextCursor":"two +"}
        """#)
        harness.add(#"""
        {"items":[
          {"source":"cainiao","carrier":"sf","trackingNumber":"SF123","state":"ready","updatedAt":1000},
          {"source":"cainiao","carrier":"sf","trackingNumber":"SF456","state":"picked_up","updatedAt":1000},
          {"source":"pinduoduo","carrier":"yto","trackingNumber":"YT789","state":"ready","updatedAt":1001,"pickupCode":"008"}]}
        """#)
        await engine.poll()
        XCTAssertEqual(engine.state, .ready)
        XCTAssertEqual(engine.snapshot?.items.compactMap(\.pickupCode), ["008", "001-2"])
        XCTAssertEqual(engine.snapshot?.items.last?.sources, ["cainiao", "taobao"])
        XCTAssertEqual(harness.bearers, [nil, nil, "synthetic-access", "synthetic-access"])
        XCTAssertEqual(harness.cursor, "two +")
        let restored = harness.engine()
        await restored.refresh()
        XCTAssertEqual(restored.state, .ready)
        XCTAssertEqual(harness.paths.count, 4)
        harness.time += 301
        harness.add(#"{"items":[]}"#)
        await restored.refresh()
        XCTAssertEqual(restored.state, .empty)
        await restored.disconnect()
        XCTAssertEqual(restored.state, .disconnected)
        XCTAssertNil(harness.disk)
    }

    @MainActor
    func testPartialRefreshKeepsSnapshotAndExpiredGrantDiffersFromEmpty() async {
        let harness = Harness()
        let engine = harness.engine()
        harness.add(#"{"device_code":"synthetic-device","user_code":"ABCD","verification_uri":"https://example.test/authorize","expires_in":120}"#)
        await engine.begin()
        harness.time += 5
        harness.add(#"{"token_type":"Bearer","access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":60}"#)
        harness.add(#"{"items":[{"source":"cainiao","carrier":"sf","trackingNumber":"SF123","state":"ready","updatedAt":1000,"pickupCode":"001"}]}"#)
        await engine.poll()
        let original = engine.snapshot?.updatedAt
        harness.time += 11
        harness.add(#"{"items":[],"nextCursor":"duplicate"}"#)
        harness.add(#"{"items":[],"nextCursor":"duplicate"}"#)
        await engine.refresh(force: true)
        XCTAssertEqual(engine.state, .incomplete)
        XCTAssertEqual(engine.snapshot?.updatedAt, original)
        XCTAssertEqual(engine.snapshot?.items.first?.pickupCode, "001")
        harness.time += 60
        harness.add(#"{"error":"invalid_grant"}"#, status: 400)
        await engine.refresh()
        XCTAssertEqual(engine.state, .expired)
    }

    @MainActor
    func testSlowDownLimitsPollAndRejectsUntrustedVerificationHost() async {
        let harness = Harness()
        let engine = harness.engine()
        harness.add(#"{"device_code":"synthetic-device","user_code":"ABCD","verification_uri":"https://other.test/authorize","expires_in":120}"#)
        await engine.begin()
        XCTAssertNil(engine.verificationURL)
        XCTAssertEqual(engine.state, .unavailable)
        harness.add(#"{"device_code":"synthetic-device","user_code":"ABCD","verification_uri":"https://example.test/authorize","expires_in":120}"#)
        await engine.begin()
        harness.time += 5
        harness.add(#"{"error":"slow_down"}"#, status: 400)
        await engine.poll()
        harness.time += 9
        await engine.poll()
        XCTAssertEqual(harness.paths.count, 3)
        harness.time += 1
        harness.add("{}", status: 429, retryAfter: 45)
        await engine.poll()
        XCTAssertEqual(engine.state, .rateLimited)
        harness.time += 44
        await engine.poll()
        XCTAssertEqual(harness.paths.count, 4)
        harness.time += 1
        harness.add(#"{"error":"access_denied"}"#, status: 400)
        await engine.poll()
        XCTAssertEqual(engine.state, .denied)
    }

    @MainActor private final class Harness {
        var disk: Data?
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var paths: [String] = []
        var bearers: [String?] = []
        var cursor: String?
        private var replies: [ParcelDirectory.Reply] = []

        func engine() -> ParcelDirectory {
            ParcelDirectory(config: .init(origin: "https://example.test", client: "ios-test"),
                            load: { self.disk }, save: { self.disk = $0 }, clear: { self.disk = nil },
                            request: { url, _, bearer in
                self.paths.append(url.path)
                self.bearers.append(bearer)
                self.cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
                guard !self.replies.isEmpty else { throw ParcelDirectory.State.unavailable }
                return self.replies.removeFirst()
            }, now: { self.time })
        }

        func add(_ json: String, status: Int = 200, retryAfter: TimeInterval = 0) {
            replies.append(.init(status: status, data: Data(json.utf8), retryAfter: retryAfter))
        }
    }
}
#endif

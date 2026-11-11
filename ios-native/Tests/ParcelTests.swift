import XCTest
import WebKit
@testable import Hanyuantong

final class ParcelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func cookie(_ value: String = "12345", provider: ParcelProvider = .taobao, domain: String? = nil, expires: Date? = nil) -> HTTPCookie {
        var p: [HTTPCookiePropertyKey: Any] = [.name: provider == .taobao ? "unb" : "pdd_user_id", .value: value,
            .domain: domain ?? (provider == .taobao ? ".taobao.com" : ".pinduoduo.net"), .path: "/", .secure: "TRUE"]
        if let expires { p[.expires] = expires }
        return HTTPCookie(properties: p)!
    }
    private func batch(_ phase: String = "partial", code: String = "01-02-003", provider: ParcelProvider = .taobao) throws -> ParcelReadBatch {
        let items: [[String: String]] = phase == "partial" ? [["station": "合成驿站", "code": code]] : []
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "provider": provider.rawValue, "phase": phase, "items": items])
        return try ParcelReadBatch.decode(String(decoding: data, as: UTF8.self), provider: provider)
    }
    func testNavigationAllowsOnlyExactOfficialHTTPSHosts() {
        XCTAssertTrue(ParcelPolicy.allowed(ParcelProvider.taobao.identityURL, provider: .taobao))
        XCTAssertTrue(ParcelPolicy.allowed(URL(string: "https://login.m.taobao.com/login.htm"), provider: .taobao))
        XCTAssertTrue(ParcelPolicy.allowed(ParcelProvider.pinduoduo.parcelURL, provider: .pinduoduo))
        for raw in ["http://m.pinduoduo.net/mdkd/package", "https://m.pinduoduo.net.evil.test/mdkd/package", "https://user@m.pinduoduo.net/mdkd/package", "https://m.pinduoduo.net:8443/mdkd/package", "https://m.pinduoduo.net./mdkd/package", "pinduoduo://com.xunmeng.pinduoduo/mdkd/package", "file:///tmp/page", "javascript:alert(1)", "https://mobile.yangkeduo.com/orders.html"] {
            XCTAssertFalse(ParcelPolicy.allowed(URL(string: raw), provider: .pinduoduo), raw)
        }
        XCTAssertFalse(ParcelPolicy.allowed(URL(string: "https://unverified.taobao.com/"), provider: .taobao))
        XCTAssertFalse(ParcelPolicy.allowed(ParcelProvider.pinduoduo.parcelURL, provider: .taobao))
    }
    func testReadRequiresExactProviderParcelPathNotIdentityOrLogin() {
        XCTAssertTrue(ParcelPolicy.readable(ParcelProvider.taobao.parcelURL, provider: .taobao))
        XCTAssertFalse(ParcelPolicy.readable(ParcelProvider.taobao.identityURL, provider: .taobao))
        XCTAssertFalse(ParcelPolicy.readable(URL(string: "https://m.pinduoduo.net/mdkd/package/other"), provider: .pinduoduo))
        XCTAssertFalse(ParcelPolicy.readable(URL(string: "https://m.pinduoduo.net/login"), provider: .pinduoduo))
    }
    func testCodeContractPreservesLeadingZerosAndRejectsPhoneTrackingValues() {
        for code in ["01-02-003", "A1 0203", "000123", "1—02—003"] { XCTAssertTrue(ParcelPolicy.code(code)) }
        for code in ["", "A", "ABC", "1234567890", "13912345678", "１２３４", "01\n02", "1<script>", "123456789012345678901234567", "1\t2"] { XCTAssertFalse(ParcelPolicy.code(code), code) }
    }
    func testStableNumericAccountScopeIsProviderBoundAndRejectsAmbiguity() throws {
        let taobao = try ParcelPolicy.account([cookie()], provider: .taobao, now: now)
        let pdd = try ParcelPolicy.account([cookie(provider: .pinduoduo)], provider: .pinduoduo, now: now)
        XCTAssertNotEqual(taobao, pdd); XCTAssertTrue(ParcelPolicy.validScope(taobao))
        XCTAssertThrowsError(try ParcelPolicy.account([cookie(), cookie("999")], provider: .taobao, now: now))
        XCTAssertThrowsError(try ParcelPolicy.account([cookie(domain: ".taobao.com.evil.test")], provider: .taobao, now: now))
        XCTAssertThrowsError(try ParcelPolicy.account([cookie("nickname")], provider: .taobao, now: now))
        XCTAssertThrowsError(try ParcelPolicy.account([cookie(expires: now.addingTimeInterval(-1))], provider: .taobao, now: now))
        XCTAssertThrowsError(try ParcelPolicy.account([], provider: .taobao, now: now))
    }
    func testBatchPhaseProviderAndLimitMustAgree() throws {
        XCTAssertEqual(try batch().items.first?.code, "01-02-003")
        for raw in [
            #"{"version":2,"provider":"taobao","phase":"empty","items":[]}"#,
            #"{"version":1,"provider":"pinduoduo","phase":"empty","items":[]}"#,
            #"{"version":1,"provider":"taobao","phase":"partial","items":[]}"#,
            #"{"version":1,"provider":"taobao","phase":"empty","items":[{"station":"测试","code":"01-02"}]}"#,
            #"{"version":1,"provider":"taobao","phase":"partial","items":[{"station":"测试","code":"13912345678"}]}"#,
            #"{"version":1,"provider":"taobao","phase":"partial","items":[{"station":"测试","code":"01-02"},{"station":"测试","code":"01-02"}]}"#
        ] { XCTAssertThrowsError(try ParcelReadBatch.decode(raw, provider: .taobao)) }
        XCTAssertThrowsError(try ParcelReadBatch.decode(String(repeating: "中", count: 34_000), provider: .taobao))
    }
    func testEmptyPartialAndFailedReadsNeverDeletePriorCodes() throws {
        let account = try ParcelPolicy.account([cookie()], provider: .taobao, now: now)
        var cache = ParcelCache(provider: .taobao, account: account)
        try cache.merge(batch(), account: account, now: now)
        let old = cache.items
        try cache.merge(batch("empty"), account: account, now: now.addingTimeInterval(10))
        XCTAssertEqual(cache.items, old); XCTAssertTrue(cache.lastReadWasEmpty)
        let beforeFailure = cache
        XCTAssertThrowsError(try cache.merge(batch("loading"), account: account, now: now.addingTimeInterval(20)))
        XCTAssertEqual(cache, beforeFailure)
        try cache.merge(batch(code: "03-04-005"), account: account, now: now.addingTimeInterval(30))
        XCTAssertEqual(cache.items.count, 2)
    }
    func testAccountChangeCannotMergeOrRestoreForeignCache() throws {
        let a = try ParcelPolicy.account([cookie()], provider: .taobao, now: now)
        let b = try ParcelPolicy.account([cookie("999")], provider: .taobao, now: now)
        var cache = ParcelCache(provider: .taobao, account: a)
        try cache.merge(batch(), account: a, now: now)
        let original = cache
        XCTAssertThrowsError(try cache.merge(batch(code: "99-001"), account: b, now: now))
        XCTAssertEqual(cache, original)
        XCTAssertThrowsError(try cache.validated(provider: .pinduoduo, account: a))
        XCTAssertThrowsError(try cache.validated(provider: .taobao, account: b))
        let envelope = ParcelEnvelope(cache: cache, cookies: [ParcelCookie(cookie("999"))], savedAt: now)
        XCTAssertThrowsError(try envelope.validated(provider: .taobao, now: now))
    }
    func testLocalTakenMarkSurvivesReadButDoesNotChangeOfficialState() throws {
        let scope = try ParcelPolicy.account([cookie()], provider: .taobao, now: now)
        var cache = ParcelCache(provider: .taobao, account: scope)
        try cache.merge(batch(), account: scope, now: now)
        cache.items[0].locallyTakenAt = now
        try cache.merge(batch(), account: scope, now: now.addingTimeInterval(20))
        XCTAssertEqual(cache.items[0].locallyTakenAt, now)
        XCTAssertEqual(cache.items[0].code, "01-02-003")
        XCTAssertEqual(cache.items[0].observedAt, now.addingTimeInterval(20))
    }
    func testCookieRoundTripIsSecureAndExpiredEnvelopeIsNotRestored() throws {
        let value = cookie()
        let savedCookie = ParcelCookie(value)
        XCTAssertTrue(try XCTUnwrap(savedCookie.cookie).isSecure)
        let scope = try ParcelPolicy.account([value], provider: .taobao, now: now)
        let envelope = ParcelEnvelope(cache: ParcelCache(provider: .taobao, account: scope), cookies: [savedCookie], savedAt: now)
        _ = try envelope.validated(provider: .taobao, now: now)
        XCTAssertThrowsError(try envelope.validated(provider: .taobao, now: now.addingTimeInterval(8 * 24 * 60 * 60)))
    }
    func testParcelVaultEncryptsAndClearDoesNotTouchOtherPlatforms() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ParcelVault(storage: try ProtectedStorage(directory: directory))
        for provider in ParcelProvider.allCases {
            let c = cookie(provider: provider)
            let scope = try ParcelPolicy.account([c], provider: provider, now: now)
            var cache = ParcelCache(provider: provider, account: scope)
            try cache.merge(batch(provider: provider), account: scope, now: now)
            try vault.write(ParcelEnvelope(cache: cache, cookies: [ParcelCookie(c)], savedAt: now), provider: provider, now: now)
            let raw = try Data(contentsOf: directory.appendingPathComponent(ParcelVault.filename(provider) + ".sealed"))
            XCTAssertNil(String(data: raw, encoding: .utf8))
            XCTAssertEqual(try vault.read(provider, now: now)?.cache.items.first?.code, "01-02-003")
        }
        try vault.remove(.taobao)
        XCTAssertNil(try vault.read(.taobao, now: now))
        XCTAssertNotNil(try vault.read(.pinduoduo, now: now))
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    @MainActor
    func testClosingSessionCancelsStateWithoutRetainingWebView() async {
        let session = ParcelSession(provider: .taobao, account: nil, received: { _, _, _ in XCTFail("Closed session accepted a result") }, invalidated: {})
        session.close()
        await session.prepare(cookies: [], identity: false)
        session.readCurrent()
        XCTAssertNil(session.web); XCTAssertFalse(session.isReading)
    }
    /// A network-denied WebKit document verifies the exact production isolated-world script.
    @MainActor
    func testActualWebKitRejectsWrongOriginWithoutReadingDocument() async throws {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let block = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "parcel-tests-inert", encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#)
        config.userContentController.add(try XCTUnwrap(block))
        let web = WKWebView(frame: .zero, configuration: config)
        let raw = try await web.callAsyncJavaScript(ParcelReader.script, arguments: ["requestedProvider": "taobao"], in: nil, contentWorld: .defaultClient)
        let result = try ParcelReadBatch.decode(try XCTUnwrap(raw as? String), provider: .taobao)
        XCTAssertEqual(result.phase, .unrecognized); XCTAssertTrue(result.items.isEmpty)
    }
}

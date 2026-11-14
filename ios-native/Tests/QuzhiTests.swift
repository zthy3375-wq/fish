import XCTest
@testable import Hanyuantong

final class QuzhiTests: XCTestCase {
    private func payload(_ data: Any) throws -> Data { try JSONSerialization.data(withJSONObject: ["success": true, "errorCode": 0, "data": data]) }
    private func object(_ source: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(source.utf8)) }
    private func session(phone: String = "13800000000", user: String = "synthetic-user") -> QuzhiSession {
        QuzhiSession(loginCode: "synthetic-login-code", userID: user, accountID: "account", projectID: "project", telephone: phone)
    }
    private func prior() -> QuzhiState {
        var snapshot = QuzhiSnapshot(); snapshot.school = "合成学校"
        snapshot.wallet = QuzhiWallet(total: "12.34"); snapshot.walletUpdatedAt = Date(timeIntervalSince1970: 1)
        snapshot.bills = [QuzhiBill(id: "old", date: "合成时间", amount: "0.125", description: "合成设备")]
        snapshot.billsMonth = "2026-10"; snapshot.billsUpdatedAt = Date(timeIntervalSince1970: 2)
        return QuzhiState(session: session(), snapshot: snapshot)
    }
    private func rejects(_ reason: QuzhiFailure, _ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) { XCTAssertEqual($0 as? QuzhiFailure, reason, file: file, line: line) }
    }
    func testPasswordAndPhoneContract() throws {
        XCTAssertEqual(try QuzhiProtocol.password("password"), "DEB882CF99")
        XCTAssertEqual(try QuzhiProtocol.smsSecret("13800000000").count, 32)
        rejects(.phone) { _ = try QuzhiProtocol.phone("13800000000&projectId=1") }
        rejects(.password) { _ = try QuzhiProtocol.password("") }
        rejects(.password) { _ = try QuzhiProtocol.password(String(repeating: "a", count: 129)) }
        rejects(.month) { _ = try QuzhiProtocol.month("2026-13") }
        rejects(.month) { _ = try QuzhiProtocol.month("2026-11\n") }
        rejects(.month) { _ = try QuzhiProtocol.month("2026-11&x=1") }
        XCTAssertEqual(try QuzhiProtocol.phone(" 13800000000 "), "13800000000")
    }
    func testShanghaiMonthAndMoneyFormatting() {
        XCTAssertEqual(QuzhiProtocol.currentMonth(Date(timeIntervalSince1970: 1793462400)), "2026-11")
        XCTAssertEqual(QuzhiProtocol.money(nil), "—")
        XCTAssertEqual(QuzhiProtocol.money("abc"), "—")
        XCTAssertEqual(QuzhiProtocol.money("12.345"), "12.345")
        XCTAssertEqual(QuzhiProtocol.money("0"), "0.00")
    }
    func testSessionsParseNestedAndFlatWithoutCrossAccountCollisions() throws {
        let nested = try QuzhiProtocol.session(object(#"{"loginCode":"nested","v3LoginCode":"unused","userId":12,"userAccount":{"accountId":34,"projectId":56}}"#), phone: "13800000000")
        XCTAssertEqual(nested.loginCode, "nested"); XCTAssertEqual(nested.accountID, "34")
        XCTAssertEqual(nested.maskedPhone, "138****0000"); XCTAssertEqual(nested.auth["telPhone"], "13800000000")
        let flat = try QuzhiProtocol.session(object(#"{"loginCode":"legacy","v3LoginCode":"v3","v3UserId":12,"projectId":56}"#), phone: "13800000000")
        XCTAssertEqual(flat.loginCode, "v3"); XCTAssertEqual(flat.userID, "12")
        XCTAssertNotEqual(nested.scope, flat.scope)
        XCTAssertNotEqual(session().scope, session(phone: "13900000000").scope)
        rejects(.format) { _ = try QuzhiProtocol.session(object(#"{"loginCode":"synthetic","userId":12}"#), phone: "13800000000") }
    }
    func testWalletUsesOnlyVerifiedUnitsAndRejectsConflicts() throws {
        XCTAssertEqual(try QuzhiProtocol.wallet(object(#"{"money":"0.00","accountRealMoney":123}"#)).total, "0")
        XCTAssertEqual(try QuzhiProtocol.wallet(object(#"{"accountMoney":12345}"#)).total, "12.345")
        XCTAssertEqual(try QuzhiProtocol.wallet(object(#"{"money":"12.345","accountMoney":"12345"}"#)).total, "12.345")
        rejects(.unverifiedUnits) { _ = try QuzhiProtocol.wallet(object(#"{"money":"12.34","accountMoney":12345}"#)) }
        rejects(.unverifiedUnits) { _ = try QuzhiProtocol.wallet(object(#"{"accountRealMoney":"3.50","accountGivenMoney":1}"#)) }
        rejects(.format) { _ = try QuzhiProtocol.wallet(object(#"{"money":"免费"}"#)) }
        rejects(.format) { _ = try QuzhiProtocol.wallet(object(#"{"accountMoney":12.345}"#)) }
    }
    func testBathCodeIsCompleteServerValueAndNeverReconstructed() throws {
        let now = Date(timeIntervalSince1970: 1)
        let code = try QuzhiProtocol.bathCode(object(#"{"useCode":"00123456","useCodeStatus":1,"useCodeRandom":"456"}"#), now: now)
        XCTAssertEqual(code.code, "00123456"); XCTAssertTrue(code.enabled)
        XCTAssertEqual(code.queriedAt, now)
        XCTAssertFalse(try QuzhiProtocol.bathCode(object(#"{"useCodeStatus":"0"}"#), now: now).enabled)
        for source in [#"{"useCodeRandom":"456","useCodeStatus":1}"#, #"{"useCode":"123","useCodeStatus":1}"#, #"{"useCode":"00123456"}"#, #"{"useCode":"00123456","useCodeStatus":2}"#, #"{"useCode":"00123456<script>","useCodeStatus":1}"#] {
            rejects(.format) { _ = try QuzhiProtocol.bathCode(object(source), now: now) }
        }
    }
    func testBillsBoundedAndExplicitEmptyDistinguishedFromMalformed() throws {
        XCTAssertTrue(try QuzhiProtocol.bills([]).items.isEmpty)
        rejects(.format) { _ = try QuzhiProtocol.bills(["items": []]) }
        rejects(.format) { _ = try QuzhiProtocol.bills([["differentShape": [:]]]) }
        let row: [String: Any] = ["consumeBillDTO": ["orderNo": 123, "consumeMoney": "0.125", "deviceDescription": "合成设备"]]
        let result = try QuzhiProtocol.bills(Array(repeating: row, count: 201))
        XCTAssertEqual(result.items.count, 200); XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.items.first?.amount, "0.125")
    }
    func testEnvelopeRejectsMalformedAuthAndThrottling() throws {
        XCTAssertEqual(try QuzhiProtocol.payload(payload(3)) as? Int, 3)
        let cases: [(String, QuzhiFailure)] = [
            (#"{"success":false,"errorCode":8,"message":"未获取到用户信息，请重新登录"}"#, .auth),
            (#"{"success":false,"errorCode":2,"message":"签名过期，请重新登录"}"#, .service),
            (#"{"success":false,"errorCode":2,"message":"请求过于频繁"}"#, .verify),
            (#"{"success":1,"errorCode":0,"data":3}"#, .service),
            (#"{"success":true,"errorCode":9}"#, .service)]
        for (source, failure) in cases { rejects(failure) { _ = try QuzhiProtocol.payload(Data(source.utf8)) } }
        rejects(.format) { _ = try QuzhiProtocol.payload(Data(repeating: 32, count: QuzhiProtocol.responseLimit + 1)) }
    }
    func testFixedTransportRejectsOriginPathMethodAndCredentialInjection() throws {
        XCTAssertTrue(QuzhiClient.allowed(URL(string: "https://v3-api.china-qzxy.cn/account/wallet")))
        for url in ["http://v3-api.china-qzxy.cn/account/wallet", "https://v3-api.china-qzxy.cn.evil.test/account/wallet", "https://user@v3-api.china-qzxy.cn/account/wallet", "https://v3-api.china-qzxy.cn:8443/account/wallet", "https://v3-api.china-qzxy.cn/account/useCode/enable", "https://v3-api.china-qzxy.cn/account/wallet#fragment"] {
            XCTAssertFalse(QuzhiClient.allowed(URL(string: url)))
        }
        rejects(.request) { _ = try QuzhiClient.makeRequest(path: "https://evil.test", values: [:], post: false) }
        rejects(.request) { _ = try QuzhiClient.makeRequest(path: "account/wallet", values: [:], post: true) }
        rejects(.request) { _ = try QuzhiClient.makeRequest(path: "user/login", values: [:], post: false) }
        let request = try QuzhiClient.makeRequest(path: "user/login", values: ["password": "x&+y= z"], post: true)
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "password=x%26%2By%3D%20z")
        XCTAssertNil(request.url?.query); XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testTransportRefusesBothSameOriginAndExternalRedirects() throws {
        let client = QuzhiClient(), session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = QuzhiProtocol.base.appendingPathComponent("account/wallet")
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil))
        for target in [original, URL(string: "https://example.invalid/collect")!] {
            var invoked = false
            client.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) {
                invoked = true; XCTAssertNil($0)
            }
            XCTAssertTrue(invoked)
        }
    }
    func testRechargeURLContainsNoUserDataOrPaymentAmount() throws {
        let components = try XCTUnwrap(URLComponents(url: QuzhiProtocol.recharge, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "alipays")
        XCTAssertEqual(components.queryItems?.map(\.name).sorted(), ["appId", "page"])
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "page" })?.value, "pages/recharge/recharge")
        XCTAssertFalse(QuzhiProtocol.paths.contains(where: { $0.contains("pay") || $0.contains("recharge") }))
    }

    @MainActor func testAllFailedQueriesPreserveSuccessfulDataAndDates() async {
        let old = prior(), storage = QuzhiMemoryPersistence(prior())
        let transport = QuzhiScriptTransport([.failure(.network), .failure(.format)])
        let store = QuzhiStore(transport: transport, persistence: storage)
        let result = await store.refresh(month: "2026-11")
        XCTAssertTrue(result)
        XCTAssertEqual(store.snapshot.wallet, old.snapshot.wallet)
        XCTAssertEqual(store.snapshot.walletUpdatedAt, old.snapshot.walletUpdatedAt)
        XCTAssertEqual(store.snapshot.bills, old.snapshot.bills)
        XCTAssertEqual(store.snapshot.billsMonth, "2026-10")
        XCTAssertEqual(store.snapshot.billsUpdatedAt, old.snapshot.billsUpdatedAt)
        XCTAssertEqual(store.snapshot.issues, ["wallet": .network, "bills": .format])
    }
    @MainActor func testAuthFailureStopsRemainingRequests() async {
        let storage = QuzhiMemoryPersistence(prior()), transport = QuzhiScriptTransport([.failure(.auth)])
        let store = QuzhiStore(transport: transport, persistence: storage)
        _ = await store.refresh(month: "2026-11")
        let paths = await transport.paths
        XCTAssertEqual(paths, ["account/wallet"])
        XCTAssertTrue(store.expired); XCTAssertEqual(store.snapshot.wallet?.total, "12.34")
        XCTAssertEqual(store.snapshot.issues["bills"], .auth)
    }
    @MainActor func testPartialSuccessAndExplicitEmptyBillsReplaceOnlyRequestedMonth() async throws {
        let storage = QuzhiMemoryPersistence(prior())
        let transport = QuzhiScriptTransport([.failure(.network), .data(try payload([]))])
        let store = QuzhiStore(transport: transport, persistence: storage, now: { Date(timeIntervalSince1970: 10) })
        _ = await store.refresh(month: "2026-11")
        XCTAssertEqual(store.snapshot.walletUpdatedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.snapshot.billsMonth, "2026-11"); XCTAssertTrue(store.snapshot.bills.isEmpty)
        XCTAssertEqual(store.snapshot.billsUpdatedAt, Date(timeIntervalSince1970: 10))
    }
    @MainActor func testNewLoginVerifiesWalletBeforeAdoptionAndIsolatesAccount() async throws {
        let storage = QuzhiMemoryPersistence(prior())
        let login = try payload(["loginCode": "new-synthetic", "userId": "other", "accountId": "other", "projectId": "other"])
        let transport = QuzhiScriptTransport([.data(login), .data(try payload(["money": "9.99"]))])
        let store = QuzhiStore(transport: transport, persistence: storage)
        let result = await store.login(phone: "13900000000", secret: "synthetic-password", mode: .password, consent: false)
        XCTAssertTrue(result); XCTAssertEqual(store.phone, "139****0000"); XCTAssertEqual(store.balanceText, "9.99")
        XCTAssertTrue(store.snapshot.bills.isEmpty); XCTAssertEqual(store.snapshot.school, "")
        XCTAssertNil(store.snapshot.billsMonth)
        let paths = await transport.paths
        XCTAssertEqual(paths, ["user/login", "account/wallet"])
    }
    @MainActor func testFailedWalletVerificationOrSaveDoesNotAdoptAccount() async throws {
        for failure in [false, true] {
            let storage = QuzhiMemoryPersistence(prior()); storage.failSave = failure
            let transport = QuzhiScriptTransport([.data(try payload(["loginCode": "new-synthetic", "userId": "new", "projectId": "new"])), failure ? .data(try payload(["money": "1"])) : .failure(.format)])
            let store = QuzhiStore(transport: transport, persistence: storage)
            let result = await store.login(phone: "13900000000", secret: "synthetic", mode: .password, consent: false)
            XCTAssertFalse(result); XCTAssertEqual(store.phone, "138****0000")
            XCTAssertEqual(store.snapshot.wallet?.total, "12.34")
        }
    }
    @MainActor func testSMSNeedsConsentAndCooldownSurvivesRecreatedStoreAndTimeout() async throws {
        let transport = QuzhiScriptTransport([.failure(.network)])
        let first = QuzhiStore(transport: transport, persistence: QuzhiMemoryPersistence(), uptime: { 1000 })
        let denied = await first.sendSMS(phone: "13711112222", consent: false)
        XCTAssertFalse(denied)
        let initially = await transport.paths; XCTAssertTrue(initially.isEmpty)
        _ = await first.sendSMS(phone: "13711112222", consent: true)
        first.cancel()
        let second = QuzhiStore(transport: transport, persistence: QuzhiMemoryPersistence(), uptime: { 1001 })
        let retry = await second.sendSMS(phone: "13711112222", consent: true)
        XCTAssertFalse(retry); XCTAssertTrue(second.loginMessage.contains("59"))
        let paths = await transport.paths; XCTAssertEqual(paths.count, 1)
        let result = await second.login(phone: "13711112222", secret: "123456", mode: .sms, consent: false)
        XCTAssertFalse(result)
        let after = await transport.paths; XCTAssertEqual(after.count, 1)
    }
    @MainActor func testLogoutFencesLateLoginAndDoesNotRecreateCredentials() async throws {
        let transport = QuzhiDelayedTransport(), storage = QuzhiMemoryPersistence(prior())
        let store = QuzhiStore(transport: transport, persistence: storage)
        let work = Task { await store.login(phone: "13900000000", secret: "synthetic", mode: .password, consent: false) }
        let pending = await transport.waitForPending(); XCTAssertTrue(pending)
        XCTAssertTrue(store.logout())
        await transport.complete(try payload(["loginCode": "late", "userId": "other", "projectId": "other"]))
        let accepted = await work.value
        XCTAssertFalse(accepted); XCTAssertFalse(store.connected); XCTAssertNil(storage.value)
        XCTAssertEqual(storage.saves, 0)
    }
    @MainActor func testNewStoreOwnershipFencesOldRefresh() async throws {
        let transport = QuzhiDelayedTransport(), storage = QuzhiMemoryPersistence(prior())
        let old = QuzhiStore(transport: transport, persistence: storage)
        let work = Task { await old.refresh(month: "2026-11") }
        let pending = await transport.waitForPending(); XCTAssertTrue(pending)
        let replacement = QuzhiStore(transport: QuzhiScriptTransport([]), persistence: storage)
        XCTAssertTrue(replacement.logout())
        await transport.complete(try payload(["money": "100"]))
        let accepted = await work.value
        XCTAssertFalse(accepted); XCTAssertNil(storage.value); XCTAssertEqual(storage.saves, 0)
    }
    @MainActor func testConcealFencesLateBathCodeAndNeverPersistsIt() async throws {
        let transport = QuzhiDelayedTransport(), storage = QuzhiMemoryPersistence(prior())
        let store = QuzhiStore(transport: transport, persistence: storage)
        let work = Task { await store.revealBathCode() }
        let pending = await transport.waitForPending(); XCTAssertTrue(pending)
        store.concealBathCode()
        await transport.complete(try payload(["useCode": "00123456", "useCodeStatus": 1]))
        let accepted = await work.value
        XCTAssertFalse(accepted); XCTAssertNil(store.bathCode); XCTAssertEqual(storage.saves, 0)
    }
    @MainActor func testBackgroundClearsDisplayedBathCodeAndRechargeRequiresValidSession() async throws {
        let storage = QuzhiMemoryPersistence(prior())
        let transport = QuzhiScriptTransport([.data(try payload(["useCode": "00123456", "useCodeStatus": 1]))])
        let store = QuzhiStore(transport: transport, persistence: storage)
        let revealed = await store.revealBathCode(); XCTAssertTrue(revealed)
        XCTAssertNotNil(store.bathCode); XCTAssertEqual(storage.saves, 0)
        store.suspend(); XCTAssertNil(store.bathCode)
        XCTAssertEqual(store.beginRechargeHandoff(), QuzhiProtocol.recharge)
        store.finishRechargeHandoff(opened: false); XCTAssertFalse(store.returnedFromRecharge)
        XCTAssertTrue(store.logout()); XCTAssertNil(store.beginRechargeHandoff())
    }
    @MainActor func testRestoreFailureReportsStorageErrorAndClearsItOnRetry() {
        let storage = QuzhiMemoryPersistence(prior()); storage.failRestore = true
        let store = QuzhiStore(transport: QuzhiScriptTransport([]), persistence: storage)
        XCTAssertFalse(store.ready); XCTAssertFalse(store.connected)
        XCTAssertEqual(store.error, QuzhiFailure.storage.localizedDescription)
        storage.failRestore = false
        store.restore()
        XCTAssertTrue(store.ready); XCTAssertTrue(store.connected)
        XCTAssertEqual(store.error, "")
        XCTAssertEqual(store.snapshot, prior().snapshot)
    }
    @MainActor func testFailedLogoutClearsVisibleSecretsAndBlocksNewOperations() async {
        let storage = QuzhiMemoryPersistence(prior()); storage.failClear = true
        let transport = QuzhiScriptTransport([])
        let store = QuzhiStore(transport: transport, persistence: storage)
        XCTAssertFalse(store.logout())
        XCTAssertFalse(store.connected); XCTAssertNil(store.snapshot.wallet)
        XCTAssertTrue(store.cleanupRequired); XCTAssertNil(store.beginRechargeHandoff())
        let allowed = await store.login(phone: "13900000000", secret: "synthetic", mode: .password, consent: false)
        XCTAssertFalse(allowed)
        let paths = await transport.paths; XCTAssertTrue(paths.isEmpty)
        storage.failClear = false
        XCTAssertTrue(store.logout()); XCTAssertFalse(store.cleanupRequired)
    }
    @MainActor func testVaultLogoutDeletionFailureRemainsRetryableAfterRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = "org.handancampus.quzhi.tests." + UUID().uuidString
        var failuresRemaining = 1
        let remove: (URL) throws -> Void = { file in
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: file)
        }
        let vault = QuzhiVault(service: service, directory: directory, removeFile: remove)
        defer { try? vault.clear(); try? FileManager.default.removeItem(at: directory) }
        try vault.save(prior())
        let cache = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let unrelatedNames = ["personal.sealed", "school.sealed", "pangguai.sealed", "quzhi-other-feature.sealed", "quzhi-" + String(repeating: "a", count: 64) + "-" + String(repeating: "-", count: 36) + ".sealed"]
        let marker = Data("unrelated-feature-record".utf8)
        for name in unrelatedNames { try marker.write(to: directory.appendingPathComponent(name)) }
        let nested = directory.appendingPathComponent("other-feature", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedRecord = nested.appendingPathComponent(cache.lastPathComponent)
        try marker.write(to: nestedRecord)

        XCTAssertThrowsError(try vault.clear()) { XCTAssertEqual($0 as? QuzhiFailure, .storage) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        // The first attempt revoked the session; the new vault must find the old cache without it.
        let retry = QuzhiVault(service: service, directory: directory, removeFile: remove)
        try retry.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertNil(try retry.restore())
        for name in unrelatedNames { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), marker) }
        XCTAssertEqual(try Data(contentsOf: nestedRecord), marker)
    }
    @MainActor func testOldCacheCleanupFailurePreservesCommittedAccountAndRetriesOnRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = "org.handancampus.quzhi.tests." + UUID().uuidString
        var failuresRemaining = 1
        let remove: (URL) throws -> Void = { file in
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: file)
        }
        let vault = QuzhiVault(service: service, directory: directory, removeFile: remove)
        defer { try? vault.clear(); try? FileManager.default.removeItem(at: directory) }
        try vault.save(prior())
        let oldFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var next = prior()
        next.session = session(phone: "13900000000", user: "other")
        next.snapshot = QuzhiSnapshot(); next.snapshot.wallet = QuzhiWallet(total: "9.99")
        try vault.save(next)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        let restored = try QuzhiVault(service: service, directory: directory, removeFile: remove).restore()
        XCTAssertEqual(restored?.session, next.session)
        XCTAssertEqual(restored?.snapshot, next.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
    @MainActor func testCleanupRejectsMatchingSymlinkWithoutFollowingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = "org.handancampus.quzhi.tests." + UUID().uuidString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("personal.sealed")
        let bytes = Data("synthetic-personal-record".utf8)
        try bytes.write(to: target)
        let link = directory.appendingPathComponent("quzhi-" + String(repeating: "a", count: 64) + "-" + UUID().uuidString + ".sealed")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = QuzhiVault(service: service, directory: directory)
        XCTAssertThrowsError(try vault.clear()) { XCTAssertEqual($0 as? QuzhiFailure, .storage) }
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }
    @MainActor func testSecureVaultRoundTripAccountIsolationAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = "org.handancampus.quzhi.tests." + UUID().uuidString
        let vault = QuzhiVault(service: service, directory: directory)
        defer { try? vault.clear(); try? FileManager.default.removeItem(at: directory) }
        try vault.save(prior())
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let encrypted = try Data(contentsOf: files[0])
        XCTAssertFalse(encrypted.range(of: Data("synthetic-login-code".utf8)) != nil)
        XCTAssertFalse(encrypted.range(of: Data("12.34".utf8)) != nil)
        let restored = try QuzhiVault(service: service, directory: directory).restore()
        XCTAssertEqual(restored?.snapshot, prior().snapshot)
        var other = prior(); other.session = session(phone: "13900000000", user: "other"); other.snapshot = QuzhiSnapshot()
        try vault.save(other)
        XCTAssertEqual(try vault.restore()?.session.scope, other.session.scope)
        XCTAssertTrue(try vault.restore()?.snapshot.bills.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path))
        try vault.clear(); XCTAssertNil(try vault.restore())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

@MainActor private final class QuzhiMemoryPersistence: QuzhiPersistence {
    var value: QuzhiState?
    var failSave = false
    var failRestore = false
    var failClear = false
    var saves = 0
    init(_ state: QuzhiState? = nil) { value = state }
    func restore() throws -> QuzhiState? { if failRestore { throw QuzhiFailure.storage }; return value }
    func save(_ state: QuzhiState) throws { if failSave { throw QuzhiFailure.storage }; value = state; saves += 1 }
    func clear() throws { if failClear { throw QuzhiFailure.storage }; value = nil }
}
private actor QuzhiScriptTransport: QuzhiTransport {
    enum Reply { case data(Data), failure(QuzhiFailure) }
    var paths: [String] = []
    var replies: [Reply]
    init(_ replies: [Reply]) { self.replies = replies }
    func request(path: String, values: [String: String], post: Bool) async throws -> Data {
        paths.append(path)
        guard !replies.isEmpty else { throw QuzhiFailure.network }
        switch replies.removeFirst() { case .data(let data): return data; case .failure(let error): throw error }
    }
}
private actor QuzhiDelayedTransport: QuzhiTransport {
    private var pending: CheckedContinuation<Data, Error>?
    func request(path: String, values: [String: String], post: Bool) async throws -> Data {
        // Intentionally ignores cancellation, simulating a late transport callback.
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForPending() async -> Bool {
        for _ in 0..<10000 { if pending != nil { return true }; await Task.yield() }
        return false
    }
    func complete(_ data: Data) { pending?.resume(returning: data); pending = nil }
}

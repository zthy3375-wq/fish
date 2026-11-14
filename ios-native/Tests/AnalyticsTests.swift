import XCTest
import Security
@testable import Hanyuantong

@MainActor final class AnalyticsTests: XCTestCase {
    private let identity = AnalyticsIdentity(id: "12345678-1234-4123-8123-123456789abc", token: String(repeating: "a", count: 64))
    private let build = AnalyticsBuild(version: "0.1.0", number: 102, rolloutReviewed: true)
    private let instant = Date(timeIntervalSince1970: 1_794_412_800)
    private func saved(choice: AnalyticsChoice = .on) -> AnalyticsRecord {
        var r = AnalyticsRecord(); r.choice = choice; r.identity = identity; r.enrolled = true; r.dirty = true
        return r
    }
    private func make(_ storage: AnalyticsMemoryStorage, _ transport: AnalyticsTestTransport, build: AnalyticsBuild? = nil) -> AnonymousAnalyticsStore {
        AnonymousAnalyticsStore(storage: storage, transport: transport, build: build ?? self.build, now: { self.instant }, makeIdentity: { self.identity })
    }

    func testNoConsentDoesNotCreateIdentityWriteCountersOrSend() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
        var identities = 0
        let store = AnonymousAnalyticsStore(storage: memory, transport: http, build: build, now: { self.instant }, makeIdentity: { identities += 1; return self.identity })
        for feature in AnalyticsFeature.allCases { store.recordFeature(feature) }
        store.flush(force: true); await store.waitForIdle()
        XCTAssertEqual(store.state.choice, .unset); XCTAssertEqual(identities, 0)
        XCTAssertEqual(memory.writes, 0); XCTAssertTrue(http.requests.isEmpty)
    }
    func testCurrentReleaseGateAndBackendVersionFloorFailClosed() async {
        XCTAssertNotNil(AnalyticsBuild.current.unavailableReason)
        for candidate in [AnalyticsBuild(version: "0.1.0", number: 1, rolloutReviewed: true),
                          AnalyticsBuild(version: "0.1.0", number: 102, rolloutReviewed: false),
                          AnalyticsBuild(version: "0.1.0-test", number: 102, rolloutReviewed: true)] {
            let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
            let store = make(memory, http, build: candidate)
            store.setEnabled(true); store.recordFeature(.water); store.flush(force: true)
            await store.waitForIdle()
            XCTAssertNotNil(store.unavailableReason); XCTAssertFalse(store.canEnable)
            XCTAssertFalse(store.state.hasIdentity); XCTAssertEqual(memory.writes, 0); XCTAssertTrue(http.requests.isEmpty)
        }
    }
    func testDeclinePersistsOnlyChoiceAndCannotBeOverriddenByFeatureUse() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport(), store = make(memory, http)
        store.setEnabled(false); store.recordFeature(.schedule); store.flush(force: true)
        await store.waitForIdle()
        XCTAssertEqual(memory.value?.choice, .off); XCTAssertNil(memory.value?.identity)
        XCTAssertNil(memory.value?.counters); XCTAssertTrue(http.requests.isEmpty)
    }
    func testExplicitOptInSavesIdentityBeforeEnrollmentAndUsesHonestVersion() async throws {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
        http.handler = { _ in
            XCTAssertEqual(memory.value?.choice, .on); XCTAssertEqual(memory.value?.identity, self.identity)
            return AnalyticsResponse(status: 200, ok: true)
        }
        let store = make(memory, http); store.setEnabled(true); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["enroll", "record"]); XCTAssertNotNil(store.state.lastSent)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(http.requests.last?.httpBody)) as? [String: Any])
        XCTAssertEqual(body["version"] as? String, "0.1.0"); XCTAssertEqual(body["versionCode"] as? Int, 102)
        XCTAssertEqual(http.requests.last?.value(forHTTPHeaderField: "User-Agent"), "Hanyuantong/0.1.0 iOS")
    }
    func testImmediateDisableBeforeQueuedSendNeverEnrolls() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport(), store = make(memory, http)
        store.setEnabled(true); store.setEnabled(false); await store.waitForIdle()
        XCTAssertTrue(http.requests.isEmpty); XCTAssertEqual(store.state.choice, .off)
        XCTAssertEqual(memory.value?.enrollmentInFlight, false)
    }
    func testImmediateDeleteBeforeQueuedSendNeverEnrollsOrDuplicatesDelete() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport(), store = make(memory, http)
        store.setEnabled(true); store.deleteData(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["delete"]); XCTAssertFalse(store.state.deletePending)
    }
    func testOffDuringEnrollmentAllowsNoRecordAfterLateAcknowledgement() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
        let started = expectation(description: "enrollment started")
        http.pauseNext = true; http.started = { started.fulfill() }
        let store = make(memory, http); store.setEnabled(true)
        await fulfillment(of: [started], timeout: 2)
        store.setEnabled(false); store.recordFeature(.water)
        http.resume(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["enroll"]); XCTAssertEqual(store.state.choice, .off)
        XCTAssertNil(memory.value?.counters); XCTAssertNil(store.state.lastSent)
    }
    func testDeleteDuringEnrollmentWaitsThenDeletesWithoutRecordingOrResurrection() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
        let started = expectation(description: "enrollment started")
        http.pauseNext = true; http.started = { started.fulfill() }
        let store = make(memory, http); store.setEnabled(true)
        await fulfillment(of: [started], timeout: 2)
        store.deleteData(); store.setEnabled(true)
        XCTAssertEqual(memory.value?.deletePending, true); XCTAssertEqual(http.actions, ["enroll"])
        http.resume(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["enroll", "delete"])
        XCTAssertFalse(store.state.deletePending); XCTAssertFalse(store.state.hasIdentity); XCTAssertEqual(store.state.choice, .off)
    }
    func testDeleteDuringRecordIgnoresLateSuccessAndCoalescesRepeatedDeletes() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport()
        let started = expectation(description: "record started")
        http.pauseNext = true; http.started = { started.fulfill() }
        let store = make(memory, http); store.flush(force: true)
        await fulfillment(of: [started], timeout: 2)
        store.deleteData(); store.deleteData(); store.recordFeature(.parcel)
        http.resume(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["record", "delete"])
        XCTAssertNil(store.state.lastSent); XCTAssertNil(memory.value?.identity); XCTAssertNil(memory.value?.counters)
    }
    func testFailedDeleteSurvivesReopenAndRetriesDeleteOnly() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport()
        http.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = make(memory, http); store.deleteData(); await store.waitForIdle()
        XCTAssertTrue(store.state.deletePending); XCTAssertEqual(memory.value?.choice, .off)
        let retry = AnalyticsTestTransport(), reopened = make(memory, retry)
        XCTAssertTrue(retry.requests.isEmpty)
        reopened.flush(); await reopened.waitForIdle()
        XCTAssertEqual(retry.actions, ["delete"]); XCTAssertFalse(reopened.state.deletePending)
    }
    func testBlockedBuildStillAllowsPreviouslySavedDeletion() async {
        let memory = AnalyticsMemoryStorage(saved(choice: .off)), http = AnalyticsTestTransport()
        let store = make(memory, http, build: AnalyticsBuild(version: "0.1.0", number: 1, rolloutReviewed: false))
        store.deleteData(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["delete"]); XCTAssertNil(memory.value?.identity)
    }
    func testAmbiguousEnrollmentNeverClaimsConfirmedErasureOrDropsCredential() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport()
        http.handler = { request in
            if request.url?.lastPathComponent == "enroll" { throw URLError(.timedOut) }
            return AnalyticsResponse(status: 200, ok: true)
        }
        let store = make(memory, http); store.setEnabled(true); await store.waitForIdle()
        XCTAssertEqual(memory.value?.enrollmentUncertain, true)
        store.deleteData(); await store.waitForIdle()
        XCTAssertTrue(store.state.deletePending); XCTAssertTrue(store.state.deletionUncertain)
        XCTAssertEqual(memory.value?.identity, identity)
        store.deleteData(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["enroll", "delete", "delete"])
        XCTAssertTrue(store.state.deletePending); XCTAssertNotNil(store.error)
    }
    func testInterruptedEnrollmentOnRelaunchIsUncertainAndNeverAutomaticallyEnrolls() async {
        var value = saved(); value.enrolled = false; value.enrollmentInFlight = true; value.choice = .off; value.deletePending = true
        let memory = AnalyticsMemoryStorage(value), http = AnalyticsTestTransport(), store = make(memory, http)
        XCTAssertEqual(memory.writes, 0); XCTAssertTrue(store.state.deletionUncertain)
        store.flush(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["delete"]); XCTAssertTrue(store.state.deletePending)
    }
    func testConsentWriteFailureDoesNotSend() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport(); memory.failWrites = true
        let store = make(memory, http); store.setEnabled(true); await store.waitForIdle()
        XCTAssertEqual(store.state.choice, .unset); XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(memory.value)
    }
    func testDeleteWriteFailureDoesNotSendOrEnableAgain() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport(), store = make(memory, http)
        memory.failWrites = true; store.deleteData(); store.flush(force: true); store.setEnabled(true)
        await store.waitForIdle()
        XCTAssertTrue(http.requests.isEmpty); XCTAssertEqual(store.state.choice, .off); XCTAssertNotNil(store.error)
        memory.failWrites = false; store.deleteData(); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["delete"]); XCTAssertNil(memory.value?.identity)
    }
    func testFailedOffWriteStopsRuntimeCollectionAndExplainsUnsavedChoice() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport(), store = make(memory, http)
        memory.failWrites = true; store.setEnabled(false); store.recordFeature(.learning); store.flush(force: true)
        await store.waitForIdle()
        XCTAssertEqual(store.state.choice, .off); XCTAssertEqual(memory.value?.choice, .on)
        XCTAssertTrue(http.requests.isEmpty); XCTAssertTrue(store.error?.contains("未能保存") == true)
    }
    func testCorruptPersistedIdentityFailsClosedWithoutOverwriting() async {
        var bad = saved(); bad.identity = AnalyticsIdentity(id: identity.id, token: "invalid")
        let memory = AnalyticsMemoryStorage(bad), http = AnalyticsTestTransport(), store = make(memory, http)
        store.setEnabled(true); store.deleteData(); store.flush(force: true); await store.waitForIdle()
        XCTAssertEqual(memory.writes, 0); XCTAssertEqual(memory.value, bad); XCTAssertTrue(http.requests.isEmpty)
    }
    func testNewCountDuringInflightRecordRemainsDirtyForLaterRetry() async throws {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport()
        let started = expectation(description: "record started")
        http.pauseNext = true; http.started = { started.fulfill() }
        let store = make(memory, http); store.flush(force: true)
        await fulfillment(of: [started], timeout: 2)
        store.recordFeature(.water); http.resume(); await store.waitForIdle()
        XCTAssertEqual(memory.value?.dirty, true)
        store.flush(force: true); await store.waitForIdle()
        XCTAssertEqual(memory.value?.dirty, false)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(http.requests.last?.httpBody)) as? [String: Any])
        XCTAssertEqual((body["features"] as? [String: Int])?["water"], 1)
    }
    func testRateLimitDoesNotClaimSuccessOrDiscardCountsAndRetryIsThrottled() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport()
        http.handler = { _ in AnalyticsResponse(status: 202, ok: false) }
        let store = make(memory, http); store.recordFeature(.schedule); await store.waitForIdle()
        XCTAssertNil(store.state.lastSent); XCTAssertEqual(memory.value?.dirty, true)
        store.flush(); await store.waitForIdle(); XCTAssertEqual(http.requests.count, 1)
        http.handler = nil; store.flush(force: true); await store.waitForIdle()
        XCTAssertNotNil(store.state.lastSent); XCTAssertEqual(memory.value?.counters?.features["schedule"], 1)
    }
    func testUnauthorizedRecordRetriesEnrollmentOnlyOnNextAttempt() async {
        let memory = AnalyticsMemoryStorage(saved()), http = AnalyticsTestTransport()
        http.handler = { _ in AnalyticsResponse(status: 401, ok: false) }
        let store = make(memory, http); store.flush(force: true); await store.waitForIdle()
        XCTAssertEqual(memory.value?.enrolled, false); XCTAssertEqual(http.actions, ["record"])
        http.handler = nil; store.flush(force: true); await store.waitForIdle()
        XCTAssertEqual(http.actions, ["record", "enroll", "record"])
    }
    func testNoIdentityDeletionNeverMakesNetworkRequest() async {
        let memory = AnalyticsMemoryStorage(), http = AnalyticsTestTransport(), store = make(memory, http)
        store.deleteData(); await store.waitForIdle()
        XCTAssertFalse(store.state.deletePending); XCTAssertEqual(store.state.choice, .off); XCTAssertTrue(http.requests.isEmpty)
    }
    func testCounterWhitelistCapDayResetAndBeijingBoundary() {
        XCTAssertEqual(Set(AnalyticsFeature.allCases.map(\.rawValue)), Set(["schedule","tasks","learning","shower","wallet","water","laundry","parcel","grades","map"]))
        var counters = AnalyticsCounters(day: "2026-11-10")
        for _ in 0..<1003 { counters.increment(.water, on: "2026-11-10") }
        XCTAssertEqual(counters.features["water"], 1000)
        counters.increment(.map, on: "2026-11-11")
        XCTAssertEqual(counters.features, ["map": 1]); XCTAssertTrue(counters.isValid)
        XCTAssertFalse(AnalyticsCounters(day: "2026-11-11", features: ["studentId": 1]).isValid)
        XCTAssertFalse(AnalyticsCounters(day: "2026-11-11", features: ["water": -1]).isValid)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(AnalyticsContract.day(formatter.date(from: "2026-11-10T15:59:59Z")!), "2026-11-10")
        XCTAssertEqual(AnalyticsContract.day(formatter.date(from: "2026-11-10T16:00:00Z")!), "2026-11-11")
    }
    func testRequestSchemaContainsOnlyPresetFieldsAndNoTokenInBody() throws {
        for action in [AnalyticsAction.enroll, .delete, .record] {
            let request = try AnalyticsContract.request(action, identity: identity, build: build,
                                                        counters: AnalyticsCounters(day: AnalyticsContract.day(instant), features: ["water": 2]), now: instant)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(Set(body.keys), action == .record ? Set(["id","day","version","versionCode","features"]) : Set(["id"]))
            XCTAssertNil(body["token"]); XCTAssertNil(body["platform"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Hyt-Token"), identity.token)
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.url?.absoluteString, AnalyticsContract.endpoint.absoluteString + "/" + action.rawValue)
            XCTAssertEqual(request.url, AnalyticsContract.destination(for: action))
            XCTAssertEqual(AnalyticsContract.action(for: try XCTUnwrap(request.url)), action)
        }
    }
    func testInvalidBuildStaleDayAndUnknownCountersCannotCreateRecordRequest() {
        XCTAssertThrowsError(try AnalyticsContract.request(.record, identity: identity, build: .current, counters: AnalyticsCounters(day: AnalyticsContract.day(instant)), now: instant))
        XCTAssertThrowsError(try AnalyticsContract.request(.record, identity: identity, build: build, counters: AnalyticsCounters(day: "2000-01-01"), now: instant))
        XCTAssertThrowsError(try AnalyticsContract.request(.record, identity: identity, build: build, counters: AnalyticsCounters(day: AnalyticsContract.day(instant), features: ["account": 1]), now: instant))
    }
    func testKeychainStorageIsDeviceOnlyAndIndependentOfOtherAccounts() throws {
        let service = "org.handancampus.test.analytics." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let marker = directory.appendingPathComponent("installation.marker")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AnalyticsKeychainStorage(service: service, installationMarker: marker)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        defer { SecItemDelete(query as CFDictionary) }
        XCTAssertNil(try storage.load())
        try storage.save(saved())
        XCTAssertEqual(try AnalyticsKeychainStorage(service: service, installationMarker: marker).load(), saved())
        var attributesQuery = query; attributesQuery[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(attributesQuery as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true)
        XCTAssertTrue(try AnalyticsKeychainStorage.makeIdentity().isValid)
        XCTAssertEqual(try marker.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try FileManager.default.removeItem(at: marker)
        XCTAssertNil(try AnalyticsKeychainStorage(service: service, installationMarker: marker).load(), "Reinstall must not restore stale Keychain consent")
    }
    func testAllCanonicalAnalyticsDestinationsReachSyntheticTransport() async throws {
        let transport = AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self])
        for action in AnalyticsAction.allCases {
            AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8))
            let request = try AnalyticsContract.request(action, identity: identity, build: build,
                                                        counters: AnalyticsCounters(day: AnalyticsContract.day(instant)), now: instant)
            let response = try await transport.send(request)
            XCTAssertTrue(response.ok)
            XCTAssertEqual(AnalyticsURLProtocol.requests.map { $0.url?.absoluteString },
                           [AnalyticsContract.endpoint.absoluteString + "/" + action.rawValue])
        }
    }
    func testAnalyticsURLAllowlistRejectsCredentialBearingVariantsBeforeTransport() async throws {
        let base = AnalyticsContract.endpoint.absoluteString
        let host = try XCTUnwrap(AnalyticsContract.endpoint.host)
        let rejected = [
            base, base + "/", base + "/delete/", base + "/unknown", base + "/%64elete",
            base + "/record/../delete", base + "//delete", base + "/delete%2F", base + "/delete?",
            base + "/delete?target=elsewhere", base + "/delete#", base + "/delete#fragment",
            base.replacingOccurrences(of: "https://", with: "http://") + "/delete",
            base.replacingOccurrences(of: host, with: host + ":443") + "/delete",
            base.replacingOccurrences(of: host, with: host + ":444") + "/delete",
            base.replacingOccurrences(of: host, with: "name:password@" + host) + "/delete",
            base.replacingOccurrences(of: host, with: host + ".other.invalid") + "/delete"
        ]
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8))
        let transport = AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self])
        for value in rejected {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(AnalyticsContract.action(for: url), "Unexpected URL accepted: \(value)")
            var request = try AnalyticsContract.request(.delete, identity: identity, build: build)
            request.url = url
            do { _ = try await transport.send(request); XCTFail("Noncanonical destination reached transport: \(value)") } catch { }
        }
        var wrongMethod = try AnalyticsContract.request(.delete, identity: identity, build: build)
        wrongMethod.httpMethod = "GET"
        do { _ = try await transport.send(wrongMethod); XCTFail("Unexpected method reached transport") } catch { }
        XCTAssertTrue(AnalyticsURLProtocol.requests.isEmpty, "Rejected URLs must never transmit installation credentials")
    }
    func testURLProtocolTransportIsSyntheticAndValidatesAcknowledgement() async throws {
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8))
        let transport = AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self])
        let request = try AnalyticsContract.request(.delete, identity: identity, build: build)
        let response = try await transport.send(request)
        XCTAssertEqual(response, AnalyticsResponse(status: 200, ok: true))
        XCTAssertEqual(AnalyticsURLProtocol.requests.count, 1)
        AnalyticsURLProtocol.reset(status: 200, data: Data("{}".utf8))
        let missing = try await transport.send(request); XCTAssertFalse(missing.ok)
        AnalyticsURLProtocol.reset(status: 401, data: Data("{\"error\":\"invalid_request\"}".utf8))
        let rejected = try await transport.send(request); XCTAssertEqual(rejected.status, 401); XCTAssertFalse(rejected.ok)
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":\"true\"}".utf8))
        do { _ = try await transport.send(request); XCTFail("Non-Boolean ack accepted") } catch { }
    }
    func testURLProtocolTransportRejectsOversizedAndOtherOriginResponses() async throws {
        let transport = AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self])
        let request = try AnalyticsContract.request(.delete, identity: identity, build: build)
        AnalyticsURLProtocol.reset(status: 200, data: Data(repeating: 32, count: 4097))
        do { _ = try await transport.send(request); XCTFail("Oversized response accepted") } catch { }
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8), responseURL: URL(string: "https://other.invalid/metrics/delete")!)
        do { _ = try await transport.send(request); XCTFail("Different response origin accepted") } catch { }
        var other = request; other.url = URL(string: "https://other.invalid/metrics/delete")!
        let before = AnalyticsURLProtocol.requests.count
        do { _ = try await transport.send(other); XCTFail("Different target accepted") } catch { }
        XCTAssertEqual(AnalyticsURLProtocol.requests.count, before)
    }
    func testURLProtocolRedirectCannotForwardInstallationCredential() async throws {
        AnalyticsURLProtocol.reset(status: 302, data: Data(), redirect: URL(string: "https://other.invalid/collect")!)
        let transport = AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self])
        let request = try AnalyticsContract.request(.delete, identity: identity, build: build)
        do { _ = try await transport.send(request); XCTFail("Redirect was followed") } catch { }
        XCTAssertEqual(AnalyticsURLProtocol.requests.count, 1)
        XCTAssertEqual(AnalyticsURLProtocol.requests.first?.url?.host, AnalyticsContract.endpoint.host)
    }
    func testCancelledURLProtocolEnrollmentKeepsUncertainDeletionCredential() async {
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8), hold: true)
        let started = expectation(description: "synthetic request started")
        AnalyticsURLProtocol.onStart = { started.fulfill() }
        let memory = AnalyticsMemoryStorage()
        let store = AnonymousAnalyticsStore(storage: memory, transport: AnalyticsHTTPTransport(protocolClasses: [AnalyticsURLProtocol.self]), build: build, makeIdentity: { self.identity })
        store.setEnabled(true); await fulfillment(of: [started], timeout: 2)
        store.cancelSending(); await store.waitForIdle()
        XCTAssertEqual(memory.value?.enrollmentUncertain, true)
        XCTAssertFalse(store.isSending); XCTAssertEqual(AnalyticsURLProtocol.requests.count, 1)
        AnalyticsURLProtocol.reset(status: 200, data: Data("{\"ok\":true}".utf8))
        store.deleteData(); await store.waitForIdle()
        XCTAssertTrue(store.state.deletePending); XCTAssertTrue(store.state.hasIdentity)
        XCTAssertEqual(AnalyticsURLProtocol.requests.map { $0.url!.lastPathComponent }, ["delete"])
    }
}

@MainActor private final class AnalyticsMemoryStorage: AnalyticsPersisting {
    var value: AnalyticsRecord?
    var writes = 0
    var failWrites = false
    init(_ value: AnalyticsRecord? = nil) { self.value = value }
    func load() throws -> AnalyticsRecord? { value }
    func save(_ record: AnalyticsRecord) throws {
        if failWrites { throw AnalyticsFailure.storage }
        writes += 1; value = record
    }
}
@MainActor private final class AnalyticsTestTransport: AnalyticsTransporting {
    var requests: [URLRequest] = []
    var actions: [String] { requests.map { $0.url!.lastPathComponent } }
    var handler: ((URLRequest) async throws -> AnalyticsResponse)?
    var started: (() -> Void)?
    var pauseNext = false
    private var pending: CheckedContinuation<AnalyticsResponse, Error>?
    func send(_ request: URLRequest) async throws -> AnalyticsResponse {
        requests.append(request)
        if pauseNext {
            pauseNext = false
            return try await withCheckedThrowingContinuation { pending = $0; started?(); started = nil }
        }
        if let handler { return try await handler(request) }
        return AnalyticsResponse(status: 200, ok: true)
    }
    func resume() { pending?.resume(returning: AnalyticsResponse(status: 200, ok: true)); pending = nil }
}

/// Every request in these transport tests is intercepted. No real analytics POST/DELETE is performed.
private final class AnalyticsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var captured: [URLRequest] = []
    private static var responseStatus = 200
    private static var responseData = Data()
    private static var responseURL: URL?
    private static var hold = false
    private static var redirect: URL?
    static var onStart: (() -> Void)?
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static func reset(status: Int, data: Data, responseURL: URL? = nil, hold: Bool = false, redirect: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        captured = []; responseStatus = status; responseData = data; self.responseURL = responseURL; self.hold = hold; self.redirect = redirect; onStart = nil
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let status = Self.responseStatus, data = Self.responseData, url = Self.responseURL ?? request.url!, hold = Self.hold, started = Self.onStart, redirect = Self.redirect
        Self.lock.unlock()
        started?()
        guard !hold else { return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        if let redirect {
            var redirected = request; redirected.url = redirect
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

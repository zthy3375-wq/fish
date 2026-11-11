import XCTest
import UIKit
import CoreImage
@testable import Hanyuantong

final class PangguaiProtocolTests: XCTestCase {
    private func json(_ text: String) throws -> PGJSON { try JSONDecoder().decode(PGJSON.self, from: Data(text.utf8)) }
    func testSignatureMatchesExistingAndroidContract() throws {
        XCTAssertEqual(try PangguaiProtocol.signature(path:"user/info", token:"synthetic-a", timestamp:"1"), "fb6a6c0cf19c6d23a186d85511ae4f3f5ba1dbb7dd6c1bf1eedd94b1f7af125f")
        XCTAssertThrowsError(try PangguaiProtocol.signature(path:"unknown", token:"", timestamp:"1"))
    }
    func testMoneyDoesNotAssumeZeroOrConvertPoints() throws {
        XCTAssertEqual(PangguaiProtocol.money(.string("12.3400")), "12.34")
        for input in ["", "1e6", "-1", "NaN", "1.12345", "100000000000"] { XCTAssertNil(PangguaiProtocol.money(.string(input))) }
        XCTAssertNil(PangguaiProtocol.money(.null))
        XCTAssertThrowsError(try PangguaiProtocol.price(.string("1.001")))
        XCTAssertEqual(try PangguaiProtocol.price(.string("3.5000")), "3.5")
    }
    func testEnvelopeRequiresExplicitSuccessAndSeparatesRisk() throws {
        XCTAssertThrowsError(try PangguaiProtocol.payload(json("{\"data\":{}}")))
        XCTAssertThrowsError(try PangguaiProtocol.payload(json("{\"code\":2}"))) { XCTAssertEqual($0 as? PGFailure, .auth) }
        XCTAssertThrowsError(try PangguaiProtocol.payload(json("{\"code\":400,\"msg\":\"需要验证码\"}"))) { XCTAssertEqual($0 as? PGFailure, .verify) }
        XCTAssertEqual(try PangguaiProtocol.payload(json("{\"code\":0,\"data\":true}")), .bool(true))
    }
    func testAccountIdentityAndLargeMerchantIdentifiers() throws {
        XCTAssertThrowsError(try PangguaiProtocol.profile(json("{\"id\":\"test\",\"phone\":\"13900000000\"}"), expectedPhone:"13800000000")) { XCTAssertEqual($0 as? PGFailure, .account) }
        XCTAssertEqual(try json("{\"id\":9007199254740993001}")["id"].text, "9007199254740993001")
    }
    func testQRCodeAcceptsOnlyInertKnownDeviceFormats() throws {
        XCTAssertEqual(try PangguaiProtocol.deviceCode("https://h5.qiekj.com/skip?NQT=synthetic-device"), ["NQT":"synthetic-device"])
        XCTAssertEqual(try PangguaiProtocol.deviceCode("http://h5.qiekj.com/skip?SN=12345678"), ["SN":"12345678"])
        let bad = ["https://evil.example/skip?SN=1234", "https://h5.qiekj.com@evil.example/skip?SN=1234", "https://h5.qiekj.com/skip?SN=1234&SN=5678", "https://h5.qiekj.com/skip?NQT=1234&SN=5678", "https://h5.qiekj.com/skip?SN=%252F1234", "https://h5.qiekj.com/skip?SN=1234&IMEI=other", "https://h5.qiekj.com:444/skip?SN=1234", "https://h5.qiekj.com/%73kip?SN=1234", "https://h5.qiekj.com/skip?SN=1234#other", "javascript:alert(1)"]
        for value in bad { XCTAssertThrowsError(try PangguaiProtocol.deviceCode(value), value) }
    }
    func testAPIRequestIsFixedHTTPSPostAndDoesNotAcceptInjectedPath() throws {
        let request = try PangguaiClient.makeRequest("user/info", fields:["value":"a&b=中"], token:"synthetic-token", timestamp:"1")
        XCTAssertEqual(request.url?.absoluteString, "https://userapi.qiekj.com/user/info")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpShouldHandleCookies, false)
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"), "synthetic-token")
        XCTAssertTrue(String(decoding:request.httpBody!, as:UTF8.self).contains("a%26b%3D%E4%B8%AD"))
        XCTAssertThrowsError(try PangguaiClient.makeRequest("../other", fields:[:], token:""))
        XCTAssertThrowsError(try PangguaiClient.makeRequest("user/info", fields:[:], token:"a\r\nInjected: true"))
    }
    func testDeviceMustMatchScanAndSKUIdsMustBeUnique() throws {
        let scan = try json("{\"id\":\"d\",\"type\":\"goods\",\"categoryCode\":\"00\"}")
        let mismatched = try json("{\"goodsId\":\"other\",\"categoryCode\":\"00\",\"name\":\"synthetic\"}")
        XCTAssertThrowsError(try PGDevice.parse(scan:scan, details:mismatched, skus:.array([])))
        let details = try json("{\"goodsId\":\"d\",\"categoryCode\":\"00\",\"name\":\"synthetic\"}")
        let skus = try json("[{\"skuId\":\"same\"},{\"skuId\":\"same\"}]")
        XCTAssertThrowsError(try PGDevice.parse(scan:scan, details:details, skus:skus))
    }
    func testOnlyVerifiedUniqueDrinkingWaterMerchantUsesMinorUnits() {
        let water = PGTicket(id:"water", name:"邯郸学院 直饮水机", balance:"1234", principal:nil, gift:nil)
        let other = PGTicket(id:"other", name:"其他钱包", balance:"1234", principal:nil, gift:nil)
        XCTAssertEqual(PangguaiWalletMath.waterTicket([water,other]), water)
        XCTAssertEqual(PangguaiWalletMath.waterAmount(water.balance), "12.34")
        XCTAssertNil(PangguaiWalletMath.waterTicket([water,water]))
        XCTAssertEqual(other.balance, "1234")
        XCTAssertNil(PangguaiWalletMath.waterAmount(nil))
    }
    func testPhotoQRIsDecodedOnDeviceFromBoundedSyntheticImage() throws {
        let code = "https://h5.qiekj.com/skip?SN=12345678"
        let filter = try XCTUnwrap(CIFilter(name:"CIQRCodeGenerator"))
        filter.setValue(Data(code.utf8),forKey:"inputMessage")
        let output = try XCTUnwrap(filter.outputImage).transformed(by:CGAffineTransform(scaleX:8,y:8))
        let image = try XCTUnwrap(CIContext().createCGImage(output,from:output.extent))
        let data = try XCTUnwrap(UIImage(cgImage:image).pngData())
        XCTAssertEqual(try PGImageQRReader.read(data),code)
        XCTAssertThrowsError(try PGImageQRReader.read(Data("not-image".utf8)))
    }
    func testPhotoRejectsTwoDifferentDeviceCodesInsteadOfChoosingOne() throws {
        func qr(_ serial: String) throws -> CIImage {
            let filter = try XCTUnwrap(CIFilter(name:"CIQRCodeGenerator"))
            filter.setValue(Data("https://h5.qiekj.com/skip?SN=\(serial)".utf8), forKey:"inputMessage")
            return try XCTUnwrap(filter.outputImage).transformed(by:CGAffineTransform(scaleX:8,y:8))
        }
        let first = try qr("12345678"), second = try qr("87654321")
        let canvas = CGRect(x:0,y:0,width:first.extent.width + second.extent.width + 96,height:first.extent.height + 64)
        let background = CIImage(color: CIColor(red:1,green:1,blue:1)).cropped(to:canvas)
        let combined = first.transformed(by:CGAffineTransform(translationX:32,y:32))
            .composited(over:second.transformed(by:CGAffineTransform(translationX:first.extent.width + 64,y:32)))
            .composited(over:background)
        let image = try XCTUnwrap(CIContext().createCGImage(combined, from:canvas))
        let data = try XCTUnwrap(UIImage(cgImage:image).pngData())
        XCTAssertThrowsError(try PGImageQRReader.read(data)) { XCTAssertEqual($0 as? PGFailure, .qr) }
    }
    func testPhotoCombinesAllDecoderVariantsBeforeAcceptingUniqueDevice() throws {
        let a = "https://h5.qiekj.com/skip?SN=12345678", b = "https://h5.qiekj.com/skip?SN=87654321"
        XCTAssertEqual(try PGImageQRReader.uniqueDeviceCode(from:[a,a]), a)
        XCTAssertEqual(try PGImageQRReader.uniqueDeviceCode(from:["https://evil.example/?SN=12345678",a]), a)
        XCTAssertThrowsError(try PGImageQRReader.uniqueDeviceCode(from:[a,a,b]))
        XCTAssertThrowsError(try PGImageQRReader.uniqueDeviceCode(from:[]))
    }
    func testStorageScopesCannotUseRawAccountPath() {
        let a = PangguaiStorage.scope("../account-a")
        XCTAssertEqual(a.count, 73)
        XCTAssertFalse(a.contains("/"))
        XCTAssertNotEqual(a, PangguaiStorage.scope("account-b"))
    }
}

@MainActor
final class PangguaiStoreTests: XCTestCase {
    private func json(_ text: String) -> PGJSON { try! JSONDecoder().decode(PGJSON.self, from:Data(text.utf8)) }
    private func harness() -> (PangguaiStore, PGTestAPI, PGTestVault) {
        let api = PGTestAPI(), vault = PGTestVault()
        let store = PangguaiStore(api:api, persistence:vault, now:{ Date(timeIntervalSince1970:1000) })
        return (store,api,vault)
    }
    func testRefreshPartialFailurePreservesLastGoodSections() async {
        let api = PGTestAPI(), vault = PGTestVault()
        var cached = PGSnapshot(); cached.balance = "9"; cached.tickets = [PGTicket(id:"old", name:"old", balance:"99", principal:nil, gift:nil)]
        vault.records["account-a"] = cached
        api.handler = { path, _, _ in
            switch path {
            case "user/info": return self.json("{\"id\":\"account-a\",\"phone\":\"13800000000\",\"balance\":\"12\"}")
            case "tokenCoin/userTokenCoins": return self.json("{\"total\":3,\"items\":[]}")
            case "order/list": return self.json("{\"items\":[]}")
            default: throw PGFailure.service
            }
        }
        let store = PangguaiStore(api:api,persistence:vault)
        await store.refresh()
        XCTAssertEqual(store.snapshot.balance,"12")
        XCTAssertEqual(store.snapshot.tickets,cached.tickets)
        XCTAssertEqual(store.snapshot.issues["tickets"],.partial)
        XCTAssertNotNil(store.snapshot.ordersUpdatedAt)
    }
    func testIdentityMismatchStopsFurtherAccountRequests() async {
        let (store,api,_) = harness()
        api.handler = { _, _, _ in self.json("{\"id\":\"other\",\"phone\":\"13800000000\",\"balance\":\"12\"}") }
        await store.refresh()
        XCTAssertTrue(store.expired)
        XCTAssertEqual(api.calls,["user/info"])
        XCTAssertNil(store.snapshot.balance)
    }
    func testLoginRequiresConsentAndSMSCooldownSurvivesCancellation() async {
        let (store,api,_) = harness()
        let refused = await store.sendCode(phone:"13800000000",consent:false); XCTAssertFalse(refused)
        XCTAssertEqual(api.calls.count,0)
        let sent = await store.sendCode(phone:"13800000000",consent:true); XCTAssertTrue(sent)
        store.cancelPending()
        let repeated = await store.sendCode(phone:"13800000000",consent:true); XCTAssertFalse(repeated)
        XCTAssertEqual(api.calls.filter { $0 == "common/sms/sendCode" }.count,1)
    }
    func testCancelledLoginCannotCommitLateCredentials() async {
        let (store,api,vault) = harness()
        var resume: CheckedContinuation<PGJSON,Error>?
        api.handler = { path, _, _ in
            if path == "user/reg" { return try await withCheckedThrowingContinuation { resume = $0 } }
            return self.json("{\"id\":\"account-b\",\"phone\":\"13900000000\",\"balance\":\"12\"}")
        }
        let task = Task { await store.login(phone:"13900000000",code:"123456",consent:true) }
        for _ in 0..<100 { if resume != nil { break }; await Task.yield() }
        XCTAssertNotNil(resume)
        store.cancelPending(); resume?.resume(returning:json("{\"token\":\"synthetic-new-token\"}"))
        let cancelled = await task.value; XCTAssertFalse(cancelled)
        XCTAssertEqual(vault.current?.id,"account-a")
        XCTAssertEqual(api.calls,["user/reg"])
    }
    func testNewAccountNeverSeesOldSnapshot() async {
        let (store,api,vault) = harness()
        var old = PGSnapshot(); old.balance = "100"; vault.records["account-a"] = old
        api.handler = { path, _, _ in path == "user/reg" ? self.json("{\"token\":\"synthetic-new\"}") : self.json("{\"id\":\"account-b\",\"phone\":\"13900000000\",\"balance\":\"2\"}") }
        let loggedIn = await store.login(phone:"13900000000",code:"123456",consent:true); XCTAssertTrue(loggedIn)
        XCTAssertEqual(store.snapshot.balance,"2")
        XCTAssertTrue(store.snapshot.tickets.isEmpty)
        XCTAssertEqual(vault.current?.id,"account-b")
    }
    func testOfficialRechargeRequiresKnownCurrentMerchant() throws {
        let (store,_,_) = harness()
        XCTAssertEqual(try store.officialURL().absoluteString,"alipays://platformapi/startapp?appId=2018072460764274")
        XCTAssertThrowsError(try store.officialURL(merchantID:"unknown"))
    }
    func testLaundryQuoteNeverCreatesOrPaysAndAlipaySDKChannelIsUnavailable() async {
        let (store,api,_) = harness(); configureLaundry(store,api)
        await store.quoteLaundry(skuID:"wash")
        XCTAssertNotNil(store.laundryQuote)
        XCTAssertFalse(api.calls.contains("trade/create"))
        XCTAssertFalse(api.calls.contains("pay/unify/pay"))
        XCTAssertFalse(store.laundryQuote?.channels.first { $0.id == "13" }?.available ?? true)
    }
    func testLostLaundryCreateIsDurableAndCannotReplay() async {
        let (store,api,vault) = harness(); configureLaundry(store,api)
        let response = api.handler
        api.handler = { path, fields, token in if path == "trade/create" { throw PGFailure.network }; return try await response(path,fields,token) }
        await store.quoteLaundry(skuID:"wash"); let quote = store.laundryQuote!
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        XCTAssertEqual(store.snapshot.laundry?.phase,"creating")
        XCTAssertEqual(vault.records["account-a"]?.laundry?.phase,"creating")
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        await store.quoteLaundry(skuID:"wash")
        XCTAssertEqual(api.calls.filter { $0 == "trade/create" }.count,1)
        XCTAssertFalse(api.calls.contains("pay/unify/pay"))
    }
    func testStorageFailurePreventsCreation() async {
        let (store,api,vault) = harness(); configureLaundry(store,api)
        await store.quoteLaundry(skuID:"wash"); let quote = store.laundryQuote!
        vault.failWrite = true
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        XCTAssertFalse(api.calls.contains("trade/create"))
    }
    func testLaundryPriceChangeRequiresNewReview() async {
        let (store,api,_) = harness(); configureLaundry(store,api)
        let response = api.handler
        await store.quoteLaundry(skuID:"wash"); let quote = store.laundryQuote!
        api.handler = { path, fields, token in if path == "order/detail" { return self.laundryDetail(price:"4") }; return try await response(path,fields,token) }
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        XCTAssertFalse(api.calls.contains("pay/unify/pay"))
        XCTAssertEqual(store.snapshot.laundry?.phase,"pending")
        XCTAssertEqual(store.snapshot.laundry?.amount,"4")
    }
    func testLostPaymentCanOnlyQueryNeverReplay() async {
        let (store,api,_) = harness(); configureLaundry(store,api)
        let response = api.handler
        api.handler = { path, fields, token in if path == "pay/unify/pay" { throw PGFailure.network }; return try await response(path,fields,token) }
        await store.quoteLaundry(skuID:"wash"); let quote = store.laundryQuote!
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        XCTAssertTrue(store.snapshot.laundry?.paySent == true)
        await store.pollSessions(); await store.quoteLaundry()
        XCTAssertNil(store.laundryQuote)
        XCTAssertEqual(api.calls.filter { $0 == "pay/unify/pay" }.count,1)
    }
    func testWrongOrderCannotBePaid() async {
        let (store,api,_) = harness(); configureLaundry(store,api)
        let response = api.handler
        api.handler = { path, fields, token in if path == "order/detail" { return self.laundryDetail(sku:"other") }; return try await response(path,fields,token) }
        await store.quoteLaundry(skuID:"wash"); let quote = store.laundryQuote!
        await store.startLaundry(confirmedQuoteID:quote.id,method:"2")
        XCTAssertFalse(api.calls.contains("pay/unify/pay"))
        XCTAssertEqual(store.snapshot.laundry?.error,.orderMismatch)
    }
    func testWaterQuoteNeverUnlocksOrSelectsPayment() async {
        let (store,api,_) = harness(); configureWater(store,api)
        await store.prepareWater(skuID:"outlet")
        XCTAssertTrue(store.waterQuote?.canStart == true)
        XCTAssertFalse(api.calls.contains("goods/water/unlock"))
        XCTAssertFalse(api.calls.contains("payChannelRoute/addUserAfterPayChannel"))
    }
    func testLostWaterUnlockCannotReplayEvenAfterLogoutRestore() async {
        let (store,api,vault) = harness(); configureWater(store,api)
        let response = api.handler
        api.handler = { path, fields, token in if path == "goods/water/unlock" { throw PGFailure.network }; return try await response(path,fields,token) }
        await store.prepareWater(skuID:"outlet"); let quote = store.waterQuote!
        await store.startWater(confirmedQuoteID:quote.id)
        XCTAssertEqual(store.snapshot.water?.phase,"starting")
        let credentials = vault.current
        store.logout(); vault.current = credentials
        let restored = PangguaiStore(api:api,persistence:vault)
        XCTAssertEqual(restored.snapshot.water?.phase,"starting")
        await store.startWater(confirmedQuoteID:quote.id)
        XCTAssertEqual(api.calls.filter { $0 == "goods/water/unlock" }.count,1)
    }
    func testPollingEndedWaterNeverCreatesBillOrPays() async throws {
        let (store,api,vault) = harness(); configureWater(store,api)
        try store.saveWater(waterSession(),epoch:store.generation)
        api.handler = { path, _, _ in
            if path == "goods/water/sync" { return self.json("{\"identify\":\"water-order\",\"status\":5,\"workStatus\":1,\"amount\":1}") }
            throw PGFailure.service
        }
        await store.pollSessions()
        XCTAssertEqual(store.snapshot.water?.phase,"ended")
        XCTAssertEqual(vault.records["account-a"]?.water?.phase,"ended")
        XCTAssertFalse(api.calls.contains("order/afterPay/creating"))
        XCTAssertFalse(api.calls.contains("order/sync"))
    }
    func testPhysicalRecoveryIsReadOnlyAndPreservesUnknownBill() async throws {
        let (store,api,_) = harness(); configureWater(store,api)
        let s = waterSession(); try store.saveWater(s,epoch:store.generation)
        api.handler = { _, _, _ in .null }
        await store.confirmPhysicalWaterEnd(sessionID:s.id)
        XCTAssertEqual(store.snapshot.water?.phase,"closed_unknown")
        XCTAssertEqual(store.snapshot.water?.endBasis,"physical_confirmed")
        XCTAssertEqual(api.calls,["goods/water/sync"])
    }
    func testWrongOwnerWaterIsNeverEndedOrPaid() async throws {
        let (store,api,_) = harness(); configureWater(store,api)
        let s = waterSession(); try store.saveWater(s,epoch:store.generation)
        api.handler = { _, _, _ in self.json("{\"identify\":\"another-user\",\"status\":1,\"workStatus\":2}") }
        await store.endWater(confirmedSessionID:s.id)
        XCTAssertEqual(store.snapshot.water?.phase,"closed_unknown")
        XCTAssertFalse(api.calls.contains("goods/endWater"))
        XCTAssertFalse(api.calls.contains("order/sync"))
    }
    func testWaterSettlementRequiresSeparateExactAmountConfirmation() async throws {
        let (store,api,_) = harness(); configureWater(store,api)
        var s = waterSession(); s.deviceEnded = true; s.phase = "ended"; try store.saveWater(s,epoch:store.generation)
        await store.prepareWaterSettlement(sessionID:s.id)
        let quote = try XCTUnwrap(store.settlementQuote)
        XCTAssertEqual(quote.amount,"0.13")
        XCTAssertFalse(api.calls.contains("order/sync"))
        await store.settleWater(confirmedQuoteID:quote.id)
        XCTAssertEqual(api.calls.filter { $0 == "order/sync" }.count,1)
        await store.settleWater(confirmedQuoteID:quote.id)
        await store.pollSessions()
        XCTAssertEqual(api.calls.filter { $0 == "order/sync" }.count,1)
    }
    func testZeroWaterNeverCreatesBillOrPays() async throws {
        let (store,api,_) = harness(); configureWater(store,api)
        try store.saveWater(waterSession(),epoch:store.generation)
        api.handler = { path, _, _ in if path == "goods/water/sync" { return self.json("{\"identify\":\"water-order\",\"status\":5,\"workStatus\":1,\"amount\":0}") }; throw PGFailure.service }
        await store.pollSessions()
        XCTAssertEqual(store.snapshot.water?.phase,"ended_zero")
        XCTAssertFalse(api.calls.contains("order/afterPay/creating"))
        XCTAssertFalse(api.calls.contains("order/sync"))
    }
    private func laundryDetail(price: String = "3.5", sku: String = "wash") -> PGJSON {
        json("{\"id\":\"order-id\",\"orderNo\":\"order-no\",\"orderStatus\":0,\"payPrice\":\"\(price)\",\"tradeOrderItem\":[{\"goodsId\":\"washer\",\"skuId\":\"\(sku)\"}]}")
    }
    private func configureLaundry(_ store: PangguaiStore, _ api: PGTestAPI) {
        store.device = PGDevice(id:"washer",name:"合成洗衣机",category:"00",operatorName:"合成运营商",payment:"before",issue:"",imei:"synthetic-imei",routeShopID:"route",shopID:"shop",isBluetooth:"0",skus:[PGSKU(id:"wash",name:"标准洗",price:"3.5",feature:"合成测试",available:true)])
        api.handler = { path, _, _ in
            switch path {
            case "trade/preview/v4": return self.json("{\"realPrice\":\"3.50\",\"items\":[{\"goodsId\":\"washer\",\"skuId\":\"wash\"}]}")
            case "payChannelRoute/prePay", "payChannelRoute/againPay": return self.json("[{\"method\":2,\"useStatus\":true,\"needOpenFlag\":false},{\"method\":13,\"useStatus\":true,\"needOpenFlag\":false}]")
            case "trade/check_device_status": return self.json("{\"health\":true,\"msgId\":\"synthetic-msg\"}")
            case "machine/sync": return .bool(true)
            case "order/list": return self.json("{\"items\":[]}")
            case "trade/create": return self.json("{\"tradeNo\":\"order-no\",\"orderId\":\"order-id\"}")
            case "order/detail": return self.laundryDetail()
            case "order/pay_status", "machine/device_is_start": return .bool(false)
            case "pay/unify/pay": return .null
            default: throw PGFailure.service
            }
        }
    }
    private func waterSession() -> PGWaterSession {
        var s = PGWaterSession(deviceID:"water",deviceName:"合成饮水机",skuID:"outlet",outlet:"常温水",feature:"每升1元",paymentName:"支付宝免密",remoteEnd:true)
        s.phase = "using"; s.orderNo = "water-order"; s.startedAt = Date(timeIntervalSince1970:999); return s
    }
    private func configureWater(_ store: PangguaiStore, _ api: PGTestAPI) {
        store.device = PGDevice(id:"water",name:"合成饮水机",category:"04",operatorName:"合成运营商",payment:"after",issue:"",imei:"synthetic-imei",routeShopID:"route",shopID:"shop",isBluetooth:"0",skus:[PGSKU(id:"outlet",name:"常温水",price:"1",feature:"每升1元",available:true)])
        api.handler = { path, _, _ in
            switch path {
            case "goods/normal/details": return self.json("{\"goodsId\":\"water\",\"categoryCode\":\"04\",\"name\":\"合成饮水机\",\"payment\":\"after\",\"isBluetooth\":0,\"imei\":\"synthetic-imei\",\"supportAppUserFinish\":true}")
            case "goods/normal/skus": return self.json("[{\"skuId\":\"outlet\",\"name\":\"常温水\",\"feature\":\"每升1元\",\"price\":1,\"scanAvailable\":true,\"stockState\":1}]")
            case "payChannelRoute/afterPay": return self.json("[{\"method\":15,\"methodName\":\"支付宝免密\",\"useStatus\":true,\"needOpenFlag\":false}]")
            case "goods/water/sync": return self.json("{\"identify\":\"old-order\",\"status\":5,\"workStatus\":1}")
            case "goods/water/unlock": return self.json("{\"orderNo\":\"water-order\"}")
            case "order/afterPay/creating": return self.json("{\"orderNo\":\"water-order\",\"orderId\":\"water-bill\"}")
            case "order/detail": return self.json("{\"id\":\"water-bill\",\"orderNo\":\"water-order\",\"orderStatus\":0,\"payPrice\":\"0.13\",\"tradeOrderItem\":[{\"goodsId\":\"water\",\"skuId\":\"outlet\"}]}")
            case "order/sync": return self.json("{\"code\":0}")
            case "payChannelRoute/addUserAfterPayChannel": return .null
            default: throw PGFailure.service
            }
        }
    }
}

@MainActor
private final class PGTestAPI: PangguaiRequesting {
    var calls: [String] = []
    var handler: (String,[String:String],String) async throws -> PGJSON = { _,_,_ in .null }
    func request(_ path: String, fields: [String:String], token: String) async throws -> PGJSON { calls.append(path); return try await handler(path,fields,token) }
}
private final class PGTestVault: PangguaiPersisting {
    var current: PGCredentials? = PGCredentials(id:"account-a",phone:"13800000000",token:"synthetic-token")
    var records: [String:PGSnapshot] = [:]
    var failWrite = false
    func credentials() throws -> PGCredentials? { current }
    func saveCredentials(_ value: PGCredentials) throws { if failWrite { throw PGFailure.storage }; current = value }
    func snapshot(accountID: String) throws -> PGSnapshot? { records[accountID] }
    func saveSnapshot(_ snapshot: PGSnapshot, accountID: String) throws { if failWrite { throw PGFailure.storage }; records[accountID] = snapshot }
    func logout() throws { current = nil }
}

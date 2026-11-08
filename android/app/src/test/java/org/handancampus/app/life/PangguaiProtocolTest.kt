package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PangguaiProtocolTest {
    private fun fails(kind:String, action:()->Unit){try{action();fail("expected rejection")}catch(e:PangguaiFailure){assertEquals(kind,e.kind)}}
    @Test fun moneyDoesNotCombinePointsOrAssumeZero(){assertEquals("12.34",PangguaiProtocol.money("12.3400"));assertNull(PangguaiProtocol.money(null));assertNull(PangguaiProtocol.money("unknown"));assertNull(PangguaiProtocol.money("1e6"))}
    @Test fun envelopeRequiresExplicitSuccess(){fails("SERVICE"){PangguaiProtocol.payload(JSONObject("{data:{balance:100}}"))};fails("AUTH"){PangguaiProtocol.payload(JSONObject("{code:2}"))};fails("VERIFY"){PangguaiProtocol.payload(JSONObject("{code:400,msg:'需要验证码'}"))}}
    @Test fun identityMustMatchEnteredPhone(){fails("ACCOUNT"){PangguaiProtocol.profile(JSONObject("{id:'test-user',phone:'13900000000',balance:'1'}"),"13800000000")}}
    @Test fun merchantIdsRemainStringsAndTicketsKeepPointUnits(){val (rows,total)=PangguaiProtocol.tickets(JSONObject("{total:1,items:[{shopId:'9007199254740993001',shopName:'人工测试商户',totalAmount:'1000',principalAmount:'900',presentAmount:'100'}]}"));assertEquals(1,total);assertEquals("9007199254740993001",rows.getJSONObject(0).getString("id"));assertEquals("1000",rows.getJSONObject(0).getString("balance"))}
    @Test fun scanOnlyParsesExpectedDeviceCode(){assertEquals(mapOf("NQT" to "test-device-123"),PangguaiProtocol.deviceCode("https://h5.qiekj.com/skip?NQT=test-device-123"));assertEquals(mapOf("SN" to "12345678"),PangguaiProtocol.deviceCode("http://h5.qiekj.com/skip?SN=12345678"))}
    @Test fun scanRejectsConfusedOrExternalInputs(){listOf("https://evil.test/skip?NQT=123456","https://h5.qiekj.com@evil.test/skip?SN=123456","javascript:alert(1)","https://h5.qiekj.com/skip?SN=123456&SN=abcdef","https://h5.qiekj.com/skip?NQT=123456&SN=abcdef","https://h5.qiekj.com/skip?SN=%252F1234","https://h5.qiekj.com/skip?SN=123456&IMEI=other").forEach{fails("QR"){PangguaiProtocol.deviceCode(it)}}}
    @Test fun detailsMustMatchScannedIdentity(){fails("DEVICE"){PangguaiProtocol.device(JSONObject("{id:'a',type:'goods',categoryCode:'00'}"),JSONObject("{goodsId:'b',categoryCode:'00',name:'test'}"),JSONArray())}}
    @Test fun signatureChangesWithPathAndToken(){val a=PangguaiProtocol.signature("user/info","synthetic-a","1");assertEquals(64,a.length);assertNotEquals(a,PangguaiProtocol.signature("order/list","synthetic-a","1"));assertNotEquals(a,PangguaiProtocol.signature("user/info","synthetic-b","1"))}
}

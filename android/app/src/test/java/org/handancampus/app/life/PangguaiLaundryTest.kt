package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PangguaiLaundryTest {
    private val device=JSONObject("""{"id":"77","name":"测试洗衣机","category":"00","payment":"before","isBluetooth":"0","imei":"synthetic-imei","routeShopId":"42","shopId":"shop-test","skus":[{"id":"wash","name":"标准洗","available":true}]}""")
    private class Harness {
        var saved:JSONObject?=null
        var time=1000L
        var status="0"
        var paid=false
        var started=false
        var detailPrice="3.5"
        var sku="wash"
        val calls=mutableListOf<String>()
        var handler:((String)->Any?)?=null
        val engine=PangguaiLaundry(request={p,_->
            calls.add(p)
            if(handler!=null)handler!!.invoke(p) else response(p)
        },persist={saved=JSONObject(it.toString())},now={time},pause={},alipay={paid=true})
        fun response(p:String):Any?=when(p) {
            "trade/preview/v4"->JSONObject("""{"realPrice":"3.50","items":[{"goodsId":"77","skuId":"wash"}]}""")
            "payChannelRoute/prePay","payChannelRoute/againPay"->JSONArray("""[{"method":2,"methodName":"余额","useStatus":true,"needOpenFlag":false},{"method":13,"methodName":"支付宝","useStatus":true,"needOpenFlag":false}]""")
            "trade/check_device_status"->JSONObject("""{"health":true,"msgId":"test-message"}""")
            "machine/sync"->true
            "trade/create"->JSONObject("""{"tradeNo":"trade-test","orderId":"id-test"}""")
            "pay/unify/pay"->{paid=true;null}
            "pay/unify/prePay"->JSONObject().put("prepayParam","synthetic-signed-parameter-for-sdk")
            "order/pay_status"->paid
            "machine/device_is_start"->started
            "order/cancel"->{status="1";null}
            "order/detail"->JSONObject().put("id","id-test").put("orderNo","trade-test").put("orderStatus",status).put("payPrice",detailPrice)
                .put("completeTime","2026-11-08 16:30:00").put("tradeOrderItem",JSONArray().put(JSONObject().put("goodsId","77").put("skuId",sku)))
            else->error("Unexpected endpoint $p")
        }
    }
    private fun fails(code:String,action:()->Unit){try{action();fail("expected $code")}catch(e:PangguaiFailure){assertEquals(code,e.kind)}}
    @Test fun quoteAndPhotoFormatsNeverCreateOrPay(){val h=Harness();h.engine.quote(device,"wash");assertFalse(h.calls.contains("trade/create"));assertFalse(h.calls.contains("pay/unify/pay"));assertEquals(mapOf("SN" to "123456789012345"),PangguaiProtocol.deviceCode("https://h5.qiekj.com/skip?SN=123456789012345"));assertEquals(mapOf("NQT" to "synthetic-washer-code"),PangguaiProtocol.deviceCode("https://h5.qiekj.com/skip?Company=qiekj&CommunicateType=1&Ver=4&NQT=synthetic-washer-code"))}
    @Test fun paidDoesNotMeanMachineStarted(){val h=Harness();val q=h.engine.quote(device,"wash");val result=h.engine.start(device,q,"2",null);assertEquals("paid",result.getString("phase"));assertEquals(1,h.calls.count{it=="trade/create"});assertEquals(1,h.calls.count{it=="pay/unify/pay"})}
    @Test fun explicitStartAndServerCompletionAreSeparate(){val h=Harness();h.started=true;val result=h.engine.start(device,h.engine.quote(device,"wash"),"2",null);assertEquals("running",result.getString("phase"));h.status="3";assertEquals("completed",h.engine.poll(result).getString("phase"))}
    @Test fun unknownCreateIsDurableAndBlocksSecondCreate(){val h=Harness();val q=h.engine.quote(device,"wash");h.handler={p->if(p=="trade/create")throw PangguaiFailure("NETWORK") else h.response(p)};fails("NETWORK"){h.engine.start(device,q,"2",null)};assertEquals("creating",h.saved!!.getString("phase"));fails("ORDER_ACTIVE"){h.engine.start(device,q,"2",h.saved)};assertEquals(1,h.calls.count{it=="trade/create"})}
    @Test fun lostPaymentResponseNeverResendsPayment(){val h=Harness();val q=h.engine.quote(device,"wash");h.handler={p->if(p=="pay/unify/pay")throw PangguaiFailure("NETWORK") else h.response(p)};fails("NETWORK"){h.engine.start(device,q,"2",null)};assertTrue(h.saved!!.getBoolean("paySent"));h.engine.poll(h.saved!!);assertEquals(1,h.calls.count{it=="pay/unify/pay"});fails("ORDER_ACTIVE"){h.engine.quoteExisting(h.saved!!)}}
    @Test fun changedOrderAmountRequiresAnotherConfirmation(){val h=Harness();val q=h.engine.quote(device,"wash");h.detailPrice="4";fails("PRICE_CHANGED"){h.engine.start(device,q,"2",null)};assertEquals("pending",h.saved!!.getString("phase"));assertFalse(h.calls.contains("pay/unify/pay"));val next=h.engine.quoteExisting(h.saved!!);assertEquals("4",next.getString("amount"));h.engine.payExisting(h.saved!!,next,"2");assertEquals(1,h.calls.count{it=="trade/create"})}
    @Test fun mismatchedOrderCannotBePaid(){val h=Harness();h.sku="other";fails("ORDER_MISMATCH"){h.engine.start(device,h.engine.quote(device,"wash"),"2",null)};assertFalse(h.calls.contains("pay/unify/pay"))}
    @Test fun expiredQuoteCannotCreate(){val h=Harness();val q=h.engine.quote(device,"wash");h.time+=61_000;fails("QUOTE_EXPIRED"){h.engine.start(device,q,"2",null)};assertFalse(h.calls.contains("trade/create"))}
    @Test fun unknownChannelFlagsAreNotPermissionToPay(){val h=Harness();h.handler={p->if(p=="payChannelRoute/prePay")JSONArray("[{method:2}]") else h.response(p)};val q=h.engine.quote(device,"wash");assertFalse(q.getJSONArray("channels").getJSONObject(0).getBoolean("available"));fails("PAY_CHANNEL"){h.engine.start(device,q,"2",null)}}
    @Test fun unsupportedWaterOrBluetoothCannotCreate(){val h=Harness();fails("DEVICE"){h.engine.quote(JSONObject(device.toString()).put("category","04"),"wash")};fails("DEVICE"){h.engine.quote(JSONObject(device.toString()).put("isBluetooth","1"),"wash")}}
    @Test fun readyTimeoutStopsBeforeCreate(){val h=Harness();h.handler={p->if(p=="machine/sync")false else h.response(p)};fails("DEVICE_BUSY"){h.engine.start(device,h.engine.quote(device,"wash"),"2",null)};assertFalse(h.calls.contains("trade/create"))}
    @Test fun sdkReturnAloneDoesNotConfirmPayment(){val h=Harness();h.handler={p->if(p=="order/pay_status")false else h.response(p)};val result=h.engine.start(device,h.engine.quote(device,"wash"),"13",null);assertEquals("checking",result.getString("phase"));assertFalse(h.calls.contains("machine/device_is_start"))}
    @Test fun cancelRechecksPaymentBeforeMutation(){val h=Harness();h.detailPrice="4";fails("PRICE_CHANGED"){h.engine.start(device,h.engine.quote(device,"wash"),"2",null)};h.status="2";fails("ORDER_ACTIVE"){h.engine.cancel(h.saved!!)};assertFalse(h.calls.contains("order/cancel"))}
    @Test fun nativeSnapshotDoesNotLeakPrivateRoutingOrQuote(){val v=PangguaiLaundry.view(JSONObject().put("id","session").put("imei","private").put("token","secret").put("shopId","routing").put("phase","paid"))!!;assertEquals("paid",v.getString("phase"));assertFalse(v.has("token"));assertFalse(v.has("imei"));assertFalse(v.has("shopId"))}
}

package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PangguaiWaterTest {
    @Test fun availableOutletDoesNotRequireAPreviousOrderEndStatusBeforeStarting(){
        for(status in listOf<String?>(null,"1","0","5")){
            val h=Harness()
            h.handler={p,_->if(p=="goods/water/sync"&&h.readingPhase=="idle"){
                JSONObject().put("workStatus",1).apply{if(status!=null)put("status",status)}
            }else h.response(p)}
            val result=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
            assertEquals("using",result.getString("phase"));assertEquals(1,h.count("goods/water/unlock"))
        }
    }
    @Test fun nonWorkingPreflightAfterArchiveStillRequiresFreshAvailabilityAndNeverReplaysOldOrder(){
        val h=Harness();val old=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        val archived=h.engine.archiveUnverified(old,true);h.readingPhase="idle"
        h.handler={p,_->if(p=="goods/water/sync"&&h.readingPhase=="idle")JSONObject("{workStatus:1}")else h.response(p)}
        val result=h.engine.start(device,h.engine.prepare(device,"outlet-test"),archived)
        assertEquals("using",result.getString("phase"));assertEquals(2,h.count("goods/water/unlock"))
        assertEquals(0,h.count("goods/endWater"));assertEquals(0,h.count("order/sync"))
    }
    @Test fun localArchiveRequiresExplicitObservationAndNeverSendsCommands(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        h.calls.clear();fails("WATER_CONFIRM_REQUIRED"){h.engine.archiveUnverified(s,false)}
        assertEquals("using",h.saved!!.getString("phase"))
        val result=h.engine.archiveUnverified(s,true)
        assertEquals("archived_unverified",result.getString("phase"));assertEquals("water-order",result.getString("orderNo"))
        assertFalse(result.optBoolean("deviceEnded"));assertFalse(result.optBoolean("billConfirmed"));assertFalse(result.has("endedAt"))
        assertTrue(h.calls.isEmpty());h.engine.poll(result);h.engine.end(result);assertTrue(h.calls.isEmpty())
    }
    @Test fun localArchiveDoesNotBypassFreshDeviceBusyCheck(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        val archived=h.engine.archiveUnverified(s,true);val quote=h.engine.prepare(device,"outlet-test")
        fails("DEVICE_BUSY"){h.engine.start(device,quote,archived)}
        assertEquals(1,h.count("goods/water/unlock"))
        h.readingPhase="idle";h.engine.start(device,h.engine.prepare(device,"outlet-test"),archived)
        assertEquals(2,h.count("goods/water/unlock"))
    }
    @Test fun incompleteDeviceResponseCannotUnlockAfterLocalArchive(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        val archived=h.engine.archiveUnverified(s,true);val quote=h.engine.prepare(device,"outlet-test")
        h.handler={p,_->if(p=="goods/water/sync")JSONObject() else h.response(p)}
        fails("WATER_WAIT"){h.engine.start(device,quote,archived)}
        assertEquals(1,h.count("goods/water/unlock"));assertEquals(1,h.count("payChannelRoute/addUserAfterPayChannel"))
    }
    private val device=JSONObject("{id:'water-device',category:'04',routeShopId:'42'}")
    private class Harness {
        var saved:JSONObject?=null;var readingPhase="idle";var finish=true;var channel=true;var amount:Any=1
        var paid=false;var orderExists=false;var identity="water-order";var billSku="outlet-test"
        val calls=mutableListOf<Pair<String,Map<String,String>>>()
        var handler:((String,Map<String,String>)->Any?)?=null
        val engine=PangguaiWater(request={p,f->calls.add(p to f);if(handler!=null)handler!!.invoke(p,f) else response(p)},persist={saved=JSONObject(it.toString())},now={1000})
        fun response(p:String):Any?=when(p){
            "goods/normal/details"->JSONObject().put("goodsId","water-device").put("categoryCode","04").put("name","测试饮水机").put("imei","synthetic-imei").put("payment","after").put("isBluetooth",0).put("supportAppUserFinish",finish)
            "goods/normal/skus"->JSONArray("[{skuId:'outlet-test',name:'常温水',feature:'按设备实际用量计费',price:'1',scanAvailable:true,stockState:1}]")
            "payChannelRoute/afterPay"->JSONArray().put(JSONObject().put("method",15).put("methodName","支付宝免密").put("useStatus",channel).put("needOpenFlag",!channel))
            "payChannelRoute/addUserAfterPayChannel"->JSONObject()
            "goods/water/unlock"->{readingPhase="using";JSONObject("{msgId:'message-test',orderNo:'water-order'}")}
            "machine/msg/sync"->JSONObject("{state:'OK',code:0}")
            "goods/water/sync"->when(readingPhase){"idle"->JSONObject("{status:5,workStatus:1,identify:'old'}");"using"->JSONObject().put("status",1).put("workStatus",2).put("identify",identity);"ended"->JSONObject().put("status",5).put("workStatus",1).put("identify",identity).put("amount",amount);else->null}
            "goods/endWater"->{readingPhase="ended";true}
            "order/afterPay/creating"->{orderExists=true;JSONObject("{orderNo:'water-order',orderId:'bill-test'}")}
            "order/sync"->{paid=true;JSONObject("{code:0}")}
            "order/detail"->{if(!orderExists)throw PangguaiFailure("SERVICE");JSONObject().put("id","bill-test").put("orderNo","water-order").put("orderStatus",if(paid)2 else 0).put("payPrice","0.13").put("tradeOrderItem",JSONArray().put(JSONObject().put("goodsId","water-device").put("skuId",billSku)))}
            else->error("Unexpected $p")
        }
        fun count(p:String)=calls.count{it.first==p}
    }
    private fun fails(kind:String,action:()->Unit){try{action();fail("expected $kind")}catch(e:PangguaiFailure){assertEquals(kind,e.kind)}}
    @Test fun preparingNeverStartsOrSelectsPayment(){val h=Harness();val q=h.engine.prepare(device,"outlet-test");assertTrue(q.getBoolean("canStart"));assertEquals(0,h.count("goods/water/unlock"));assertEquals(0,h.count("payChannelRoute/addUserAfterPayChannel"))}
    @Test fun unavailableChannelCannotStart(){val h=Harness();h.channel=false;val q=h.engine.prepare(device,"outlet-test");fails("WATER_CHANNEL"){h.engine.start(device,q,null)};assertEquals(0,h.count("goods/water/unlock"))}
    @Test fun explicitStartConfirmsMatchingSession(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);assertEquals("using",s.getString("phase"));assertEquals(1,h.count("goods/water/unlock"));assertEquals("15",h.calls.single{it.first=="payChannelRoute/addUserAfterPayChannel"}.second["method"])}
    @Test fun busyDeviceBlocksUnlock(){val h=Harness();val q=h.engine.prepare(device,"outlet-test");h.readingPhase="using";fails("DEVICE_BUSY"){h.engine.start(device,q,null)};assertEquals(0,h.count("goods/water/unlock"))}
    @Test fun acknowledgementAloneDoesNotMeanUsing(){val h=Harness();val q=h.engine.prepare(device,"outlet-test");h.handler={p,_->if(p=="goods/water/unlock")JSONObject("{msgId:'message-test',orderNo:'water-order'}") else h.response(p)};val s=h.engine.start(device,q,null);assertEquals("starting",s.getString("phase"));assertFalse(s.has("startedAt"))}
    @Test fun lostUnlockResponseCannotReplay(){val h=Harness();val q=h.engine.prepare(device,"outlet-test");h.handler={p,_->if(p=="goods/water/unlock")throw PangguaiFailure("NETWORK") else h.response(p)};fails("NETWORK"){h.engine.start(device,q,null)};assertEquals("starting",h.saved!!.getString("phase"));fails("WATER_ACTIVE"){h.engine.start(device,q,h.saved)};assertEquals(1,h.count("goods/water/unlock"))}
    @Test fun physicalOnlyDeviceDoesNotSendRemoteEnd(){val h=Harness();h.finish=false;val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);fails("WATER_PHYSICAL_END"){h.engine.end(s)};assertEquals(0,h.count("goods/endWater"));h.readingPhase="ended";assertEquals("settled",h.engine.poll(h.saved!!).getString("phase"))}
    @Test fun remoteFinishSettlesTheSameOrderOnce(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);val done=h.engine.end(s);assertEquals("settled",done.getString("phase"));assertEquals("0.13",done.getString("amount"));h.engine.poll(done);assertEquals(1,h.count("goods/endWater"));assertEquals(1,h.count("order/afterPay/creating"));assertEquals(1,h.count("order/sync"));assertEquals("water-order",h.calls.single{it.first=="order/sync"}.second["orderNo"])}
    @Test fun zeroUsageDoesNotCreateOrCharge(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.amount="0.00";h.readingPhase="ended";val done=h.engine.poll(s);assertEquals("ended_zero",done.getString("phase"));assertFalse(done.has("amount"));assertEquals(0,h.count("order/sync"));assertEquals(0,h.count("order/afterPay/creating"))}
    @Test fun otherOrderIsNeverEndedOrSettled(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.identity="someone-else";val closed=h.engine.end(s);assertEquals("closed_unknown",closed.getString("phase"));assertEquals(0,h.count("goods/endWater"));assertEquals(0,h.count("order/sync"));assertEquals(0,h.count("order/afterPay/creating"))}
    @Test fun unknownUsageIsNotTreatedAsZero(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.amount=JSONObject.NULL;h.readingPhase="ended";assertEquals("settled",h.engine.poll(s).getString("phase"));assertEquals(1,h.count("order/afterPay/creating"))}
    @Test fun lostSettlementResponseOnlyQueriesExistingBill(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.readingPhase="ended";h.handler={p,_->if(p=="order/sync"){h.paid=true;throw PangguaiFailure("NETWORK")}else h.response(p)};fails("NETWORK"){h.engine.poll(s)};assertTrue(h.saved!!.getBoolean("settleSent"));assertEquals("settled",h.engine.poll(h.saved!!).getString("phase"));assertEquals(1,h.count("order/sync"))}
    @Test fun lostAfterPayCreationCanRecoverWithoutRecreating(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.readingPhase="ended";h.handler={p,_->if(p=="order/afterPay/creating"){h.orderExists=true;throw PangguaiFailure("NETWORK")}else h.response(p)};fails("NETWORK"){h.engine.poll(s)};assertEquals("settled",h.engine.poll(h.saved!!).getString("phase"));assertEquals(1,h.count("order/afterPay/creating"))}
    @Test fun billIdentityCheckedBeforeSettlement(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.readingPhase="ended";h.billSku="different-outlet";fails("ORDER_MISMATCH"){h.engine.poll(s)};assertEquals(0,h.count("order/sync"))}
    @Test fun endAcknowledgementDoesNotMeanDeviceEnded(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.handler={p,_->if(p=="goods/endWater")true else h.response(p)};val result=h.engine.end(s);assertEquals("ending",result.getString("phase"));assertEquals(0,h.count("order/sync"))}
    @Test fun snapshotContainsNoPrivateCommandData(){val source=JSONObject("{id:'s',msgId:'m',skuId:'sku',token:'secret',phase:'using'}");val view=PangguaiWater.view(source)!!;assertFalse(view.has("token"));assertFalse(view.has("msgId"));assertFalse(view.has("skuId"))}
    @Test fun paidBillWithoutDeviceEndCannotClaimWaterHasStopped(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.orderExists=true;h.paid=true;h.readingPhase="empty";val result=h.engine.poll(s);assertEquals("using",result.getString("phase"));assertTrue(result.getBoolean("billConfirmed"));assertFalse(result.optBoolean("deviceEnded"));assertEquals(0,h.count("order/sync"))}

    @Test fun twoSuccessfulEmptyReadsAfterUseHandleObservedPhysicalSettlementVariant(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.readingPhase="empty";val first=h.engine.poll(s);assertEquals("using",first.getString("phase"));assertEquals(0,h.count("order/afterPay/creating"));val second=h.engine.poll(first);assertEquals("settled",second.getString("phase"));assertEquals("session_closed",second.getString("endBasis"));assertEquals(1,h.count("order/afterPay/creating"))}

    @Test fun immediateEndAndLostPaymentKeepsNewestDurableIntent(){val h=Harness();val q=h.engine.prepare(device,"outlet-test");h.handler={p,_->when(p){"goods/water/unlock"->{h.readingPhase="ended";JSONObject("{msgId:'message-test',orderNo:'water-order'}")};"order/sync"->{h.paid=true;throw PangguaiFailure("NETWORK")};else->h.response(p)}};fails("NETWORK"){h.engine.start(device,q,null)};assertTrue(h.saved!!.getBoolean("settleSent"));assertEquals("settled",h.engine.poll(h.saved!!).getString("phase"));assertEquals(1,h.count("order/sync"));assertEquals(1,h.count("order/afterPay/creating"))}

    @Test fun remoteEndAndLostPaymentKeepsNewestDurableIntent(){val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.handler={p,_->if(p=="order/sync"){h.paid=true;throw PangguaiFailure("NETWORK")}else h.response(p)};fails("NETWORK"){h.engine.end(s)};assertTrue(h.saved!!.getBoolean("settleSent"));assertEquals("settled",h.engine.poll(h.saved!!).getString("phase"));assertEquals(1,h.count("goods/endWater"));assertEquals(1,h.count("order/sync"))}

    @Test fun persistedOwnershipMismatchClosesOldSessionAndCanStartAgainOnIdleDevice(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        val legacy=JSONObject(running.toString()).put("error","WATER_OWNERSHIP").put("startedAt",-21_000_000)
        h.identity="someone-else"
        val closed=h.engine.poll(legacy)
        assertEquals("closed_unknown",closed.getString("phase"));assertEquals("order_replaced",closed.getString("endBasis"))
        assertEquals(1000,closed.getLong("endedAt"));assertFalse(closed.getBoolean("remoteEnd"));assertFalse(closed.has("amount"))
        assertEquals(0,h.count("goods/endWater"));assertEquals(0,h.count("order/afterPay/creating"));assertEquals(0,h.count("order/sync"))
        h.readingPhase="idle";h.identity="water-order"
        // Even callers still holding the legacy snapshot are reconciled before start's active-session guard.
        val fresh=h.engine.start(device,h.engine.prepare(device,"outlet-test"),legacy)
        assertEquals("using",fresh.getString("phase"));assertEquals(2,h.count("goods/water/unlock"))
    }
    @Test fun replacedSessionOnlyReadsOriginalBillAndMayLaterBecomeSettled(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        h.identity="someone-else";val closed=h.engine.poll(running)
        h.orderExists=true;h.paid=true;val billed=h.engine.poll(JSONObject(closed.toString()))
        assertEquals("settled",billed.getString("phase"));assertEquals("0.13",billed.getString("amount"))
        assertTrue(h.calls.filter{it.first=="order/detail"}.all{it.second["orderNo"]=="water-order"})
        assertEquals(0,h.count("goods/endWater"));assertEquals(0,h.count("order/afterPay/creating"));assertEquals(0,h.count("order/sync"))
    }
    @Test fun ownOngoingSessionStillBlocksDuplicateUnlock(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        fails("WATER_ACTIVE"){h.engine.start(device,h.engine.prepare(device,"outlet-test"),running)}
        assertEquals(1,h.count("goods/water/unlock"))
    }
    @Test fun blankIdentityOnBusyDeviceDoesNotFreeSessionOrSendEnd(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.identity=""
        val uncertain=h.engine.poll(running);assertEquals("using",uncertain.getString("phase"))
        assertEquals("WATER_OWNERSHIP",uncertain.getString("error"));fails("WATER_OWNERSHIP"){h.engine.end(uncertain)}
        assertEquals(0,h.count("goods/endWater"));assertEquals(0,h.count("order/sync"))
    }
    @Test fun idleDeviceWithoutIdentityReleasesUsedRecordWithoutCharging(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        h.readingPhase="idle";h.handler={p,_->if(p=="goods/water/sync")JSONObject("{status:5,workStatus:1}") else h.response(p)}
        val closed=h.engine.poll(running);assertEquals("closed_unknown",closed.getString("phase"))
        assertEquals("device_idle",closed.getString("endBasis"));assertEquals(0,h.count("order/afterPay/creating"))
    }
    @Test fun ownershipChangeBetweenEndChecksNeverEndsReplacementOrder(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);var reads=0
        h.handler={p,_->if(p=="goods/water/sync"&&++reads==2)JSONObject("{status:1,workStatus:2,identify:'someone-else'}") else h.response(p)}
        assertEquals("closed_unknown",h.engine.end(running).getString("phase"));assertEquals(0,h.count("goods/endWater"))
    }
    @Test fun commandAcknowledgementFailureCannotBlockAuthoritativeOwnershipRecovery(){
        val h=Harness();val running=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.identity="someone-else"
        h.handler={p,_->if(p=="machine/msg/sync")throw PangguaiFailure("NETWORK") else h.response(p)}
        assertEquals("closed_unknown",h.engine.poll(running).getString("phase"));assertEquals(0,h.count("order/sync"))
    }

    @Test fun legacyUsingWithoutStartTimestampReleasesReplacedOrderAndCanStartAgain(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        s.remove("startedAt");s.put("error","WATER_OWNERSHIP");h.readingPhase="idle"
        val next=h.engine.start(device,h.engine.prepare(device,"outlet-test"),s)
        assertEquals("using",next.getString("phase"));assertEquals(2,h.count("goods/water/unlock"))
        assertEquals(0,h.count("order/sync"));assertEquals(0,h.count("goods/endWater"))
    }
    @Test fun unconfirmedStartupDoesNotAutomaticallyReleaseAgainstPreviousDeviceReading(){
        val h=Harness();val q=h.engine.prepare(device,"outlet-test")
        h.handler={p,_->if(p=="goods/water/unlock")JSONObject("{orderNo:'water-order'}") else h.response(p)}
        val s=h.engine.start(device,q,null)
        fails("WATER_ACTIVE"){h.engine.start(device,q,s)}
        assertEquals("starting",h.saved!!.getString("phase"));assertEquals(1,h.count("goods/water/unlock"))
    }
    @Test fun manualRecoveryOfEndedOwnOrderOnlyReadsDeviceAndKeepsUnconfirmedBill(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        s.remove("startedAt");h.readingPhase="ended";h.calls.clear()
        val closed=h.engine.confirmPhysicalEnd(s)
        assertEquals("closed_unknown",closed.getString("phase"));assertEquals("device_idle",closed.getString("endBasis"))
        assertEquals("water-order",closed.getString("orderNo"));assertFalse(closed.has("amount"))
        assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
        h.orderExists=true;h.paid=true
        assertEquals("settled",h.engine.poll(closed).getString("phase"))
        assertEquals(0,h.count("order/sync"));assertEquals(0,h.count("order/afterPay/creating"))
    }
    @Test fun manualRecoveryOnDifferentActiveOrderNeverControlsReplacement(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        s.remove("startedAt");s.put("phase","starting");h.identity="someone-else";h.calls.clear()
        val closed=h.engine.confirmPhysicalEnd(s)
        assertEquals("order_replaced",closed.getString("endBasis"));assertEquals("closed_unknown",closed.getString("phase"))
        assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
        fails("DEVICE_BUSY"){h.engine.start(device,h.engine.prepare(device,"outlet-test"),closed)}
        assertEquals(0,h.count("goods/water/unlock"))
    }
    @Test fun manualRecoveryDoesNotClearOwnStillRunningSession(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.calls.clear()
        fails("WATER_STILL_ACTIVE"){h.engine.confirmPhysicalEnd(s)}
        assertEquals("using",h.saved!!.getString("phase"));assertFalse(h.saved!!.optBoolean("deviceEnded"))
        assertEquals("WATER_STILL_ACTIVE",h.saved!!.getString("error"));assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
    }
    @Test fun blankBusyIdentityCannotBeManuallyReleased(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.identity="";h.calls.clear()
        fails("WATER_WAIT"){h.engine.confirmPhysicalEnd(s)}
        assertEquals("using",h.saved!!.getString("phase"));assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
    }
    @Test fun explicitPhysicalConfirmationCanArchiveAbsentSessionWithoutClaimingPaid(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null)
        h.readingPhase="empty";h.calls.clear();val closed=h.engine.confirmPhysicalEnd(s)
        assertEquals("physical_confirmed",closed.getString("endBasis"));assertEquals("closed_unknown",closed.getString("phase"))
        assertEquals("WATER_BILL_UNKNOWN",closed.getString("error"));assertFalse(closed.has("amount"))
        assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
    }
    @Test fun failedRecoveryPreservesSessionAndDoesNotUnlockOrCharge(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.calls.clear()
        h.handler={_,_->throw PangguaiFailure("NETWORK")}
        fails("NETWORK"){h.engine.confirmPhysicalEnd(s)}
        assertEquals("using",h.saved!!.getString("phase"));assertEquals("water-order",h.saved!!.getString("orderNo"))
        assertEquals(listOf("goods/water/sync"),h.calls.map{it.first})
    }
    @Test fun missingUnlockResponseNeedsPhysicalConfirmationAndIdleDevice(){
        val h=Harness();val s=JSONObject("{id:'unknown',deviceId:'water-device',skuId:'outlet-test',phase:'starting'}")
        h.readingPhase="using";fails("WATER_WAIT"){h.engine.confirmPhysicalEnd(s)}
        h.readingPhase="idle";val closed=h.engine.confirmPhysicalEnd(s)
        assertEquals("closed_unknown",closed.getString("phase"));assertEquals("device_idle",closed.getString("endBasis"))
        assertFalse(closed.has("orderNo"));assertEquals(0,h.count("goods/water/unlock"))
    }
    @Test fun repeatedManualRecoveryOfClosedRecordSendsNoRequests(){
        val h=Harness();val s=h.engine.start(device,h.engine.prepare(device,"outlet-test"),null);h.readingPhase="empty"
        val closed=h.engine.confirmPhysicalEnd(s);h.calls.clear()
        assertEquals(closed.toString(),h.engine.confirmPhysicalEnd(closed).toString());assertTrue(h.calls.isEmpty())
    }

}

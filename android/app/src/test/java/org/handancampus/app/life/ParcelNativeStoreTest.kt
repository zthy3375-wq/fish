package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ParcelNativeStoreTest {
    private fun parcel(p:String="taobao",id:String="waybill:SYNTHETIC001",code:String="01-02-003",station:String="合成东站") = NativeParcel(p,id,code,station,"SYNTHETIC001",syncedAt=10)
    @Test fun failedPartialAndEmptyResultsDoNotDeleteExistingParcels() {
        val ledger=ParcelLedger();val a=parcel();ledger.merge(NativeParcelBatch("taobao","partial",listOf(a)),10)
        for(phase in listOf("empty","login","verify","unrecognized","loading"))ledger.merge(NativeParcelBatch("taobao",phase,emptyList()),20)
        assertEquals(listOf(a),ledger.items.values.toList())
        assertEquals(20L,ledger.updated["taobao"])
    }
    @Test fun accountsAreIsolatedAndOnlyMatchingProviderCleared() {
        val ledger=ParcelLedger();ledger.bind("taobao","account-a");ledger.bind("pinduoduo","account-b")
        ledger.merge(NativeParcelBatch("taobao","partial",listOf(parcel())))
        ledger.merge(NativeParcelBatch("pinduoduo","partial",listOf(parcel("pinduoduo"))))
        ledger.bind("taobao","account-c")
        assertEquals(1,ledger.items.size);assertEquals("pinduoduo",ledger.items.values.single().provider)
    }
    @Test fun identicalCodesOnDifferentStationsAndProvidersRemainSeparate() {
        val ledger=ParcelLedger()
        val parcels=listOf(parcel(id="shelf:东:01",station="东"),parcel(id="shelf:西:01",station="西"))
        ledger.merge(NativeParcelBatch("taobao","partial",parcels));ledger.merge(NativeParcelBatch("pinduoduo","partial",listOf(parcel("pinduoduo"))))
        assertEquals(3,ledger.items.size)
    }
    @Test fun partialResponseReconcilesProvisionalCardAndRetainsUserMarkedTaken() {
        val ledger=ParcelLedger();val provisional=parcel(id="shelf:合成东站:01-02-003")
        ledger.merge(NativeParcelBatch("taobao","partial",listOf(provisional)));ledger.mark(provisional.key,true,25)
        ledger.merge(NativeParcelBatch("taobao","partial",listOf(parcel())))
        assertEquals(1,ledger.items.size);assertEquals(25L,ledger.items.values.single().takenAt)
        ledger.mark(parcel().key,false);assertEquals(0L,ledger.items.values.single().takenAt)
    }
    @Test fun serializedCachePreservesLeadingZeroesAndLocalStateAcrossRecreation() {
        val ledger=ParcelLedger();val a=parcel();ledger.merge(NativeParcelBatch("taobao","partial",listOf(a)));ledger.mark(a.key,true,100)
        val restored=ParcelLedger();restored.restore(ledger.json().toString())
        assertEquals("01-02-003",restored.items.values.single().code);assertEquals(100L,restored.items.values.single().takenAt)
    }
    @Test fun parserRejectsMalformedSourceOversizeAndUnsafeValues() {
        val valid=JSONObject().put("version",2).put("provider","taobao").put("phase","partial").put("items",JSONArray().put(parcel().json()))
        assertEquals("partial",NativeParcelBatch.parse("taobao",JSONObject.quote(valid.toString())).phase)
        assertEquals("unrecognized",NativeParcelBatch.parse("pinduoduo",valid.toString()).phase)
        valid.getJSONArray("items").getJSONObject(0).put("code","13800138000")
        assertEquals("unrecognized",NativeParcelBatch.parse("taobao",valid.toString()).phase)
        assertEquals("unrecognized",NativeParcelBatch.parse("taobao","x".repeat(300001)).phase)
    }
}

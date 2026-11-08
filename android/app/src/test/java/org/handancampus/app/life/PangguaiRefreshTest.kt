package org.handancampus.app.life

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PangguaiRefreshTest {
    private fun source()=JSONObject("""{"token":"synthetic-token","id":"synthetic-user","phone":"13800000000","snapshot":{"balance":"8.50","walletUpdatedAt":10,"tickets":[{"id":"old"}],"ticketsUpdatedAt":11,"orders":[{"id":"old-order"}],"ordersUpdatedAt":12}}""")
    @Test fun failuresPreserveLastGoodSections(){val initial=source();val result=PangguaiRefresh.execute(initial,{_,_,_->throw PangguaiFailure("NETWORK")},{100});val s=result.getJSONObject("snapshot");assertEquals("8.50",s.getString("balance"));assertEquals(10,s.getLong("walletUpdatedAt"));assertEquals("old",s.getJSONArray("tickets").getJSONObject(0).getString("id"));assertEquals("old-order",s.getJSONArray("orders").getJSONObject(0).getString("id"));assertFalse(initial.getJSONObject("snapshot").has("issues"))}
    @Test fun authStopsFurtherRequests(){var count=0;val result=PangguaiRefresh.execute(source(),{_,_,_->count++;throw PangguaiFailure("AUTH")},{100});assertEquals(1,count);assertTrue(result.getBoolean("expired"))}
    @Test fun accountSwitchCannotReplaceBalance(){val result=PangguaiRefresh.execute(source(),{_,_,_->JSONObject("{id:'another-user',phone:'13800000000',balance:'99'}")},{100});assertTrue(result.getBoolean("expired"));assertEquals("8.50",result.getJSONObject("snapshot").getString("balance"))}
    @Test fun incompleteMerchantPagesDoNotEraseCache(){val result=PangguaiRefresh.execute(source(),{path,_,_->when(path){"user/info"->JSONObject("{id:'synthetic-user',phone:'13800000000',balance:'9'}");"tokenCoin/userTokenCoins"->JSONObject("{total:2,items:[]}");else->JSONObject("{items:[]}")}},{100});val s=result.getJSONObject("snapshot");assertEquals("9",s.getString("balance"));assertEquals("old",s.getJSONArray("tickets").getJSONObject(0).getString("id"));assertEquals("PARTIAL",s.getJSONObject("issues").getString("tickets"));assertEquals(0,s.getJSONArray("orders").length())}
}

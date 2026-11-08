package org.handancampus.app.analytics
import org.json.JSONObject
object AnalyticsContract {
    val features = setOf("schedule","tasks","learning","shower","wallet","water","laundry","parcel","grades","map")
    fun counters(raw: String?, day: String): JSONObject {
        val old = try { JSONObject(raw ?: "{}") } catch (_:Exception) { JSONObject() }
        val data = if(old.optString("day")==day) old.optJSONObject("features") ?: JSONObject() else JSONObject()
        val clean=JSONObject()
        for(key in features) { val n=data.optInt(key,0).coerceIn(0,1000);if(n>0)clean.put(key,n) }
        return JSONObject().put("day",day).put("features",clean)
    }
    fun increment(raw: String?, day: String, feature: String): JSONObject {
        require(feature in features)
        val result=counters(raw,day);val values=result.getJSONObject("features")
        values.put(feature,(values.optInt(feature,0)+1).coerceAtMost(1000));return result
    }
}

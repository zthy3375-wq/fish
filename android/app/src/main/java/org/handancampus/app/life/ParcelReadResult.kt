package org.handancampus.app.life

import org.json.JSONObject
import org.json.JSONTokener

/** Bounded display-only values; never persist this result or attach it to telemetry. */
data class ParcelPickup(val station: String, val code: String)
data class ParcelReadResult(val phase: String, val items: List<ParcelPickup>) {
    companion object {
        fun parse(provider: String, raw: String?): ParcelReadResult {
            if (raw == null || raw.length > 40_000) return ParcelReadResult("unrecognized", emptyList())
            return try {
                var value = JSONTokener(raw).nextValue()
                if (value is String) value = JSONTokener(value).nextValue()
                val obj = value as JSONObject
                require(obj.getInt("version") == 1 && obj.getString("provider") == provider)
                val phase = obj.getString("phase")
                require(phase in setOf("partial", "empty", "loading", "login", "unrecognized"))
                val array = obj.getJSONArray("items")
                require(array.length() <= 100)
                val items = (0 until array.length()).map {
                    val item = array.getJSONObject(it)
                    val station = item.getString("station")
                    val code = item.getString("code")
                    require(station.isNotBlank() && station.length <= 100 && station.none(Char::isISOControl))
                    require(code.length in 2..24 && code.none(Char::isISOControl) && code.any(Char::isDigit) &&
                        code.matches(Regex("[A-Za-z0-9]+(?:[-—–－\\s][A-Za-z0-9]+)*")) && !code.matches(Regex("\\d{11,}")))
                    ParcelPickup(station, code)
                }.distinct()
                require((phase == "partial") == items.isNotEmpty())
                ParcelReadResult(phase, items)
            } catch (_: Exception) { ParcelReadResult("unrecognized", emptyList()) }
        }
    }
}

/** A navigation, account reset or background event invalidates all pending read callbacks. */
class ParcelReadSession {
    val snapshots = linkedMapOf<String, ParcelReadResult>()
    var generation = 0
        private set
    fun invalidate(provider: String) { generation++; snapshots.remove(provider) }
    fun clear() { generation++; snapshots.clear() }
    fun accept(provider: String, ticket: Int, raw: String?): Boolean {
        if (ticket != generation) return false
        snapshots[provider] = ParcelReadResult.parse(provider, raw)
        return true
    }
}

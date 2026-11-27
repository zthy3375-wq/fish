package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import javax.net.ssl.HttpsURLConnection

internal class ParcelDirectory(
    private val origin: URI,
    private val clientId: String,
    private val load: () -> String?,
    private val save: (String) -> Unit,
    private val clear: () -> Unit,
    private val request: (URL, Map<String, String>?, String?) -> Reply = ::https,
    private val now: () -> Long = System::currentTimeMillis,
) {
    data class Reply(val status: Int, val body: JSONObject, val retryAfter: Long = 0)
    private class Failure(val state: String) : Exception()
    private data class Listing(val items: JSONArray, val maskedPhone: String?, val phoneManagement: URI?)
    private data class Challenge(val deviceCode: String, val userCode: String, val uri: URI, val expiry: Long, var interval: Long, var next: Long)
    private var challenge: Challenge? = null
    private var account = load()?.let { runCatching { JSONObject(it) }.getOrNull() }
    private var lastAttempt = 0L
    private var retryAt = 0L
    private var notice: String? = null

    fun state(): JSONObject = JSONObject().apply {
        val cached = account?.optJSONObject("snapshot")
        put("state", notice ?: when {
            challenge != null -> "pending"
            account == null -> "disconnected"
            cached == null -> "waiting"
            cached.optJSONArray("items")?.length() == 0 -> "empty"
            else -> "ready"
        })
        put("connected", account != null)
        cached?.let {
            put("items", it.getJSONArray("items"))
            put("updatedAt", it.getLong("updatedAt"))
            if (it.has("maskedPhone")) put("maskedPhone", it.getString("maskedPhone"))
            put("canManagePhone", phoneManagementUri() != null)
        }
        challenge?.let { put("userCode", it.userCode) }
    }

    fun verificationUri(): URI? = challenge?.takeIf { now() < it.expiry }?.uri

    fun phoneManagementUri(): URI? = account?.optJSONObject("snapshot")
        ?.optString("phoneManagementUri")?.let(::checkedVerificationUri)

    fun begin(): JSONObject = operation {
        if (account != null || (challenge?.expiry ?: 0L) > now()) return@operation
        if (now() < retryAt) throw Failure("rateLimited")
        val reply = send("/oauth/device/code", mapOf("client_id" to clientId, "scope" to "parcels.read offline_access"))
        val body = verified(reply)
        val baseUri = checkedVerificationUri(body.required("verification_uri", 2048)) ?: throw Failure("unavailable")
        val uri = body.optString("verification_uri_complete").takeIf { it.isNotBlank() }?.let(::checkedVerificationUri) ?: baseUri
        val interval = body.optLong("interval", 5).also { check(it in 1..3600) }.coerceAtLeast(5) * 1000
        val expiry = body.optLong("expires_in").also { check(it in 1..3600) } * 1000
        challenge = Challenge(body.required("device_code", 4096), body.required("user_code", 64), uri, now() + expiry, interval, now() + interval)
    }

    fun poll(): JSONObject = operation {
        val pending = challenge ?: return@operation
        if (now() >= pending.expiry) {
            challenge = null
            throw Failure("expired")
        }
        if (now() < retryAt) throw Failure("rateLimited")
        if (now() < pending.next) return@operation
        pending.next = now() + pending.interval
        val reply = try {
            send("/oauth/token", mapOf(
                "grant_type" to "urn:ietf:params:oauth:grant-type:device_code",
                "device_code" to pending.deviceCode, "client_id" to clientId,
            ))
        } catch (error: IOException) {
            delayChallenge(pending)
            throw error
        }
        when (reply.body.optString("error")) {
            "authorization_pending" -> return@operation
            "slow_down" -> {
                pending.interval += 5000
                pending.next = now() + pending.interval
                return@operation
            }
            "access_denied", "expired_token" -> {
                challenge = null
                throw Failure(if (reply.body.optString("error") == "access_denied") "denied" else "expired")
            }
        }
        if (reply.status in 200..299) {
            updateToken(reply, null)
            challenge = null
            sync(force = true)
        } else {
            if (reply.status >= 500) delayChallenge(pending) else challenge = null
            verified(reply)
        }
    }

    private fun checkedVerificationUri(value: String): URI? = runCatching {
        URI(value).takeIf {
            value.length <= 2048 && it.scheme == "https" && it.host.equals(origin.host, true) &&
                it.port == origin.port && it.userInfo == null
        }
    }.getOrNull()

    private fun delayChallenge(pending: Challenge) {
        pending.interval = maxOf(pending.interval, minOf(pending.interval * 2, 300_000L))
        pending.next = now() + pending.interval
    }

    fun refresh(force: Boolean): JSONObject = operation { sync(force) }

    fun disconnect(): JSONObject = operation {
        clear()
        account = null
        challenge = null
        lastAttempt = 0L
        retryAt = 0L
    }

    private fun operation(block: () -> Unit): JSONObject {
        notice = null
        try {
            block()
        } catch (error: Failure) {
            notice = error.state
            if (account != null && error.state in setOf("expired", "rejected", "forbidden")) {
                account = null
                lastAttempt = 0L
                runCatching { clear() }.onFailure { notice = "unavailable" }
            }
        } catch (_: Exception) { notice = "unavailable" }
        return state()
    }

    private fun sync(force: Boolean) {
        val current = account ?: return
        val time = now()
        if (time < retryAt) throw Failure("rateLimited")
        if (lastAttempt > 0L && time - lastAttempt in 0..9_999L) return
        if (!force && current.optLong("expiresAt") > time + 30_000L &&
            time - (current.optJSONObject("snapshot")?.optLong("updatedAt") ?: 0L) in 0..299_999L) return
        lastAttempt = time
        if (current.optLong("expiresAt") <= time + 30_000L) renew()
        val listing = try { directory() } catch (error: Failure) {
            if (error.state != "rejected") throw error
            renew()
            try { directory() } catch (retry: Failure) {
                if (retry.state == "rejected") throw Failure("expired")
                throw retry
            }
        }
        val updated = JSONObject(account.toString())
        updated.put("snapshot", JSONObject().put("items", listing.items).put("updatedAt", now()).apply {
            listing.maskedPhone?.let { put("maskedPhone", it) }
            listing.phoneManagement?.let { put("phoneManagementUri", it.toString()) }
        })
        persist(updated)
    }

    private fun renew() {
        val previous = account ?: throw Failure("expired")
        val token = previous.optString("refreshToken").takeIf { it.isNotBlank() } ?: throw Failure("expired")
        val reply = send("/oauth/token", mapOf("grant_type" to "refresh_token", "refresh_token" to token, "client_id" to clientId))
        if (reply.body.optString("error") == "invalid_grant" || reply.status == 401) throw Failure("expired")
        updateToken(reply, previous)
    }

    private fun updateToken(reply: Reply, previous: JSONObject?) {
        val body = verified(reply)
        check(body.required("token_type", 16).equals("Bearer", true))
        val token = body.required("access_token", 8192)
        check(token.all { it.code in 33..126 })
        val expires = body.optLong("expires_in").also { check(it in 1..2_592_000) }
        val updated = JSONObject(previous?.toString() ?: "{}")
        updated.put("accessToken", token).put("expiresAt", now() + expires * 1000)
        if (body.has("refresh_token")) updated.put("refreshToken", body.required("refresh_token", 8192))
        persist(updated)
    }

    private fun persist(value: JSONObject) {
        val raw = value.toString()
        check(raw.length <= 3_000_000)
        save(raw)
        account = value
    }

    private fun directory(): Listing {
        val token = account!!.getString("accessToken")
        val merged = linkedMapOf<String, JSONObject>()
        val seen = mutableSetOf<String>()
        var cursor: String? = null
        var maskedPhone: String? = null
        var phoneManagement: URI? = null
        val deadline = now() + 40_000L
        repeat(12) {
            if (now() > deadline) throw Failure("incomplete")
            val path = "/v1/parcels" + (cursor?.let { "?cursor=" + encode(it) } ?: "")
            val page = verified(send(path, bearer = token))
            if (cursor == null) {
                maskedPhone = page.opt("maskedPhone").let { it as? String }
                    ?.takeIf { it.matches(Regex("1[0-9]{2}[*]{4}[0-9]{4}")) }
                phoneManagement = (page.opt("phoneManagementUri") as? String)?.let(::checkedVerificationUri)
            }
            val entries = page.getJSONArray("items")
            check(entries.length() <= 250)
            for (index in 0 until entries.length()) {
                val entry = entries.getJSONObject(index)
                val item = normalize(entry)
                val key = item.getString("carrier") + ":" + item.getString("trackingNumber")
                val existing = merged[key]
                val sources = (existing?.optJSONArray("sources")?.let { a -> (0 until a.length()).map(a::getString) }.orEmpty() +
                    item.getString("source")).distinct().sorted()
                val preferred = if (existing == null || preferred(item, existing)) item else existing
                preferred.put("sources", JSONArray(sources))
                merged[key] = preferred
            }
            if (!page.has("nextCursor") || page.isNull("nextCursor")) {
                val items = merged.values.filter { it.getString("state") == "ready" }
                    .sortedWith(compareByDescending<JSONObject> { it.getLong("updatedAt") }.thenBy { it.getString("trackingNumber") })
                return Listing(JSONArray(items), maskedPhone, phoneManagement)
            }
            val next = page.required("nextCursor", 1024)
            if (!seen.add(next)) throw Failure("incomplete")
            cursor = next
        }
        throw Failure("incomplete")
    }

    private fun send(path: String, form: Map<String, String>? = null, bearer: String? = null): Reply {
        val reply = request(URL(origin.toString() + path), form, bearer)
        if (reply.status == 429 || (reply.status == 503 && reply.retryAfter > 0)) {
            retryAt = now() + reply.retryAfter.coerceIn(30, 3600) * 1000
            throw Failure("rateLimited")
        }
        return reply
    }

    private fun verified(reply: Reply): JSONObject {
        if (reply.status == 401) throw Failure("rejected")
        if (reply.status == 403) throw Failure("forbidden")
        if (reply.status !in 200..299) throw Failure("unavailable")
        return reply.body
    }

    companion object {
        internal fun approvedOrigin(value: String): URI? = runCatching {
            URI(value.trimEnd('/')).takeIf {
                it.scheme == "https" && !it.host.isNullOrBlank() && it.port == -1 && it.userInfo == null &&
                    it.query == null && it.fragment == null && it.rawPath.isEmpty()
            }
        }.getOrNull()

        private fun JSONObject.required(name: String, length: Int): String {
            return (get(name) as? String)?.trim()?.takeIf { it.isNotEmpty() && it.length <= length && it.none(Char::isISOControl) }
                ?: error("Invalid directory field")
        }

        private fun normalize(row: JSONObject): JSONObject {
            val state = row.required("state", 24)
            check(state in setOf("ready", "picked_up", "in_transit", "unknown"))
            val updated = row.get("updatedAt") as? Number ?: error("Invalid timestamp")
            check(updated.toLong() in 1..4_102_444_800_000L && updated.toDouble() == updated.toLong().toDouble())
            val carrier = row.required("carrier", 32).lowercase(Locale.ROOT)
            val tracking = row.required("trackingNumber", 64).uppercase(Locale.ROOT)
            check(carrier.matches(Regex("[a-z0-9_-]+")) && tracking.matches(Regex("[A-Z0-9-]+")))
            val source = row.required("source", 32)
            check(source.matches(Regex("[a-z0-9_-]+")))
            return JSONObject().put("carrier", carrier).put("trackingNumber", tracking)
                .put("state", state).put("source", source).put("updatedAt", updated.toLong()).apply {
                    val arrived = row.opt("arrivedAt") as? Number
                    if (arrived != null && arrived.toLong() in 1..4_102_444_800_000L &&
                        arrived.toDouble() == arrived.toLong().toDouble()) put("arrivedAt", arrived.toLong())
                    for ((name, limit) in listOf("station" to 160, "pickupCode" to 64)) {
                        if (!row.isNull(name)) put(name, row.required(name, limit))
                    }
                }
        }

        private fun preferred(a: JSONObject, b: JSONObject): Boolean {
            val time = a.getLong("updatedAt").compareTo(b.getLong("updatedAt"))
            if (time != 0) return time > 0
            val rank = listOf("unknown", "in_transit", "ready", "picked_up")
            val state = rank.indexOf(a.getString("state")).compareTo(rank.indexOf(b.getString("state")))
            if (state != 0) return state > 0
            if (a.has("pickupCode") != b.has("pickupCode")) return a.has("pickupCode")
            val source = a.getString("source").compareTo(b.getString("source"))
            if (source != 0) return source < 0
            val code = a.optString("pickupCode").compareTo(b.optString("pickupCode"))
            return if (code != 0) code < 0 else a.optString("station") < b.optString("station")
        }

        private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
        private fun https(url: URL, form: Map<String, String>?, token: String?): Reply {
            val conn = url.openConnection() as HttpsURLConnection
            try {
                conn.instanceFollowRedirects = false
                conn.connectTimeout = 7000
                val deadline = android.os.SystemClock.elapsedRealtime() + 12000
                conn.readTimeout = 7000
                conn.setRequestProperty("Accept", "application/json")
                conn.setRequestProperty("Cache-Control", "no-store")
                conn.useCaches = false
                if (token != null) conn.setRequestProperty("Authorization", "Bearer " + token)
                if (form != null) {
                    conn.requestMethod = "POST"
                    conn.doOutput = true
                    conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    conn.outputStream.use { it.write(form.entries.joinToString("&") { (k, v) -> encode(k) + "=" + encode(v) }.toByteArray()) }
                }
                val status = conn.responseCode
                val stream = if (status < HttpURLConnection.HTTP_BAD_REQUEST) conn.inputStream else conn.errorStream
                val bytes = java.io.ByteArrayOutputStream()
                stream?.use {
                    val buffer = ByteArray(8192)
                    while (true) {
                        val size = it.read(buffer)
                        if (size == -1) break
                        check(bytes.size() + size <= 1_048_576 && android.os.SystemClock.elapsedRealtime() < deadline)
                        bytes.write(buffer, 0, size)
                    }
                }
                val body = if (status in 200..299) JSONObject(bytes.toString("UTF-8"))
                    else runCatching { JSONObject(bytes.toString("UTF-8")) }.getOrDefault(JSONObject())
                return Reply(status, body, conn.getHeaderField("Retry-After")?.toLongOrNull() ?: 0)
            } finally { conn.disconnect() }
        }
    }
}

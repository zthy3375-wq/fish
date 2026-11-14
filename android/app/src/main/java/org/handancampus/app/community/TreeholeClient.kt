package org.handancampus.app.community

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

internal interface TreeholeTokenStore { fun read(): String?; fun save(token: String); fun clear() }
internal data class TreeholeResponse(val status: Int, val body: JSONObject)
internal fun interface TreeholeTransport { fun send(action: String, body: JSONObject, token: String?): TreeholeResponse }
internal class TreeholeFailure(val code: String) : Exception(code)

/** A serialized native session. Tokens and server-selected identities never cross the JS bridge. */
internal class TreeholeClient(private val vault: TreeholeTokenStore, private val transport: TreeholeTransport = TreeholeHttp()) {
    companion object {
        val actions = setOf("config", "register", "login", "recover", "me", "logout", "profile.update", "password.change", "account.delete", "posts.list", "posts.get", "posts.create", "posts.delete", "comments.create", "comments.delete", "reactions.set", "reports.create", "blocks.set", "blocks.clear", "admin.reports", "admin.resolve")
        private val auth = setOf("register", "login", "recover")
        private val tokenPattern = Regex("[A-Za-z0-9_-]{43}")
    }
    @Synchronized fun request(action: String, body: JSONObject): JSONObject {
        if (action !in actions) throw TreeholeFailure("invalid_request")
        if (body.toString().toByteArray().size > 20000) throw TreeholeFailure("invalid_request")
        val token = vault.read()?.takeIf { tokenPattern.matches(it) }
        if (action == "logout") {
            // Revoke when reachable, but a network failure must never prevent local sign-out.
            vault.clear()
            if (token != null) runCatching { transport.send(action, JSONObject(), token) }
            return JSONObject()
        }
        if (action !in auth && action != "config" && token == null) throw TreeholeFailure("session_expired")
        val response = transport.send(action, body, if (action in auth) null else token)
        if (response.status !in 200..299) {
            val error = response.body.optString("error", "temporarily_unavailable")
            if (error == "session_expired") vault.clear()
            throw TreeholeFailure(error.take(80))
        }
        val result = response.body
        if (action in auth) {
            val next = result.optString("sessionToken")
            if (!tokenPattern.matches(next) || result.optJSONObject("user") == null) throw TreeholeFailure("invalid_response")
            try { vault.save(next) } catch (_: Exception) {
                runCatching { transport.send("logout", JSONObject(), next) }
                throw TreeholeFailure("secure_storage_failed")
            }
        }
        if (action == "account.delete") vault.clear()
        result.remove("sessionToken"); result.remove("passwordHash"); result.remove("recoveryHash")
        return result
    }
}
internal class TreeholeHttp : TreeholeTransport {
    override fun send(action: String, body: JSONObject, token: String?): TreeholeResponse {
        require(action in TreeholeClient.actions)
        val url = URI("https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/$action").toURL()
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.instanceFollowRedirects = false; conn.connectTimeout = 12000; conn.readTimeout = 25000
            conn.useCaches = false; conn.setRequestProperty("Accept", "application/json")
            if (token != null) conn.setRequestProperty("Authorization", "Bearer $token")
            if (action == "config") conn.requestMethod = "GET" else {
                conn.requestMethod = "POST"; conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                val bytes = body.toString().toByteArray(Charsets.UTF_8); conn.setFixedLengthStreamingMode(bytes.size)
                conn.outputStream.use { it.write(bytes) }
            }
            val status = conn.responseCode
            if (status in 300..399) throw TreeholeFailure("invalid_response")
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val bytes = stream?.use { input ->
                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                while (true) { val count = input.read(buffer); if (count < 0) break; if (output.size() + count > 2_000_000) throw TreeholeFailure("invalid_response"); output.write(buffer, 0, count) }
                output.toByteArray()
            } ?: byteArrayOf()
            if (bytes.size > 2_000_000) throw TreeholeFailure("invalid_response")
            val result = runCatching { JSONObject(String(bytes, Charsets.UTF_8)) }.getOrElse { throw TreeholeFailure("temporarily_unavailable") }
            return TreeholeResponse(status, result)
        } finally { conn.disconnect() }
    }
}

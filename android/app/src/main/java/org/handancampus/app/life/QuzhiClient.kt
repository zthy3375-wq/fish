package org.handancampus.app.life

import org.json.JSONObject
import java.net.URL
import java.net.URLEncoder
import javax.net.ssl.HttpsURLConnection

internal class QuzhiClient {
    /** Fixed same-origin requests. Redirects never carry login/session material elsewhere. */
    fun request(path: String, values: Map<String, String>, post: Boolean = false): Any? {
        if (path !in QuzhiProtocol.paths) throw QuzhiFailure("REQUEST")
        val body = values.entries.joinToString("&") { encode(it.key) + "=" + encode(it.value) }
        val connection = (URL(QuzhiProtocol.BASE + path + if (post) "" else "?$body").openConnection() as HttpsURLConnection)
        try {
            connection.connectTimeout = 12000
            connection.readTimeout = 15000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "HandanCampus/0.8.1 Android")
            if (post) {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            if (status == 401) throw QuzhiFailure("AUTH")
            if (status == 403 || status == 429) throw QuzhiFailure("VERIFY")
            if (status !in 200..299) throw QuzhiFailure("NETWORK")
            val bytes = connection.inputStream.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (out.size() + count > 1024 * 1024) throw QuzhiFailure("FORMAT")
                    out.write(buffer, 0, count)
                }
                out.toByteArray()
            }
            val envelope = try { JSONObject(String(bytes, Charsets.UTF_8).removePrefix("\uFEFF")) }
                catch (_: Exception) { throw QuzhiFailure("FORMAT") }
            return QuzhiProtocol.payload(envelope)
        } finally { connection.disconnect() }
    }
    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
}

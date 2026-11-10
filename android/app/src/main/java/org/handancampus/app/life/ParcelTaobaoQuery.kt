package org.handancampus.app.life

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest

/** Fixed read-only MTOP query. Session supplied by this app's isolated WebView; no credential export. */
object ParcelTaobaoQuery {
    private const val API = "mtop.cainiao.pickup.plus.queryMultiStaPackages4Xy"
    private const val APP_KEY = "12574478"
    const val ORIGIN = "https://h5api.m.taobao.com"
    data class Reply(val bodies: List<String>, val cookies: List<String>)
    fun query(cookies: String, userAgent: String, openConnection: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection }, onPage: (Reply) -> Unit = {}): Reply {
        if (cookies.isBlank()) return Reply(emptyList(), emptyList())
        val token = Regex("(?:^|;\\s*)_m_h5_tk=([^;]+)").find(cookies)?.groupValues?.get(1)?.substringBefore('_') ?: return Reply(emptyList(), emptyList())
        val bodies = mutableListOf<String>(); val rotated = mutableListOf<String>()
        // Pagination is bounded; presentation remains explicitly partial.
        for (page in 1..3) {
            if (Thread.currentThread().isInterrupted) break
            val data = JSONObject().put("stationType", "XY").put("source", "").put("traceId", System.currentTimeMillis().toString())
                .put("pageNo", page).put("pageSize", 30).toString()
            val time = System.currentTimeMillis().toString()
            val sign = MessageDigest.getInstance("MD5").digest("$token&$time&$APP_KEY&$data".toByteArray()).joinToString("") { "%02x".format(it) }
            val url = "$ORIGIN/h5/${API.lowercase()}/1.0/?jsv=2.3.18&appKey=$APP_KEY&t=$time&sign=$sign&type=originaljson&dataType=json&data=${URLEncoder.encode(data, "UTF-8") }"
            val connection = openConnection(URL(url))
            try {
                connection.connectTimeout = 8000; connection.readTimeout = 8000; connection.instanceFollowRedirects = false
                connection.setRequestProperty("Cookie", cookies); connection.setRequestProperty("User-Agent", userAgent)
                connection.setRequestProperty("Origin", "https://h5.m.taobao.com"); connection.setRequestProperty("Referer", "https://h5.m.taobao.com/")
                if (connection.responseCode != 200) break
                val bytes = connection.inputStream.use { input ->
                    val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (out.size() <= 1_500_000 && !Thread.currentThread().isInterrupted) { val n=input.read(buffer); if(n<0)break;out.write(buffer,0,n) }
                    out.toByteArray()
                }
                if (bytes.size > 1_500_000) break
                val body = String(bytes, Charsets.UTF_8)
                val ret = JSONObject(body).optJSONArray("ret")?.toString().orEmpty()
                // Apply only MTOP token cookies to their originating host, after generation validation in the worker.
                connection.headerFields.entries.filter { it.key.equals("Set-Cookie", true) }.flatMap { it.value }.filter {
                    it.startsWith("_m_h5_tk=") || it.startsWith("_m_h5_tk_enc=")
                }.forEach { rotated.add(it) }
                if (!ret.contains("SUCCESS")) { onPage(Reply(emptyList(), rotated.toList())); break }
                bodies.add(body)
                onPage(Reply(listOf(body), rotated.toList()))
                rotated.clear()
            } finally { connection.disconnect() }
        }
        return Reply(bodies, rotated)
    }
}

package org.handancampus.app.life

import org.json.JSONObject
import java.net.URL
import java.net.URLEncoder
import javax.net.ssl.HttpsURLConnection

internal class PangguaiClient {
    fun request(path: String, values: Map<String,String> = emptyMap(), token: String = ""): Any? {
        require(path in PangguaiProtocol.paths)
        val connection = URL("https://userapi.qiekj.com/$path").openConnection() as HttpsURLConnection
        try {
            connection.connectTimeout = 12000; connection.readTimeout = 15000
            connection.instanceFollowRedirects = false; connection.useCaches = false
            connection.requestMethod = "POST"; connection.doOutput = true
            val timestamp = System.currentTimeMillis().toString()
            mapOf("Content-Type" to "application/x-www-form-urlencoded;charset=UTF-8", "Version" to PangguaiProtocol.VERSION,
                "channel" to "android_app", "timestamp" to timestamp, "phoneBrand" to android.os.Build.BRAND,
                "User-Agent" to "HandanCampus/0.8.3 Android").forEach { (k,v) -> connection.setRequestProperty(k,v) }
            if (token.isNotEmpty()) {
                connection.setRequestProperty("token",token); connection.setRequestProperty("Authorization",token)
                connection.setRequestProperty("sign",PangguaiProtocol.signature(path,token,timestamp))
            }
            val form = (values + if (token.isNotEmpty()) mapOf("token" to token) else emptyMap()).entries.joinToString("&") {
                URLEncoder.encode(it.key,"UTF-8")+"="+URLEncoder.encode(it.value,"UTF-8")
            }.toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(form.size)
            connection.outputStream.use { it.write(form) }
            when (connection.responseCode) {
                401 -> throw PangguaiFailure("AUTH")
                403,429 -> throw PangguaiFailure("VERIFY")
                !in 200..299 -> throw PangguaiFailure("NETWORK")
            }
            val bytes = connection.inputStream.use { input ->
                val out=java.io.ByteArrayOutputStream(); val buffer=ByteArray(8192)
                while(true) { val n=input.read(buffer); if(n<0)break; if(out.size()+n>1024*1024)throw PangguaiFailure("FORMAT");out.write(buffer,0,n) };out.toByteArray()
            }
            val envelope = try { JSONObject(String(bytes,Charsets.UTF_8)) } catch (_:Exception) { throw PangguaiFailure("FORMAT") }
            return PangguaiProtocol.payload(envelope)
        } finally { connection.disconnect() }
    }
}

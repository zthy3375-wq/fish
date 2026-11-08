package org.handancampus.app.update

import org.json.JSONObject
import java.net.URI

/** The channel contains release metadata only. No user account or device identifier is sent. */
data class UpdatePolicy(val code: Int, val name: String, val minimum: Int, val minSdk: Int,
    val url: String, val sha256: String, val size: Long, val notes: List<String>) {
    fun available(installed: Int, sdk: Int) = code > installed && sdk >= minSdk
    fun mandatory(installed: Int, sdk: Int) = available(installed, sdk) && installed < minimum
    fun json() = JSONObject().put("schema", 1).put("versionCode", code).put("versionName", name)
        .put("minSupportedVersionCode", minimum).put("minSdk", minSdk).put("apkUrl", url)
        .put("sha256", sha256).put("sizeBytes", size).put("notes", org.json.JSONArray(notes))
    companion object {
        const val ORIGIN = "https://hanyuantong-updates.dewydahlia.chatgpt.site"
        const val CHANNEL = "$ORIGIN/android/stable.json"
        const val MAX_APK_BYTES = 80L * 1024 * 1024
        fun trustedUrl(raw: String): Boolean = try {
            val u = URI(raw); val origin = URI(ORIGIN)
            u.scheme == "https" && u.host == origin.host && (u.port == -1 || u.port == 443) &&
                u.rawUserInfo == null && u.rawFragment == null
        } catch (_: Exception) { false }
        fun parse(raw: String): UpdatePolicy {
            require(raw.toByteArray(Charsets.UTF_8).size <= 64 * 1024)
            val j = JSONObject(raw)
            require(j.getInt("schema") == 1)
            val code = j.getInt("versionCode"); val minimum = j.getInt("minSupportedVersionCode")
            val name = j.getString("versionName"); val sdk = j.getInt("minSdk")
            val url = j.getString("apkUrl"); val hash = j.getString("sha256").lowercase()
            val size = j.getLong("sizeBytes"); val lines = j.getJSONArray("notes")
            require(code in 1..Int.MAX_VALUE && minimum in 1..code && sdk in 23..100)
            require(name.isNotBlank() && name.length <= 40 && trustedUrl(url))
            require(Regex("[a-f0-9]{64}").matches(hash) && size in 1..MAX_APK_BYTES && lines.length() <= 20)
            val notes = (0 until lines.length()).map { lines.getString(it).also { line -> require(line.length <= 500) } }
            return UpdatePolicy(code, name, minimum, sdk, url, hash, size, notes)
        }
    }
}

package org.handancampus.app.life

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only display fields cross out of the official WebView. Account credentials never enter a parcel. */
data class NativeParcel(
    val provider: String, val id: String, val code: String, val station: String,
    val tracking: String = "", val courier: String = "", val title: String = "",
    val state: String = "pending", val syncedAt: Long = 0, val takenAt: Long = 0
) {
    val key get() = "$provider:$id"
    fun json() = JSONObject().put("provider", provider).put("id", id).put("code", code)
        .put("station", station).put("tracking", tracking).put("courier", courier).put("title", title)
        .put("state", state).put("syncedAt", syncedAt).put("takenAt", takenAt)
}
data class NativeParcelBatch(val provider: String, val phase: String, val items: List<NativeParcel>) {
    companion object {
        fun parse(provider: String, raw: String?, now: Long = System.currentTimeMillis()): NativeParcelBatch {
            val invalid = NativeParcelBatch(provider, "unrecognized", emptyList())
            if (provider !in setOf("taobao", "pinduoduo") || raw == null || raw.length > 300_000) return invalid
            return try {
                var value = JSONTokener(raw).nextValue()
                if (value is String) value = JSONTokener(value).nextValue()
                val o = value as JSONObject
                require(o.getInt("version") == 2 && o.getString("provider") == provider)
                val phase = o.getString("phase")
                require(phase in setOf("partial", "empty", "loading", "login", "verify", "unrecognized"))
                val a = o.getJSONArray("items"); require(a.length() <= 300)
                val items = (0 until a.length()).map { i ->
                    val n = a.getJSONObject(i)
                    fun field(key: String, max: Int): String = n.optString(key).also { require(it.length <= max && it.none(Char::isISOControl)) }
                    val code = field("code", 24)
                    require(code.isEmpty() || validCode(code))
                    val id = field("id", 240); require(id.isNotBlank())
                    val state = field("state", 20); require(state in setOf("pending", "transit", "picked"))
                    require(code.isNotEmpty() || field("tracking", 64).isNotEmpty())
                    NativeParcel(provider, id, if (state == "picked") "" else code, field("station", 120), field("tracking", 64), field("courier", 120), field("title", 120), state, now)
                }.distinctBy { it.key }
                require(if (phase == "partial") items.isNotEmpty() else items.isEmpty())
                NativeParcelBatch(provider, phase, items)
            } catch (_: Exception) { invalid }
        }
        fun validCode(code: String) = code.length in 2..24 && code.any(Char::isDigit) &&
            code.matches(Regex("[A-Za-z0-9]+(?:[-—–－\\s][A-Za-z0-9]+)*")) && !code.matches(Regex("\\d{10,}"))
    }
}

/** Merge-only until an authoritative complete snapshot exists; a failed/empty scan never deletes codes. */
class ParcelLedger {
    val items = linkedMapOf<String, NativeParcel>()
    val scopes = mutableMapOf<String, String>()
    val updated = mutableMapOf<String, Long>()
    fun clear(provider: String) { items.entries.removeAll { it.value.provider == provider }; scopes.remove(provider); updated.remove(provider) }
    fun bind(provider: String, scope: String) {
        if (scope.isBlank()) return
        if (scopes[provider] != null && scopes[provider] != scope) clear(provider)
        scopes[provider] = scope
    }
    fun merge(batch: NativeParcelBatch, now: Long = System.currentTimeMillis()) {
        if (batch.phase !in setOf("partial", "empty")) return
        updated[batch.provider] = now
        batch.items.forEach { incoming ->
            val old = items[incoming.key]
            // Reconcile a provisional shelf card only within the same source and station.
            val provisional = if (!incoming.id.startsWith("shelf:") && incoming.code.isNotBlank())
                items.values.filter { it.provider == incoming.provider && it.id.startsWith("shelf:") && it.code == incoming.code && it.station == incoming.station } else emptyList()
            provisional.forEach { items.remove(it.key) }
            val existing = old ?: provisional.singleOrNull()
            items[incoming.key] = incoming.copy(takenAt = existing?.takenAt ?: 0)
        }
        if (items.size > 600) items.values.sortedBy { it.syncedAt }.take(items.size - 600).forEach { items.remove(it.key) }
    }
    fun mark(key: String, taken: Boolean, now: Long = System.currentTimeMillis()) {
        items[key]?.let { items[key] = it.copy(takenAt = if (taken) now else 0) }
    }
    fun json(): JSONObject = JSONObject().put("version", 1).put("items", JSONArray(items.values.map { it.json() }))
        .put("scopes", JSONObject(scopes.toMap())).put("updated", JSONObject(updated.toMap()))
    fun restore(raw: String) {
        val root = JSONObject(raw); require(root.getInt("version") == 1)
        val a = root.getJSONArray("items"); require(a.length() <= 600)
        val restored = linkedMapOf<String, NativeParcel>()
        for (i in 0 until a.length()) {
            val o = a.getJSONObject(i); val provider = o.getString("provider")
            val wrapped = JSONObject().put("version", 2).put("provider", provider).put("phase", "partial").put("items", JSONArray().put(o))
            val p = NativeParcelBatch.parse(provider, wrapped.toString(), o.getLong("syncedAt")).items.singleOrNull() ?: continue
            restored[p.key] = p.copy(takenAt = o.optLong("takenAt"))
        }
        items.clear(); items.putAll(restored)
        for (p in listOf("taobao", "pinduoduo")) {
            root.optJSONObject("scopes")?.optString(p)?.takeIf { it.isNotBlank() }?.let { scopes[p] = it }
            root.optJSONObject("updated")?.optLong(p)?.takeIf { it > 0 }?.let { updated[p] = it }
        }
    }
}

/** Authenticated encryption, atomic writes and noBackupFilesDir; never included in app exports or analytics. */
class ParcelStore(context: Context) {
    val ledger = ParcelLedger()
    private val file = AtomicFile(File(context.noBackupFilesDir, "parcel-cards-v1.bin"))
    var storageAvailable = true
        private set
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val name = "hyt.parcel.cache.v1"
        (ks.getKey(name, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(name, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    init {
        if (file.baseFile.exists()) try {
            val bytes = file.readFully(); require(bytes.size in 29..1_000_000)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            ledger.restore(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        } catch (_: Exception) { file.delete(); storageAvailable = false }
    }
    fun save() {
        var stream: java.io.FileOutputStream? = null
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
            val encrypted = cipher.doFinal(ledger.json().toString().toByteArray(Charsets.UTF_8))
            stream = file.startWrite(); stream.write(cipher.iv); stream.write(encrypted); file.finishWrite(stream)
            storageAvailable = true
        } catch (_: Exception) { stream?.let { file.failWrite(it) }; storageAvailable = false }
    }
    fun clear(provider: String) { ledger.clear(provider); file.delete(); save() }
}

package org.handancampus.app.community

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.academic.SchoolSessionVault
import java.util.concurrent.Executors

@CapacitorPlugin(name = "Treehole")
class TreeholePlugin : Plugin() {
    private val executor = Executors.newSingleThreadExecutor()
    private val vault by lazy { SchoolSessionVault(context, "hyt_community_session_v1", "hyt.community.session.v1", 128) }
    private val hallVault by lazy { SchoolSessionVault(context, "hyt_collection_hall", "hyt.collection.cache") }
    private val client by lazy {
        TreeholeClient(object : TreeholeTokenStore {
            override fun read() = vault.restore()
            override fun save(token: String) { hallVault.clear(); vault.save(token) }
            override fun clear() { vault.clear(); hallVault.clear() }
        })
    }
    @PluginMethod fun request(call: PluginCall) {
        val action = call.getString("action") ?: ""
        val body = call.getObject("body") ?: JSObject()
        executor.execute {
            try {
                val result = client.request(action, body)
                // Only the server's private hall includes progress. Public profile reads never enter this cache.
                val hall = result.optJSONObject("hall")
                if (hall?.has("progress") == true) {
                    runCatching {
                        val cached = hallVault.restore()?.let { JSObject(it) } ?: JSObject()
                        val snapshot = if (cachedOwner(cached) == hall.optString("id")) cached else JSObject()
                        snapshot.remove("dirty")
                        hallVault.save(snapshot.put("hall", hall).put("cachedAt", System.currentTimeMillis()).toString())
                    }
                } else if (action in setOf("posts.create","comments.create","posts.delete","comments.delete","reactions.set","honors.change","collection.wear","collection.visibility","collection.showcase","collection.change") || (result.optJSONArray("unlocks")?.length() ?: 0) > 0) {
                    runCatching { hallVault.restore()?.let { hallVault.save(JSObject(it).put("dirty", true).toString()) } }
                }
                // Reuse authenticated self projections for the offline personal exhibit.
                // Token replacement and logout clear this vault before another account can read it.
                if (action in setOf("me", "login", "register", "recover", "profile.update") && result.has("user")) {
                    runCatching {
                        val user = result.getJSONObject("user")
                        val id = user.getString("id")
                        val owner = JSObject().put("id", id)
                            .put("badges", user.optJSONObject("badges") ?: JSObject())
                            .put("showcase", user.optJSONArray("showcase") ?: org.json.JSONArray())
                        val cached = hallVault.restore()?.let { JSObject(it) } ?: JSObject()
                        val oldOwner = cachedOwner(cached)
                        val snapshot = if (oldOwner == null || oldOwner == id) cached else JSObject()
                        if (snapshot.optJSONObject("owner")?.toString() != owner.toString()) {
                            hallVault.save(snapshot.put("owner", owner).toString())
                        }
                    }
                }
                if (action == "collection.profile" && body.optInt("offset") == 0) {
                    runCatching {
                        val collection = result.getJSONObject("collection")
                        val cached = hallVault.restore()?.let { JSObject(it) } ?: JSObject()
                        val id = collection.getString("id")
                        val owner = cachedOwner(cached)
                        if (body.optString("memberId").isBlank() || id == owner) {
                            val snapshot = if (owner == null || owner == id) cached else JSObject()
                            hallVault.save(snapshot.put("collection", collection).toString())
                        }
                    }
                }
                if (action == "collection.showcase") {
                    runCatching {
                        val update = result.getJSONObject("updatedIdentity")
                        val cached = hallVault.restore()?.let { JSObject(it) } ?: JSObject()
                        val collection = cached.optJSONObject("collection")
                        if (collection != null && collection.optString("id") == update.optString("id")) {
                            collection.put("showcase", update.getJSONArray("showcase"))
                            hallVault.save(cached.toString())
                        }
                    }
                }
                call.resolve(JSObject(result.toString()))
            }
            catch (e: TreeholeFailure) { call.reject(e.code, e.code) }
            catch (_: Exception) { call.reject("network_unavailable", "network_unavailable") }
        }
    }
    private fun cachedOwner(snapshot: JSObject): String? =
        (snapshot.optJSONObject("owner") ?: snapshot.optJSONObject("hall")
            ?: snapshot.optJSONObject("collection"))?.optString("id")?.takeIf { it.isNotBlank() }
    @PluginMethod fun cachedHall(call: PluginCall) {
        executor.execute {
            val signedIn = vault.restore() != null
            val result = if (signedIn) hallVault.restore()?.let { JSObject(it) } ?: JSObject() else JSObject()
            call.resolve(result.put("signedIn", signedIn))
        }
    }
    private fun journal(scope: String): SchoolSessionVault {
        require(scope == "device" || scope.matches(Regex("(school|learning)-[A-Za-z0-9_-]{8,96}")))
        return SchoolSessionVault(context, "hyt_collection_$scope", "hyt.collection.journal.$scope")
    }
    @PluginMethod fun journalRead(call: PluginCall) {
        executor.execute {
            try { call.resolve(JSObject().put("value", journal(call.getString("scope") ?: "").restore())) }
            catch (_: Exception) { call.reject("journal_unavailable") }
        }
    }
    @PluginMethod fun journalWrite(call: PluginCall) {
        executor.execute {
            try {
                val value = call.getString("value") ?: error("missing_value")
                require(value.length in 2..16000)
                journal(call.getString("scope") ?: "").save(value)
                call.resolve()
            } catch (_: Exception) { call.reject("journal_unavailable") }
        }
    }
    override fun handleOnDestroy() { executor.shutdown(); super.handleOnDestroy() }
}

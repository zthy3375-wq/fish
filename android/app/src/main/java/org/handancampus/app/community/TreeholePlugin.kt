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
    private val client by lazy {
        val vault = SchoolSessionVault(context, "hyt_community_session_v1", "hyt.community.session.v1", 128)
        TreeholeClient(object : TreeholeTokenStore {
            override fun read() = vault.restore()
            override fun save(token: String) = vault.save(token)
            override fun clear() = vault.clear()
        })
    }
    @PluginMethod fun request(call: PluginCall) {
        val action = call.getString("action") ?: ""
        val body = call.getObject("body") ?: JSObject()
        executor.execute {
            try { call.resolve(JSObject(client.request(action, body).toString())) }
            catch (e: TreeholeFailure) { call.reject(e.code, e.code) }
            catch (_: Exception) { call.reject("network_unavailable", "network_unavailable") }
        }
    }
    override fun handleOnDestroy() { executor.shutdown(); super.handleOnDestroy() }
}

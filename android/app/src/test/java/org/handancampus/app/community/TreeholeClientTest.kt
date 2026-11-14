package org.handancampus.app.community

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TreeholeClientTest {
    private class Vault : TreeholeTokenStore {
        var token: String? = null
        override fun read() = token
        override fun save(token: String) { this.token = token }
        override fun clear() { token = null }
    }
    @Test fun loginStoresOnlyNativeTokenAndStripsItFromBridge() {
        val vault = Vault(); val token = "t".repeat(43)
        val client = TreeholeClient(vault) { action, body, sent ->
            assertEquals("login", action); assertNull(sent); assertEquals("app_account", body.getString("username"))
            TreeholeResponse(200, JSONObject().put("sessionToken", token).put("user", JSONObject().put("nickname", "邯院同学")))
        }
        val result = client.request("login", JSONObject().put("username", "app_account"))
        assertEquals(token, vault.token); assertFalse(result.has("sessionToken")); assertTrue(result.has("user"))
    }
    @Test fun authenticatedRequestsUseVaultAndExpiredSessionsClearIt() {
        val vault = Vault().apply { token = "a".repeat(43) }
        val client = TreeholeClient(vault) { _, _, token ->
            assertEquals(vault.token, token)
            TreeholeResponse(401, JSONObject().put("error", "session_expired"))
        }
        try { client.request("posts.list", JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("session_expired", e.code) }
        assertNull(vault.token)
    }
    @Test fun logoutClearsLocallyEvenWhenOfflineAndCannotRestoreLateSession() {
        val vault = Vault().apply { token = "a".repeat(43) }
        val client = TreeholeClient(vault) { action, _, sent ->
            assertEquals("logout", action); assertNull(vault.token); assertNotNull(sent)
            throw java.io.IOException("offline")
        }
        client.request("logout", JSONObject()); assertNull(vault.token)
        try { client.request("me", JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("session_expired", e.code) }
    }
    @Test fun arbitraryActionsNeverReachNetwork() {
        val vault = Vault(); val client = TreeholeClient(vault) { _, _, _ -> fail("Must not send"); error("unreachable") }
        for (action in listOf("https://evil.invalid", "../credentials", "credentials", "session", "rate")) {
            try { client.request(action, JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("invalid_request", e.code) }
        }
    }
    @Test fun malformedAuthenticationDoesNotOverwriteExistingAccount() {
        val vault = Vault().apply { token = "a".repeat(43) }
        val client = TreeholeClient(vault) { _, _, _ -> TreeholeResponse(200, JSONObject().put("sessionToken", "bad")) }
        try { client.request("login", JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("invalid_response", e.code) }
        assertEquals("a".repeat(43), vault.token)
    }
}

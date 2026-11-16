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
    @Test fun imageUploadsHaveBoundedLargerPayloadWithoutRelaxingOtherActions() {
        val vault = Vault().apply { token = "a".repeat(43) }; var sent = 0
        val client = TreeholeClient(vault) { _, _, token -> assertEquals(vault.token, token); sent++; TreeholeResponse(200, JSONObject()) }
        val image = JSONObject().put("data", "a".repeat(1_600_000))
        client.request("media.upload", image); assertEquals(1, sent)
        for (action in listOf("posts.create", "comments.create", "media.upload")) {
            val body = if (action == "media.upload") JSONObject().put("data", "a".repeat(1_650_001)) else image
            try { client.request(action, body); fail() } catch (e: TreeholeFailure) { assertEquals("invalid_request", e.code) }
        }
        assertEquals(1, sent)
        for (action in listOf("media.url", "media.discard", "comments.replies", "comments.like")) client.request(action, JSONObject())
        assertEquals(5, sent)
    }

    @Test fun participationActionsKeepAuthenticationAndPrivateMediaOperationsBlocked() {
        val vault = Vault().apply { token = "a".repeat(43) }; val sent = mutableListOf<String>()
        val client = TreeholeClient(vault) { action, body, token ->
            assertEquals(vault.token, token); sent.add(action)
            if (action == "responses.set") assertTrue(body.isNull("kind"))
            TreeholeResponse(200, JSONObject().put("sessionToken", "must-not-cross").put("user", JSONObject()))
        }
        for (action in listOf("avatar.set", "responses.set")) assertFalse(client.request(action, JSONObject().put("kind", JSONObject.NULL)).has("sessionToken"))
        for (action in listOf("media.reserve", "media.commit", "media.cleanup", "media.purge")) {
            try { client.request(action, JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("invalid_request", e.code) }
        }
        assertEquals(2, sent.size)
    }

    @Test fun followActionsRequireNativeSessionAndNeverReturnSessionMaterial() {
        val vault = Vault(); var sent = 0
        val client = TreeholeClient(vault) { action, body, token ->
            assertEquals(vault.token, token); assertTrue(action in setOf("follows.set", "follows.list")); sent++
            if (action == "follows.set") assertEquals(false, body.getBoolean("enabled"))
            TreeholeResponse(200, JSONObject().put("sessionToken", "private").put("following", org.json.JSONArray()))
        }
        try { client.request("follows.list", JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("session_expired", e.code) }
        assertEquals(0, sent); vault.token = "a".repeat(43)
        assertFalse(client.request("follows.set", JSONObject().put("memberId", "public-id").put("enabled", false)).has("sessionToken"))
        assertFalse(client.request("follows.list", JSONObject()).has("sessionToken")); assertEquals(2, sent)
    }

    @Test fun pollVotingKeepsNativeAuthenticationAndNullCancellation() {
        val vault = Vault(); var sent = 0
        val client = TreeholeClient(vault) { action, body, token ->
            assertEquals("polls.vote", action); assertEquals(vault.token, token); sent++
            assertTrue(body.isNull("optionId"))
            TreeholeResponse(200, JSONObject().put("sessionToken", "private"))
        }
        try { client.request("polls.vote", JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("session_expired", e.code) }
        assertEquals(0, sent); vault.token = "a".repeat(43)
        assertFalse(client.request("polls.vote", JSONObject().put("postId", "post").put("optionId", JSONObject.NULL)).has("sessionToken")); assertEquals(1, sent)
    }

    @Test fun buddyActionsPreserveExplicitStateAndRequireNativeSession() {
        val vault = Vault(); var sent = 0
        val client = TreeholeClient(vault) { action, body, token ->
            assertEquals(vault.token, token); sent++
            if (action == "buddies.join") assertEquals(false, body.getBoolean("enabled"))
            if (action == "buddies.close") assertEquals(false, body.getBoolean("closed"))
            TreeholeResponse(200, JSONObject().put("sessionToken", "private"))
        }
        for (action in listOf("buddies.join", "buddies.close", "buddies.members")) {
            try { client.request(action, JSONObject()); fail() } catch (e: TreeholeFailure) { assertEquals("session_expired", e.code) }
        }
        assertEquals(0, sent); vault.token = "a".repeat(43)
        for (action in listOf("buddies.join", "buddies.close", "buddies.members")) {
            assertFalse(client.request(action, JSONObject().put("postId", "post").put("enabled", false).put("closed", false)).has("sessionToken"))
        }
        assertEquals(3, sent)
    }

}

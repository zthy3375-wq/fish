package org.handancampus.app.life

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ParcelDirectoryTest {
    private val origin = ParcelDirectory.approvedOrigin("https://example.test")!!
    private val responses = ArrayDeque<ParcelDirectory.Reply>()
    private val paths = mutableListOf<String>()
    private val bearers = mutableListOf<String?>()
    private var stored: String? = null
    private var time = 1_800_000_000_000L

    private fun client() = ParcelDirectory(origin, "android-test", { stored }, { stored = it }, { stored = null },
        { url, _, bearer ->
            paths += url.file
            bearers += bearer
            responses.removeFirst()
        }, { time })

    private fun reply(body: String, status: Int = 200, retryAfter: Long = 0) {
        responses.add(ParcelDirectory.Reply(status, JSONObject(body), retryAfter))
    }

    private fun begin(engine: ParcelDirectory) {
        reply("""{"device_code":"synthetic-device","user_code":"ABCD","verification_uri":"https://example.test/verify","expires_in":120}""")
        assertEquals("pending", engine.begin().getString("state"))
    }

    private fun token(expires: Int = 3600, value: String = "synthetic-access") =
        reply("""{"token_type":"Bearer","access_token":"$value","refresh_token":"synthetic-refresh","expires_in":$expires}""")

    @Test fun paginatedDirectoryDeduplicatesRemovesPickedUpAndPersistsOnRelaunch() {
        val engine = client()
        begin(engine)
        assertFalse(engine.state().toString().contains("synthetic-device"))
        engine.poll()
        assertEquals(listOf("/oauth/device/code"), paths)
        time += 5100
        token()
        reply("""{"items":[
          {"source":"taobao","carrier":"  SF ","trackingNumber":" sf123 ","state":"ready","updatedAt":1000,"pickupCode":"001-2"},
          {"source":"taobao","carrier":"sf","trackingNumber":"SF456","state":"ready","updatedAt":1000,"pickupCode":"old"}],
          "nextCursor":"page +2"}""")
        reply("""{"items":[
          {"source":"cainiao","carrier":"sf","trackingNumber":"SF123","state":"ready","updatedAt":1000},
          {"source":"cainiao","carrier":"sf","trackingNumber":"SF456","state":"picked_up","updatedAt":1000},
          {"source":"pinduoduo","carrier":"yto","trackingNumber":"YT789","state":"ready","updatedAt":1001,"pickupCode":"008"}]}""")
        val result = engine.poll()
        val rows = result.getJSONArray("items")
        assertEquals(2, rows.length())
        assertEquals("008", rows.getJSONObject(0).getString("pickupCode"))
        assertEquals("001-2", rows.getJSONObject(1).getString("pickupCode"))
        assertEquals("""["cainiao","taobao"]""", rows.getJSONObject(1).getJSONArray("sources").toString())
        assertFalse(result.toString().contains("synthetic-access"))
        assertEquals("/v1/parcels?cursor=page+%2B2", paths.last())
        assertEquals(listOf(null, null, "synthetic-access", "synthetic-access"), bearers)
        assertEquals("ready", client().refresh(false).getString("state"))
        assertEquals(4, paths.size)
        time += 301_000
        reply("""{"items":[]}""")
        assertEquals("empty", client().refresh(false).getString("state"))
    }

    @Test fun partialSyncPreservesSnapshotAndExpiredAuthorizationIsDistinct() {
        val engine = client()
        begin(engine)
        time += 5100
        token(expires = 60)
        reply("""{"items":[{"source":"cainiao","carrier":"sf","trackingNumber":"SF123","state":"ready","updatedAt":1000,"pickupCode":"001"}]}""")
        val previous = engine.poll().getJSONArray("items").toString()
        time += 11_000
        reply("""{"items":[],"nextCursor":"same"}""")
        reply("""{"items":[],"nextCursor":"same"}""")
        val incomplete = engine.refresh(true)
        assertEquals("incomplete", incomplete.getString("state"))
        assertEquals(previous, incomplete.getJSONArray("items").toString())
        time += 60_000
        reply("""{"error":"invalid_grant"}""", 400)
        assertEquals("expired", engine.refresh(false).getString("state"))
        assertEquals("disconnected", engine.disconnect().getString("state"))
        assertNull(stored)
    }

    @Test fun respectsProviderSlowDownAndRetryAfter() {
        val engine = client()
        begin(engine)
        time += 5_000
        reply("""{"error":"slow_down"}""", 400)
        assertEquals("pending", engine.poll().getString("state"))
        time += 9_999
        engine.poll()
        assertEquals(2, paths.size)
        time += 1
        reply("{}", 429, 45)
        assertEquals("rateLimited", engine.poll().getString("state"))
        time += 44_999
        engine.poll()
        assertEquals(3, paths.size)
        time += 1
        reply("""{"error":"access_denied"}""", 400)
        assertEquals("denied", engine.poll().getString("state"))
    }

    @Test fun refusesUntrustedVerificationOrigin() {
        assertNull(ParcelDirectory.approvedOrigin("https://example.test/elsewhere"))
        assertNull(ParcelDirectory.approvedOrigin("https://user@example.test"))
        assertNull(ParcelDirectory.approvedOrigin("http://example.test"))
        val engine = client()
        reply("""{"device_code":"synthetic","user_code":"ABCD","verification_uri":"https://other.example.test/verify","expires_in":120}""")
        assertEquals("unavailable", engine.begin().getString("state"))
        assertNull(engine.verificationUri())
    }
}

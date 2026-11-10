package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ParcelReadResultTest {
    private fun payload(provider: String = "taobao", phase: String = "partial", code: String = "01-002-003") = JSONObject()
        .put("version", 1).put("provider", provider).put("phase", phase)
        .put("items", JSONArray().put(JSONObject().put("station", "测试驿站").put("code", code))).toString()

    @Test fun acceptsBothWebViewResultEncodingsAndKeepsLeadingZeroes() {
        val raw = payload()
        assertEquals("01-002-003", ParcelReadResult.parse("taobao", raw).items.single().code)
        assertEquals("01-002-003", ParcelReadResult.parse("taobao", JSONObject.quote(raw)).items.single().code)
    }
    @Test fun rejectsMismatchedProviderInvalidCodesAndContradictoryEmptyStates() {
        listOf(payload("pinduoduo"), payload(phase = "empty"), payload(code = "13800138000"),
            payload(code = "<img>"), payload(code = "A\nB2"), "null", "private data", "x".repeat(40_001)).forEach {
            assertEquals(ParcelReadResult("unrecognized", emptyList()), ParcelReadResult.parse("taobao", it))
        }
    }
    @Test fun aLoginResultNeverRetainsOldItems() {
        val raw = JSONObject().put("version", 1).put("provider", "taobao").put("phase", "login").put("items", JSONArray()).toString()
        assertEquals(ParcelReadResult("login", emptyList()), ParcelReadResult.parse("taobao", raw))
        assertEquals("unrecognized", ParcelReadResult.parse("taobao", payload(phase = "login")).phase)
    }
    @Test fun backgroundAndAccountChangesDiscardLateResponsesInsteadOfRestoringCodes() {
        val session = ParcelReadSession()
        val ticket = session.generation
        assertTrue(session.accept("taobao", ticket, payload()))
        session.clear()
        assertFalse(session.accept("taobao", ticket, payload()))
        assertTrue(session.snapshots.isEmpty())
        assertTrue(session.accept("taobao", session.generation, payload()))
        val another = session.generation
        session.invalidate("taobao")
        assertFalse(session.accept("taobao", another, payload()))
        assertTrue(session.snapshots.isEmpty())
    }
    @Test fun failedOrLoginReadReplacesCodesAndDoesNotClearTheOtherPlatform() {
        val session = ParcelReadSession()
        session.accept("taobao", session.generation, payload())
        session.accept("pinduoduo", session.generation, payload("pinduoduo"))
        session.accept("taobao", session.generation, "null")
        assertTrue(session.snapshots.getValue("taobao").items.isEmpty())
        assertEquals(1, session.snapshots.getValue("pinduoduo").items.size)
    }
}

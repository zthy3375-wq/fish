package org.handancampus.app.update
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class UpdatePolicyTest {
    private fun manifest() = JSONObject().put("schema",1).put("versionCode",102).put("versionName","1.0.2")
        .put("minSupportedVersionCode",101).put("minSdk",23).put("apkUrl",UpdatePolicy.ORIGIN+"/android/app-102.apk")
        .put("sha256","a".repeat(64)).put("sizeBytes",12000000).put("notes",org.json.JSONArray().put("修复问题"))
    private fun rejected(j:JSONObject) { try { UpdatePolicy.parse(j.toString()); fail("must reject malformed release") } catch (_:IllegalArgumentException) {} }
    @Test fun versionAndMinimumAreIndependent() { val p=UpdatePolicy.parse(manifest().toString());assertTrue(p.available(101,35));assertFalse(p.mandatory(101,35));assertTrue(p.mandatory(100,35));assertFalse(p.available(102,35));assertFalse(p.available(103,35)) }
    @Test fun unsupportedAndroidIsNeverLocked() { val p=UpdatePolicy.parse(manifest().put("minSdk",30).toString());assertFalse(p.available(100,29));assertFalse(p.mandatory(100,29)) }
    @Test fun malformedPolicyCannotLockUsers() { rejected(manifest().put("minSupportedVersionCode",103));rejected(manifest().put("versionCode",0));rejected(manifest().put("sha256","x".repeat(64)));rejected(manifest().put("sizeBytes",0));rejected(manifest().put("sizeBytes",UpdatePolicy.MAX_APK_BYTES+1)) }
    @Test fun rejectsUntrustedDownloadTargets() { for(url in listOf("http://hanyuantong-updates.dewydahlia.chatgpt.site/a.apk","https://evil.example/a.apk",UpdatePolicy.ORIGIN+":444/a.apk","https://evil@hanyuantong-updates.dewydahlia.chatgpt.site/a.apk",UpdatePolicy.ORIGIN+"/a.apk#x")) rejected(manifest().put("apkUrl",url)) }
    @Test fun cachedPolicyRoundTripsWithoutChangingRequirement() {val p=UpdatePolicy.parse(manifest().toString());assertEquals(p,UpdatePolicy.parse(p.json().toString()))}
    @Test fun operatorCanWithdrawMandatoryRequirement() {val p=UpdatePolicy.parse(manifest().put("minSupportedVersionCode",100).toString());assertFalse(p.mandatory(100,35));assertTrue(p.available(100,35))}
    @Test fun boundsReleaseNotes() {rejected(manifest().put("notes",org.json.JSONArray().put("a".repeat(501))))}
}

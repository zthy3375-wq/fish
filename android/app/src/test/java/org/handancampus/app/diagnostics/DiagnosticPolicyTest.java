package org.handancampus.app.diagnostics;
import org.junit.Test;
import org.handancampus.app.BuildConfig;
import static org.junit.Assert.*;
public class DiagnosticPolicyTest {
    @Test public void actualBuildFlagsMatchTheVariant() {
        assertEquals("diagnostic".equals(BuildConfig.BUILD_TYPE), BuildConfig.ACADEMIC_DIAGNOSTICS);
        assertEquals("diagnostic".equals(BuildConfig.BUILD_TYPE),
            DiagnosticPolicy.enabled(BuildConfig.DEBUG, BuildConfig.ACADEMIC_DIAGNOSTICS));
    }
    @Test public void bothBuildGatesAreRequired() {
        assertTrue(DiagnosticPolicy.enabled(true, true));
        assertFalse(DiagnosticPolicy.enabled(true, false));
        assertFalse(DiagnosticPolicy.enabled(false, true));
        assertFalse(DiagnosticPolicy.enabled(false, false));
    }
    @Test public void onlyExactHttpsOfficialLaunchIsAllowed() {
        assertTrue(DiagnosticPolicy.allowedLaunch(DiagnosticPolicy.OFFICIAL_LOGIN));
        String[] rejected = {null, "", "http://jwgl.hdc.edu.cn/xtgl/login_slogin.html",
          "https://jwgl.hdc.edu.cn.evil.invalid/xtgl/login_slogin.html",
          "https://jwgl.hdc.edu.cn@evil.invalid/xtgl/login_slogin.html",
          "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html?token=secret",
          "https://jwgl.hdc.edu.cn:443/xtgl/login_slogin.html", "javascript:alert(1)",
          "intent://jwgl.hdc.edu.cn/", "https://idp.hdc.edu.cn/", "https://jwgl.hdc.edu.cn/other"};
        for (String url : rejected) assertFalse(DiagnosticPolicy.allowedLaunch(url));
    }
    @Test public void limitedWebviewAllowsOnlyVerifiedSchoolHttpsOrigin() {
        assertTrue(DiagnosticPolicy.allowedSchoolUrl("https://jwgl.hdc.edu.cn/kbcx/test?term=1"));
        assertTrue(DiagnosticPolicy.allowedSchoolUrl("https://jwgl.hdc.edu.cn:443/test"));
        String[] rejected={"http://jwgl.hdc.edu.cn/", "https://jwgl.hdc.edu.cn.evil.invalid/", "https://jwgl.hdc.edu.cn@evil.invalid/", "https://evil@jwgl.hdc.edu.cn/", "https://jwgl.hdc.edu.cn:444/", "file:///etc/passwd", "javascript:alert(1)", "https://idp.hdc.edu.cn/"};
        for(String url:rejected) assertFalse(DiagnosticPolicy.allowedSchoolUrl(url));
        assertFalse(DiagnosticPolicy.readableCourseCandidate(DiagnosticPolicy.OFFICIAL_LOGIN));
        assertTrue(DiagnosticPolicy.readableCourseCandidate("https://jwgl.hdc.edu.cn/kbcx/test"));
    }
    @Test public void permissionCannotBeSelfGrantedByUserCheckboxOrBrowserLogin() {
        assertFalse(DiagnosticPolicy.mayReadSchoolPage());
    }
}

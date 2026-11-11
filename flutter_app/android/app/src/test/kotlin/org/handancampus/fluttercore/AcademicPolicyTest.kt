package org.handancampus.fluttercore

import org.junit.Assert.*
import org.junit.Test

class AcademicPolicyTest {
    @Test fun onlyExactSchoolHttpsOriginIsAllowed() {
        assertTrue(AcademicPolicy.allowed("https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html"))
        assertTrue(AcademicPolicy.allowed("https://jwgl.hdc.edu.cn:443/kbcx/xskbcx_cxXsgrkb.html"))
        for (url in listOf(null, "http://jwgl.hdc.edu.cn/", "https://jwgl.hdc.edu.cn:444/",
                "https://jwgl.hdc.edu.cn.evil.example/", "https://evil.example/",
                "https://user@jwgl.hdc.edu.cn/", "https://evil@jwgl.hdc.edu.cn/",
                "file:///etc/passwd", "javascript:alert(1)", "https://sub.jwgl.hdc.edu.cn/")) {
            assertFalse("Unsafe school origin accepted", AcademicPolicy.allowed(url))
        }
    }
    @Test fun loginRouteIsNotTreatedAsAuthenticatedHome() {
        assertTrue(AcademicPolicy.loginPage(AcademicPolicy.LOGIN))
        assertTrue(AcademicPolicy.loginPage("https://jwgl.hdc.edu.cn/cas/login"))
        assertTrue(AcademicPolicy.loginPage("https://jwgl.hdc.edu.cn/auth/login"))
        assertTrue(AcademicPolicy.loginPage("https://evil.example/"))
        assertFalse(AcademicPolicy.loginPage(AcademicPolicy.HOME))
    }
}

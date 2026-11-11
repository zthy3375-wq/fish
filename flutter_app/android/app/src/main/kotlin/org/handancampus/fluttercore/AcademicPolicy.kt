package org.handancampus.fluttercore

object AcademicPolicy {
    const val ORIGIN = "https://jwgl.hdc.edu.cn"
    const val LOGIN = "$ORIGIN/xtgl/login_slogin.html"
    const val HOME = "$ORIGIN/xtgl/index_initMenu.html"
    fun allowed(url: String?): Boolean = try {
        val u = java.net.URI(url ?: "")
        u.scheme == "https" && u.host == "jwgl.hdc.edu.cn" && u.userInfo == null && (u.port == -1 || u.port == 443)
    } catch (_: Exception) { false }
    fun loginPage(url: String?): Boolean = !allowed(url) || java.net.URI(url).path.let {
        it.contains("/xtgl/login") || it.contains("/cas/") || it.contains("/auth/")
    }
}

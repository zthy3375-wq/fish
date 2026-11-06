package org.handancampus.app.diagnostics;

/** Fixed external handoff only. No caller-provided URL, SSO discovery, cookies or WebView. */
public final class DiagnosticPolicy {
    public static final String OFFICIAL_LOGIN = "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html";
    private DiagnosticPolicy() {}
    public static boolean enabled(boolean debug, boolean diagnosticBuild) {
        return debug && diagnosticBuild;
    }
    public static boolean allowedLaunch(String url) {
        return OFFICIAL_LOGIN.equals(url);
    }
    public static boolean allowedSchoolUrl(String url) {
        try {
            java.net.URI uri = new java.net.URI(url);
            return "https".equalsIgnoreCase(uri.getScheme()) && "jwgl.hdc.edu.cn".equalsIgnoreCase(uri.getHost())
                && uri.getUserInfo() == null && (uri.getPort() == -1 || uri.getPort() == 443);
        } catch (Exception e) { return false; }
    }
    public static boolean readableCourseCandidate(String url) {
        if (!allowedSchoolUrl(url)) return false;
        String path = java.net.URI.create(url).getPath().toLowerCase(java.util.Locale.ROOT);
        return !path.contains("/xtgl/login") && !path.contains("/cas/") && !path.contains("/auth/");
    }
    public static boolean mayReadSchoolPage() {
        // No school permission or external-browser DOM channel has been verified.
        return false;
    }
}

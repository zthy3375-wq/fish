import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {openPangguaiOfficial, pangguaiLaunchMessage, pangguaiOfficialSupported, type PangguaiPage} from '../src/services/pangguai-official';

const bridge = vi.hoisted(() => ({open: vi.fn(), platform: 'android', available: true}));
vi.mock('@capacitor/core', () => ({
  Capacitor: {getPlatform: () => bridge.platform, isPluginAvailable: () => bridge.available},
  registerPlugin: () => ({open: bridge.open}),
}));
beforeEach(() => { bridge.open.mockReset(); bridge.platform = 'android'; bridge.available = true });

describe('official Pangguai page bridge', () => {
  it.each(['wallet', 'operators', 'login'] as const)('passes only the fixed %s enum, never account or redirect parameters', async page => {
    bridge.open.mockResolvedValue({page, status: 'opened'});
    expect(await openPangguaiOfficial(page)).toEqual({page, status: 'opened'});
    expect(bridge.open).toHaveBeenCalledExactlyOnceWith({page});
  });
  it.each(['web', 'ios'])('does not navigate from %s previews', async platform => {
    bridge.platform = platform;
    expect(pangguaiOfficialSupported()).toBe(false);
    expect(await openPangguaiOfficial('wallet')).toEqual({page: 'wallet', status: 'unsupported'});
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it('handles an Android build missing the plugin', async () => {
    bridge.available = false;
    expect((await openPangguaiOfficial('operators')).status).toBe('unsupported');
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it.each(['', 'WALLET', 'wallet ', 'https://h5.qiekj.com/login', 'alipays://platformapi/startapp', 'account'])('rejects non-contract page %s', async raw => {
    await expect(openPangguaiOfficial(raw as PangguaiPage)).rejects.toThrow('INVALID_PAGE');
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it.each(['unavailable', 'cancelled'] as const)('preserves %s without inventing authentication state', async status => {
    bridge.open.mockResolvedValue({page: 'wallet', status});
    expect(await openPangguaiOfficial('wallet')).toEqual({page: 'wallet', status});
  });
  it.each([null, {}, {page: 'login', status: 'opened'}, {page: 'wallet', status: 'authenticated'}, {page: 'wallet', status: 'paid'}, {page: 'wallet', status: {toString: (): string => 'opened'}}])('rejects a malformed or mismatched native result', async result => {
    bridge.open.mockResolvedValue(result);
    expect((await openPangguaiOfficial('wallet')).status).toBe('unavailable');
  });
  it('never echoes native/provider error payloads', async () => {
    bridge.open.mockRejectedValue(new Error('phone=private&token=private'));
    const result = await openPangguaiOfficial('operators');
    expect(result.status).toBe('unavailable');
    expect(pangguaiLaunchMessage(result)).not.toContain('private');
    expect(pangguaiLaunchMessage(result)).toContain('手动进入胖乖官方 App');
  });
  it('does not turn a launch or return into login or payment success', () => {
    expect(pangguaiLaunchMessage({page: 'wallet', status: 'opened'})).toContain('已请求打开');
    expect(pangguaiLaunchMessage({page: 'wallet', status: 'opened'})).toContain('返回不代表充值成功');
  });
  it('registers a private Activity and no provider Javascript/account bridge', () => {
    const manifest = readFileSync('android/app/src/main/AndroidManifest.xml', 'utf8');
    const activityDeclaration = manifest.match(/<activity\b[^>]*android:name="\.life\.PangguaiOfficialActivity"[^>]*\/?\s*>/s)?.[0];
    expect(activityDeclaration).toContain('android:exported="false"');
    expect(readFileSync('android/app/src/main/java/org/handancampus/app/MainActivity.java', 'utf8')).toContain('registerPlugin(org.handancampus.app.life.PangguaiOfficialPlugin.class)');
    const activity = readFileSync('android/app/src/main/java/org/handancampus/app/life/PangguaiOfficialActivity.kt', 'utf8');
    expect(activity).not.toMatch(/addJavascriptInterface|evaluateJavascript|Intent\.parseUri|setPackage\(null\)|userAgentString\s*=|setUserAgentString|removeAllCookies|removeSessionCookies|clearCache|getCookie\(|WebStorage.*delete|handler\.proceed\(/);
    expect(activity).toContain('handler.cancel()');
    expect(activity.indexOf('WebView.setWebContentsDebuggingEnabled(false)')).toBeLessThan(activity.indexOf('view = WebView(this)'));
    expect(activity).toContain('WebView.setWebContentsDebuggingEnabled(false)');
    expect(readFileSync('capacitor.config.ts', 'utf8')).toContain('webContentsDebuggingEnabled: false');
    expect(activity).toContain('setAcceptThirdPartyCookies(web, false)');
    expect(activity).toContain('WebSettings.MIXED_CONTENT_NEVER_ALLOW');
    expect(activity).toContain('allowFileAccess = false');
    expect(activity).toContain('allowContentAccess = false');
    expect(activity).toContain('request.deny()');
    expect(activity).toContain('setPositiveButton("打开支付宝")');
    expect(activity).toContain('支付宝小程序的登录账号与此网页独立，不会转移网页会话');
    expect(activity).toContain('核对手机号/账户、实际运营商和金额');
    expect(activity).toContain('.setPackage(PangguaiOfficialPolicy.ALIPAY_PACKAGE)');
    expect(activity).toContain('resolved.packageName != PangguaiOfficialPolicy.ALIPAY_PACKAGE');
    expect(activity).not.toMatch(/setCookie\(|getString\("(?:token|phone|verify|shopId|url|uri)"\)/);
  });
  it('isolates the official browser before providers initialize and never falls back to the school profile', () => {
    const manifest = readFileSync('android/app/src/main/AndroidManifest.xml', 'utf8');
    expect(manifest).toContain('android:name=".life.PangguaiProfileApplication"');
    expect(manifest).toContain('android:process=":pangguai_official"');
    const application = readFileSync('android/app/src/main/java/org/handancampus/app/life/PangguaiProfileApplication.kt', 'utf8');
    expect(application).toContain('override fun attachBaseContext');
    expect(application).toContain('PangguaiProfileSession.configureDataDirectory(base)');
    const session = readFileSync('android/app/src/main/java/org/handancampus/app/life/PangguaiProfileSession.kt', 'utf8');
    expect(session).toContain('Application.getProcessName(), context.packageName');
    expect(session.indexOf('PangguaiProfileLifecycle.isolationEligible(')).toBeLessThan(session.indexOf('WebView.setDataDirectorySuffix('));
    expect(session.indexOf('WebView.setDataDirectorySuffix(')).toBeLessThan(session.indexOf('WebView.setWebContentsDebuggingEnabled('));
    expect(session).toContain('if (!suffixConfigured) { lifecycle.initialize(false); return }');
  });
  it('uses completion-bearing isolated deletion and a durable pending fence, not origin inspection or legacy cleanup', () => {
    const session = readFileSync('android/app/src/main/java/org/handancampus/app/life/PangguaiProfileSession.kt', 'utf8');
    expect(session).toContain('WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)');
    expect(session).toContain('WebStorageCompat.deleteBrowsingData(WebStorage.getInstance(), Runnable');
    expect(session).toContain('pending = preferences!!.getBoolean(PENDING_RESET, false)');
    expect(session).toContain('if (pending) reset()');
    expect(session.indexOf('pending = preferences!!.getBoolean')).toBeLessThan(session.indexOf('lifecycle.initialize(true)'));
    expect(session).toContain('lifecycle.initialize(supported = true, markerReadable = false)');
    expect(session.indexOf('putBoolean(PENDING_RESET, true).commit()')).toBeLessThan(session.indexOf('WebStorageCompat.deleteBrowsingData('));
    expect(session.indexOf('val detached = disposeOwnedView()')).toBeLessThan(session.indexOf('WebStorageCompat.deleteBrowsingData('));
    expect(session).not.toMatch(/deleteAllData|getOrigins|removeAllCookies|removeSessionCookies|getCookie|deleteRecursively|user\/release/);
    expect(readFileSync('android/variables.gradle', 'utf8')).toContain("androidxWebkitVersion = '1.13.0'");
    expect(readFileSync('android/app/build.gradle', 'utf8')).toContain('implementation "androidx.webkit:webkit:$androidxWebkitVersion"');
  });
  it('removes destroyed views, fences stale callbacks, and offers no native account-unbind shortcut', () => {
    const activity = readFileSync('android/app/src/main/java/org/handancampus/app/life/PangguaiOfficialActivity.kt', 'utf8');
    expect(activity).toContain('private var web: WebView? = null');
    expect(activity).toContain('PangguaiProfileSession.ownsView(viewGeneration)');
    expect(activity.indexOf('web = null // Fence')).toBeLessThan(activity.indexOf('previous.destroy()'));
    expect(activity).toContain('if (!current(view)) return blockedResponse()');
    expect(activity).toContain('setPositiveButton("清除")');
    expect(activity).not.toContain('button("账号');
    expect(activity).not.toContain('user/release');
  });
});

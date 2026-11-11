import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {openParcelShortcut, parcelLaunchMessage, parcelShortcutsSupported, type ParcelProvider} from '../src/services/parcel-shortcuts';

const bridge = vi.hoisted(() => ({open: vi.fn(), platform: 'android', available: true}));
vi.mock('@capacitor/core', () => ({
  Capacitor: {getPlatform: () => bridge.platform, isPluginAvailable: () => bridge.available},
  registerPlugin: () => ({open: bridge.open}),
}));
beforeEach(() => { bridge.open.mockReset(); bridge.platform = 'android'; bridge.available = true });

describe('parcel shortcut bridge', () => {
  it.each(['taobao', 'pinduoduo'] as const)('sends only the fixed %s provider, not a URI or identity', async provider => {
    bridge.open.mockResolvedValue({provider, status: 'opened'});
    expect(await openParcelShortcut(provider)).toEqual({provider, status: 'opened'});
    expect(bridge.open).toHaveBeenCalledExactlyOnceWith({provider});
  });
  it.each(['web', 'ios'])('never launches arbitrary links in %s', async platform => {
    bridge.platform = platform;
    expect(parcelShortcutsSupported()).toBe(false);
    expect((await openParcelShortcut('taobao')).status).toBe('unsupported');
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it('handles an Android build without the plugin', async () => {
    bridge.available = false;
    expect((await openParcelShortcut('pinduoduo')).status).toBe('unsupported');
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it.each(['', 'TAOBAO', ' taobao', 'https://example.com', 'javascript:alert(1)'])('rejects invalid provider %s before the bridge', async provider => {
    await expect(openParcelShortcut(provider as ParcelProvider)).rejects.toThrow('INVALID_PROVIDER');
    expect(bridge.open).not.toHaveBeenCalled();
  });
  it.each(['not_installed', 'unavailable', 'cancelled'] as const)('preserves the %s launch result', async status => {
    bridge.open.mockResolvedValue({provider: 'taobao', status});
    expect(await openParcelShortcut('taobao')).toEqual({provider: 'taobao', status});
  });
  it.each([null, {}, {provider: 'pinduoduo', status: 'opened'}, {provider: 'taobao', status: 'picked_up'}, {provider: 'taobao', status: {toString: (): string => 'opened'}}])('treats malformed replies as unavailable', async result => {
    bridge.open.mockResolvedValue(result);
    expect((await openParcelShortcut('taobao')).status).toBe('unavailable');
  });
  it('uses fixed error text rather than exposing native payloads', async () => {
    bridge.open.mockRejectedValue(new Error('token=private'));
    const result = await openParcelShortcut('pinduoduo');
    expect(result.status).toBe('unavailable');
    expect(parcelLaunchMessage(result)).not.toContain('private');
    expect(parcelLaunchMessage(result)).toContain('手动进入官方 App');
    bridge.open.mockRejectedValue({code: 'CANCELLED', message: 'private'});
    expect((await openParcelShortcut('pinduoduo')).status).toBe('cancelled');
  });
  it('does not translate launch acceptance into verification or pickup success', () => {
    expect(parcelLaunchMessage({provider: 'taobao', status: 'opened'})).toContain('已请求打开淘宝');
    expect(parcelLaunchMessage({provider: 'taobao', status: 'opened'})).toContain('返回本应用不代表已出库');
    expect(parcelLaunchMessage({provider: 'pinduoduo', status: 'not_installed'})).toContain('先安装官方 App');
  });
  it('registers the native plugin and declares only the required app visibility', () => {
    const manifest = readFileSync('android/app/src/main/AndroidManifest.xml', 'utf8');
    expect(manifest).toContain('<package android:name="com.taobao.taobao" />');
    expect(manifest).toContain('<package android:name="com.xunmeng.pinduoduo" />');
    expect(manifest).not.toContain('QUERY_ALL_PACKAGES');
    expect(readFileSync('android/app/src/main/java/org/handancampus/app/MainActivity.java', 'utf8')).toContain('registerPlugin(org.handancampus.app.life.ParcelShortcutsPlugin.class)');
    const plugin = readFileSync('android/app/src/main/java/org/handancampus/app/life/ParcelShortcutsPlugin.kt', 'utf8');
    const launcher = readFileSync('android/app/src/main/java/org/handancampus/app/life/ParcelAndroidLauncher.kt', 'utf8');
    expect(launcher).toContain('intent.setPackage(target.packageName)');
    expect(launcher).toContain('getLaunchIntentSenderForPackage');
    expect(plugin).not.toMatch(/getApplicationInfo|resolveActivity/);
    expect(plugin).not.toMatch(/setPackage\(null\)|evaluateJavascript|loadUrl|startActivityForResult/);
  });
});

it.each(['app_opened', 'system_opened', 'web_opened'] as const)('preserves accurate %s result without claiming an identity page', async status => {
 bridge.open.mockResolvedValue({provider:'taobao',status});
 const result=await openParcelShortcut('taobao','system');expect(bridge.open).toHaveBeenCalledExactlyOnceWith({provider:'taobao',mode:'system'});
 expect(result.status).toBe(status);expect(parcelLaunchMessage(result)).not.toMatch(/已出库|登录成功|取件成功/);
});
it('rejects unsupported compatibility modes before native dispatch',async()=>{
 await expect(openParcelShortcut('taobao','browser' as never)).rejects.toThrow('INVALID_PROVIDER');expect(bridge.open).not.toHaveBeenCalled();
});

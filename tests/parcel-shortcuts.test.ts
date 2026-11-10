import {beforeEach, describe, expect, it, vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {openEmbeddedParcel, openParcelShortcut, parcelLaunchMessage, parcelShortcutsSupported, type ParcelProvider} from '../src/services/parcel-shortcuts';

const bridge = vi.hoisted(() => ({open: vi.fn(), embedded: vi.fn(), platform: 'android', available: true}));
vi.mock('@capacitor/core', () => ({
  Capacitor: {getPlatform: () => bridge.platform, isPluginAvailable: () => bridge.available},
  registerPlugin: () => ({open: bridge.open, openEmbedded: bridge.embedded}),
}));
beforeEach(() => { bridge.open.mockReset(); bridge.embedded.mockReset(); bridge.platform = 'android'; bridge.available = true });

describe('embedded parcel bridge', () => {
  it('only passes a fixed provider and checks the reply provider', async () => {
    bridge.embedded.mockResolvedValue({provider:'taobao',status:'opened'});
    expect(await openEmbeddedParcel('taobao')).toBe(true);
    expect(bridge.embedded).toHaveBeenCalledExactlyOnceWith({provider:'taobao'});
    expect(await openEmbeddedParcel('pinduoduo')).toBe(false);
    bridge.embedded.mockResolvedValue({provider:'taobao',status:'logged_in'});
    expect(await openEmbeddedParcel('taobao')).toBe(false);
  });
  it('contains native failures and never opens embedded pages outside Android', async () => {
    bridge.embedded.mockRejectedValue(new Error('private'));
    expect(await openEmbeddedParcel('taobao')).toBe(false);
    bridge.embedded.mockClear(); bridge.platform = 'web';
    expect(await openEmbeddedParcel('taobao')).toBe(false);
    expect(bridge.embedded).not.toHaveBeenCalled();
  });
});

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
    expect(plugin).toContain('.setPackage(target.packageName)');
    expect(plugin).toContain('info.packageName == target.packageName');
    expect(plugin).not.toMatch(/setPackage\(null\)|evaluateJavascript|loadUrl|startActivityForResult/);
  });
});

// @vitest-environment jsdom
import {afterEach, beforeEach, expect, it, vi} from 'vitest';
import {createApp, h, nextTick} from 'vue';
import ParcelShortcuts from '../src/components/ParcelShortcuts.vue';
import type {ParcelLaunchResult} from '../src/services/parcel-shortcuts';

const bridge = vi.hoisted(() => ({supported: true, open: vi.fn(), embedded: vi.fn()}));
vi.mock('../src/services/parcel-shortcuts', async original => ({
  ...await original<typeof import('../src/services/parcel-shortcuts')>(),
  parcelShortcutsSupported: () => bridge.supported,
  openParcelShortcut: bridge.open,
  openEmbeddedParcel: bridge.embedded,
}));
let root: HTMLElement, app: ReturnType<typeof createApp> | undefined;
async function settle() { await Promise.resolve(); await Promise.resolve(); await nextTick() }
function mount() { app = createApp({render: () => h(ParcelShortcuts)}); app.mount(root) }
function button(name: string) { return [...root.querySelectorAll('button')].find(b => b.textContent?.includes(name))! }
beforeEach(() => { bridge.supported = true; bridge.open.mockReset(); bridge.embedded.mockReset(); root = document.createElement('div'); document.body.append(root) });
afterEach(() => { app?.unmount(); app = undefined; root.remove() });

it('offers two clearly labelled official-app shortcuts without a code or account form', () => {
  mount();
  expect(button('淘宝出库码')).toBeTruthy(); expect(button('拼多多出库码')).toBeTruthy();
  expect(root.textContent).toContain('应用内查看');
  expect(root.textContent).toContain('仅在本机展示');
  expect(root.querySelector('input,canvas,img,iframe')).toBeNull();
  expect(bridge.open).not.toHaveBeenCalled();
});
it('opens embedded pages deliberately and fences late callbacks', async () => {
  let finish!: (value: boolean) => void;
  bridge.embedded.mockReturnValue(new Promise<boolean>(resolve => { finish = resolve })); mount();
  button('打开取件中心').click(); button('打开取件中心').click(); await nextTick();
  expect(bridge.embedded).toHaveBeenCalledExactlyOnceWith('taobao');
  expect(button('打开取件中心').disabled).toBe(true);
  app!.unmount(); app = undefined; mount(); finish(true); await settle();
  expect(root.querySelector('[role=status]')).toBeNull();
});
it('does not describe opening a window as a successful login or data sync', async () => {
  bridge.embedded.mockResolvedValue(true); mount(); button('打开取件中心').click(); await settle();
  expect(root.textContent).toContain('首次使用请连接账号');
  expect(root.textContent).not.toMatch(/登录成功|同步成功|已连接账号/);
  bridge.embedded.mockResolvedValue(false); button('打开取件中心').click(); await settle();
  expect(root.textContent).toContain('暂时无法打开应用内页面');
  expect(button('打开取件中心').disabled).toBe(false);
});
it('disables web previews instead of silently navigating to a provider URL', () => {
  bridge.supported = false; mount();
  button('淘宝出库码').click();
  expect(button('淘宝出库码').disabled).toBe(true);
  expect(button('拼多多出库码').disabled).toBe(true);
  expect(root.textContent).toContain('Android 客户端');
  expect(bridge.open).not.toHaveBeenCalled();
});
it('coalesces repeated taps while the bridge is pending and never claims pickup success', async () => {
  let finish!: (value: ParcelLaunchResult) => void;
  bridge.open.mockReturnValue(new Promise<ParcelLaunchResult>(resolve => { finish = resolve })); mount();
  button('淘宝出库码').click(); button('淘宝出库码').click(); button('拼多多出库码').click();
  await nextTick();
  expect(button('拼多多出库码').disabled).toBe(true);
  expect(bridge.open).toHaveBeenCalledExactlyOnceWith('taobao');
  finish({provider: 'taobao', status: 'opened'}); await settle();
  expect(root.textContent).toContain('已请求打开淘宝');
  expect(root.textContent).toContain('返回本应用不代表已出库');
  expect(root.textContent).not.toMatch(/取件成功|验证成功/);
  expect(button('拼多多出库码').disabled).toBe(false);
});
it.each(['not_installed', 'unavailable', 'cancelled'] as const)('handles %s and permits a deliberate retry', async status => {
  bridge.open.mockResolvedValue({provider: 'pinduoduo', status}); mount();
  button('拼多多出库码').click(); await settle();
  expect(root.querySelector('[role=status]')?.textContent).toContain(status === 'not_installed' ? '未检测到拼多多' : status === 'cancelled' ? '已取消打开拼多多' : '手动进入官方 App');
  expect(button('拼多多出库码').disabled).toBe(false);
  button('拼多多出库码').click(); await settle();
  expect(bridge.open).toHaveBeenCalledTimes(2);
});
it('contains unexpected bridge failures and releases both buttons', async () => {
  bridge.open.mockRejectedValue(new Error('private payload')); mount();
  button('淘宝出库码').click(); await settle();
  expect(root.textContent).toContain('暂时无法打开淘宝出库码');
  expect(root.textContent).not.toContain('private payload');
  expect(button('淘宝出库码').disabled).toBe(false);
});
it('does not carry a late launch reply onto a different page or remount', async () => {
  let finish!: (value: ParcelLaunchResult) => void;
  bridge.open.mockReturnValue(new Promise<ParcelLaunchResult>(resolve => { finish = resolve })); mount();
  button('淘宝出库码').click(); await nextTick();
  app!.unmount(); app = undefined;
  mount();
  finish({provider: 'taobao', status: 'opened'}); await settle();
  expect(root.querySelector('[role=status]')).toBeNull();
  expect(button('淘宝出库码').disabled).toBe(false);
  expect(bridge.open).toHaveBeenCalledTimes(1);
});

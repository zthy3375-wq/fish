// @vitest-environment jsdom
import {afterEach, beforeEach, expect, it, vi} from 'vitest';
import {createApp, h, nextTick} from 'vue';
import PangguaiOfficialEntry from '../src/components/PangguaiOfficialEntry.vue';
import type {PangguaiLaunchResult} from '../src/services/pangguai-official';

const bridge = vi.hoisted(() => ({supported: true, open: vi.fn()}));
vi.mock('../src/services/pangguai-official', async original => ({
  ...await original<typeof import('../src/services/pangguai-official')>(),
  pangguaiOfficialSupported: () => bridge.supported,
  openPangguaiOfficial: bridge.open,
}));
let root: HTMLElement, app: ReturnType<typeof createApp> | undefined;
function mount() { app = createApp({render: () => h(PangguaiOfficialEntry)}); app.mount(root) }
function button(name: string) { return [...root.querySelectorAll('button')].find(b => b.textContent?.includes(name))! }
async function settle() { await Promise.resolve(); await Promise.resolve(); await nextTick() }
beforeEach(() => { bridge.supported = true; bridge.open.mockReset(); root = document.createElement('div'); document.body.append(root) });
afterEach(() => { app?.unmount(); app = undefined; root.remove() });

it('offers official pages with honest scope and session disclosure, not a native balance or login form', () => {
  mount();
  expect(button('官方钱包')).toBeTruthy();
  expect(button('官方充值页面')).toBeTruthy();
  expect(root.textContent).toContain('实际运营商');
  expect(root.textContent).toContain('此处不显示余额');
  expect(root.textContent).toContain('兼容性待手机验证');
  expect(root.textContent).toContain('官方页面会话可能保留在本机');
  expect(root.textContent).toContain('关闭不等于退出');
  expect(root.textContent).toContain('清除本机胖乖网页数据');
  expect(root.textContent).toContain('不影响教务或官方账号绑定');
  expect(root.querySelector('input,iframe,canvas')).toBeNull();
  expect(root.textContent).not.toMatch(/[¥￥]|0\.00|已连接/);
  expect(bridge.open).not.toHaveBeenCalled();
});
it('disables unsupported previews without opening an external page', () => {
  bridge.supported = false; mount();
  button('官方钱包').click();
  expect(button('官方钱包').disabled).toBe(true);
  expect(button('官方充值页面').disabled).toBe(true);
  expect(root.textContent).toContain('Android 客户端');
  expect(bridge.open).not.toHaveBeenCalled();
});
it('coalesces rapid taps, then describes only the accepted open request', async () => {
  let finish!: (value: PangguaiLaunchResult) => void;
  bridge.open.mockReturnValue(new Promise<PangguaiLaunchResult>(resolve => { finish = resolve })); mount();
  button('官方钱包').click(); button('官方钱包').click(); button('官方充值页面').click();
  await nextTick();
  expect(bridge.open).toHaveBeenCalledExactlyOnceWith('wallet');
  expect(button('官方充值页面').disabled).toBe(true);
  expect(root.querySelector('[role=status]')?.textContent).toContain('正在请求打开');
  finish({page: 'wallet', status: 'opened'}); await settle();
  expect(root.querySelector('[role=status]')?.textContent).toContain('返回不代表充值成功');
  expect(button('官方充值页面').disabled).toBe(false);
});
it('opens the operator list rather than constructing a school/shop or payment choice', async () => {
  bridge.open.mockResolvedValue({page: 'operators', status: 'opened'}); mount();
  button('官方充值页面').click(); await settle();
  expect(bridge.open).toHaveBeenCalledExactlyOnceWith('operators');
  expect(root.querySelectorAll('button')).toHaveLength(2);
});
it.each(['unavailable', 'cancelled'] as const)('handles %s and allows deliberate retry', async status => {
  bridge.open.mockResolvedValue({page: 'wallet', status}); mount();
  button('官方钱包').click(); await settle();
  expect(root.querySelector('[role=status]')?.textContent).toContain(status === 'cancelled' ? '已取消' : '手动进入胖乖官方 App');
  button('官方钱包').click(); await settle();
  expect(bridge.open).toHaveBeenCalledTimes(2);
});
it('contains unexpected errors without displaying private payloads', async () => {
  bridge.open.mockRejectedValue(new Error('token=private')); mount();
  button('官方钱包').click(); await settle();
  expect(root.textContent).not.toContain('private');
  expect(root.querySelector('[role=status]')?.textContent).toContain('暂时无法打开');
  expect(button('官方钱包').disabled).toBe(false);
});
it('does not transfer late results or native status between page instances', async () => {
  let finish!: (value: PangguaiLaunchResult) => void;
  bridge.open.mockReturnValue(new Promise<PangguaiLaunchResult>(resolve => { finish = resolve })); mount();
  button('官方钱包').click(); await nextTick(); app!.unmount(); app = undefined;
  mount(); finish({page: 'wallet', status: 'opened'}); await settle();
  expect(root.querySelector('[role=status]')).toBeNull();
  expect(button('官方钱包').disabled).toBe(false);
});

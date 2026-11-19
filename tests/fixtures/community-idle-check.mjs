// Actual Vue component request-budget checks with isolated native transport fixtures.
// No requests are sent to Tencent Cloud and no production account is used.
import { build } from 'esbuild';
import { parse, compileScript } from '@vue/compiler-sfc';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import assert from 'node:assert/strict';
const bundle = await build({
  stdin: { contents: "import {createApp} from 'vue';import Feed from './src/components/Treehole.vue';import Messages from './src/components/TreeholeMessages.vue';window.app=createApp(window.subject==='feed'?Feed:Messages,{drafts:{}});window.app.mount('#app');", resolveDir: resolve('.'), loader: 'ts' },
  loader: {".css":"empty"},
  bundle: true, write: false, format: 'iife', platform: 'browser',
  define: { 'process.env.NODE_ENV': '"test"', __VUE_OPTIONS_API__: 'true', __VUE_PROD_DEVTOOLS__: 'false', __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: 'false' },
  plugins: [{ name: 'vue-sfc', setup(build) { build.onLoad({ filter: /\.vue$/ }, async ({ path }) => {
    const { descriptor } = parse(await readFile(path, 'utf8'));
    return { contents: compileScript(descriptor, { id: path, inlineTemplate: true }).content, loader: 'ts', resolveDir: dirname(path) };
  }); } }],
});
const member = { id: '11111111-1111-4111-8111-111111111111', username: 'fixture', nickname: '测试', role: 'member' };
const thread = { id: '22222222-2222-4222-8222-222222222222', member: { id: '33333333-3333-4333-8333-333333333333', nickname: '同学' }, lastSeq: '0', updatedAt: '2026-11-19T00:00:00Z', lastMessage: null, unreadCount: 0 };
let dom;
async function mount(subject) {
  if (dom) { dom.window.app.unmount(); dom.window.close(); }
  dom = new JSDOM('<div id="app"></div>', { url: 'https://localhost', runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window, calls = [], timers = new Map(); let clock = 1_000_000, nextTimer = 0;
  w.subject = subject; w.Date.now = () => clock;
  w.setInterval = (callback, delay) => { const id = ++nextTimer; timers.set(id, { callback, delay }); return id; };
  w.clearInterval = id => timers.delete(id);
  w.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
  w.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} };
  w.scrollTo = () => {};
  w.Capacitor = { PluginHeaders: [{ name: 'Treehole', methods: [{ name: 'request', rtype: 'promise' }] }], nativePromise: async (_, __, options) => {
    const action = options.action; calls.push(action);
    if (action === 'me') return { user: member, posts: [], next: null, config: { contestsEnabled:true,schema:14,engagementEnabled: true, messagesEnabled: true, combinedUnread: true } };
    if (action === 'notifications.unread') return { unreadCount: 0, messageUnreadCount: 0 };
    if (action === 'messages.inbox') return { conversations: [thread], messageUnreadCount: 0, next: null };
    if (action === 'messages.list') return { conversation: thread, messages: [], next: null };
    return {};
  } };
  w.eval(bundle.outputFiles[0].text);
  const settle = async () => { for (let i = 0; i < 10; i++) await new Promise(r => setTimeout(r, 5)); };
  await settle();
  return { w, calls, settle, advance: async milliseconds => { clock += milliseconds; for (const timer of timers.values()) timer.callback(); await settle(); } };
}
try {
  let h = await mount('feed');
  assert(h.calls.includes('notifications.unread'));
  const initial = h.calls.length;
  await h.advance(60 * 60_000); assert.equal(h.calls.length, initial, 'idle community must not wake the database');
  h.w.document.dispatchEvent(new h.w.Event('visibilitychange')); await h.settle();
  assert.equal(h.calls.at(-1), 'notifications.unread', 'returning to the visible page refreshes counts');
  h = await mount('messages');
  const inbox = h.calls.length;
  await h.advance(60 * 60_000); assert.equal(h.calls.length, inbox, 'inbox has no timer-driven database reads');
  h.w.document.querySelector('[data-conversation-id]').click(); await h.settle();
  const chat = h.calls.length;
  await h.advance(8000); assert.equal(h.calls.length, chat + 1, 'active conversation can receive messages');
  await h.advance(120_000); const idle = h.calls.length;
  await h.advance(60 * 60_000); assert.equal(h.calls.length, idle, 'idle chat polling pauses');
  h.w.document.querySelector('.th-dm').dispatchEvent(new h.w.Event('pointerdown', { bubbles: true })); await h.settle();
  assert.equal(h.calls.length, idle + 1, 'real interaction resumes chat refresh');
  console.log('Request budget verified: one hour idle feed/inbox/chat adds zero API calls; foreground and active chat still refresh.');
} finally { if (dom) { dom.window.app.unmount(); dom.window.close(); } }

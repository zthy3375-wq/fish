// DOM interaction harness using the actual Vue components and PostgreSQL RPC.
// Network/image decoding and mobile keyboards require separate device verification.
import { build } from "esbuild";
import { parse, compileScript } from "@vue/compiler-sfc";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { JSDOM } from "jsdom";
import { indexedDB, IDBKeyRange } from "fake-indexeddb";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import assert from "node:assert/strict";
import { createCommunity } from "../../cloudbase/functions/community/core.mjs";
const db = new PGlite();
await db.exec(await readFile("cloudbase/community-schema.sql", "utf8"));
const api = createCommunity({
  contestsEnabled: true,
  registrationEnabled: true,
  db: async (a, b, t) =>
    (
      await db.query("SELECT hyt_community($1,$2::jsonb,$3) AS result", [
        a,
        JSON.stringify(b),
        t,
      ])
    ).rows[0].result,
});
const register = (username) =>
  api.execute(
    "register",
    { username, password: "fixture-ui-password-123", agreed: true },
    "",
    username,
  );
const owner = await register("ui-owner"),
  author = await register("ui-author"),
  voter = await register("ui-voter");
await db.query("UPDATE hyt_members SET developer_since=now() WHERE id=$1", [
  owner.user.id,
]);
await db.exec("UPDATE hyt_members SET created_at=now()-interval '30 days'");
const call = (u, a, b) => api.execute(a, b, u.sessionToken, "fixture-ui");
const original = (
  await call(author, "posts.create", {
    requestId: randomUUID(),
    title: "原创校园故事",
    body: "这是我的非匿名原帖。",
    category: "daily",
    anonymous: false,
  })
).post;
const date = (h) => new Date(Date.now() + h * 3600000).toISOString();
const id = randomUUID();
await call(owner, "contests.save", {
  contestId: id,
  title: "校园光影",
  type: "文字赛",
  edition: "第一届",
  description: "留下校园故事",
  rules: "原创、同票并列",
  startsAt: date(-1),
  submissionEnds: date(5),
  votingStarts: date(5),
  votingEnds: date(6),
  awardAt: date(7),
  formats: ["text"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 1,
  minAccountHours: 0,
  excellence: 1,
  autoPublish: false,
});
await call(owner, "contests.manage", {
  contestId: id,
  operation: "publish",
  reason: "发布测试赛事",
});
const bundle = await build({
  stdin: {
    contents:
      "import {createApp} from 'vue';import Hub from './src/components/contests/ContestHub.vue';window.app=createApp(Hub,{user:window.fixtureUser});window.app.mount('#app');",
    resolveDir: resolve("."),
    loader: "ts",
  },
  loader: { ".css": "empty" },
  bundle: true,
  write: false,
  format: "iife",
  platform: "browser",
  define: {
    "process.env.NODE_ENV": '"test"',
    __VUE_OPTIONS_API__: "true",
    __VUE_PROD_DEVTOOLS__: "false",
    __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: "false",
  },
  plugins: [
    {
      name: "vue-sfc",
      setup(build) {
        build.onLoad({ filter: /\.vue$/ }, async ({ path }) => {
          const { descriptor } = parse(await readFile(path, "utf8"));
          return {
            contents: compileScript(descriptor, {
              id: path,
              inlineTemplate: true,
            }).content,
            loader: "ts",
            resolveDir: dirname(path),
          };
        });
      },
    },
  ],
});
let dom;
async function until(check) {
  for (let i = 0; i < 300; i++) {
    if (check()) return;
    await new Promise((r) => setTimeout(r, 10));
  }
  throw Error("UI wait failed: " + dom.window.document.body.textContent);
}
function button(label) {
  return [...dom.window.document.querySelectorAll("button")].find(
    (b) => b.textContent.trim() === label,
  );
}
function input(label, value) {
  const node = [...dom.window.document.querySelectorAll("label")].find((n) =>
    n.textContent.trim().startsWith(label),
  );
  const el = node.querySelector("input,textarea");
  el.value = value;
  el.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
  return el;
}
const actions = [];
async function mount(who) {
  if (dom) {
    dom.window.app.unmount();
    dom.window.close();
  }
  dom = new JSDOM('<div id="app"></div>', {
    url: "https://localhost",
    runScripts: "outside-only",
  });
  const w = dom.window;
  w.indexedDB = indexedDB;
  w.IDBKeyRange = IDBKeyRange;
  w.scrollTo = () => {};
  w.matchMedia = () => ({ matches: true });
  w.HTMLDialogElement.prototype.showModal = function () {
    this.open = true;
  };
  w.HTMLDialogElement.prototype.close = function () {
    this.open = false;
  };
  w.fixtureUser = who.user;
  w.Capacitor = {
    PluginHeaders: [
      { name: "Treehole", methods: [{ name: "request", rtype: "promise" }] },
    ],
    nativePromise: async (_, __, options) => {
      actions.push(options.action);
      return call(who, options.action, options.body);
    },
  };
  w.eval(bundle.outputFiles[0].text);
  await until(
    () =>
      button("我要参赛") || w.document.body.textContent.includes("校园光影"),
  );
}
try {
  await mount(author);
  await until(() => button("我要参赛"));
  button("我要参赛").click();
  await until(() => button("预览作品") && !button("预览作品").disabled);
  input("作品名称", "我们的早八");
  input("作品内容", "教室窗前的一缕光。");
  [...dom.window.document.querySelectorAll("label")]
    .find((l) => l.textContent.includes("我已阅读规则"))
    .querySelector("input")
    .click();
  dom.window.document
    .querySelector("form")
    .dispatchEvent(
      new dom.window.Event("submit", { bubbles: true, cancelable: true }),
    );
  await until(() => button("确认参赛"));
  button("确认参赛").click();
  await until(() => button("编辑作品"));
  assert(dom.window.document.body.textContent.includes("我们的早八"));
  button("编辑作品").click();
  await until(() => button("选择我的帖子参赛"));
  button("选择我的帖子参赛").click();
  await until(() => dom.window.document.querySelector(".pick-post"));
  dom.window.document.querySelector(".pick-post").click();
  await until(() => button("改为直接投稿"));
  const linkedBody = dom.window.document.querySelector("textarea");
  assert.equal(linkedBody.value, original.body);
  assert(linkedBody.readOnly);
  button("改为直接投稿").click();
  await until(() => !linkedBody.readOnly);
  button("选择我的帖子参赛").click();
  await until(() => dom.window.document.querySelector(".pick-post"));
  dom.window.document.querySelector(".pick-post").click();
  await until(() => linkedBody.readOnly);
  [...dom.window.document.querySelectorAll("label")]
    .find((l) => l.textContent.includes("我已阅读规则"))
    .querySelector("input")
    .click();
  dom.window.document
    .querySelector("form")
    .dispatchEvent(
      new dom.window.Event("submit", { bubbles: true, cancelable: true }),
    );
  await until(() => button("保存作品"));
  button("保存作品").click();
  await until(() => button("编辑作品"));
  const linked = (
    await db.query("SELECT post_id,linked,body FROM hyt_contest_entries")
  ).rows[0];
  assert.equal(linked.post_id, original.id);
  assert.equal(linked.linked, true);
  assert.equal(linked.body, original.body);
  await db.query(
    "UPDATE hyt_contests SET starts_at=now()-interval '4 hours',submission_ends=now()-interval '3 hours',voting_starts=now()-interval '2 hours' WHERE id=$1",
    [id],
  );
  await mount(voter);
  await until(() => dom.window.document.querySelector(".ct-work-open"));
  dom.window.document.querySelector(".ct-work-open").click();
  await until(() => button("投一票"));
  const before = actions.length;
  button("投一票").click();
  await until(() => button("已投票 · 撤回"));
  assert.deepEqual(actions.slice(before), ["contests.vote"]);
  assert(dom.window.document.body.textContent.includes("还可投 2 / 3 票"));
  assert.equal(
    (await db.query("SELECT count(*)::int AS n FROM hyt_contest_votes")).rows[0]
      .n,
    1,
  );
  const count = actions.length;
  await new Promise((r) => setTimeout(r, 150));
  assert.equal(actions.length, count);
  assert(!dom.window.document.querySelector(".ct-final-votes"));
  console.log(
    "Vue 2.0: current event → independent preview/submit → own-post edit → detail voting; committed response, no detail refresh or idle calls.",
  );
} finally {
  if (dom) {
    dom.window.app.unmount();
    dom.window.close();
  }
  await db.close();
}

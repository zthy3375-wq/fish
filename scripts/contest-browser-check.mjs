import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { chromium } from "playwright";
import { createCommunity } from "../cloudbase/functions/community/core.mjs";

const output = "/tmp/handan-community-contests-qa";
await mkdir(output, { recursive: true });
const db = new PGlite();
await db.exec(await readFile("cloudbase/community-schema.sql", "utf8"));
const media = new Map();
let origin = "",
  sign = 0;
const api = createCommunity({
  storage: {
    put: async (key, bytes) => media.set(key, bytes),
    url: async (key) => origin + "/fixtures/" + key + "?signed=" + ++sign,
    remove: async (key) => media.delete(key),
  },
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
const reg = (name) =>
  api.execute(
    "register",
    { username: name, password: "browser-fixture-password", agreed: true },
    "",
    name,
  );
const owner = await reg("contest-admin"),
  author = await reg("contest-author"),
  voter = await reg("contest-voter");
await db.query("UPDATE hyt_members SET developer_since=now() WHERE id=$1", [
  owner.user.id,
]);
await db.exec("UPDATE hyt_members SET created_at=now()-interval '30 days'");
const call = (u, a, b) =>
  api.execute(a, b, u.sessionToken, "browser-fixture-campus");
const stamp = (h) => new Date(Date.now() + h * 3600000).toISOString();
const id = randomUUID();
await call(owner, "contests.save", {
  contestId: id,
  title: "把校园写成一首诗",
  type: "文字赛",
  edition: "第一届",
  description:
    "从早八路上的一束光，到晚自习窗外的风。用一段文字，收藏你的邯院日常。",
  rules: "原创文字投稿，尊重他人隐私。同票并列，下一名次连续排列。",
  startsAt: stamp(-1),
  submissionEnds: stamp(5),
  votingStarts: stamp(5),
  votingEnds: stamp(6),
  awardAt: stamp(7),
  formats: ["text"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 1,
  minAccountHours: 0,
  excellence: 3,
  autoPublish: true,
});
await call(owner, "contests.manage", {
  contestId: id,
  operation: "publish",
  reason: "发布已核验的测试赛事",
});
await call(author, "contests.submit", {
  contestId: id,
  title: "早八路上的光",
  body: "我把没睡醒的清晨\n交给教学楼的一扇窗。\n阳光落在课本上，\n今天也有了温柔的开场。",
  images: [],
  agreed: true,
  requestId: randomUUID(),
});
const root = path.resolve("dist");
const server = createServer(async (req, res) => {
  try {
    const name = new URL(req.url, "http://localhost").pathname;
    if (name.startsWith("/fixtures/")) {
      const bytes = media.get(name.slice("/fixtures/".length));
      if (!bytes) throw Error("missing_fixture");
      res.setHeader("Content-Type", "image/jpeg");
      res.end(bytes);
      return;
    }
    const file = path.resolve(
      root,
      "." + (name === "/" ? "/index.html" : name),
    );
    if (!file.startsWith(root + "/")) throw Error();
    res.setHeader(
      "Content-Type",
      {
        ".js": "text/javascript",
        ".css": "text/css",
        ".html": "text/html",
        ".webp": "image/webp",
        ".png": "image/png",
      }[path.extname(file)] || "application/octet-stream",
    );
    res.end(await readFile(file));
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
origin = `http://127.0.0.1:${server.address().port}`;
let browser;
const checks = [],
  metrics = [];
try {
  browser = await chromium.launch({
    args: ["--no-sandbox"],
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
  });
  for (const width of [360, 390, 430]) {
    const context = await browser.newContext({
      viewport: { width, height: 844 },
      serviceWorkers: "block",
    });
    const actions = [];
    await context.exposeBinding("__contestNative", async (_, options) => {
      actions.push(options.action);
      const result = await call(voter, options.action, options.body);
      delete result.sessionToken;
      return result;
    });
    await context.addInitScript(() => {
      const methods = {
        Treehole: ["request"],
        Preferences: ["get", "set", "remove"],
        App: ["addListener", "removeListener", "exitApp"],
        StatusBar: ["setStyle", "setBackgroundColor"],
        LocalNotifications: ["getPending", "cancel", "checkPermissions"],
      };
      window.androidBridge = {};
      window.Capacitor = {
        PluginHeaders: Object.entries(methods).map(([name, methods]) => ({
          name,
          methods: methods.map((name) => ({ name, rtype: "promise" })),
        })),
        nativePromise: async (plugin, method, args) => {
          if (plugin === "Treehole") return window.__contestNative(args);
          if (plugin === "Preferences") {
            if (method === "get")
              return { value: localStorage.getItem(args.key) };
            if (method === "set") localStorage.setItem(args.key, args.value);
            if (method === "remove") localStorage.removeItem(args.key);
          }
          if (plugin === "LocalNotifications" && method === "getPending")
            return { notifications: [] };
          return {};
        },
      };
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.setDefaultTimeout(20000);
    await page.goto(`http://127.0.0.1:${server.address().port}/#/community`);
    await page
      .getByRole("button", { name: /主题赛事.*把校园写成一首诗/ })
      .waitFor();
    await page.waitForTimeout(400);
    await page
      .locator(".unlock-toast")
      .waitFor({ state: "hidden", timeout: 10000 });
    await page.screenshot({
      animations: "disabled",
      path: path.join(output, `contest-entry-${width}.png`),
      fullPage: false,
    });
    await page.waitForTimeout(400);
    await page
      .locator(".unlock-toast")
      .waitFor({ state: "hidden", timeout: 10000 });
    await page.locator(".contest-entry").click();
    await page.getByRole("button", { name: "我要参赛", exact: true }).waitFor();
    await page.screenshot({
      animations: "disabled",
      path: path.join(output, `contest-detail-${width}.png`),
      fullPage: true,
    });
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth > innerWidth,
      ),
      false,
    );
    await page.getByRole("button", { name: "我要参赛", exact: true }).click();
    await page.getByLabel("作品名称", { exact: true }).fill("窗外");
    await page.getByLabel("文字内容", { exact: true }).fill("晚风穿过一页书。");
    await page.getByLabel("我已阅读规则，拥有作品的发布权").check();
    await page.getByRole("button", { name: "提交作品", exact: true }).click();
    await page.getByText("作品已提交", { exact: true }).waitFor();
    await db.query(
      "UPDATE hyt_contests SET submission_ends=now()-interval '20 minutes',voting_starts=now()-interval '10 minutes' WHERE id=$1",
      [id],
    );
    await page.getByRole("button", { name: "刷新赛事", exact: true }).click();
    await page.getByRole("button", { name: "投一票", exact: true }).click();
    await page
      .getByRole("button", { name: "已投票 · 撤回", exact: true })
      .waitFor();
    const idle = actions.filter((action) =>
      action.startsWith("contests."),
    ).length;
    await page.waitForTimeout(300);
    assert.equal(
      actions.filter((action) => action.startsWith("contests.")).length,
      idle,
    );
    assert(
      !(await page
        .locator(".contest-work footer")
        .filter({ hasText: /\d+ 票/ })
        .count()),
    );
    await page.screenshot({
      animations: "disabled",
      path: path.join(output, `contest-voted-${width}.png`),
      fullPage: true,
    });
    assert.deepEqual(errors, []);
    checks.push(
      `${width}px actual community entry, detail, text submission, confirmed vote, hidden totals, idle request count and horizontal fit`,
    );
    if (width === 390) {
      const imageEvent = randomUUID();
      await call(owner, "contests.save", {
        contestId: imageEvent,
        title: "配图上传回归",
        type: "自定义赛",
        edition: "测试夹具",
        description: "验证原图、缩略图与地址重签。",
        rules: "本地测试数据，不发布到真实社区。",
        startsAt: stamp(-1),
        submissionEnds: stamp(5),
        votingStarts: stamp(5),
        votingEnds: stamp(6),
        awardAt: stamp(7),
        formats: ["image"],
        maxEntries: 1,
        votesPerUser: 3,
        minEntries: 5,
        minAccountHours: 0,
        excellence: 3,
        autoPublish: false,
      });
      await call(owner, "contests.manage", {
        contestId: imageEvent,
        operation: "publish",
        reason: "本地图片交互回归",
      });
      const image = (
        await call(author, "media.upload", {
          data: (await readFile("public/campus/east-plan.jpg")).toString(
            "base64",
          ),
          requestId: randomUUID(),
        })
      ).image;
      await call(author, "contests.submit", {
        contestId: imageEvent,
        title: "校园平面图测试",
        body: "",
        images: [image.id],
        agreed: true,
        requestId: randomUUID(),
      });
      let failedOnce = false;
      await page.route("**/fixtures/**", (route) => {
        if (!failedOnce) {
          failedOnce = true;
          return route.fulfill({ status: 403, body: "Expired fixture URL" });
        }
        return route.continue();
      });
      await page.getByRole("button", { name: "全部赛事", exact: true }).click();
      await page.getByRole("button", { name: "刷新赛事", exact: true }).click();
      await page
        .locator(".event-row")
        .filter({ hasText: "配图上传回归" })
        .click();
      await page.waitForFunction(() => {
        const image = document.querySelector(".contest-work .th-media img");
        return image?.complete && image.naturalWidth > 0;
      });
      assert(actions.includes("contests.image"));
      await page.locator(".contest-work .th-media button").click();
      await page.waitForFunction(() => {
        const image = document.querySelector(".th-gallery img");
        return image?.complete && image.naturalWidth > 0;
      });
      await page.screenshot({
        path: path.join(output, "contest-image-390.png"),
        animations: "disabled",
        fullPage: false,
      });
      await page.getByRole("button", { name: "关闭大图", exact: true }).click();
      checks.push(
        "390px JPEG submission, expired thumbnail renewal and existing full-screen gallery",
      );
    }
    metrics.push({
      width,
      requests: actions.reduce(
        (counts, action) => ({
          ...counts,
          [action]: (counts[action] || 0) + 1,
        }),
        {},
      ),
    });
    await context.close();
    // Reset only synthetic fixture data between viewport runs.
    await db.query("DELETE FROM hyt_contest_requests WHERE member_id=$1", [
      voter.user.id,
    ]);
    await db.query("DELETE FROM hyt_contest_votes WHERE member_id=$1", [
      voter.user.id,
    ]);
    await db.query("DELETE FROM hyt_contest_entries WHERE member_id=$1", [
      voter.user.id,
    ]);
    await db.query(
      "UPDATE hyt_contest_entries SET votes=0 WHERE contest_id=$1",
      [id],
    );
    await db.query(
      "UPDATE hyt_contests SET submission_ends=$2,voting_starts=$2 WHERE id=$1",
      [id, stamp(5)],
    );
  }
  await writeFile(
    path.join(output, "checks.json"),
    JSON.stringify(
      {
        fixture:
          "Synthetic accounts and content with real PostgreSQL RPC and production Vue build",
        checks,
        metrics,
      },
      null,
      2,
    ),
  );
  console.log(checks.join("\n"));
} finally {
  if (browser) await browser.close();
  await new Promise((resolve) => server.close(resolve));
  await db.close();
}

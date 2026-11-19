// @vitest-environment jsdom
import "fake-indexeddb/auto";
import { beforeEach, afterEach, it, expect, vi } from "vitest";
import { createApp, nextTick, type Component } from "vue";
import { randomUUID } from "node:crypto";
import Hub from "../src/components/contests/ContestHub.vue";
import Composer from "../src/components/contests/ContestComposer.vue";
import Management from "../src/components/contests/ContestManagement.vue";
import Admin from "../src/components/contests/ContestAdmin.vue";
import {
  contestRequest,
  resetContestCache,
  type Contest,
  type ContestEntry,
} from "../src/services/contests";
import {
  readDraftRecord,
  writeDraftRecord,
  deleteDraftRecord,
} from "../src/services/treeholeDrafts";
import {
  contestSchedule,
  beijingInput,
  beijingISO,
  primaryContestAction,
  confirmedVote,
} from "../src/domain/contests";
const bridge = vi.hoisted(() => ({ request: vi.fn() }));
vi.mock("../src/services/treehole", async (original) => ({
  ...(await original<object>()),
  treeholeRequest: (...a: unknown[]) => bridge.request(...a),
}));
const now = Date.now(),
  iso = (n: number) => new Date(now + n * 3600000).toISOString();
let event: Contest,
  work: ContestEntry,
  owner: string,
  app: ReturnType<typeof createApp> | undefined,
  root: HTMLElement,
  vm: any;
const btn = (name: string) =>
  [...root.querySelectorAll<HTMLButtonElement>("button")].find(
    (b) =>
      b.textContent?.trim() === name || b.getAttribute("aria-label") === name,
  )!;
async function ready(fn: () => unknown) {
  await expect.poll(fn, { timeout: 5000 }).toBeTruthy();
  await nextTick();
}
async function mount(c: Component, props: Record<string, unknown>) {
  root = document.createElement("div");
  document.body.append(root);
  app = createApp(c, props);
  vm = app.mount(root);
  await nextTick();
}
function type(label: string, value: string) {
  const field = [...root.querySelectorAll("label")]
    .find((x) => x.textContent?.trim().startsWith(label))!
    .querySelector<HTMLInputElement>("input,textarea")!;
  field.value = value;
  field.dispatchEvent(new Event("input", { bubbles: true }));
}
async function submitForm() {
  root
    .querySelector("form")!
    .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  await nextTick();
}
beforeEach(() => {
  resetContestCache();
  owner = randomUUID();
  event = {
    id: randomUUID(),
    title: "窗前的校园",
    type: "文字赛",
    edition: "第一届",
    description: "写下你的校园生活",
    rules: "原创、同票并列",
    state: "submitting",
    paused: false,
    startsAt: iso(-1),
    submissionEnds: iso(5),
    votingStarts: iso(5),
    votingEnds: iso(6),
    awardAt: iso(7),
    formats: ["text"],
    maxEntries: 1,
    votesPerUser: 3,
    minEntries: 5,
    minAccountHours: 0,
    excellence: 3,
    autoPublish: false,
    version: 1,
    entryCount: 1,
    participantCount: 1,
    coverPostId: null,
  };
  work = {
    id: randomUUID(),
    contestId: event.id,
    memberId: randomUUID(),
    title: "那一缕光",
    body: "清晨经过走廊。",
    postId: null,
    status: "approved",
    author: "同学",
    mine: false,
    linked: false,
    createdAt: iso(-0.5),
    voted: false,
    votes: null,
    images: [],
    awards: [],
    version: 1,
  };
  bridge.request.mockReset().mockImplementation(async (action: string) =>
    action === "contests.list"
      ? { contests: [event] }
      : action === "contests.get"
        ? {
            contest: event,
            myEntries: [],
            votesUsed: 0,
            serverTime: new Date().toISOString(),
          }
        : action === "contests.entries"
          ? { entries: [work] }
          : { themes: [] },
  );
  Object.defineProperty(Element.prototype, "scrollIntoView", {
    value: vi.fn(),
    configurable: true,
  });
  Object.defineProperty(window, "scrollTo", {
    value: vi.fn(),
    configurable: true,
  });
  Object.defineProperty(window, "matchMedia", {
    value: () => ({ matches: true }),
    configurable: true,
  });
  Object.defineProperty(HTMLDialogElement.prototype, "showModal", {
    value: function () {
      this.open = true;
    },
    configurable: true,
  });
  Object.defineProperty(HTMLDialogElement.prototype, "close", {
    value: function () {
      this.open = false;
    },
    configurable: true,
  });
});
afterEach(() => {
  app?.unmount();
  app = undefined;
  root?.remove();
});
it("deduplicates concurrent reads, returns independent copies and caches a single database response", async () => {
  let resolve!: (v: object) => void;
  bridge.request.mockImplementation(() => new Promise((r) => (resolve = r)));
  const a = contestRequest(owner, "contests.get", { contestId: event.id });
  const b = contestRequest(owner, "contests.get", { contestId: event.id });
  expect(bridge.request).toHaveBeenCalledTimes(1);
  resolve({ contest: event });
  const [x, y] = await Promise.all([a, b]);
  x.contest!.title = "本地编辑";
  expect(y.contest!.title).toBe(event.title);
  expect(
    (await contestRequest(owner, "contests.get", { contestId: event.id }))
      .contest!.title,
  ).toBe(event.title);
  expect(bridge.request).toHaveBeenCalledTimes(1);
});
it("does not cache reads started before a write and cannot deliver another account late response", async () => {
  let resolve!: (v: object) => void;
  bridge.request.mockImplementation((a: string) =>
    a === "contests.get"
      ? new Promise((r) => (resolve = r))
      : Promise.resolve({}),
  );
  const read = contestRequest(owner, "contests.get", { contestId: event.id });
  const rejected = expect(read).rejects.toThrow("contest_stale_response");
  await contestRequest(owner, "contests.vote", { entryId: work.id });
  resolve({ contest: event });
  await rejected;
  const next = contestRequest(owner, "contests.get", { contestId: event.id });
  const stale = expect(next).rejects.toThrow("contest_account_changed");
  await contestRequest(randomUUID(), "contests.list");
  resolve({ contest: event });
  await stale;
});
it("failed reads are retryable and do not poison the request queue", async () => {
  bridge.request.mockRejectedValueOnce(Error("offline"));
  await expect(contestRequest(owner, "contests.list")).rejects.toThrow(
    "offline",
  );
  await contestRequest(owner, "contests.list");
  expect(bridge.request).toHaveBeenCalledTimes(2);
});
it("assigns custom stages and campus time independently of device timezone", () => {
  for (const days of [1, 3, 7, 14, 30, 61]) {
    const s = contestSchedule(days, now);
    expect(Date.parse(s.awardAt) - Date.parse(s.startsAt)).toBe(
      days * 86400000,
    );
    expect(s.votingStarts).toBe(s.submissionEnds);
    expect(Date.parse(s.votingEnds)).toBeLessThan(Date.parse(s.awardAt));
  }
  expect(beijingInput("2026-11-20T00:00:00Z")).toBe("2026-11-20T08:00");
  expect(beijingISO("2026-11-20T08:00")).toBe("2026-11-20T00:00:00.000Z");
});
it("uses known own entry for the primary action and supports the schema13 vote response", () => {
  expect(primaryContestAction(event, [{ ...work, mine: true }], now)).toBe(
    "查看我的作品",
  );
  expect(confirmedVote(work, true, 0, {}).votesUsed).toBe(1);
  expect(confirmedVote({ ...work, voted: true }, true, 1, {}).votesUsed).toBe(
    1,
  );
});
it("isolates archive filters from the current event and restores the home on system back", async () => {
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("历届赛事"));
  btn("历届赛事").click();
  await ready(() => root.querySelector("select"));
  const select = root.querySelector("select")!;
  select.value = "2025";
  select.dispatchEvent(new Event("change", { bubbles: true }));
  await ready(() =>
    bridge.request.mock.calls.some(
      (c) => c[0] === "contests.list" && c[1]?.year === 2025,
    ),
  );
  vm.requestBack();
  await nextTick();
  expect(root.textContent).toContain(event.title);
  btn("刷新").click();
  await ready(
    () =>
      bridge.request.mock.calls
        .filter((c) => c[0] === "contests.list")
        .at(-1)?.[1]?.year === 0,
  );
  expect(
    bridge.request.mock.calls
      .filter((c) => c[0] === "contests.list")
      .at(-1)?.[1]?.type,
  ).toBe("");
});
it("voting commits locally without a follow-up get, rejects rapid duplicate clicks and stays voted after back", async () => {
  event.submissionEnds = event.votingStarts = iso(-0.1);
  bridge.request.mockImplementation(async (a: string, b: any) =>
    a === "contests.vote"
      ? { entry: { ...work, voted: b.enabled }, votesUsed: b.enabled ? 1 : 0 }
      : a === "contests.list"
        ? { contests: [event] }
        : a === "contests.get"
          ? { contest: event, votesUsed: 0, myEntries: [] }
          : a === "contests.entries"
            ? { entries: [work] }
            : {},
  );
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("查看作品：" + work.title));
  btn("查看作品：" + work.title).click();
  await ready(() => btn("投一票"));
  const n = bridge.request.mock.calls.length;
  btn("投一票").click();
  btn("确认中…")?.click();
  await ready(() => btn("已投票 · 撤回"));
  expect(bridge.request.mock.calls.slice(n).map((c) => c[0])).toEqual([
    "contests.vote",
  ]);
  expect(root.textContent).toContain("还可投 2 / 3 票");
  vm.requestBack();
  await nextTick();
  btn("查看作品：" + work.title).click();
  await ready(() => btn("已投票 · 撤回"));
  btn("已投票 · 撤回").click();
  await ready(() => btn("投一票"));
  expect(root.textContent).toContain("还可投 3 / 3 票");
});
it("uses schema13 confirmation even when a hypothetical next detail read fails", async () => {
  event.submissionEnds = event.votingStarts = iso(-0.1);
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("查看作品：" + work.title));
  btn("查看作品：" + work.title).click();
  await ready(() => btn("投一票"));
  bridge.request.mockImplementation(async (a: string) => {
    if (a === "contests.vote") return {};
    throw Error("detail_offline");
  });
  btn("投一票").click();
  await ready(() => btn("已投票 · 撤回"));
  expect(root.textContent).not.toContain("detail_offline");
});
it("ended events initially request all entries and keep explicit winners filtering", async () => {
  event.state = "ended";
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("获奖作品"));
  expect(
    bridge.request.mock.calls.find((c) => c[0] === "contests.entries")?.[1]
      ?.winnersOnly,
  ).toBe(false);
  btn("获奖作品").click();
  await ready(() =>
    bridge.request.mock.calls.some(
      (c) => c[0] === "contests.entries" && c[1]?.winnersOnly === true,
    ),
  );
});
it("existing participants get their own work action without opening a second composer", async () => {
  work.mine = true;
  bridge.request.mockImplementation(async (a: string) =>
    a === "contests.list"
      ? { contests: [event] }
      : a === "contests.get"
        ? { contest: event, myEntries: [work] }
        : a === "contests.entries"
          ? { entries: [work] }
          : {},
  );
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("查看我的作品"));
  btn("查看我的作品").click();
  await ready(() => btn("编辑作品"));
  expect(root.querySelector("form")).toBeNull();
});
it("keeps draft text and existing images through background/unmount, then restores them under the same account only", async () => {
  work.mine = true;
  event.formats = ["mixed"];
  work.images = [
    {
      id: randomUUID(),
      url: "https://fixture.invalid/photo.jpg",
      width: 400,
      height: 300,
    },
  ];
  const key = `contest-v2:${owner}:${event.id}:${work.id}`;
  await mount(Composer, { owner, contest: event, entry: work });
  await ready(() => btn("预览作品") && !btn("预览作品").disabled);
  type("作品名称", "未完成的编辑");
  document.dispatchEvent(new Event("visibilitychange"));
  await ready(async () => !!(await readDraftRecord(key)));
  app!.unmount();
  app = undefined;
  root.remove();
  await new Promise((r) => setTimeout(r, 20));
  await mount(Composer, { owner, contest: event, entry: work });
  await ready(() => btn("恢复草稿"));
  btn("恢复草稿").click();
  await nextTick();
  expect(root.querySelector("input")!.value).toBe("未完成的编辑");
  expect(root.querySelector("img")?.src).toBe(work.images[0].url);
  await deleteDraftRecord(key);
});
it("retains one submission nonce when the server committed but the reply timed out", async () => {
  const submitted = vi.fn();
  let drops = 1;
  bridge.request.mockImplementation(async (a: string) => {
    if (a === "contests.submit") {
      if (drops--) throw Error("network_unavailable");
      return { entry: { ...work, mine: true } };
    }
    return {};
  });
  await mount(Composer, { owner, contest: event, onSubmitted: submitted });
  await ready(() => btn("预览作品") && !btn("预览作品").disabled);
  type("作品名称", work.title);
  type("作品内容", work.body);
  [...root.querySelectorAll("label")]
    .find((l) => l.textContent?.includes("我已阅读规则"))!
    .querySelector<HTMLInputElement>("input")!
    .click();
  await submitForm();
  await ready(() => btn("确认参赛"));
  btn("确认参赛").click();
  await ready(() => btn("重试并确认投稿"));
  btn("重试并确认投稿").click();
  await ready(() => submitted.mock.calls.length === 1);
  const calls = bridge.request.mock.calls.filter(
    (c) => c[0] === "contests.submit",
  );
  expect(calls).toHaveLength(2);
  expect(calls[0][1]).toEqual(calls[1][1]);
  expect(
    await readDraftRecord(`contest-v2:${owner}:${event.id}:new`),
  ).toBeUndefined();
});
it("a failed admin mutation never emits success and retry keeps identical request and stages", async () => {
  const saved = vi.fn();
  bridge.request
    .mockRejectedValueOnce(Error("network_unavailable"))
    .mockImplementation(async () => ({ contest: event }));
  await mount(Admin, { owner, backendSchema: 14, onSaved: saved });
  type("赛事名称", event.title);
  type("主题与介绍", event.description);
  await submitForm();
  await ready(() => btn("重试并确认"));
  expect(saved).not.toHaveBeenCalled();
  btn("重试并确认").click();
  await ready(() => saved.mock.calls.length === 1);
  const calls = bridge.request.mock.calls.filter(
    (c) => c[0] === "contests.save",
  );
  expect(calls[0][1]).toEqual(calls[1][1]);
});
it("new submission and withdrawal keep the primary action and wall correct through multiple system backs", async () => {
  bridge.request.mockImplementation(async (a: string, b: any) =>
    a === "contests.list"
      ? { contests: [event] }
      : a === "contests.get"
        ? { contest: event, myEntries: [] }
        : a === "contests.entries"
          ? { entries: [work] }
          : a === "contests.submit"
            ? {
                entry: {
                  ...work,
                  id: "my-entry",
                  title: b.title,
                  body: b.body,
                  mine: true,
                  memberId: owner,
                },
              }
            : {},
  );
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("我要参赛"));
  btn("我要参赛").click();
  await ready(() => btn("预览作品") && !btn("预览作品").disabled);
  type("作品名称", "我的新作品");
  type("作品内容", "我的校园生活");
  [...root.querySelectorAll("label")]
    .find((l) => l.textContent?.includes("我已阅读规则"))!
    .querySelector<HTMLInputElement>("input")!
    .click();
  await submitForm();
  await ready(() => btn("确认参赛"));
  btn("确认参赛").click();
  await ready(() => btn("编辑作品"));
  vm.requestBack();
  await ready(() => btn("查看我的作品"));
  btn("查看我的作品").click();
  await ready(() => btn("撤回作品"));
  btn("撤回作品").click();
  await ready(() => root.querySelector("dialog[open]"));
  const dialog = root.querySelector("dialog[open]")!;
  [...dialog.querySelectorAll<HTMLButtonElement>("button")]
    .find((b) => b.textContent?.trim() === "撤回作品")!
    .click();
  await ready(() => btn("我要参赛"));
  expect([...root.querySelectorAll(".ct-work-open")].length).toBe(1);
  expect(root.textContent).not.toContain("我的新作品");
});
it("late submission cleanup cannot delete a newer draft using the same account/event key", async () => {
  const key = `contest-v2:${owner}:${event.id}:new`;
  await writeDraftRecord(key, {
    requestId: "new-request",
    title: "重新开始的草稿",
  });
  await deleteDraftRecord(key, "old-request");
  expect((await readDraftRecord<{ title: string }>(key))?.title).toBe(
    "重新开始的草稿",
  );
  await deleteDraftRecord(key, "new-request");
  expect(await readDraftRecord(key)).toBeUndefined();
});
it("management loads work moderation on demand and applies the confirmed restore without reloading entries", async () => {
  work.status = "removed";
  const updated = vi.fn(),
    opened = vi.fn();
  bridge.request.mockImplementation(async (a: string) => {
    if (a === "contests.admin")
      return {
        metrics: { validEntries: work.status === "approved" ? 1 : 0 },
        votes: [],
        awards: [],
        audit: [],
      };
    if (a === "contests.entries") return { entries: [work] };
    if (a === "contests.review") {
      work = { ...work, status: "approved" };
      return { contest: event, entry: work };
    }
    return {};
  });
  await mount(Management, {
    owner,
    contest: event,
    onUpdated: updated,
    onWork: opened,
  });
  await ready(() => btn("刷新统计") && !btn("刷新统计").disabled);
  expect(
    bridge.request.mock.calls.some((c) => c[0] === "contests.entries"),
  ).toBe(false);
  const fold = [...root.querySelectorAll("details")].find(
    (d) => d.querySelector("summary")?.textContent === "作品审核",
  )!;
  fold.open = true;
  fold.dispatchEvent(new Event("toggle"));
  await ready(() => btn("恢复作品"));
  btn("查看作品").click();
  expect(opened).toHaveBeenCalledWith(expect.objectContaining({ id: work.id }));
  btn("恢复作品").click();
  await ready(() => root.querySelector("dialog[open]"));
  const reason = root.querySelector<HTMLTextAreaElement>("dialog textarea")!;
  reason.value = "已核实为原创";
  reason.dispatchEvent(new Event("input", { bubbles: true }));
  await nextTick();
  btn("确认处理").click();
  await ready(() => btn("下架作品"));
  expect(updated).toHaveBeenCalledTimes(1);
  expect(
    bridge.request.mock.calls.filter((c) => c[0] === "contests.entries"),
  ).toHaveLength(1);
});
it("failed moderation keeps its dialog and nonce and never announces a successful mutation", async () => {
  let fail = true;
  const updated = vi.fn();
  bridge.request.mockImplementation(async (a: string) => {
    if (a === "contests.admin")
      return { metrics: { validEntries: 1 }, votes: [], awards: [], audit: [] };
    if (a === "contests.entries") return { entries: [work] };
    if (a === "contests.review") {
      if (fail) throw Error("network_unavailable");
      return { contest: event, entry: { ...work, status: "removed" } };
    }
    return {};
  });
  await mount(Management, { owner, contest: event, onUpdated: updated });
  await ready(() => btn("刷新统计") && !btn("刷新统计").disabled);
  const fold = [...root.querySelectorAll("details")].find(
    (d) => d.querySelector("summary")?.textContent === "作品审核",
  )!;
  fold.open = true;
  fold.dispatchEvent(new Event("toggle"));
  await ready(() => btn("下架作品"));
  btn("下架作品").click();
  await ready(() => root.querySelector("dialog[open]"));
  const reason = root.querySelector<HTMLTextAreaElement>("dialog textarea")!;
  reason.value = "核对作品授权";
  reason.dispatchEvent(new Event("input", { bubbles: true }));
  await nextTick();
  btn("确认处理").click();
  vm.requestBack();
  await ready(() => root.querySelector(".ct-error"));
  expect(root.querySelector("dialog[open]")).not.toBeNull();
  expect(updated).not.toHaveBeenCalled();
  expect(root.textContent).not.toContain("处理已确认");
  fail = false;
  btn("确认处理").click();
  await ready(() => btn("恢复作品"));
  const calls = bridge.request.mock.calls.filter(
    (c) => c[0] === "contests.review",
  );
  expect(calls[0][1]).toEqual(calls[1][1]);
});
it("switching a captioned original post to direct image-only submission clears text that the form cannot edit", async () => {
  event.formats = ["image"];
  const key = `contest-v2:${owner}:${event.id}:new`;
  await writeDraftRecord(key, {
    title: "图片作品",
    body: "原帖附带的文字",
    postId: work.id,
    linked: true,
    kept: [
      {
        id: randomUUID(),
        url: "https://fixture.invalid/image.jpg",
        width: 400,
        height: 300,
      },
    ],
    photos: [],
    share: false,
    agreed: true,
    requestId: randomUUID(),
    savedAt: Date.now(),
  });
  await mount(Composer, { owner, contest: event });
  await ready(() => btn("恢复草稿"));
  btn("恢复草稿").click();
  await ready(() => btn("改为直接投稿"));
  btn("改为直接投稿").click();
  document.dispatchEvent(new Event("visibilitychange"));
  await ready(
    async () => (await readDraftRecord<{ body: string }>(key))?.body === "",
  );
  expect(root.querySelector("input[type=file]")).not.toBeNull();
  await deleteDraftRecord(key);
});
it("an upload finishing after unmount cannot overwrite a newer draft or automatically submit the old account work", async () => {
  event.formats = ["image"];
  const key = `contest-v2:${owner}:${event.id}:new`;
  await writeDraftRecord(key, {
    title: "上传中的作品",
    body: "",
    postId: null,
    linked: false,
    kept: [],
    photos: [{ id: randomUUID(), data: "YQ==", width: 1, height: 1 }],
    share: false,
    agreed: true,
    requestId: randomUUID(),
    savedAt: Date.now(),
  });
  let release!: (r: object) => void;
  bridge.request.mockImplementation((a: string) =>
    a === "media.upload"
      ? new Promise((r) => (release = r))
      : Promise.resolve({}),
  );
  await mount(Composer, { owner, contest: event });
  await ready(() => btn("恢复草稿"));
  btn("恢复草稿").click();
  await ready(() => btn("预览作品"));
  await submitForm();
  await ready(() => btn("确认参赛"));
  btn("确认参赛").click();
  await ready(() => !!release);
  vm.requestBack();
  await nextTick();
  expect(btn("正在确认…")).toBeTruthy();
  app!.unmount();
  app = undefined;
  await new Promise((r) => setTimeout(r, 30));
  await writeDraftRecord(key, { requestId: "new-draft", title: "新的作品" });
  release({ image: { id: randomUUID(), width: 1, height: 1 } });
  await new Promise((r) => setTimeout(r, 40));
  expect(
    bridge.request.mock.calls.some((c) => c[0] === "contests.submit"),
  ).toBe(false);
  expect((await readDraftRecord<{ requestId: string }>(key))?.requestId).toBe(
    "new-draft",
  );
  await deleteDraftRecord(key);
});
it("an upcoming preview opens the complete theme and rules instead of pointing to an empty work wall", async () => {
  event.startsAt = iso(2);
  event.description = "完整主题介绍".repeat(40);
  await mount(Hub, { user: { id: owner } });
  await ready(() => btn("查看预告"));
  btn("查看预告").click();
  await nextTick();
  const rules = root.querySelector<HTMLDetailsElement>("#contest-rules")!;
  expect(rules.open).toBe(true);
  expect(rules.textContent).toContain(event.description);
});

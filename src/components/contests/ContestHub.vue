<script setup lang="ts">
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
  nextTick,
} from "vue";
import { Trophy, ChevronRight, Plus, ArchiveRestore } from "lucide-vue-next";
import {
  contestRequest,
  contestStage,
  contestRemaining,
  contestLabels,
  type Contest,
  type ContestEntry,
  type ContestResult,
} from "../../services/contests";
import { treeholeError, type TreeholeUser } from "../../services/treehole";
import { confirmedVote } from "../../domain/contests";
import ContestDetail from "./ContestDetail.vue";
import ContestWorkDetail from "./ContestWorkDetail.vue";
import ContestComposer from "./ContestComposer.vue";
import ContestArchive from "./ContestArchive.vue";
import ContestAdmin from "./ContestAdmin.vue";
import ContestManagement from "./ContestManagement.vue";
import ContestThemes from "./ContestThemes.vue";
import ContestRecycleBin from "./ContestRecycleBin.vue";
import ContestDialog from "./ContestDialog.vue";
import "./contests.css";
const props = defineProps<{
  user: TreeholeUser;
  compact?: boolean;
  initialId?: string;
  initialEntryId?: string;
  backendSchema?: number;
  restore?: Record<string, any>;
}>();
const emit = defineEmits<{
  open: [id?: string];
  profile: [id: string];
  post: [id: string];
  image: [entry: ContestEntry, index: number];
  heading: [title: string];
}>();
type Page =
  | "trash"
  | "home"
  | "detail"
  | "entry"
  | "compose"
  | "archive"
  | "admin"
  | "create"
  | "edit"
  | "manage"
  | "themes";
const view = ref<Page>("home"),
  contests = ref<Contest[]>([]),
  managed = ref<Contest[]>([]),
  managementMore = ref(false),
  preview = ref(false),
  selected = ref<Contest>(),
  entries = ref<ContestEntry[]>([]),
  mine = ref<ContestEntry[]>([]),
  entry = ref<ContestEntry>(),
  editing = ref<ContestEntry>();
const votesUsed = ref(0),
  winners = ref(false),
  more = ref(false),
  moreContests = ref(false),
  adminBusy = ref(false),
  loading = ref(false),
  wallLoading = ref(false),
  mineReady = ref(true),
  pendingVote = ref(false),
  error = ref(""),
  notice = ref(""),
  now = ref(Date.now());
const child = ref<{ requestBack: () => boolean }>();
const admin = computed(() => props.user.badges?.official?.code === "developer");
const seed =
  props.restore?.owner === props.user.id &&
  typeof props.restore.seed === "string"
    ? props.restore.seed
    : crypto.randomUUID();
let live = true,
  epoch = 0,
  offset = 0,
  lastId = "";
let requestedEntry:ContestEntry|undefined;
const head = computed(
  () =>
    contests.value.find(
      (c) =>
        !["ended", "cancelled", "draft"].includes(
          contestStage(c, now.value + offset),
        ),
    ) || contests.value.find((c) => c.state === "ended"),
);
const current = computed(()=>contests.value.find(c=>!["ended","cancelled","draft"].includes(contestStage(c,now.value+offset))));
const compactAction = computed(() => {
  const contest = current.value;
  if (!contest || contest.paused) return "查看赛事";
  const phase = contestStage(contest, now.value + offset);
  if (phase === "submitting") return "去投稿";
  if (phase === "voting") return "去投票";
  return phase === "upcoming" ? "查看预告" : "查看赛事";
});
const history: Record<string, any>[] = [];
const title = computed(
  () =>
    ({
      trash: "赛事回收站",
      home: "主题赛事",
      detail: "主题赛事",
      entry: "作品详情",
      compose: editing.value ? "编辑作品" : "我要参赛",
      archive: "历届赛事",
      admin: "赛事管理",
      create: "创建赛事",
      edit: "编辑赛事",
      manage: "管理比赛",
      themes: "主题征集",
    })[view.value],
);
watch(
  title,
  (t) => {
    if (!props.compact) emit("heading", t);
  },
  { immediate: true },
);
const clock = setInterval(() => (now.value = Date.now()), 60000);
onBeforeUnmount(() => {
  live = false;
  epoch++;
  clearInterval(clock);
});
function routeSnapshot() {
  return {
    owner: props.user.id,
    seed,
    preview: preview.value,
    view: view.value,
    selected: selected.value,
    entries: entries.value,
    mine: mine.value,
    entry: entry.value,
    votesUsed: votesUsed.value,
    winners: winners.value,
    more: more.value,
    mineReady: mineReady.value,
    contests: contests.value,
    moreContests: moreContests.value,
    offset,
    scroll: window.scrollY,
  };
}
function snapshot() {
  return { ...routeSnapshot(), history: [...history] };
}
function restore(s: Record<string, any>) {
  view.value = s.view;
  preview.value = !!s.preview;
  selected.value = s.selected;
  entries.value = s.entries || [];
  mine.value = s.mine || [];
  entry.value = s.entry;
  votesUsed.value = s.votesUsed || 0;
  winners.value = !!s.winners;
  more.value = !!s.more;
  mineReady.value = s.mineReady !== false;
  contests.value = s.contests || contests.value;
  moreContests.value = !!s.moreContests;
  offset = s.offset || 0;
}
function go(next: Page) {
  history.push(routeSnapshot());
  if (history.length > 20) history.shift();
  view.value = next;
  notice.value = "";
  error.value = "";
  void nextTick(() => window.scrollTo({ top: 0, behavior: "instant" }));
}
async function call(
  action: string,
  body: Record<string, unknown> = {},
  fresh = false,
) {
  const owner = props.user.id,
    sequence = epoch;
  const r = await contestRequest(owner, action, body, fresh);
  if (
    !live ||
    (sequence !== epoch &&
      ["contests.list", "contests.get", "contests.entries"].includes(action)) ||
    owner !== props.user.id
  )
    throw Error("contest_account_changed");
  if (r.serverTime)
    offset = Date.parse(r.serverTime) - (r.receivedAt || Date.now());
  return r;
}
function showError(e: unknown) {
  const message = (e as Error)?.message;
  if (
    live &&
    !["contest_account_changed", "contest_stale_response"].includes(message)
  )
    error.value = treeholeError(e);
}
async function run(work: () => Promise<void>) {
  error.value = "";
  try {
    await work();
  } catch (e) {
    showError(e);
  }
}
async function list(fresh = false, append = false) {
  const r = await call(
    "contests.list",
    { scope:"public", offset: append ? contests.value.length : 0, type: "", year: 0 },
    fresh,
  );
  moreContests.value = (r.contests?.length || 0) > 20;
  contests.value = [
    ...new Map(
      [
        ...(append ? contests.value : []),
        ...(r.contests || []).slice(0, 20),
      ].map((c) => [c.id, c]),
    ).values(),
  ];
}
async function wall(append = false, fresh = false) {
  if (!selected.value) return;
  const cid = selected.value.id,
    mode = winners.value;
  wallLoading.value = true;
  try {
    const r = await call(
      "contests.entries",
      {
        contestId: cid,
        view:"public",
        ...(preview.value?{preview:true}:{}),
        seed,
        winnersOnly: mode,
        offset: 0,
        afterId: append ? entries.value.at(-1)?.id : null,
      },
      fresh,
    );
    if (selected.value?.id !== cid || winners.value !== mode) return;
    more.value = (r.entries?.length || 0) > 20;
    const rows = (r.entries || []).slice(0, 20).filter(e=>!preview.value||e.status==="approved");
    entries.value = [
      ...new Map(
        [...(append ? entries.value : []), ...rows].map((e) => [e.id, e]),
      ).values(),
    ];
  } finally {
    wallLoading.value = false;
  }
}
async function loadLegacyOwnWorks(contest: Contest, fresh: boolean) {
  const activeWorks: ContestEntry[] = [];
  let afterId: string | undefined;
  do {
    const result = await call(
      "contests.entries",
      { contestId: contest.id, seed, mine: true, afterId },
      fresh,
    );
    const page = result.entries || [];
    const rows = page.slice(0, 20);
    activeWorks.push(...rows.filter((work) => work.status === "approved"));
    afterId = page.length > 20 ? rows[19]?.id : undefined;
  } while (afterId && activeWorks.length < contest.maxEntries);

  if (selected.value?.id === contest.id) {
    mine.value = activeWorks;
    mineReady.value = true;
  }
}
async function loadEvent(id: string, fresh = false) {
  lastId = id;
  loading.value = true;
  if (selected.value?.id !== id) {
    selected.value = undefined;
    entries.value = [];
    mine.value = [];
  }
  try {
    const r = await call("contests.get", { contestId: id,view:"public",...(preview.value?{preview:true}:{}),...(props.initialEntryId?{entryId:props.initialEntryId}:{}) }, fresh);
    if (!r.contest) throw Error("invalid_response");
    selected.value = r.contest;
    requestedEntry=r.entry;
    votesUsed.value = r.votesUsed || 0;
    mineReady.value =
      preview.value ||
      r.myEntries !== undefined ||
      contestStage(r.contest, now.value + offset) !== "submitting";
    mine.value = preview.value ? [] : r.myEntries || [];
    winners.value = false;
    await Promise.all([
      wall(false, fresh),
      mineReady.value
        ? Promise.resolve()
        : loadLegacyOwnWorks(r.contest, fresh),
    ]);
  } finally {
    loading.value = false;
  }
}
async function home(fresh = false) {
  loading.value = true;
  try {
    await list(fresh);
    if (head.value) await loadEvent(head.value.id, fresh);
  } finally {
    loading.value = false;
  }
}
function open(id: string, awardOnly = false) {
  go("detail");
  void run(async () => {
    await loadEvent(id);
    if (awardOnly && selected.value?.state === "ended") {
      winners.value = true;
      await wall();
    }
  });
}
function openWork(work: ContestEntry) {
  go("entry");
  entry.value = work;
}
function compose(work?: ContestEntry) {
  editing.value = work;
  go("compose");
}
async function primary() {
  if (!selected.value || preview.value) return;
  const phase = contestStage(selected.value, now.value + offset);
  if (phase === "submitting") {
    if (!mineReady.value) {
      await run(() => loadEvent(selected.value!.id, true));
      return;
    }
    const own = mine.value.filter((work) => work.status === "approved");
    if (own.length > 1) scrollToSection("contest-own-works");
    else if (own.length === 1) openWork(own[0]);
    else compose();
  } else if (phase === "upcoming" || phase === "draft") {
    const rules = document.getElementById(
      "contest-rules",
    ) as HTMLDetailsElement | null;
    if (rules) {
      rules.open = true;
      rules.scrollIntoView({
        behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth",
      });
    }
  } else scrollToSection("contest-wall");
}
function scrollToSection(id: string) {
  document.getElementById(id)?.scrollIntoView({
    behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
      ? "auto"
      : "smooth",
  });
}
function composeAnother() {
  const contest = selected.value;
  if (!contest || preview.value || contest.paused || !mineReady.value) return;
  if (contestStage(contest, now.value + offset) !== "submitting") return;
  const used = mine.value.filter((work) => work.status === "approved").length;
  if (used < contest.maxEntries) compose();
}
function applyEntry(work: ContestEntry) {
  for (const previous of history) {
    if (previous.selected?.id === work.contestId) {
      previous.entries = (previous.entries || []).map((e: ContestEntry) =>
        e.id === work.id ? work : e,
      );
      if (previous.entry?.id === work.id) previous.entry = work;
      previous.votesUsed = votesUsed.value;
    }
  }
  if (entry.value?.id === work.id) entry.value = work;
  entries.value = entries.value.map((e) => (e.id === work.id ? work : e));
  if (work.mine) {
    mine.value = [work, ...mine.value.filter((e) => e.id !== work.id)];
  }
}
function updateEvent(contest: Contest) {
  managed.value=managed.value.map(c=>c.id===contest.id?contest:c);
  selected.value = contest;
  contests.value = contests.value.map((c) =>
    c.id === contest.id ? contest : c,
  );
  for (const previous of history) {
    if (previous.selected?.id === contest.id) previous.selected = contest;
    previous.contests = contests.value;
  }
}
function syncOwnWork() {
  if (!selected.value) return;
  for (const previous of history) {
    if (previous.selected?.id === selected.value.id) {
      previous.mine = [...mine.value];
      if (!previous.winners) previous.entries = [...entries.value];
    }
  }
}
function submitted(work: ContestEntry) {
  const was = mine.value.some((e) => e.id === work.id);
  applyEntry(work);
  entry.value = work;
  if (!entries.value.some((e) => e.id === work.id)) entries.value.unshift(work);
  if (selected.value && !was) {
    updateEvent({
      ...selected.value,
      entryCount: selected.value.entryCount + 1,
      participantCount:
        selected.value.participantCount + (mine.value.length === 1 ? 1 : 0),
    });
  }
  syncOwnWork();
  if (history.at(-1)?.view === "entry" && history.at(-1)?.entry?.id === work.id)
    history.pop();
  view.value = "entry";
  void nextTick(() => window.scrollTo({ top: 0, behavior: "instant" }));
  notice.value = editing.value ? "作品已保存" : "参赛成功，期待同学们的喜欢";
  editing.value = undefined;
}
async function vote() {
  if (preview.value || pendingVote.value || !entry.value || !selected.value) return;
  const before = entry.value,
    cid = selected.value.id,
    enabled = !before.voted,
    used = votesUsed.value;
  pendingVote.value = true;
  error.value = "";
  try {
    const r = await call("contests.vote", {
      contestId: cid,
      entryId: before.id,
      enabled,
    });
    const committed = confirmedVote(before, enabled, used, r);
    if (selected.value?.id === cid) {
      votesUsed.value = committed.votesUsed;
      applyEntry(committed.entry);
      if (view.value === "entry" && entry.value?.id === before.id) {
        notice.value = committed.entry.voted
          ? "这一票，已送达"
          : "已撤回，可以重新选择";
      }
    }
  } catch (e) {
    showError(e);
  } finally {
    pendingVote.value = false;
  }
}
const confirmation = ref<{
  kind: "withdraw" | "report";
  entry: ContestEntry;
}>();
const reportReason = ref(""),
  confirmBusy = ref(false);
async function confirm() {
  if (preview.value || !confirmation.value || !selected.value || confirmBusy.value) return;
  const op = confirmation.value;
  confirmBusy.value = true;
  try {
    if (op.kind === "withdraw") {
      await call("contests.withdraw", {
        contestId: selected.value.id,
        entryId: op.entry.id,
      });
      mine.value = mine.value.filter((e) => e.id !== op.entry.id);
      entries.value = entries.value.filter((e) => e.id !== op.entry.id);
      updateEvent({
        ...selected.value,
        entryCount: Math.max(0, selected.value.entryCount - 1),
        participantCount: Math.max(
          0,
          selected.value.participantCount - (mine.value.length ? 0 : 1),
        ),
      });
      syncOwnWork();
      confirmation.value = undefined;
      popRoute();
      notice.value = "作品已撤回，截止前可以重新投稿。";
    } else {
      if (reportReason.value.trim().length < 2) return;
      await call("contests.report", {
        contestId: selected.value.id,
        entryId: op.entry.id,
        reason: reportReason.value,
      });
      confirmation.value = undefined;
      notice.value = "举报已提交，开发者会处理。";
    }
  } catch (e) {
    showError(e);
  } finally {
    confirmBusy.value = false;
  }
}
async function finishAdmin(id: string, known?: Contest) {
  const r = known
    ? { contest: known }
    : await call("contests.get", { contestId: id }, true);
  if (!r.contest) throw Error("invalid_response");
  selected.value = r.contest;
  managed.value=[r.contest,...managed.value.filter(c=>c.id!==id)];
  contests.value = [r.contest, ...contests.value.filter((c) => c.id !== id)];
  if (history.at(-1)?.view === "manage") history.pop();
  view.value = "manage";
  notice.value = "赛事已保存";
  void nextTick(() => window.scrollTo({ top: 0, behavior: "instant" }));
}
async function adminList(append = false, fresh = false) {
  if (adminBusy.value) return;
  adminBusy.value = true;
  try {
    const r = await call("contests.list", { scope: "manage", offset: append ? managed.value.length : 0 }, fresh);
    if (view.value !== "admin") return;
    managementMore.value = (r.contests?.length || 0) > 20;
    managed.value = [...(append ? managed.value : []), ...(r.contests || []).slice(0, 20)];
  } finally {
    adminBusy.value = false;
  }
}
function adminHome() {
  go("admin");
  void run(() => adminList());
}
async function openPreview(){
  if(!selected.value)return;
  const id=selected.value.id;go("detail");preview.value=true;
  await run(()=>loadEvent(id));
}
function endPreview(){preview.value=false;popRoute();}
async function removed(contest: Contest) {
  managed.value = managed.value.filter((item) => item.id !== contest.id);
  contests.value = contests.value.filter((item) => item.id !== contest.id);
  for (const previous of history) {
    previous.contests = previous.contests?.filter((item: Contest) => item.id !== contest.id);
    if (previous.selected?.id === contest.id) previous.selected = undefined;
  }
  if (history.at(-1)?.view === "admin") popRoute();
  else view.value = "admin";
  selected.value = undefined;
  notice.value = contest.visibility === "hidden" ? "赛事已下架，可在回收站恢复。" : "赛事已移入回收站。";
  await run(() => adminList(false, true));
}
function restored() {
  if (history.at(-1)?.view === "trash") popRoute();
  notice.value = "赛事已恢复。";
}
function manage() {
  go("manage");
}
function openManage(id: string) {
  go("manage");
  selected.value = undefined;
  loading.value = true;
  void run(async () => {
    try {
      const r = await call("contests.get", { contestId: id });
      if (!r.contest) throw Error("invalid_response");
      selected.value = r.contest;
    } finally {
      loading.value = false;
    }
  });
}
function popRoute() {
  epoch++;
  loading.value = false;
  wallLoading.value = false;
  error.value = "";
  notice.value = "";
  const previous = history.pop();
  if (previous) {
    restore(previous);
    void nextTick(() =>
      window.scrollTo({ top: previous.scroll || 0, behavior: "instant" }),
    );
    return true;
  }
  if (view.value !== "home") {
    view.value = "home";
    void run(() => home());
    return true;
  }
  return false;
}
function requestBack() {
  if (confirmation.value) {
    if (!confirmBusy.value) confirmation.value = undefined;
    return true;
  }
  if (child.value?.requestBack()) return true;
  return popRoute();
}
function refresh() {
  return run(() => view.value === "admin" ? adminList(false, true) :
    view.value === "home" || !selected.value ? home(true) : loadEvent(selected.value.id, true));
}
defineExpose({ requestBack, snapshot, refresh });
onMounted(() => {
  if (props.restore?.owner === props.user.id && !props.compact) {
    restore(props.restore);
    history.push(...(props.restore.history || []));
    return;
  }
  void run(async () => {
    if (props.compact) {
      await list();
      return;
    }
    if(props.initialId){
      await list();go("detail");await loadEvent(props.initialId);
      if(props.initialEntryId){const found=requestedEntry||entries.value.find(e=>e.id===props.initialEntryId);if(found)openWork(found);else notice.value="已打开获奖比赛，可在作品墙中查看完整记录。";}
    } else await home();
  });
});
</script>
<template>
  <button v-if="compact" class="contest-entry ct-compact" :class="{'ct-compact-empty':!current}" @click="emit('open',current?.id)" :aria-label="current?'校园赛事：'+current.title:'校园赛事，查看赛事'">
    <Trophy :size="18" aria-hidden="true"/>
    <span v-if="current" class="ct-entry-copy"><strong>{{current.title}}</strong><small>{{current.paused?'已暂停':contestLabels[contestStage(current,now+offset)]}}<span v-if="!current.paused && contestRemaining(current,now+offset)"> · {{contestRemaining(current,now+offset)}}</span></small></span>
    <strong v-else class="ct-entry-label">校园赛事</strong>
    <span class="ct-entry-action">{{ compactAction }}<ChevronRight :size="15"/></span>
  </button>
  <section v-else class="ct" :aria-busy="loading">
    <div v-if="preview" class="ct-preview-bar" role="status"><span>普通用户视角 · 只读预览</span><button class="ct-link" @click="endPreview">结束预览</button></div>
    <p v-if="error" class="ct-error" role="alert">
      {{ error
      }}<button
        v-if="!['compose', 'create', 'edit'].includes(view)"
        class="ct-link"
        @click="refresh"
      >
        重试
      </button>
    </p>
    <p v-if="notice" class="ct-notice" role="status">{{ notice }}</p>
    <template v-if="view === 'home' || view === 'detail'"
      ><div v-if="admin && !preview" class="ct-toolbar">
        <button v-if="admin && !preview" class="ct-link" @click="adminHome">
          赛事管理</button
        >
      </div>
      <ContestDetail
        v-if="selected"
        :contest="selected"
        :entries="entries"
        :mine="mine"
        :mine-ready="mineReady"
        :legacy-eligibility="(backendSchema || 13) < 14"
        :now="now + offset"
        :votes-used="votesUsed"
        :more="more"
        :loading="wallLoading"
        :winners="winners"
        :admin="false"
        :readonly="preview"
        @primary="primary"
        @compose="composeAnother"
        @entry="openWork"
        @more="run(() => wall(true))"
        @filter="
          winners = $event;
          run(() => wall(false, true));
        "
        @manage="manage" />
      <p v-else-if="loading" class="ct-loading" role="status">正在打开比赛…</p>
      <div v-else class="ct-empty">
        <h3>暂时没有正在进行的赛事</h3>
        <p>
          新比赛发布后会出现在这里，历届作品仍可随时回看。
        </p>
      </div>
      <footer class="ct-footer-links">
        <button @click="go('archive')">
          <Trophy :size="17" />历届赛事<ChevronRight :size="16" /></button
        ><button @click="go('themes')">
          下一期主题征集<ChevronRight :size="16" />
        </button></footer></template
    ><ContestWorkDetail
      v-else-if="view === 'entry' && selected && entry"
      :entry="entry"
      :contest="selected"
      :now="now + offset"
      :votes-used="votesUsed"
      :pending="pendingVote"
      :readonly="preview"
      @vote="vote"
      @edit="compose(entry)"
      @withdraw="confirmation = { kind: 'withdraw', entry }"
      @report="
        confirmation = { kind: 'report', entry };
        reportReason = '';
      "
      @profile="emit('profile', entry.memberId)"
      @post="entry.postId && emit('post', entry.postId)"
      @image="emit('image', entry, $event)"
    /><ContestComposer
      v-else-if="view === 'compose' && selected"
      ref="child"
      :owner="user.id"
      :contest="selected"
      :entry="editing"
      @submitted="submitted"
      @close="popRoute"
    /><KeepAlive
      ><ContestArchive
        v-if="view === 'archive'"
        :owner="user.id"
        @open="open" /></KeepAlive
    ><template v-if="view === 'admin' && admin">
      <div class="ct-manage-actions ct-admin-actions">
        <button class="ct-primary" @click="go('create')"><Plus :size="17" aria-hidden="true" />创建赛事</button>
        <button v-if="(backendSchema || 13) >= 15" class="ct-secondary" @click="go('trash')"><ArchiveRestore :size="17" aria-hidden="true" />回收站</button>
      </div>
      <p v-if="adminBusy && !managed.length" class="ct-loading" role="status">正在读取赛事…</p>
      <p v-else-if="!managed.length && !error" class="ct-subtitle">暂无赛事</p>
      <button
        v-for="c in managed"
        :key="c.id"
        class="ct-row"
        @click="openManage(c.id)"
      >
        <span class="ct-row-copy"
          ><h3>{{ c.title }}</h3>
          <small
            >{{ contestLabels[c.state] }} · {{ c.entryCount }}件作品</small
          ></span
        ><ChevronRight :size="17" /></button
      ><button
        v-if="managementMore"
        class="ct-secondary ct-more"
        :disabled="adminBusy"
        @click="run(() => adminList(true))"
      >
        更多管理赛事</button
      ><p v-if="(backendSchema || 13) < 15" class="ct-subtitle">赛事清理与回收站将在后台升级后启用。</p><button class="ct-link" @click="go('themes')">
        管理主题征集
      </button></template
    ><ContestAdmin
      v-if="(view === 'create' || view === 'edit') && admin"
      ref="child"
      :owner="user.id"
      :contest="view === 'edit' ? selected : undefined"
      :backend-schema="backendSchema"
      @saved="(id, c) => run(() => finishAdmin(id, c))"
      @close="popRoute"
    /><KeepAlive><ContestManagement
      v-if="view === 'manage' && selected && admin"
      ref="child"
      :key="selected.id"
      :owner="user.id"
      :contest="selected"
      :backend-schema="backendSchema"
      @preview="openPreview"
      @removed="removed"
      @restored="restored"
      @updated="updateEvent"
      @edit="go('edit')"
      @work="openWork"
    /></KeepAlive><ContestRecycleBin v-if="view==='trash' && admin" :owner="user.id" @open="openManage"/><ContestThemes
      v-if="view === 'themes'"
      ref="child"
      :owner="user.id"
      :admin="admin"
      :legacy-contest-id="contests[0]?.id"
      :backend-schema="backendSchema"
    /><ContestDialog
      :open="!!confirmation"
      :title="
        confirmation?.kind === 'withdraw' ? '撤回这件作品？' : '举报这件作品'
      "
      :busy="confirmBusy"
      :danger="confirmation?.kind === 'withdraw'"
      :confirm="confirmation?.kind === 'withdraw' ? '撤回作品' : '提交举报'"
      @cancel="confirmation = undefined"
      @confirm="confirm"
      ><p>
        {{
          confirmation?.kind === "withdraw"
            ? "撤回后将从公开展示中移除，保留本人的投稿记录。截止前可以重新投稿。"
            : "请说明不符合规则的地方，开发者会据此审核。"
        }}
      </p>
      <label v-if="confirmation?.kind === 'report'" class="ct-form"
        >举报原因<textarea
          style="resize: none"
          v-model="reportReason"
          rows="3"
          maxlength="300"
        />
      </label>
      <p v-if="error" role="alert">{{ error }}</p></ContestDialog
    >
  </section>
</template>
<style scoped>
.contest-entry.ct-compact{width:100%;display:flex;align-items:center;gap:10px;text-align:left;padding:12px;margin:4px 0 10px;border:1px solid var(--color-border);border-radius:12px;background:var(--color-surface);color:var(--color-muted);min-height:76px;box-sizing:border-box}
.ct-entry-copy{display:grid;gap:4px;flex:1;min-width:0}.ct-entry-copy strong{font-size:14px;line-height:1.4;color:var(--color-text);display:-webkit-box;-webkit-line-clamp:1;-webkit-box-orient:vertical;overflow:hidden}.ct-entry-copy small{font-size:11px;line-height:1.5}.ct-entry-action{display:flex;align-items:center;gap:3px;font-size:12px;flex:none;background:var(--color-background);border-radius:8px;min-height:36px;padding:0 10px;color:var(--color-text)}.contest-entry.ct-compact.ct-compact-empty{min-height:48px;padding:2px 12px}.ct-entry-label{flex:1;font-size:13px;color:var(--color-text)}.ct-compact-empty .ct-entry-action{background:transparent;color:var(--color-muted)}.ct-compact:hover{background:var(--color-background)}
</style>

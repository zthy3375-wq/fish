<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from "vue";
import {
  contestRequest,
  contestLabels,
  awardLabels,
  type Contest,
  type ContestResult,
  type ContestEntry,
} from "../../services/contests";
import { contestDate } from "../../domain/contests";
import { treeholeError,treeholeErrorCode } from "../../services/treehole";
import ContestDialog from "./ContestDialog.vue";
const props = defineProps<{ owner: string; contest: Contest; backendSchema?:number }>();
const emit = defineEmits<{
  updated: [contest: Contest];
  edit: [];
  work: [entry: ContestEntry];
  preview: [];
  removed: [contest:Contest];
}>();
const data = ref<ContestResult>({}),
  error = ref(""),
  notice = ref(""),
  busy = ref(false),
  offset = ref(0),
  more = ref(false);
let alive = true;
onBeforeUnmount(() => (alive = false));
const operation = ref<{
  action: string;
  body: Record<string, unknown>;
  title: string;
  danger: boolean;
}>();
const reason = ref("");
const works = ref<ContestEntry[]>([]),
  worksLoaded = ref(false),
  moreWorks = ref(false),
  workSeed = crypto.randomUUID();
async function loadWorks(append = false) {
  const r = await contestRequest(
    props.owner,
    "contests.entries",
    {
      contestId: props.contest.id,
      seed: workSeed,
      afterId: append ? works.value.at(-1)?.id : null,
    },
    true,
  );
  if (!alive) return;
  moreWorks.value = (r.entries?.length || 0) > 20;
  works.value = [
    ...new Map(
      [...(append ? works.value : []), ...(r.entries || []).slice(0, 20)].map(
        (e) => [e.id, e],
      ),
    ).values(),
  ];
  worksLoaded.value = true;
}
function openWorks(event: Event) {
  if ((event.target as HTMLDetailsElement).open && !worksLoaded.value)
    void run(() => loadWorks());
}
async function load(append = false) {
  const r = await contestRequest(
    props.owner,
    "contests.admin",
    { contestId: props.contest.id, offset: append ? offset.value + 20 : 0 },
    true,
  );
  if (!alive) return;
  more.value = [r.votes, r.awards, r.audit].some((x) => (x?.length || 0) > 20);
  offset.value = append ? offset.value + 20 : 0;
  data.value = {
    ...r,
    votes: [
      ...(append ? data.value.votes || [] : []),
      ...(r.votes || []).slice(0, 20),
    ],
    awards: [
      ...(append ? data.value.awards || [] : []),
      ...(r.awards || []).slice(0, 20),
    ],
    audit: [
      ...(append ? data.value.audit || [] : []),
      ...(r.audit || []).slice(0, 20),
    ],
  };
}
async function run(work: () => Promise<void>) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    await work();
  } catch (e) {
    if (alive) {error.value = treeholeError(e);if(treeholeErrorCode(e)==="contest_changed"){operation.value=undefined;void load().catch(()=>{});}}
  } finally {
    if (alive) busy.value = false;
  }
}
function manage(op: string, title: string, danger = false) {
  reason.value = "";
  operation.value = {
    action: "contests.manage",
    body: {
      contestId: props.contest.id,
      operation: op,
      requestId: crypto.randomUUID(),
      ...(["remove","restore"].includes(op)?{expectedVersion:props.contest.version}:{}),
      ...(op==="remove"?{expectedCounts:{entries:data.value.metrics?.entries??0,votes:data.value.metrics?.votes??0,awards:data.value.metrics?.awards??0}}:{}),
    },
    title,
    danger,
  };
}
function review(kind: string, id: string, decision: string, title: string) {
  reason.value = "";
  operation.value = {
    action: "contests.review",
    body: {
      contestId: props.contest.id,
      kind,
      targetId: id,
      decision,
      requestId: crypto.randomUUID(),
    },
    title,
    danger: ["remove", "exclude"].includes(decision),
  };
}
async function confirm() {
  if (!operation.value || reason.value.trim().length < 2) return;
  const op = operation.value;
  await run(async () => {
    op.body.reason ??= reason.value;
    const r = await contestRequest(props.owner, op.action, op.body);
    if (!alive) return;
    if (r.contest) emit("updated", r.contest);
    if (r.entry)
      works.value = works.value.map((e) =>
        e.id === r.entry!.id ? r.entry! : e,
      );
    operation.value = undefined;
    if(op.body.operation==="remove" && r.contest){emit("removed",r.contest);return;}
    notice.value = "处理已确认";
    try {
      await load();
      if (worksLoaded.value && op.body.kind === "entry" && !r.entry)
        await loadWorks();
    } catch {
      error.value = "处理已成功，统计暂未刷新，请手动重试。";
    }
  });
}
function requestBack() {
  if (operation.value) {
    if (!busy.value) operation.value = undefined;
    return true;
  }
  return busy.value;
}
defineExpose({ requestBack });
onMounted(() => run(() => load()));
</script>
<template>
  <section>
    <p v-if="contest.visibility && contest.visibility!=='visible'" class="ct-notice">{{contest.visibility==='hidden'?'这场赛事已下架':'这场赛事已移入回收站'}}。原始数据仍然保留。</p>
    <p class="ct-subtitle">{{ contest.title }}</p>
    <h2>{{ contest.paused ? "比赛已暂停" : contestLabels[contest.state] }}</h2>
    <p v-if="error" role="alert" class="ct-error">{{ error }}</p>
    <p v-if="notice" role="status" class="ct-notice">{{ notice }}</p>
    <div class="ct-stats">
      <div>
        <small>{{
          data.metrics?.validEntries === undefined ? "投稿记录" : "有效作品"
        }}</small
        ><strong>{{
          data.metrics?.validEntries ??
          data.metrics?.entries ??
          contest.entryCount
        }}</strong>
      </div>
      <div>
        <small>{{
          data.metrics?.validVotes === undefined ? "投票记录" : "有效票数"
        }}</small
        ><strong>{{
          data.metrics?.validVotes ?? data.metrics?.votes ?? "—"
        }}</strong>
      </div>
      <div>
        <small>待处理举报</small
        ><strong>{{
          data.metrics?.pendingReports ?? data.contestReports?.length ?? "—"
        }}</strong>
      </div>
      <div>
        <small>待复核异常票</small
        ><strong>{{ data.metrics?.pendingRisk ?? "—" }}</strong>
      </div>
    </div>
    <button
      v-if="(!contest.visibility||contest.visibility==='visible') && contest.state === 'draft'"
      class="ct-primary"
      :disabled="busy"
      @click="manage('publish', '发布这场赛事？')"
    >
      发布赛事</button
    ><button
      v-else-if="(!contest.visibility||contest.visibility==='visible') && contest.state === 'reviewing'"
      class="ct-primary"
      :disabled="busy"
      @click="manage('announce', '审核并公布结果？')"
    >
      审核并公布结果
    </button>
    <button v-if="!contest.visibility||contest.visibility==='visible'" class="ct-secondary ct-more" :disabled="busy" @click="emit('preview')">预览普通用户视角</button>
    <div class="ct-pair">
      <button v-if="(!contest.visibility||contest.visibility==='visible') && !['cancelled','ended'].includes(contest.state)" class="ct-link" :disabled="busy" @click="emit('edit')">
        编辑日程与规则</button
      ><button class="ct-link" :disabled="busy" @click="run(() => load())">
        刷新统计
      </button>
    </div>
    <details class="ct-rules" @toggle="openWorks">
      <summary>作品审核</summary>
      <p class="ct-subtitle">
        公开作品与下架记录在这里集中处理，普通作品卡片保持简洁。
      </p>
      <button class="ct-link" :disabled="busy" @click="run(() => loadWorks())">
        刷新审核作品
      </button>
      <p v-if="!worksLoaded">展开后按需读取，暂不加载全部作品。</p>
      <p v-else-if="!works.length">还没有投稿记录。</p>
      <article v-for="work in works" :key="work.id" class="ct-section">
        <strong>{{ work.title }}</strong>
        <p>
          {{ work.author }} ·
          {{
            work.status === "approved"
              ? "公开展示"
              : work.status === "withdrawn"
                ? "用户已撤回"
                : "已下架"
          }}
        </p>
        <button class="ct-link" @click="emit('work', work)">查看作品</button>
        <div v-if="work.status !== 'withdrawn'" class="ct-pair">
          <button
            v-if="work.status === 'removed'"
            class="ct-secondary"
            :disabled="busy"
            @click="review('entry', work.id, 'approve', '恢复这件作品？')"
          >
            恢复作品</button
          ><button
            v-else
            class="ct-link"
            :disabled="busy"
            @click="review('entry', work.id, 'remove', '下架这件作品？')"
          >
            下架作品
          </button>
        </div>
      </article>
      <button
        v-if="moreWorks"
        class="ct-secondary ct-more"
        :disabled="busy"
        @click="run(() => loadWorks(true))"
      >
        更多审核作品
      </button>
    </details>
    <section v-if="data.contestReports?.length" class="ct-section">
      <h3>待处理举报</h3>
      <div
        v-for="report in data.contestReports"
        :key="report.id"
        class="ct-section"
      >
        <strong>{{ report.entry.title }}</strong>
        <p>{{ report.reason }}</p>
        <button class="ct-link" @click="emit('work', report.entry)">
          查看作品
        </button>
        <div class="ct-pair">
          <button
            class="ct-secondary"
            :disabled="busy"
            @click="
              review('entry', report.entry_id, 'approve', '保留作品并结案？')
            "
          >
            保留作品</button
          ><button
            class="ct-link"
            :disabled="busy"
            @click="
              review('entry', report.entry_id, 'remove', '下架这件作品？')
            "
          >
            下架作品
          </button>
        </div>
      </div>
    </section>
    <details class="ct-rules">
      <summary>投票复核与剔除</summary>
      <p v-if="!data.votes?.length">暂无投票记录。</p>
      <article v-for="v in data.votes" :key="v.id" class="ct-section">
        <small>作品 {{ v.entry_id.slice(0, 8) }}</small>
        <p>
          {{
            v.excluded
              ? "已剔除"
              : !v.enabled
                ? "已撤回"
                : v.risk === "vote_burst"
                  ? "反复切票，待复核"
                  : ["young_account", "rapid_votes"].includes(v.risk || "")
                    ? "历史风险标记，可复核"
                    : "常规投票"
          }}
        </p>
        <div class="ct-pair">
          <button
            class="ct-secondary"
            :disabled="busy"
            @click="review('vote', v.id, 'valid', '确认这张票有效？')"
          >
            确认有效</button
          ><button
            class="ct-link"
            :disabled="busy"
            @click="review('vote', v.id, 'exclude', '剔除这张票？')"
          >
            剔除
          </button>
        </div>
      </article>
    </details>
    <details class="ct-rules">
      <summary>奖励记录与撤奖</summary>
      <p v-if="!data.awards?.length">结果公布后保留完整奖励记录。</p>
      <article v-for="a in data.awards" :key="a.id" class="ct-section">
        <strong>{{ awardLabels[a.kind] }} · {{ a.title }}</strong>
        <p>{{ a.revoked_at ? "已撤销" : "有效" }}</p>
        <button
          v-if="!a.revoked_at && a.entry_id"
          class="ct-link"
          :disabled="busy"
          @click="
            review('entry', a.entry_id, 'remove', '撤销该作品的获奖资格？')
          "
        >
          撤销作品资格</button
        ><button
          v-if="a.revoked_at && a.entry_id"
          class="ct-link"
          :disabled="busy"
          @click="
            review('entry', a.entry_id, 'approve', '重新审核并恢复该作品？')
          "
        >
          重新审核作品
        </button>
      </article>
    </details>
    <details class="ct-rules">
      <summary>更多赛事操作</summary>
      <template v-if="!contest.visibility||contest.visibility==='visible'">
      <div class="ct-pair">
        <button
          v-if="contest.state !== 'ended' && contest.state !== 'cancelled'"
          class="ct-secondary"
          :disabled="busy"
          @click="
            manage(
              contest.paused ? 'resume' : 'pause',
              contest.paused ? '恢复比赛？' : '暂停比赛？',
            )
          "
        >
          {{ contest.paused ? "恢复比赛" : "暂停比赛" }}</button
        ><button
          class="ct-link"
          :disabled="busy || contest.state === 'cancelled'"
          @click="manage('cancel', '取消比赛并撤销已发奖项？', true)"
        >
          取消赛事
        </button>
      </div>
      <button v-if="!['cancelled','ended'].includes(contest.state)" class="ct-link" @click="emit('edit')">延长尚未结束的阶段</button>
      <button v-if="(backendSchema||13)>=15" class="ct-link ct-danger-text" :disabled="busy||data.metrics?.awards===undefined" @click="manage('remove', (data.metrics?.entries||data.metrics?.votes||data.metrics?.awards)?'下架这场赛事？':'删除这场赛事？',true)">{{(data.metrics?.entries||data.metrics?.votes||data.metrics?.awards)?'下架赛事':'删除赛事'}}</button>
      <p v-else class="ct-subtitle">清理功能需后台升级后启用，现有数据不会改变。</p>
      </template>
      <button v-else class="ct-secondary" :disabled="busy" @click="manage('restore','恢复这场赛事？')">恢复赛事</button>
    </details>
    <details class="ct-rules">
      <summary>资源统计</summary>
      <p>
        投稿记录 {{ data.metrics?.entries ?? "—" }} · 图片资源
        {{ data.metrics?.images ?? "—" }} · 投票记录
        {{ data.metrics?.votes ?? "—" }}
      </p>
      <small
        >投稿和票记录包含撤回与下架；图片仅统计直接附在赛事作品上的资源。这些是数据规模参考，不是腾讯云账单。</small
      >
    </details>
    <details class="ct-rules">
      <summary>删除与恢复记录</summary>
      <p v-if="!data.audit?.some(a=>['remove','restore'].includes(a.action))" class="ct-subtitle">当前页没有清理记录，可继续读取较早的管理记录。</p>
      <article v-for="a in data.audit?.filter(a=>['remove','restore'].includes(a.action))" :key="a.id" class="ct-section"><strong>{{a.action==='restore'?'恢复赛事':'移入回收站'}}</strong><p>{{a.reason}}</p><small>{{contestDate(a.created_at,true)}} · 北京时间</small><p v-if="a.snapshot?.associations">投稿{{a.snapshot.associations.entries}} · 投票{{a.snapshot.associations.votes}} · 奖项{{a.snapshot.associations.awards}}</p></article>
    </details>
    <details class="ct-rules">
      <summary>操作审计</summary>
      <article v-for="a in data.audit" :key="a.id" class="ct-section">
        <strong>{{ a.action }}</strong>
        <p>{{ a.reason }}</p>
        <small>{{ a.created_at }}</small>
      </article>
    </details>
    <button
      v-if="more"
      class="ct-secondary ct-more"
      :disabled="busy"
      @click="run(() => load(true))"
    >
      更多管理记录</button
    ><ContestDialog
      :open="!!operation"
      :title="operation?.title || ''"
      :danger="operation?.danger"
      :busy="busy"
      :confirm="operation?.body.operation==='remove'?'移入回收站':operation?.body.operation==='restore'?'确认恢复':'确认处理'"
      @cancel="operation = undefined"
      @confirm="confirm"
      ><div v-if="['remove','restore'].includes(String(operation?.body.operation))" class="ct-removal-summary"><strong>{{contest.title}}</strong><p>{{contestLabels[contest.state]}} · {{data.metrics?.entries??'—'}} 条投稿 · {{data.metrics?.votes??'—'}} 条投票 · {{data.metrics?.awards??'—'}} 条奖励</p><p>{{operation?.body.operation==='restore'?'恢复原始记录及公开展示，不会重新颁发奖励。':'从公开列表、档案和榜单隐藏，所有原始数据仍然保留，可在回收站恢复。'}}</p></div><p v-else>操作会记录在管理审计中。取消或撤销资格后，荣誉和档案会同步更新。</p>
      <label class="ct-form"
        >处理原因<textarea
          style="resize: none"
          v-model="reason"
          :disabled="busy || !!operation?.body.reason"
          rows="3"
          maxlength="300"
          placeholder="填写原因，至少两个字"
        />
      </label>
      <p v-if="error" role="alert">{{ error }}</p></ContestDialog
    >
  </section>
</template>

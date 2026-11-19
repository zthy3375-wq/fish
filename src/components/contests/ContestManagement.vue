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
import { treeholeError } from "../../services/treehole";
import ContestDialog from "./ContestDialog.vue";
const props = defineProps<{ owner: string; contest: Contest }>();
const emit = defineEmits<{
  updated: [contest: Contest];
  edit: [];
  work: [entry: ContestEntry];
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
    if (alive) error.value = treeholeError(e);
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
    const r = await contestRequest(props.owner, op.action, {
      ...op.body,
      reason: reason.value,
    });
    if (!alive) return;
    if (r.contest) emit("updated", r.contest);
    operation.value = undefined;
    notice.value = "处理已确认";
    try {
      await load();
    } catch {
      error.value = "处理已成功，统计暂未刷新，请手动重试。";
    }
  });
}
function requestBack() {
  if (operation.value) {
    operation.value = undefined;
    return true;
  }
  return busy.value;
}
defineExpose({ requestBack });
onMounted(() => run(() => load()));
</script>
<template>
  <section>
    <p class="ct-subtitle">{{ contest.title }}</p>
    <h2>{{ contest.paused ? "比赛已暂停" : contestLabels[contest.state] }}</h2>
    <p v-if="error" role="alert" class="ct-error">{{ error }}</p>
    <p v-if="notice" role="status" class="ct-notice">{{ notice }}</p>
    <div class="ct-stats">
      <div>
        <small>有效作品</small><strong>{{ contest.entryCount }}</strong>
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
      v-if="contest.state === 'draft'"
      class="ct-primary"
      :disabled="busy"
      @click="manage('publish', '发布这场赛事？')"
    >
      发布赛事</button
    ><button
      v-else-if="contest.state === 'reviewing'"
      class="ct-primary"
      :disabled="busy"
      @click="manage('announce', '审核并公布结果？')"
    >
      审核并公布结果
    </button>
    <div class="ct-pair">
      <button class="ct-link" :disabled="busy" @click="emit('edit')">
        编辑日程与规则</button
      ><button class="ct-link" :disabled="busy" @click="run(() => load())">
        刷新统计
      </button>
    </div>
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
      <button class="ct-link" @click="emit('edit')">延长尚未结束的阶段</button>
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
      confirm="确认处理"
      @cancel="operation = undefined"
      @confirm="confirm"
      ><p>操作会记录在管理审计中。取消或撤销资格后，荣誉和档案会同步更新。</p>
      <label class="ct-form"
        >处理原因<textarea
          style="resize: none"
          v-model="reason"
          rows="3"
          maxlength="300"
          placeholder="填写原因，至少两个字"
        />
      </label>
      <p v-if="error" role="alert">{{ error }}</p></ContestDialog
    >
  </section>
</template>

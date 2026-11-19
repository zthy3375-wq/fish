<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from "vue";
import { contestRequest, type ContestTheme } from "../../services/contests";
import { treeholeError } from "../../services/treehole";
import ContestDialog from "./ContestDialog.vue";
const themeLabels: Record<string, string> = {
  pending: "待审核",
  approved: "候选主题",
  removed: "未采纳",
  merged: "已合并",
};
const props = defineProps<{
  owner: string;
  admin: boolean;
  legacyContestId?: string;
  backendSchema?: number;
}>();
const rows = ref<ContestTheme[]>([]),
  open = ref(false),
  busy = ref(false),
  error = ref(""),
  notice = ref(""),
  title = ref(""),
  more = ref(false),
  reason = ref(""),
  mergeId = ref("");
let nonce = crypto.randomUUID(),
  alive = true;
onBeforeUnmount(() => (alive = false));
const operation = ref<{
  kind: string;
  targetId?: string;
  decision?: string;
  enabled?: boolean;
  requestId: string;
}>();
async function load(append = false) {
  const r = await contestRequest(
    props.owner,
    "contests.themes",
    { offset: append ? rows.value.length : 0 },
    true,
  );
  if (!alive) return;
  open.value = !!r.solicitation;
  more.value = (r.themes?.length || 0) > 20;
  rows.value = [
    ...(append ? rows.value : []),
    ...(r.themes || []).slice(0, 20),
  ];
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
async function suggest() {
  if (title.value.trim().length < 3) {
    error.value = "主题至少写三个字。";
    return;
  }
  await run(async () => {
    await contestRequest(props.owner, "contests.suggest", {
      title: title.value,
      requestId: nonce,
    });
    nonce = crypto.randomUUID();
    title.value = "";
    notice.value = "主题已提交，等待开发者审核。";
    try {
      await load();
    } catch {
      error.value = "提交已成功，列表暂未刷新。";
    }
  });
}
async function vote(t: ContestTheme) {
  await run(async () => {
    const enabled = !t.voted;
    const r = await contestRequest(props.owner, "contests.themevote", {
      themeId: t.id,
      enabled,
    });
    const updated = r.themes?.find((x) => x.id === t.id);
    Object.assign(
      t,
      updated || { voted: enabled, votes: t.votes + (enabled ? 1 : -1) },
    );
  });
}
function resetNonce() {
  nonce = crypto.randomUUID();
}
function ask(kind: string, targetId?: string, decision?: string) {
  reason.value = "";
  mergeId.value = "";
  operation.value = {
    kind,
    targetId,
    decision,
    enabled: !open.value,
    requestId: crypto.randomUUID(),
  };
}
async function confirm() {
  if (!operation.value || reason.value.trim().length < 2) return;
  if (operation.value.kind === "merge" && !mergeId.value) {
    error.value = "请先选择要合并到的候选主题。";
    return;
  }
  const op = operation.value;
  await run(async () => {
    if (op.kind === "solicitation")
      await contestRequest(props.owner, "contests.manage", {
        contestId:
          (props.backendSchema || 13) >= 14 ? null : props.legacyContestId,
        operation: "solicitation",
        enabled: op.enabled,
        reason: reason.value,
        requestId: op.requestId,
      });
    else
      await contestRequest(props.owner, "contests.review", {
        contestId: null,
        kind: op.kind,
        targetId: op.targetId,
        decision: op.decision,
        mergeId: mergeId.value || null,
        reason: reason.value,
        requestId: op.requestId,
      });
    operation.value = undefined;
    notice.value = "处理已确认";
    try {
      await load();
    } catch {
      error.value = "处理已成功，列表暂未刷新。";
    }
  });
}
onMounted(() => run(() => load()));
function requestBack() {
  if (operation.value) {
    operation.value = undefined;
    return true;
  }
  return busy.value;
}
defineExpose({ requestBack });
</script>
<template>
  <section>
    <h2>下一场，想比什么？</h2>
    <p class="ct-subtitle">
      分享你的主题，同学投票表达喜欢，开发者确认后发布比赛。
    </p>
    <p v-if="error" class="ct-error" role="alert">{{ error }}</p>
    <p v-if="notice" class="ct-notice" role="status">{{ notice }}</p>
    <form v-if="open" class="ct-form" novalidate @submit.prevent="suggest">
      <label
        >提议一个主题<input
          v-model="title"
          maxlength="80"
          placeholder="例如：邯院最美的日落"
          :disabled="busy"
          @input="resetNonce" /></label
      ><button class="ct-primary" :disabled="busy">提交主题</button>
    </form>
    <p v-else class="ct-subtitle">主题征集暂未开启，先看看大家的想法。</p>
    <button
      v-if="admin"
      class="ct-link"
      :disabled="busy || ((backendSchema || 13) < 14 && !legacyContestId)"
      @click="ask('solicitation')"
    >
      {{ open ? "结束主题征集" : "开启主题征集" }}
    </button>
    <article v-for="theme in rows" :key="theme.id" class="ct-section">
      <h3>{{ theme.title }}</h3>
      <p class="ct-subtitle">
        {{ themeLabels[theme.status] }} · {{ theme.votes }}人喜欢
      </p>
      <button
        v-if="theme.status === 'approved'"
        class="ct-secondary"
        :disabled="busy || !open"
        :aria-pressed="theme.voted"
        @click="vote(theme)"
      >
        {{ theme.voted ? "已支持 · 取消" : "喜欢这个主题" }}
      </button>
      <details v-if="admin" class="ct-rules">
        <summary>审核主题</summary>
        <div class="ct-pair">
          <button
            class="ct-link"
            :disabled="busy"
            @click="ask('theme', theme.id, 'approve')"
          >
            加入候选</button
          ><button
            class="ct-link"
            :disabled="busy"
            @click="ask('theme', theme.id, 'remove')"
          >
            不采纳</button
          ><button
            class="ct-link"
            :disabled="busy"
            @click="ask('merge', theme.id, 'approve')"
          >
            合并重复主题
          </button>
        </div>
      </details>
    </article>
    <p v-if="!rows.length && !busy" class="ct-empty">还没有候选主题。</p>
    <button
      v-if="more"
      class="ct-secondary ct-more"
      :disabled="busy"
      @click="run(() => load(true))"
    >
      更多候选主题</button
    ><ContestDialog
      :open="!!operation"
      title="确认主题征集操作"
      :busy="busy"
      confirm="确认处理"
      @cancel="operation = undefined"
      @confirm="confirm"
      ><div class="ct-form">
        <label v-if="operation?.kind === 'merge'"
          >合并到<select v-model="mergeId">
            <option value="">选择候选主题</option>
            <option
              v-for="t in rows.filter(
                (x) => x.status === 'approved' && x.id !== operation?.targetId,
              )"
              :key="t.id"
              :value="t.id"
            >
              {{ t.title }}
            </option>
          </select></label
        ><label
          >处理原因<textarea
            style="resize: none"
            v-model="reason"
            rows="3"
            maxlength="300"
          />
        </label>
        <p v-if="error" role="alert">{{ error }}</p>
      </div></ContestDialog
    >
  </section>
</template>

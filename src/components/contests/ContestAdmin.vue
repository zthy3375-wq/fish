<script setup lang="ts">
import ContestPostPicker from "./ContestPostPicker.vue";
import { onMounted, ref } from "vue";
import {
  contestRequest,
  awardLabels,
  type Contest,
  type ContestResult,
} from "../../services/contests";
import { treeholeError } from "../../services/treehole";
const props = defineProps<{ owner: string; contest?: Contest }>();
const emit = defineEmits<{ saved: [id: string]; close: [] }>();
function local(date: number) {
  return new Date(date - new Date(date).getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
}
const monday = new Date();
monday.setDate(monday.getDate() + ((8 - monday.getDay()) % 7 || 7));
monday.setHours(0, 0, 0, 0);
const start = monday.getTime(),
  day = 86400000;
const form = ref({
  id: crypto.randomUUID() as string,
  title: "",
  type: "摄影赛",
  edition: "",
  description: "",
  rules:
    "原创投稿，尊重隐私。同票并列，下一名次连续排列。前三名仅授予获得有效票的作品。",
  coverPostId: null as string | null,
  startsAt: local(start),
  submissionEnds: local(start + 5 * day),
  votingStarts: local(start + 5 * day),
  votingEnds: local(start + 6 * day),
  awardAt: local(start + 6.5 * day),
  formats: ["text", "image", "mixed"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 5,
  minAccountHours: 24,
  excellence: 3,
  autoPublish: false,
});
const busy = ref(false),
  error = ref(""),
  reason = ref(""),
  data = ref<ContestResult>({}),
  offset = ref(0),
  more = ref(false);
const metricLabels: Record<string, string> = {
  votes: "投票记录",
  entries: "投稿记录",
  images: "图片资源",
  pendingRisk: "待复核票",
};
const timeFields = {
  startsAt: "投稿开始",
  submissionEnds: "投稿截止",
  votingStarts: "投票开始",
  votingEnds: "投票截止",
  awardAt: "公布时间",
} as const;
async function run(work: () => Promise<void>) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    await work();
  } catch (e) {
    error.value = treeholeError(e);
  } finally {
    busy.value = false;
  }
}
async function audit(append = false) {
  const r = await contestRequest(
    props.owner,
    "contests.admin",
    { contestId: form.value.id, offset: append ? offset.value + 20 : 0 },
    true,
  );
  offset.value = append ? offset.value + 20 : 0;
  more.value = [r.votes, r.audit, r.awards].some(
    (rows) => (rows?.length || 0) > 20,
  );
  data.value = {
    ...r,
    votes: [
      ...(append ? data.value.votes || [] : []),
      ...(r.votes || []).slice(0, 20),
    ],
    audit: [
      ...(append ? data.value.audit || [] : []),
      ...(r.audit || []).slice(0, 20),
    ],
    awards: [
      ...(append ? data.value.awards || [] : []),
      ...(r.awards || []).slice(0, 20),
    ],
  };
}
async function reviewEntry(id: string, decision: string) {
  await contestRequest(props.owner, "contests.review", {
    contestId: form.value.id,
    kind: "entry",
    targetId: id,
    decision,
    reason: reason.value,
  });
  await audit();
}
async function save() {
  const body = {
    ...form.value,
    coverPostId: form.value.coverPostId || null,
    contestId: form.value.id,
  };
  for (const key of Object.keys(timeFields) as (keyof typeof timeFields)[])
    body[key] = new Date(body[key]).toISOString();
  await contestRequest(props.owner, "contests.save", body);
  emit("saved", form.value.id);
}
async function manage(operation: string, enabled = false) {
  await contestRequest(props.owner, "contests.manage", {
    contestId: form.value.id,
    operation,
    reason: reason.value,
    enabled,
  });
  emit("saved", form.value.id);
}
async function review(id: string, decision: string) {
  await contestRequest(props.owner, "contests.review", {
    contestId: form.value.id,
    kind: "vote",
    targetId: id,
    decision,
    reason: reason.value,
  });
  await audit();
}
function duration(event: Event) {
  const n = Number((event.target as HTMLSelectElement).value);
  if (!n) return;
  const base = Date.parse(form.value.startsAt);
  form.value.submissionEnds = local(base + (day * n * 5) / 7);
  form.value.votingStarts = form.value.submissionEnds;
  form.value.votingEnds = local(base + (day * n * 6) / 7);
  form.value.awardAt = local(base + day * n);
}
onMounted(() => {
  if (props.contest) {
    Object.assign(form.value, props.contest);
    for (const key of Object.keys(timeFields) as (keyof typeof timeFields)[])
      form.value[key] = local(Date.parse(props.contest[key]));
    void run(() => audit());
  }
});
</script>
<template>
  <section class="contest-admin">
    <button @click="emit('close')">返回赛事</button>
    <h2>{{ contest ? "管理赛事" : "创建主题赛事" }}</h2>
    <p v-if="error" role="alert">{{ error }}</p>
    <form @submit.prevent="run(save)">
      <label>名称<input v-model="form.title" required maxlength="80" /></label>
      <div class="pair">
        <label
          >类型<input
            v-model="form.type"
            required
            list="contest-types"
            maxlength="40" /></label
        ><label>届次<input v-model="form.edition" maxlength="40" /></label>
      </div>
      <datalist id="contest-types">
        <option
          v-for="type in [
            '摄影赛',
            '搞笑赛',
            '文字赛',
            '创作赛',
            '创意赛',
            '特别赛',
            '自定义赛',
          ]"
          :key="type"
        >
          {{ type }}
        </option>
      </datalist>
      <label
        >主题描述<textarea
          v-model="form.description"
          required
          maxlength="2000"
          rows="3"
        /></label
      ><label
        >投稿规则<textarea
          v-model="form.rules"
          required
          maxlength="4000"
          rows="5"
        /></label
      ><ContestPostPicker
        image-only
        @choose="form.coverPostId = $event.id"
      /><label
        >封面原帖 ID<input
          v-model="form.coverPostId"
          placeholder="选填，使用已有帖子首图"
      /></label>
      <label
        >周期<select @change="duration">
          <option value="0">自定义时间</option>
          <option v-for="n in [1, 3, 7, 14, 30]" :key="n" :value="n">
            {{ n }} 天
          </option>
        </select></label
      >
      <div class="pair">
        <label v-for="(label, key) in timeFields" :key="key"
          >{{ label }}<input v-model="form[key]" type="datetime-local" required
        /></label>
      </div>
      <fieldset>
        <legend>允许投稿类型</legend>
        <label
          v-for="(label, key) in { text: '文字', image: '图片', mixed: '图文' }"
          :key="key"
          ><input v-model="form.formats" type="checkbox" :value="key" />{{
            label
          }}</label
        >
      </fieldset>
      <div class="pair">
        <label
          >每人作品上限<input
            v-model.number="form.maxEntries"
            type="number"
            min="1"
            max="10" /></label
        ><label
          >每人票数<input
            v-model.number="form.votesPerUser"
            type="number"
            min="1"
            max="10" /></label
        ><label
          >颁发前三最低作品数<input
            v-model.number="form.minEntries"
            type="number"
            min="1"
            max="1000" /></label
        ><label
          >投票账号至少注册几小时<input
            v-model.number="form.minAccountHours"
            type="number"
            min="0"
            max="8760" /></label
        ><label
          >优秀作品名次数量<input
            v-model.number="form.excellence"
            type="number"
            min="0"
            max="30"
        /></label>
      </div>
      <label class="check"
        ><input
          v-model="form.autoPublish"
          type="checkbox"
        />到公布时间自动结算，疑似异常票会转人工审核</label
      >
      <p class="muted">
        时间使用当前设备所在时区。开启后规则固定，仍可延长尚未结束的阶段。并列名次采用密集排名，下一名次连续排列。
      </p>
      <button class="primary" :disabled="busy || !form.formats.length">
        保存赛事
      </button>
    </form>
    <template v-if="contest"
      ><label
        >操作理由<textarea
          v-model="reason"
          minlength="2"
          maxlength="300"
          placeholder="填写处理原因"
        />
      </label>
      <div class="actions">
        <button
          v-for="(label, key) in {
            publish: '发布赛事',
            pause: '暂停',
            resume: '恢复',
            announce: '审核并公布',
            cancel: '取消赛事',
          }"
          :key="key"
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => manage(key))"
        >
          {{ label }}</button><button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => manage('solicitation', true))"
        >
          开启主题征集</button
        ><button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => manage('solicitation', false))"
        >
          结束征集
        </button>
      </div>
      <h3>资源与复核</h3>
      <p class="muted">
        计数来自当前赛事。列表每页20条，每次读取一次服务请求，无实时监听。
      </p>
      <dl>
        <template v-for="(value, key) in data.metrics" :key="key"
          ><dt>{{ metricLabels[key] || key }}</dt>
          <dd>{{ value }}</dd></template
        >
      </dl>
      <article v-for="report in data.contestReports" :key="report.id">
        <strong>作品举报</strong>
        <p>{{ report.reason }}</p>
        <small>作品 {{ report.entry_id }}</small>
        <h4>{{ report.entry.title }}</h4>
        <p>{{ report.entry.body }}</p>
        <a
          v-for="image in report.entry.images"
          :key="image.id"
          :href="image.url || undefined"
          target="_blank"
          rel="noopener noreferrer"
          ><img
            v-if="image.url"
            :src="image.url"
            alt="被举报作品配图"
            style="max-width: 100%; max-height: 200px" /></a
        ><button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => reviewEntry(report.entry_id, 'approve'))"
        >
          保留作品并结案</button
        ><button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => reviewEntry(report.entry_id, 'remove'))"
        >
          下架作品并结案
        </button>
      </article>
      <article v-for="vote in data.votes" :key="vote.id">
        <small>作品 {{ vote.entry_id }}</small>
        <p>
          {{
            vote.risk === "young_account"
              ? "新注册账号，请复核"
              : vote.risk === "rapid_votes"
                ? "短时集中投票，请复核"
                : "常规投票"
          }}
          · {{ vote.excluded ? "已剔除" : vote.enabled ? "有效" : "已撤回" }}
        </p>
        <button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => review(vote.id, 'valid'))"
        >
          确认有效</button
        ><button
          :disabled="busy || reason.trim().length < 2"
          @click="run(() => review(vote.id, 'exclude'))"
        >
          剔除
        </button>
      </article>
      <h3>奖项发放记录</h3>
      <article v-for="award in data.awards" :key="award.id">
        <strong>{{ awardLabels[award.kind] }} · {{ award.title }}</strong>
        <p>
          {{ award.revoked_at ? "已撤销" : "有效"
          }}{{ award.rank ? " · 第 " + award.rank + " 名" : "" }}
        </p>
        <small>{{ new Date(award.awarded_at!).toLocaleString("zh-CN") }}</small>
      </article>
      <h3>操作记录</h3>
      <article v-for="log in data.audit" :key="log.id">
        <strong>{{ log.action }}</strong>
        <p>{{ log.reason }}</p>
        <small>{{ new Date(log.created_at).toLocaleString("zh-CN") }}</small>
      </article>
      <button v-if="more" :disabled="busy" @click="run(() => audit(true))">
        更多投票与记录
      </button></template
    >
  </section>
</template>
<style scoped>
.contest-admin {
  padding: 16px 0;
}
h2 {
  font-size: 24px;
  margin: 12px 0 20px;
}
h3 {
  font-size: 17px;
  margin-top: 24px;
}
label {
  display: block;
  font-size: 13px;
  margin: 12px 0;
}
input:not([type="checkbox"]),
textarea,
select {
  display: block;
  width: 100%;
  font: inherit;
  min-height: 44px;
  border: 1px solid var(--color-border);
  border-radius: 9px;
  padding: 10px;
  background: var(--color-bg);
  color: var(--color-text);
  margin-top: 6px;
}
.pair {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0 12px;
}
.pair label {
  min-width: 0;
}
fieldset {
  display: flex;
  gap: 15px;
  border: 0;
  padding: 10px 0;
}
fieldset label,
.check {
  display: flex;
  align-items: center;
  gap: 8px;
}
button {
  min-height: 44px;
  color: var(--color-primary);
  padding: 6px 12px;
}
button.primary {
  width: 100%;
  background: var(--color-primary);
  color: #fff;
  border-radius: 10px;
}
.muted,
small {
  font-size: 12px;
  color: var(--color-muted);
  line-height: 1.7;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.actions button {
  background: var(--color-tint);
  border-radius: 8px;
}
dl {
  display: grid;
  grid-template-columns: 1fr auto;
  font-size: 13px;
  gap: 8px;
}
article {
  padding: 12px 0;
  border-bottom: 1px solid var(--color-divider);
  overflow-wrap: anywhere;
}
p[role="alert"] {
  color: var(--color-danger);
}
</style>

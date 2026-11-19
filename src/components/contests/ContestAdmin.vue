<script setup lang="ts">
import { ref, computed } from "vue";
import { contestRequest, type Contest } from "../../services/contests";
import { treeholeError, type TreeholePost } from "../../services/treehole";
import {
  contestSchedule,
  contestDate,
  beijingISO,
  beijingInput,
} from "../../domain/contests";
import ContestPostPicker from "./ContestPostPicker.vue";
import ContestDialog from "./ContestDialog.vue";
const props = defineProps<{
  owner: string;
  contest?: Contest;
  backendSchema?: number;
}>();
const emit = defineEmits<{
  saved: [id: string, contest: Contest];
  close: [];
}>();
const defaults = {
  id: crypto.randomUUID(),
  title: "",
  type: "摄影赛",
  edition: "",
  description: "",
  rules:
    "原创投稿，尊重隐私，禁止自投。同票并列，下一名次连续排列。满足公布的有效作品门槛且有有效票时颁发前三；有效参赛者保留纪念。",
  coverPostId: null as string | null,
  ...contestSchedule(7),
  formats: ["image", "mixed", "text"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 5,
  minAccountHours: 0,
  excellence: 3,
  autoPublish: false,
  reviewRisk: true,
};
const form = ref({ ...defaults, ...props.contest });
const duration = ref(7),
  customDays = ref(7),
  manualTimes = ref(!!props.contest),
  cover = ref(props.contest?.cover?.url || ""),
  busy = ref(false),
  error = ref(""),
  leave = ref(false),
  dirty = ref(false);
let alive = true;
import { watch, onBeforeUnmount } from "vue";
onBeforeUnmount(() => {
  alive = false;
});
watch(form, () => (dirty.value = true), { deep: true });
const requestId = ref(crypto.randomUUID());
const fields = {
  startsAt: "投稿开始",
  submissionEnds: "投稿截止",
  votingStarts: "投票开始",
  votingEnds: "投票截止",
  awardAt: "公布时间",
} as const;
const formatNames = { text: "文字", image: "图片", mixed: "图文" };
function applyDuration() {
  const days = duration.value || customDays.value;
  if (days >= 1 && days <= 365) {
    Object.assign(form.value, contestSchedule(days));
    manualTimes.value = false;
    requestId.value = crypto.randomUUID();
  }
}
function setTime(key: keyof typeof fields, event: Event) {
  try {
    form.value[key] = beijingISO((event.target as HTMLInputElement).value);
    manualTimes.value = true;
  } catch {
    error.value = "请检查日程时间";
  }
}
function pickCover(post: TreeholePost) {
  form.value.coverPostId = post.id;
  cover.value = post.images?.[0]?.url || "";
}
const ordered = computed(() => {
  const f = form.value;
  return (
    Date.parse(f.startsAt) < Date.parse(f.submissionEnds) &&
    Date.parse(f.submissionEnds) <= Date.parse(f.votingStarts) &&
    Date.parse(f.votingStarts) < Date.parse(f.votingEnds) &&
    Date.parse(f.votingEnds) <= Date.parse(f.awardAt)
  );
});
const pending = ref<Record<string, unknown>>();
async function save(publish: boolean) {
  if (busy.value) return;
  error.value = "";
  const f = form.value;
  if (
    !f.title.trim() ||
    !f.description.trim() ||
    !f.rules.trim() ||
    !f.formats.length ||
    !ordered.value
  ) {
    error.value = "请填写名称、介绍、规则，选择投稿类型，并检查时间先后。";
    return;
  }
  busy.value = true;
  try {
    if (!pending.value) {
      if (!props.contest && !manualTimes.value)
        Object.assign(f, contestSchedule(duration.value || customDays.value));
      pending.value = {
        ...f,
        formats: [...f.formats],
        contestId: f.id,
        requestId: requestId.value,
        expectedVersion: props.contest?.version,
        publish,
      };
    }
    let r = await contestRequest(props.owner, "contests.save", pending.value);
    // schema13 saves a draft first. Confirm its publication before claiming success.
    if (publish && r.contest?.state === "draft")
      r = await contestRequest(props.owner, "contests.manage", {
        contestId: f.id,
        operation: "publish",
        reason: "发布已确认主题与规则的赛事",
        requestId: publishRequestId,
      });
    if (!r.contest) throw Error("invalid_response");
    if (alive) {
      dirty.value = false;
      emit("saved", r.contest.id, r.contest);
    }
  } catch (e) {
    if (alive) {
      error.value = treeholeError(e) + " 已保留填写内容。";
      if (
        /contest_conflict|invalid_request|contest_rules_locked|contest_closed|forbidden/.test(
          (e as Error).message,
        )
      )
        pending.value = undefined;
    }
  } finally {
    if (alive) busy.value = false;
  }
}
// UUIDs remain valid and stable for independent save/publication retries.
const publishRequestId = crypto.randomUUID();
function requestBack() {
  if (busy.value) return true;
  if (leave.value) {
    leave.value = false;
    return true;
  }
  if (dirty.value) {
    leave.value = true;
    return true;
  }
  emit("close");
  return true;
}
defineExpose({ requestBack });
</script>
<template>
  <section>
    <h2>{{ contest ? "编辑赛事" : "发起一场校园比赛" }}</h2>
    <p class="ct-subtitle">主题清楚、规则简单，让同学们轻松参与。</p>
    <p v-if="error" role="alert" class="ct-error">{{ error }}</p>
    <form class="ct-form" novalidate @submit.prevent="save(!contest)">
      <label
        >赛事名称<input
          v-model="form.title"
          maxlength="80"
          placeholder="例如：把校园拍成一张明信片"
          :disabled="busy || !!pending" /></label
      ><label
        >主题与介绍<textarea
          style="resize: none"
          v-model="form.description"
          maxlength="2000"
          rows="3"
          placeholder="告诉同学们，这次想看见什么。"
          :disabled="busy || !!pending"
        />
      </label>
      <div>
        <span class="ct-subtitle">赛事封面（可选）</span
        ><img
          v-if="cover"
          :src="cover"
          alt="赛事封面预览"
          style="
            width: 100%;
            aspect-ratio: 16/8;
            object-fit: cover;
            border-radius: 12px;
          "
        /><ContestPostPicker
          image-only
          :disabled="busy || !!pending"
          @choose="pickCover"
        /><button
          v-if="form.coverPostId"
          type="button"
          class="ct-link"
          :disabled="busy || !!pending"
          @click="
            form.coverPostId = null;
            cover = '';
          "
        >
          移除封面
        </button>
      </div>
      <fieldset class="ct-options" :disabled="busy || !!pending || !!contest">
        <legend>比赛持续时间</legend>
        <label v-for="n in [3, 7, 14, 0]" :key="n"
          ><input
            type="radio"
            v-model.number="duration"
            :value="n"
            @change="applyDuration"
          />{{ n ? n + "天" : "自定义" }}</label
        >
      </fieldset>
      <label v-if="duration === 0"
        >持续天数<input
          v-model.number="customDays"
          type="number"
          min="1"
          max="365"
          :disabled="busy || !!pending"
          @change="applyDuration"
      /></label>
      <fieldset class="ct-options" :disabled="busy || !!pending">
        <legend>允许的作品</legend>
        <label v-for="(name, key) in formatNames" :key="key"
          ><input type="checkbox" v-model="form.formats" :value="key" />{{
            name
          }}</label
        >
      </fieldset>
      <div class="ct-schedule">
        <h3>{{ contest ? "日程" : "日程预览" }} · 北京时间</h3>
        <p v-for="(name, key) in fields" :key="key">
          <span>{{ name }}</span
          ><span>{{ contestDate(form[key]) }}</span>
        </p>
        <small v-if="!contest && !manualTimes"
          >发布时开始，自动安排投稿、投票和结果审核阶段。</small
        >
      </div>
      <details>
        <summary>高级设置</summary>
        <div class="ct-advanced">
          <label
            >赛事类型<input
              v-model="form.type"
              maxlength="40"
              :disabled="busy || !!pending" /></label
          ><label
            >届次（可选）<input
              v-model="form.edition"
              maxlength="40"
              :disabled="busy || !!pending" /></label
          ><label
            >投稿规则<textarea
              style="resize: none"
              v-model="form.rules"
              rows="5"
              maxlength="4000"
              :disabled="busy || !!pending"
            />
          </label>
          <div class="ct-pair">
            <label
              >每人作品<input
                v-model.number="form.maxEntries"
                type="number"
                min="1"
                max="10"
                :disabled="busy || !!pending" /></label
            ><label
              >每人票数<input
                v-model.number="form.votesPerUser"
                type="number"
                min="1"
                max="10"
                :disabled="busy || !!pending"
            /></label>
          </div>
          <label
            >前三最低有效作品数<input
              v-model.number="form.minEntries"
              type="number"
              min="1"
              max="1000"
              :disabled="busy || !!pending" /></label
          ><label
            >优秀作品名次数量<input
              v-model.number="form.excellence"
              type="number"
              min="0"
              max="30"
              :disabled="busy || !!pending" /></label
          ><label
            >投票开始前注册满（小时；0不限制）<input
              v-model.number="form.minAccountHours"
              type="number"
              min="0"
              max="8760"
              :disabled="busy || !!pending" /></label
          ><label v-for="(name, key) in fields" :key="key"
            >{{ name
            }}<input
              type="datetime-local"
              :value="beijingInput(form[key])"
              :disabled="busy || !!pending"
              @change="setTime(key, $event)" /></label
          ><label class="ct-check"
            ><input
              type="checkbox"
              v-model="form.autoPublish"
              :disabled="busy || !!pending"
            />到期自动公布，无需手动颁奖</label
          ><label class="ct-check"
            ><input
              type="checkbox"
              v-model="form.reviewRisk"
              :disabled="busy || !!pending || (backendSchema || 13) < 14"
            />异常票转人工复核</label
          >
          <p v-if="(backendSchema || 13) < 14" class="ct-subtitle">
            当前后台继续使用现有审核策略；改进后的风险识别需后台升级后启用。
          </p>
        </div>
      </details>
      <button class="ct-primary" :disabled="busy">
        {{
          busy
            ? "正在确认…"
            : pending
              ? "重试并确认"
              : contest
                ? "保存修改"
                : "发布赛事"
        }}</button
      ><button
        v-if="!contest"
        type="button"
        class="ct-link"
        :disabled="busy"
        @click="save(false)"
      >
        先保存草稿
      </button>
    </form>
    <ContestDialog
      :open="leave"
      title="离开赛事编辑？"
      confirm="离开编辑"
      @cancel="leave = false"
      @confirm="emit('close')"
      ><p>填写内容尚未提交。返回后需要重新填写。</p></ContestDialog
    >
  </section>
</template>

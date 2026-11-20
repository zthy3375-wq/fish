<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, onActivated } from "vue";
import { ChevronRight, Trophy } from "lucide-vue-next";
import {
  contestRequest,
  contestLabels,
  type Contest,
} from "../../services/contests";
import { treeholeError } from "../../services/treehole";
const props = defineProps<{ owner: string }>();
const emit = defineEmits<{ open: [id: string, winners?: boolean] }>();
const mode = ref("history"),
  year = ref(0),
  type = ref(""),
  events = ref<Contest[]>([]),
  leaders = ref<{ id: string; nickname: string; score: number }[]>([]),
  busy = ref(false),
  error = ref(""),
  more = ref(false);
let offset = 0,
  revision = 0,
  alive = true;
onBeforeUnmount(() => {
  alive = false;
  revision++;
});
const currentYear = Number(
  new Intl.DateTimeFormat("en", {
    year: "numeric",
    timeZone: "Asia/Shanghai",
  }).format(new Date()),
);
async function load(append = false, fresh = false) {
  const request = ++revision;
  busy.value = true;
  error.value = "";
  try {
    const r = await contestRequest(
      props.owner,
      mode.value === "year" ? "contests.year" : "contests.list",
      mode.value === "year"
        ? { year: year.value || currentYear, offset: append ? offset + 20 : 0 }
        : {
            scope:"archive",
            year: year.value,
            type: type.value.trim(),
            offset: append ? offset + 20 : 0,
          },
      fresh,
    );
    if (!alive || request !== revision) return;
    offset = append ? offset + 20 : 0;
    const rows = mode.value === "year" ? r.leaders || [] : r.contests || [];
    more.value = rows.length > 20;
    if (mode.value === "year")
      leaders.value = [
        ...(append ? leaders.value : []),
        ...(r.leaders || []).slice(0, 20),
      ];
    else
      events.value = [
        ...(append ? events.value : []),
        ...(r.contests || []).slice(0, 20),
      ].filter((c) => ["ended", "cancelled"].includes(c.state));
  } catch (e) {
    if (alive && request === revision) error.value = treeholeError(e);
  } finally {
    if (alive && request === revision) busy.value = false;
  }
}
function change(next: string) {
  mode.value = next;
  events.value = [];
  leaders.value = [];
  void load();
}
onMounted(() => load());
onActivated(() => load());
</script>
<template>
  <section>
    <div class="ct-segments" aria-label="历届赛事内容">
      <button
        v-for="(label, key) in {
          history: '历史赛事',
          champions: '冠军档案',
          year: '年度榜单',
        }"
        :key="key"
        :aria-pressed="mode === key"
        @click="change(key)"
      >
        {{ label }}
      </button>
    </div>

    <form class="ct-form" novalidate @submit.prevent="load()">
      <div class="ct-pair">
        <label
          >年份<select v-model.number="year" @change="load()">
            <option :value="0">
              {{ mode === "year" ? "本年度" : "全部年份" }}
            </option>
            <option
              v-for="n in currentYear - 2019"
              :key="n"
              :value="currentYear - n + 1"
            >
              {{ currentYear - n + 1 }}年
            </option>
          </select></label
        ><label v-if="mode !== 'year'"
          >赛事类型<input
            v-model="type"
            placeholder="所有类型"
            maxlength="40"
            @change="load()"
        /></label>
      </div>
    </form>
    <p v-if="error" role="alert" class="ct-error">
      {{ error }}<button class="ct-link" @click="load()">重试</button>
    </p>
    <p v-if="mode === 'year'" class="ct-subtitle">
      冠军5分、亚军3分、季军2分、优秀作品1分，同分并列。
    </p>
    <button
      v-for="event in events"
      :key="event.id"
      class="ct-row"
      @click="emit('open', event.id, mode === 'champions')"
    >
      <img
        v-if="event.cover?.url"
        :src="event.cover.url"
        loading="lazy"
        alt=""
      /><Trophy v-else :size="24" /><span class="ct-row-copy"
        ><h3>{{ event.title }}</h3>
        <small
          >{{ event.type }} · {{ contestLabels[event.state] }} ·
          {{ event.entryCount }}件作品</small
        ><small v-if="mode === 'champions'"
          >进入比赛查看获奖作品与完整记录</small
        ></span
      ><ChevronRight :size="17" />
    </button>
    <div v-for="(leader, index) in leaders" :key="leader.id" class="ct-row">
      <strong>{{
        new Set(leaders.slice(0, index + 1).map((x) => x.score)).size
      }}</strong
      ><span class="ct-row-copy">{{ leader.nickname }}</span
      ><strong>{{ leader.score }}分</strong>
    </div>
    <p v-if="busy" class="ct-loading" role="status">正在读取档案…</p>
    <div
      v-else-if="!events.length && !leaders.length && !error"
      class="ct-empty"
    >
      <h3>
        {{ mode === "year" ? "年度故事正在积累" : "还没有符合筛选的赛事" }}
      </h3>
      <p>每次公布结果后，作品与荣誉会留在这里。</p>
    </div>
    <button
      v-if="more"
      class="ct-secondary ct-more"
      :disabled="busy"
      @click="load(true)"
    >
      更多{{ mode === "year" ? "年度排名" : "历史赛事" }}
    </button>
  </section>
</template>

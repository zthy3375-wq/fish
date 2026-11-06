<script setup lang="ts">
import { computed, ref, watch, onBeforeUnmount } from "vue";
import {
  ArrowLeft,
  ChevronDown,
  Plus,
  MapPin,
  CalendarDays,
  Clock3,
} from "lucide-vue-next";
import {
  uid,
  arrangementFromCell,
  periodTimes,
  resolveArrangement,
  activeWeeks,
  colors,
  validateCourse,
  collisions,
  type ManagedCourse,
  type Semester,
  type TimeTable,
  type CellPreset,
  type Arrangement,
  type WeekRule,
} from "../domain/schedule";
const props = defineProps<{
  course?: ManagedCourse;
  semester: Semester;
  table: TimeTable;
  existing: ManagedCourse[];
  preset?: CellPreset;
  saving?: boolean;
  saveError?: string;
}>();
const emit = defineEmits<{
  save: [course: ManagedCourse, allowConflicts: boolean];
  cancel: [];
}>();
const draft = ref<ManagedCourse>(
  props.course
    ? JSON.parse(JSON.stringify(props.course))
    : {
        id: uid(),
        semesterId: props.semester.id,
        name: "",
        teacher: "",
        color: colors[(props.preset?.day ?? 1) % colors.length],
        notes: "",
        arrangements: [
          arrangementFromCell(
            props.table,
            props.semester.weekCount,
            props.preset,
          ),
        ],
      },
);
const initial = JSON.stringify(draft.value),
  dirty = computed(() => JSON.stringify(draft.value) !== initial);
const error = ref(""),
  issues = ref<string[]>([]),
  confirmed = ref(false),
  expanded = ref(""),
  removeId = ref(""),
  exitConfirm = ref(false);
watch(
  draft,
  () => {
    confirmed.value = false;
    issues.value = [];
    error.value = "";
  },
  { deep: true },
);
const days = ["一", "二", "三", "四", "五", "六", "日"];
function summary(a: Arrangement) {
  return `周${days[a.day - 1]} · ${a.timeMode === "period" ? `第 ${a.startPeriod}–${a.endPeriod} 节` : `${a.start}–${a.end}`} · ${a.rule === "all" ? "每周" : a.rule === "odd" ? "单周" : a.rule === "even" ? "双周" : "自定义周"}`;
}
function syncPeriods(a: Arrangement) {
  try {
    if (a.startPeriod! > a.endPeriod!) a.endPeriod = a.startPeriod;
    Object.assign(a, periodTimes(props.table, a.startPeriod, a.endPeriod));
  } catch (e) {
    error.value = (e as Error).message;
  }
}
function mode(a: Arrangement) {
  if (a.timeMode === "period") {
    a.startPeriod =
      a.startPeriod && a.startPeriod <= props.table.slots.length
        ? a.startPeriod
        : 1;
    a.endPeriod =
      a.endPeriod && a.endPeriod <= props.table.slots.length
        ? a.endPeriod
        : a.startPeriod;
    syncPeriods(a);
  }
}
function rule(a: Arrangement, value: WeekRule) {
  const weeks = activeWeeks(a);
  a.rule = value;
  if (value === "custom" && !a.customWeeks.length) a.customWeeks = weeks;
}
function clampWeeks(a: Arrangement) {
  a.customWeeks = a.customWeeks.filter(
    (w) => w >= a.startWeek && w <= a.endWeek,
  );
}
function toggleWeek(a: Arrangement, w: number) {
  a.customWeeks = a.customWeeks.includes(w)
    ? a.customWeeks.filter((x) => x !== w)
    : [...a.customWeeks, w].sort((a, b) => a - b);
}
function add() {
  const a = arrangementFromCell(
    props.table,
    props.semester.weekCount,
    props.preset,
  );
  draft.value.arrangements.push(a);
  expanded.value = a.id;
}
function requestCancel() {
  if (props.saving) return;
  if (exitConfirm.value) { exitConfirm.value = false; return; }
  if (dirty.value) exitConfirm.value = true;
  else emit("cancel");
}
defineExpose({ requestCancel, hasChanges: () => dirty.value });
function beforeUnload(e: BeforeUnloadEvent) {
  if (dirty.value) {
    e.preventDefault();
    e.returnValue = "";
  }
}
window.addEventListener("beforeunload", beforeUnload);
onBeforeUnmount(() => window.removeEventListener("beforeunload", beforeUnload));
function save() {
  error.value = "";
  issues.value = [];
  try {
    const course: ManagedCourse = JSON.parse(JSON.stringify(draft.value));
    course.name = course.name.trim();
    course.arrangements = course.arrangements.map((a) =>
      resolveArrangement(a, props.table),
    );
    validateCourse(course, props.semester);
    const p = collisions(course, props.existing);
    if (p.some((x) => x.kind === "duplicate"))
      throw Error("存在完全重复的安排，请修改或删除重复项");
    issues.value = p.map((p) => p.message);
    if (p.length && !confirmed.value)
      throw Error("这些安排与已有课程重叠，请核对后确认保留");
    emit("save", course, confirmed.value);
  } catch (e) {
    error.value = (e as Error).message;
  }
}
</script>
<template>
  <form class="course-editor-page" @submit.prevent="save">
    <header class="editor-header">
      <button
        type="button"
        class="icon-button"
        aria-label="返回课表"
        @click="requestCancel"
      >
        <ArrowLeft :size="21" />
      </button>
      <div>
        <h2>{{ course ? "编辑课程" : "添加课程" }}</h2>
        <small
          >{{ semester.academicYear }} {{ semester.season }} · 个人课表</small
        >
      </div>
      <button class="primary" type="submit" :disabled="saving">
        {{ saving ? "保存中" : "保存" }}
      </button>
    </header>
    <div class="editor-scroll">
      <fieldset :disabled="saving" class="editor-fields">
        <section class="editor-basic">
          <label class="form-label"
            >课程名称 *<input
              v-model="draft.name"
              maxlength="150"
              required
              placeholder="例如：高等数学"
              autocomplete="off" /></label
          ><label class="form-label"
            >任课教师<input
              v-model="draft.teacher"
              maxlength="100"
              placeholder="选填" /></label
          ><label class="form-label"
            >上课教室<input
              v-model="draft.arrangements[0].room"
              maxlength="150"
              placeholder="例如：实验楼 305"
          /></label>
        </section>
        <div class="editor-section-title">
          <h3><CalendarDays :size="17" />上课安排</h3>
          <span>{{ draft.arrangements.length }} 个安排</span>
        </div>
        <p class="muted editor-hint">
          {{
            course
              ? "已有安排会保留，点开后可单独编辑。"
              : preset
                ? "已填入选中格子的星期、节次与时间。"
                : "已填入默认上课时间。"
          }}点开安排可调整节次、单双周或增加其他教室。
        </p>
        <article
          v-for="(a, i) in draft.arrangements"
          :key="a.id"
          class="arrangement-panel"
        >
          <button
            type="button"
            class="arrangement-summary"
            :aria-expanded="expanded === a.id"
            @click="expanded = expanded === a.id ? '' : a.id"
          >
            <span
              ><strong>{{ summary(a) }}</strong
              ><small
                >{{ a.start }}–{{ a.end }} · {{ a.room || "地点待填" }} · 第
                {{ a.startWeek }}–{{ a.endWeek }} 周</small
              ></span
            ><ChevronDown :size="18" :class="{ rotated: expanded === a.id }" />
          </button>
          <div v-if="expanded === a.id" class="arrangement-options">
            <div class="form-grid">
              <label class="form-label"
                >星期<select v-model.number="a.day">
                  <option v-for="d in 7" :key="d" :value="d">
                    星期{{ days[d - 1] }}
                  </option>
                </select></label
              ><label class="form-label"
                >这个安排的教室<input v-model="a.room" maxlength="150"
              /></label>
            </div>
            <label class="form-label"
              >时间方式<select v-model="a.timeMode" @change="mode(a)">
                <option value="period">按节次 · 随作息表联动</option>
                <option value="custom">自定义时间 · 保持独立</option>
              </select></label
            >
            <div v-if="a.timeMode === 'period'" class="form-grid">
              <label class="form-label"
                >开始节次<select
                  v-model.number="a.startPeriod"
                  @change="syncPeriods(a)"
                >
                  <option
                    v-for="s in table.slots"
                    :key="s.number"
                    :value="s.number"
                  >
                    第 {{ s.number }} 节 · {{ s.start }}
                  </option>
                </select></label
              ><label class="form-label"
                >结束节次<select
                  v-model.number="a.endPeriod"
                  @change="syncPeriods(a)"
                >
                  <option
                    v-for="s in table.slots.filter(
                      (s) => s.number >= a.startPeriod!,
                    )"
                    :key="s.number"
                    :value="s.number"
                  >
                    第 {{ s.number }} 节 · {{ s.end }}
                  </option>
                </select></label
              >
            </div>
            <div v-else class="form-grid">
              <label class="form-label"
                >开始时间<input v-model="a.start" type="time" required /></label
              ><label class="form-label"
                >结束时间<input v-model="a.end" type="time" required
              /></label>
            </div>
            <p class="editor-hint muted">
              <Clock3 :size="13" />{{
                a.timeMode === "period"
                  ? table.name + " · " + a.start + "–" + a.end
                  : "保留独立时间，修改作息表不会移动这个安排。"
              }}
            </p>
            <div class="weeks-options">
              <h4>教学周</h4>
              <div class="rule-chips">
                <button
                  v-for="r in [
                    { id: 'all', name: '每周' },
                    { id: 'odd', name: '单周' },
                    { id: 'even', name: '双周' },
                    { id: 'custom', name: '自定义' },
                  ]"
                  :key="r.id"
                  type="button"
                  :class="{ selected: a.rule === r.id }"
                  :aria-pressed="a.rule === r.id"
                  @click="rule(a, r.id as WeekRule)"
                >
                  {{ r.name }}
                </button>
              </div>
              <div class="form-grid">
                <label class="form-label"
                  >开始教学周<input
                    v-model.number="a.startWeek"
                    @change="clampWeeks(a)"
                    type="number"
                    min="1"
                    :max="semester.weekCount"
                    required /></label
                ><label class="form-label"
                  >结束教学周<input
                    v-model.number="a.endWeek"
                    @change="clampWeeks(a)"
                    type="number"
                    min="1"
                    :max="semester.weekCount"
                    required
                /></label>
              </div>
              <div v-if="a.rule === 'custom'" class="week-chips">
                <button
                  v-for="w in semester.weekCount"
                  :key="w"
                  type="button"
                  :disabled="w < a.startWeek || w > a.endWeek"
                  :class="{ selected: a.customWeeks.includes(w) }"
                  :aria-label="`第${w}周`"
                  :aria-pressed="a.customWeeks.includes(w)"
                  @click="toggleWeek(a, w)"
                >
                  {{ w }}
                </button>
              </div>
            </div>
            <template v-if="draft.arrangements.length > 1"
              ><button
                v-if="removeId !== a.id"
                class="text-button danger"
                type="button"
                @click="removeId = a.id"
              >
                删除这个安排
              </button>
              <div v-else class="confirmation">
                <p>删除安排 {{ i + 1 }}，其他安排保留？</p>
                <button
                  type="button"
                  class="text-button danger"
                  @click="
                    draft.arrangements.splice(i, 1);
                    removeId = '';
                  "
                >
                  确认删除安排</button
                ><button
                  type="button"
                  class="text-button"
                  @click="removeId = ''"
                >
                  取消
                </button>
              </div></template
            >
          </div>
        </article>
        <button
          type="button"
          class="secondary full add-arrangement"
          @click="add"
        >
          <Plus :size="17" />添加另一个上课安排
        </button>
        <details class="editor-advanced">
          <summary>颜色与备注 <ChevronDown :size="16" /></summary>
          <div class="color-options">
            <button
              v-for="(c, i) in colors"
              :key="c"
              type="button"
              :class="[c, { selected: draft.color === c }]"
              :aria-pressed="draft.color === c"
              @click="draft.color = c"
            >
              {{ ["蓝灰", "淡紫", "青绿", "暖杏"][i] }}
            </button>
          </div>
          <label class="form-label"
            >课程备注<textarea
              v-model="draft.notes"
              rows="3"
              maxlength="2000"
              placeholder="选填：携带教材、教室说明等"
            />
          </label>
        </details>
      </fieldset>
      <div v-if="error || saveError" role="alert" class="form-error">
        {{ error || saveError }}
      </div>
      <template v-if="issues.length"
        ><p v-for="(issue, i) in issues" :key="i" class="inline-note">
          {{ issue }}
        </p>
        <label class="check-line"
          ><input
            v-model="confirmed"
            type="checkbox"
          />已核对，允许保留这些冲突安排</label
        ></template
      >
      <p class="editor-save-note">
        保存到当前设备，首页与日 / 周课表同步更新。
      </p>
    </div>
    <div v-if="exitConfirm" class="editor-exit-scrim">
      <section
        role="alertdialog"
        aria-modal="true"
        aria-label="放弃未保存修改？"
        class="editor-exit"
      >
        <h3>放弃未保存修改？</h3>
        <p>已保存的课程不会受到影响。</p>
        <div class="modal-actions">
          <button class="secondary" type="button" @click="exitConfirm = false">
            继续编辑</button
          ><button class="primary" type="button" @click="emit('cancel')">
            放弃修改
          </button>
        </div>
      </section>
    </div>
  </form>
</template>

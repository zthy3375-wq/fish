<script setup lang="ts">
import {handanTimeTable} from "../domain/handan-time-table";
import { computed, ref } from "vue";
import { Plus, Clock3 } from "lucide-vue-next";
import { schedule, semester, changeSchedule } from "../composables/schedule";
import {
  tableForSemester,
  validateTimeTable,
  validateState,
  uid,
  collisions,
  type TimeTable,
  type ScheduleState,
} from "../domain/schedule";
const table = computed(() => tableForSemester(schedule.value));
const selected = ref(table.value.id),
  draft = ref<TimeTable>(JSON.parse(JSON.stringify(table.value))),
  error = ref(""),
  message = ref(""),
  pending = ref<ScheduleState>(),
  changes = ref<string[]>([]),
  conflicts = ref<string[]>([]),
  confirmed = ref(false),
  busy = ref(false);
function loadHandan(){draft.value=handanTimeTable();prepare(true);}
function choose() {
  draft.value = JSON.parse(
    JSON.stringify(
      schedule.value.timeTables.find((t) => t.id === selected.value)!,
    ),
  );
  pending.value = undefined;
}
function add() {
  const last = draft.value.slots.at(-1)!;
  const [h, m] = last.end.split(":").map(Number);
  const value = h * 60 + m + 10;
  if (value + 45 >= 1440) {
    error.value = "当天已没有更多可用时间";
    return;
  }
  const fmt = (v: number) =>
    `${String(Math.floor(v / 60)).padStart(2, "0")}:${String(v % 60).padStart(2, "0")}`;
  draft.value.slots.push({
    number: draft.value.slots.length + 1,
    start: fmt(value),
    end: fmt(value + 45),
  });
}
function prepare(saveCopy: boolean) {
  error.value = "";
  message.value = "";
  pending.value = undefined;
  confirmed.value = false;
  try {
    const next: ScheduleState = JSON.parse(JSON.stringify(schedule.value));
    const t: TimeTable = JSON.parse(JSON.stringify(draft.value));
    if (saveCopy) {
      t.id = uid();
      next.timeTables.push(t);
    } else {
      const original = next.timeTables.find((t) => t.id === selected.value);
      if (!original) throw Error("作息方案不存在");
      Object.assign(t, original);
    }
    next.semesters.find((s) => s.id === semester.value.id)!.timeTableId = t.id;
    validateTimeTable(t);
    const clean = validateState(next);
    changes.value = [];
    for (const c of clean.courses.filter(
      (c) => c.semesterId === semester.value.id,
    ))
      for (const a of c.arrangements) {
        const old = schedule.value.courses
          .find((x) => x.id === c.id)
          ?.arrangements.find((x) => x.id === a.id);
        if (old && (old.start !== a.start || old.end !== a.end))
          changes.value.push(
            `${c.name}：${old.start}–${old.end} → ${a.start}–${a.end}`,
          );
      }
    conflicts.value = [
      ...new Set(
        clean.courses
          .filter((c) => c.semesterId === semester.value.id)
          .flatMap((c, i, list) =>
            collisions(c, list.slice(0, i)).map((x) => x.message),
          ),
      ),
    ];
    pending.value = clean;
  } catch (e) {
    error.value = (e as Error).message;
  }
}
async function apply() {
  if (!pending.value) return;
  busy.value = true;
  error.value = "";
  try {
    if ((changes.value.length || conflicts.value.length) && !confirmed.value)
      throw Error("请核对变化与冲突，再确认应用");
    const proposal = pending.value,
      stamp = schedule.value.updatedAt;
    await changeSchedule((s) => {
      if (s.updatedAt !== stamp)
        throw Error("课表已被其他页面修改，请重新预览");
      s.timeTables = proposal.timeTables;
      s.semesters = proposal.semesters;
    });
    selected.value = table.value.id;
    draft.value = JSON.parse(JSON.stringify(table.value));
    pending.value = undefined;
    message.value = "作息已保存。自定义时间与旧版课程保持原时间。";
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section class="time-table-manager">
    <h3><Clock3 :size="18" />作息时间表</h3>
    <p class="muted">
      当前课表关联一份作息。仅“按节次”安排随作息联动，旧版及自定义时间课程保持原时间。
    </p>
    <button class="secondary full" @click="loadHandan">载入邯郸学院作息 · 40分钟 / 13节</button>
    <p class="muted">依据你提供的上课时间表。先预览变化，再确认应用到当前学期；其他学期和自定义时间安排不变。</p>
    <p class="source-label">当前使用：{{ table.name }}</p>
    <label class="form-label"
      >选择作息方案<select v-model="selected" @change="choose">
        <option v-for="t in schedule.timeTables" :key="t.id" :value="t.id">
          {{ t.name }}
        </option>
      </select></label
    ><button class="secondary full" @click="prepare(false)">
      预览切换到这个方案</button
    ><label class="form-label"
      >另存方案名称<input
        v-model="draft.name"
        maxlength="60"
        @input="pending = undefined"
    /></label>
    <div class="time-slot-head">
      <span>节次</span><span>开始</span><span>结束</span>
    </div>
    <div v-for="s in draft.slots" :key="s.number" class="time-slot-row">
      <strong>{{ s.number }}</strong
      ><input
        v-model="s.start"
        type="time"
        :aria-label="`第${s.number}节开始时间`"
        @input="pending = undefined"
      /><input
        v-model="s.end"
        type="time"
        :aria-label="`第${s.number}节结束时间`"
        @input="pending = undefined"
      />
    </div>
    <div class="modal-actions">
      <button
        class="secondary"
        :disabled="draft.slots.length >= 24"
        @click="
          add();
          pending = undefined;
        "
      >
        <Plus :size="16" />增加一节</button
      ><button
        class="text-button danger"
        :disabled="draft.slots.length <= 1"
        @click="
          draft.slots.pop();
          pending = undefined;
        "
      >
        移除最后一节
      </button>
    </div>
    <p class="muted">
      保存为新方案，只关联当前学期，不改动其他学期使用的方案。
    </p>
    <button class="primary full" :disabled="busy" @click="prepare(true)">
      预览并另存作息方案
    </button>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="message" role="status" class="inline-note">{{ message }}</p>
    <div v-if="pending" class="time-change-preview">
      <h4>应用前确认</h4>
      <p>{{ changes.length }} 个联动安排会调整；其他课程保持原时间。</p>
      <p v-for="(line, i) in changes" :key="i">{{ line }}</p>
      <p v-for="(line, i) in conflicts" :key="'c' + i" class="form-error">
        时间重叠：{{ line }}
      </p>
      <label v-if="changes.length || conflicts.length" class="check-line"
        ><input
          v-model="confirmed"
          type="checkbox"
        />已核对时间变化与冲突，确认应用</label
      >
      <div class="modal-actions">
        <button class="secondary" @click="pending = undefined">取消</button
        ><button class="primary" :disabled="busy" @click="apply">
          确认应用作息
        </button>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { Layers, Plus } from "lucide-vue-next";
import type { Course } from "../domain/academic";
import {
  semesterDate,
  type Semester,
  type TimeTable,
  type CellPreset,
} from "../domain/schedule";
import {
  buildTimeAxis,
  layoutWeek,
  timePosition,
} from "../domain/timetable-layout";
import {
  dayNumber,
  weekdays,
  currentWeek,
  timeOf,
} from "../domain/presentation";
const props = defineProps<{
  courses: Course[];
  table: TimeTable;
  semester: Semester;
  week: number;
  now: Date;
}>();
const emit = defineEmits<{
  course: [course: Course];
  conflict: [courses: Course[]];
  create: [preset: CellPreset];
}>();
const visible = computed(() =>
  props.courses.filter((c) => c.weeks.includes(props.week)),
);
const axis = computed(() => buildTimeAxis(props.table, visible.value));
const clusters = computed(() =>
  layoutWeek(props.courses, props.week, axis.value),
);
const inCurrentWeek = computed(
  () => currentWeek(props.now, props.semester) === props.week,
);
const today = (day: number) =>
  inCurrentWeek.value && dayNumber(props.now) === day;
const rows = computed(() => axis.value.segments.filter((s) => s.slot));
const date = (day: number) => {
  const d = semesterDate(props.semester, props.week, day);
  return `${d.getMonth() + 1}/${d.getDate()}`;
};
const pos = (top: number, bottom: number) => ({
  top: `calc(${top} * var(--period-height) + 2px)`,
  height: `calc(${bottom - top} * var(--period-height) - 4px)`,
});
const currentPosition = computed(() =>
  timePosition(axis.value, timeOf(props.now)),
);
</script>
<template>
  <div
    class="period-grid"
    aria-label="按节次定位的周课程表"
    :style="{ '--axis-units': axis.units }"
  >
    <div class="period-grid-head">
      <span class="axis-head">节次</span>
      <div v-for="d in 7" :key="d" :class="{ today: today(d) }">
        <strong>周{{ weekdays[d - 1] }}</strong
        ><small>{{ date(d) }}</small
        ><span v-if="today(d)" class="today-mark" />
      </div>
    </div>
    <div
      class="period-grid-body"
      :style="{ height: `calc(${axis.units} * var(--period-height))` }"
    >
      <div class="period-axis">
        <div
          v-for="s in rows"
          :key="s.slot!.number"
          class="period-label"
          :style="pos(s.from, s.to)"
        >
          <strong>{{ s.slot!.number }}</strong
          ><small>{{ s.slot!.start }}</small
          ><small>{{ s.slot!.end }}</small>
        </div>
        <div
          v-for="(s, i) in axis.segments.filter((s) => !s.slot)"
          :key="'break' + i"
          class="break-mark"
          :style="pos(s.from, s.to)"
          aria-hidden="true"
        >
          ·
        </div>
      </div>
      <div
        v-for="d in 7"
        :key="d"
        class="period-day"
        :class="{ today: today(d) }"
      >
        <button
          v-for="s in rows"
          :key="s.slot!.number"
          class="empty-period"
          :style="pos(s.from, s.to)"
          :aria-label="`添加周${weekdays[d - 1]}第${s.slot!.number}节课程，${s.slot!.start}`"
          @click="emit('create', { day: d, period: s.slot!.number, week })"
        >
          <Plus :size="15" aria-hidden="true" />
        </button>
        <template
          v-for="group in clusters.filter((c) => c.day === d)"
          :key="group.items.map((i) => i.course.id).join('/')"
        >
          <button
            v-if="group.items.length === 1"
            class="positioned-course"
            :class="group.items[0].course.color"
            :style="pos(group.top, group.bottom)"
            :data-course-id="group.items[0].course.id"
            :aria-label="`${group.items[0].course.name}，${group.items[0].course.room}，${group.items[0].course.start}至${group.items[0].course.end}`"
            @click="emit('course', group.items[0].course)"
          >
            <strong>{{ group.items[0].course.name }}</strong
            ><span>{{ group.items[0].course.room || "地点待填" }}</span
            ><small v-if="group.bottom - group.top >= 1.5">{{
              group.items[0].course.start
            }}</small>
          </button>
          <button
            v-else
            class="positioned-course overlap-course"
            :style="pos(group.top, group.bottom)"
            :aria-label="`${group.items.length}门重叠课程：${group.items.map((i) => i.course.name).join('、')}，点击逐门查看`"
            @click="
              emit(
                'conflict',
                group.items.map((i) => i.course),
              )
            "
          >
            <span class="overlap-count"
              ><Layers :size="13" />{{ group.items.length }}门</span
            ><strong
              v-for="item in group.items.slice(0, 2)"
              :key="item.course.id"
              >{{ item.course.name }}</strong
            ><small>重叠 · 查看</small>
          </button>
        </template>
        <div
          v-if="today(d) && currentPosition > 0 && currentPosition < axis.units"
          class="current-time-line"
          :style="{ top: `calc(${currentPosition} * var(--period-height))` }"
          aria-hidden="true"
        />
      </div>
    </div>
  </div>
</template>

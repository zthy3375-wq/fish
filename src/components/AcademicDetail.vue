<script setup lang="ts">
import WeekCalibration from "./WeekCalibration.vue";
import { computed, ref, watch } from "vue";
import { ChevronLeft, ChevronRight, Info } from 'lucide-vue-next';
import type { AcademicData, Course } from "../domain/academic";
import { coursesForDay } from "../domain/academic";
import {
  currentWeek,
  dayNumber,
  weekdays,
  courseState,
} from "../domain/presentation";
import {
  semesterDate,
  type Semester,
  type TimeTable,
  type CellPreset,
} from "../domain/schedule";
import { scheduleViews } from '../composables/view-state';
import { academicCache, academicBusy, selectSchoolTerm } from '../composables/handan-academic';
import ScheduleGrid from "./ScheduleGrid.vue";
import CourseCard from "./CourseCard.vue";
import EmptyState from "./EmptyState.vue";
const comfortable=ref(false);
const props = defineProps<{
  practice?: {name:string;teacher:string;weeks:string}[];
  table: TimeTable;
  semester: Semester;
  mode: "demo" | "personal" | "official";
  section: string;
  data: AcademicData;
  now: Date;
}>();
const emit = defineEmits<{
  navigate: [section: string];
  course: [course: Course];
  create: [preset?: CellPreset];
  conflict: [courses: Course[]];
}>();
const state = computed(() => {
  scheduleViews[props.semester.id] ??= {
  week: Math.max(1, Math.min(props.semester.weekCount, currentWeek(props.now, props.semester))),
  day: dayNumber(props.now), view: 'week',
  };
  return scheduleViews[props.semester.id];
});
const week = computed({get:()=>Math.min(props.semester.weekCount,state.value.week),set:(value:number)=>{state.value.week=value}});
const day = computed({get:()=>state.value.day,set:(value:number)=>{state.value.day=value}});
const view = computed({get:()=>state.value.view,set:(value:'day'|'week')=>{state.value.view=value}});
function termChange(event:Event) {
  const [xnm,xqm]=(event.target as HTMLSelectElement).value.split('-');
  void selectSchoolTerm({xnm,xqm});
}
watch(()=>props.semester.weekStartDate,()=>{week.value=Math.max(1,Math.min(props.semester.weekCount,currentWeek(props.now,props.semester)));day.value=dayNumber(props.now)});
const actualWeek = computed(() => currentWeek(props.now, props.semester));
const selectedCourses = computed(() =>
  coursesForDay(props.data.courses, day.value, week.value),
);
const isToday = computed(
  () => week.value === actualWeek.value && day.value === dayNumber(props.now),
);
const upcomingId = computed(() =>
  isToday.value
    ? selectedCourses.value.find(
        (c) =>
          c.start >
          `${String(props.now.getHours()).padStart(2, "0")}:${String(props.now.getMinutes()).padStart(2, "0")}`,
      )?.id
    : undefined,
);
function details(c: Course) {
  emit("course", c);
}
function weekDate(week: number, day: number) {
  const d = semesterDate(props.semester, week, day);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}
let touchX = 0,
  touchY = 0;
function touchStart(e: TouchEvent) {
  touchX = e.changedTouches[0].clientX;
  touchY = e.changedTouches[0].clientY;
}
function touchEnd(e: TouchEvent) {
  const dx = e.changedTouches[0].clientX - touchX,
    dy = e.changedTouches[0].clientY - touchY;
  if (touchX < 24 || touchX > window.innerWidth - 24) return;
  if (Math.abs(dx) > 80 && Math.abs(dx) > Math.abs(dy) * 2)
    week.value = Math.max(
      1,
      Math.min(props.semester.weekCount, week.value + (dx < 0 ? 1 : -1)),
    );
}
</script>
<template>
  <section
    v-if="section === 'schedule'"
    class="schedule-page"
    @touchstart.passive="touchStart"
    @touchend.passive="touchEnd"
  >
    <label v-if="academicCache.semesters.data?.length" class="schedule-term">
      <span>学期</span><select :value="academicCache.selectedTerm" :disabled="academicBusy" aria-label="课表学期" @change="termChange"><option v-for="t in academicCache.semesters.data" :key="`${t.xnm}-${t.xqm}`" :value="`${t.xnm}-${t.xqm}`">{{t.xnm}}–{{Number(t.xnm)+1}} {{t.xqm==='3'?'秋季':'春季'}}</option></select>
    </label>
    <WeekCalibration :semester="semester" :now="now" @saved="week=Math.max(1,Math.min(semester.weekCount,currentWeek(now,semester)));day=dayNumber(now)"/>
    <div class="schedule-toolbar"><button class="text-button" :aria-pressed="comfortable" @click="comfortable=!comfortable">{{comfortable?'舒适阅读':'整周总览'}}</button>
      <div class="segmented" aria-label="课表视图">
        <button
          :class="{ selected: view === 'day' }"
          :aria-pressed="view === 'day'"
          @click="view = 'day'"
        >
          日视图</button
        ><button
          :class="{ selected: view === 'week' }"
          :aria-pressed="view === 'week'"
          @click="view = 'week'"
        >
          周视图
        </button>
      </div>
      <button
        class="text-button"
        @click="
          week = Math.max(1, Math.min(semester.weekCount, actualWeek));
          day = dayNumber(now);
        "
      >
        回到本周
      </button>
    </div>
    <div class="week-toolbar">
      <button
        class="icon-button"
        aria-label="上一周"
        :disabled="week === 1"
        @click="week--"
      >
        <ChevronLeft :size="20" /></button
      ><label
        ><select v-model.number="week" aria-label="跳转教学周">
          <option v-for="w in semester.weekCount" :key="w" :value="w">
            第 {{ w }} 周
          </option></select
        ><span
          >{{ weekDate(week, 1) }} — {{ weekDate(week, 7) }} ·
          {{ week === actualWeek ? "当前周" : "非当前周" }}</span
        ></label
      ><button
        class="icon-button"
        aria-label="下一周"
        :disabled="week === semester.weekCount"
        @click="week++"
      >
        <ChevronRight :size="20" />
      </button>
    </div>
    <div v-if="view === 'day'" class="week-days" aria-label="选择星期">
      <button
        v-for="(d, i) in weekdays"
        :key="d"
        :class="{
          selected: day === i + 1,
          today: week === actualWeek && i + 1 === dayNumber(now),
        }"
        :aria-pressed="day === i + 1"
        @click="day = i + 1"
      >
        <small>周{{ d }}</small
        ><strong>{{ weekDate(week, i + 1).split("/")[1] }}</strong
        ><i />
      </button>
    </div>
    <div :key="`${view}-${week}-${day}`" class="schedule-view">
        <template v-if="view === 'day'"
          ><div class="section-heading agenda-heading">
            <h2>周{{ weekdays[day - 1] }}的安排</h2>
            <span class="section-meta"
              >{{ selectedCourses.length }} 节课程 ·
              {{
                mode === "official"
                  ? "学校授权"
                  : mode === "demo"
                    ? "演示"
                    : "个人"
              }}</span
            >
          </div>
          <div class="course-list">
            <CourseCard
              v-for="c in selectedCourses"
              :key="c.id"
              :course="c"
              :status="courseState(c, now, isToday)"
              :next="c.id === upcomingId"
              @select="details"
            /><EmptyState
              v-if="!selectedCourses.length"
              title="这天没有课程"
              description="留一点时间，安排自己的节奏。"
            /></div
        ></template>
        <ScheduleGrid
          :class="{comfortable}"
          v-else
          :read-only="false"
          :courses="data.courses"
          :table="table"
          :semester="semester"
          :week="week"
          :now="now"
          @course="details"
          @create="emit('create', $event)"
          @conflict="emit('conflict', $event)"
        />
    </div>
    <section v-if="practice?.length" class="panel"><h2>实践课程</h2><p class="muted">学校按教学周安排，未提供具体星期与节次。</p><article v-for="(p,i) in practice" :key="i" class="service-row"><span class="row-copy"><strong>{{p.name}}</strong><small>{{p.weeks}} · {{p.teacher}}</small></span></article></section>
    <p class="footnote">
      {{
        mode === "official"
          ? "学校课表已缓存 · 教学周按本机校历"
          : mode === "demo"
            ? "演示课表"
            : "个人课表 · 已保存在本机"
      }}
      · 左右滑动切周 ·
      {{ mode === "official" ? "学校课程只读，个人事项可编辑" : "点击空白格添加" }} ·
      重叠课程点开逐门查看
    </p>
  </section>
  <section v-else-if="section === 'calendar'" class="panel">
    <div class="section-heading">
      <div>
        <h2>学期校历</h2>
        <p class="muted">
          {{ semester.startDate }} 开始，共 {{ semester.weekCount }} 周
        </p>
      </div>
      <span class="soft-pill">{{
        mode === "official"
          ? "本机教学周"
          : mode === "demo"
            ? "演示校历"
            : "个人学期"
      }}</span>
    </div>
    <div class="calendar-grid">
      <button
        v-for="w in semester.weekCount"
        :key="w"
        :class="{ current: w === actualWeek }"
        @click="
          week = w;
          emit('navigate', 'schedule');
        "
      >
        <small>第 {{ w }} 周</small><strong>{{ weekDate(w, 1) }}</strong
        ><span>{{ w === actualWeek ? "当前周" : "教学周" }}</span>
      </button>
    </div>
    <p class="inline-note">
      <Info :size="17" />{{
        mode === "official"
          ? "教学周日期采用本机学期设置，实际放假与调课以学校通知为准。"
          : "此为本机配置的学期日历，并非学校官方校历。"
      }}
    </p>
  </section>
</template>

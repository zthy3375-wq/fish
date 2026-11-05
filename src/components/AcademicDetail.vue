<script setup lang="ts">
import { ref, computed, watch } from "vue";
import {
  ChevronLeft,
  ChevronRight,
  MapPin,
  BookOpen,
  GraduationCap,
  LibraryBig,
  ArrowUpRight,
  CalendarDays,
  Info,
  Search,
} from "lucide-vue-next";
import type { AcademicData, Course } from "../domain/academic";
import { coursesForDay, weightedAverage } from "../domain/academic";
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
import ScheduleGrid from "./ScheduleGrid.vue";
import CourseCard from "./CourseCard.vue";
import EmptyState from "./EmptyState.vue";
const props = defineProps<{
  table: TimeTable;
  semester: Semester;
  mode: "demo" | "personal";
  section: string;
  data: AcademicData;
  now: Date;
  major: string;
}>();
const emit = defineEmits<{
  navigate: [section: string];
  course: [course: Course];
  manage: [tab?: string];
  create: [preset?: CellPreset];
  conflict: [courses: Course[]];
}>();
const week = ref(
    Math.max(
      1,
      Math.min(
        props.semester.weekCount,
        currentWeek(props.now, props.semester),
      ),
    ),
  ),
  day = ref(dayNumber(props.now)),
  view = ref("week"),
  query = ref(""),
  term = ref("all");
const actualWeek = computed(() => currentWeek(props.now, props.semester));
const prefs = computed(() => ({ major: props.major }));
const selectedCourses = computed(() =>
  coursesForDay(props.data.courses, day.value, week.value),
);
const filteredGrades = computed(() =>
  props.data.grades.filter(
    (g) =>
      (term.value === "all" || g.term === term.value) &&
      g.name.includes(query.value),
  ),
);
const average = computed(() =>
  weightedAverage(filteredGrades.value).toFixed(1),
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
watch(
  () =>
    `${props.semester.id}/${props.semester.weekStartDate}/${props.semester.weekCount}`,
  () => {
    week.value = Math.max(
      1,
      Math.min(
        props.semester.weekCount,
        currentWeek(props.now, props.semester),
      ),
    );
  },
);
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
    <div class="schedule-actions">
      <button class="primary" @click="emit('create')">＋ 添加课程</button
      ><button class="secondary" @click="emit('manage', 'import')">导入</button
      ><button class="secondary" @click="emit('manage', 'times')">
        作息与设置
      </button>
    </div>
    <div class="schedule-toolbar">
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
    <Transition name="content" mode="out-in"
      ><div :key="`${view}-${week}-${day}`">
        <template v-if="view === 'day'"
          ><div class="section-heading agenda-heading">
            <h2>周{{ weekdays[day - 1] }}的安排</h2>
            <span class="section-meta"
              >{{ selectedCourses.length }} 节课程 ·
              {{ mode === "demo" ? "演示" : "个人" }}</span
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
          v-else
          :courses="data.courses"
          :table="table"
          :semester="semester"
          :week="week"
          :now="now"
          @course="details"
          @create="emit('create', $event)"
          @conflict="emit('conflict', $event)"
        /></div
    ></Transition>
    <p class="footnote">
      {{ mode === "demo" ? "演示课表" : "个人课表 · 已保存在本机" }} ·
      左右滑动切周 · 点击空白格添加 · 重叠课程点开逐门查看
    </p>
    <button
      class="text-button academic-services-link"
      @click="emit('navigate', 'overview')"
    >
      成绩、考试与其他教务服务 <ChevronRight :size="15" />
    </button>
  </section>
  <section v-else-if="section === 'grades'" class="panel">
    <div class="section-heading">
      <div>
        <h2>成绩查询</h2>
        <p class="muted">成绩与学分均为演示内容</p>
      </div>
      <select v-model="term" aria-label="筛选学期">
        <option value="all">全部学期</option>
        <option>2025–2026 春季</option>
        <option>2025–2026 秋季</option>
      </select>
    </div>
    <div class="grade-stats">
      <div>
        <small>加权平均分</small><strong>{{ average }}</strong>
      </div>
      <div>
        <small>已获学分（当前筛选）</small
        ><strong>{{ filteredGrades.reduce((s, g) => s + g.credit, 0) }}</strong>
      </div>
      <div>
        <small>通过课程</small
        ><strong
          >{{ filteredGrades.filter((g) => g.score >= 60).length
          }}<em> / {{ filteredGrades.length }}</em></strong
        >
      </div>
    </div>
    <label class="search"
      ><Search :size="18" /><input
        v-model="query"
        placeholder="搜索课程名称"
        aria-label="搜索课程名称"
    /></label>
    <div class="grade-list">
      <div v-for="g in filteredGrades" :key="g.name" class="grade-row">
        <span class="entry-icon blue"><BookOpen :size="20" /></span>
        <div>
          <h3>{{ g.name }}</h3>
          <small>{{ g.term }} · {{ g.kind }} · {{ g.credit }} 学分</small>
        </div>
        <strong>{{ g.score }}<small>分</small></strong>
      </div>
      <EmptyState
        v-if="!filteredGrades.length"
        title="没有找到匹配的课程"
        description="试试其他名称或学期。"
      />
    </div>
    <p class="muted">
      加权平均分 = Σ（成绩 × 学分）/ Σ学分；暂不推算学校官方 GPA。
    </p>
  </section>
  <section v-else-if="section === 'exams'" class="panel">
    <div class="section-heading">
      <h2>考试安排</h2>
      <span class="soft-pill">{{ data.exams.length }} 场模拟考试</span>
    </div>
    <div class="exam-list">
      <article v-for="(e, i) in data.exams" :key="e.name" class="exam-card">
        <span class="exam-number">0{{ i + 1 }}</span>
        <div>
          <h3>{{ e.name }}</h3>
          <p><CalendarDays :size="15" />{{ e.date }} · {{ e.time }}</p>
          <p><MapPin :size="15" />{{ e.room }} · 座位 {{ e.seat }}</p>
        </div>
        <span class="soft-pill">期末考试</span>
      </article>
    </div>
    <div class="inline-note">
      <Info :size="17" />实际考试时间、地点请以学校发布的信息为准。
    </div>
  </section>
  <section v-else-if="section === 'study'" class="panel">
    <h2>学业信息</h2>
    <p class="muted">模拟培养方案 · 非官方毕业资格判断</p>
    <div class="study-summary">
      <GraduationCap :size="43" />
      <div>
        <h3>{{ prefs.major }}</h3>
        <p>四年制本科 · 演示学籍</p>
      </div>
    </div>
    <div
      class="credit-block"
      v-for="c in [
        { name: '通识教育', done: 28, total: 40 },
        { name: '专业教育', done: 52, total: 90 },
        { name: '实践教学', done: 12, total: 30 },
      ]"
      :key="c.name"
    >
      <div>
        <strong>{{ c.name }}</strong
        ><span>{{ c.done }} / {{ c.total }} 学分</span>
      </div>
      <div class="progress">
        <span :style="{ width: (c.done / c.total) * 100 + '%' }" />
      </div>
    </div>
    <p class="inline-note">
      学分进度为独立模拟示例，与成绩页的演示课程不构成完整对应。
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
        mode === "demo" ? "演示校历" : "个人学期"
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
      <Info :size="17" />本校历不是邯郸学院官方校历，不用于实际教学安排。
    </p>
  </section>
  <section v-else class="panel official-panel">
    <span class="entry-icon blue"><LibraryBig :size="30" /></span>
    <h2>连接官方，获取准确信息。</h2>
    <p>
      在学校官方网站查询正式教务信息。<br />本应用不会读取或保存你在学校网站输入的账号与密码。
    </p>
    <a
      href="https://jwgl.hdc.edu.cn/xtgl/login_slogin.html"
      target="_blank"
      rel="noopener noreferrer"
      class="official-link"
      ><span
        ><strong>教学综合信息服务平台</strong
        ><small>jwgl.hdc.edu.cn</small></span
      ><ArrowUpRight :size="22" /></a
    ><a
      href="https://www.hdc.edu.cn/"
      target="_blank"
      rel="noopener noreferrer"
      class="official-link"
      ><span
        ><strong>邯郸学院官方网站</strong><small>www.hdc.edu.cn</small></span
      ><ArrowUpRight :size="22"
    /></a>
    <p class="muted">链接将于外部浏览器打开；能否访问取决于学校网络服务。</p>
  </section>
</template>

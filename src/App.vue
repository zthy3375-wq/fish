<script setup lang="ts">
import LearningCenter from './components/LearningCenter.vue';
import TaskDetail from './components/TaskDetail.vue';
import TaskSettings from './components/TaskSettings.vue';
import TodayTasks from './components/TodayTasks.vue';
import {beijingDay,type CampusTask} from './domain/agenda';
import {initLearning,syncLearning,learningTasks} from './composables/learning';
import {taskSummary} from './domain/tasks';
import CampusAgenda from './components/CampusAgenda.vue';
import {initTasks,reloadTasks,taskSnapshot,tasksReady,agendaView,taskView,allTasks,reconcileTaskReminders} from './composables/tasks';
import {version as appVersion} from '../package.json';
import {
  ref,
  computed,
  watch,
  onMounted,
  onUnmounted,
  nextTick,
} from "vue";
import { Capacitor, type PluginListenerHandle } from "@capacitor/core";
import { App as NativeApp } from "@capacitor/app";
import { StatusBar, Style } from "@capacitor/status-bar";
import {
  GraduationCap,
  BookOpen,
  CalendarDays,
  ChartNoAxesColumnIncreasing,
  UserRound,
  Settings2,
  ShieldCheck,
  Database,
  Sun,
  Moon,
  Monitor,
  X,
  Check,
  RefreshCw,
  Info,
  Bell,
  ChevronRight,
  ArrowRight,
  ArrowUpRight,
  Clock3,
  MapPin,
  CheckCheck,
  Github,
  MessageSquare,
} from "lucide-vue-next";
import type { AcademicData, Course } from "./domain/academic";
import { coursesForDay, weightedAverage } from "./domain/academic";
import {
  campusNow,
  currentWeek,
  dayNumber,
  timeOf,
  nextOccurrence,
  dateLabel,
  untilLabel,
  courseState,
  upcomingExams,
  weekdays,
} from "./domain/presentation";
import ScheduleManager from "./components/ScheduleManager.vue";
import CourseEditor from "./components/CourseEditor.vue";
import { isSchoolPageSemester } from "./services/legacy-school-semester";
import { upsertCourse } from "./services/course-management";
import {
  schedule,
  semester as personalSemester,
  initSchedule,
  refreshSchedule,
  changeSchedule,
  storageError,
} from "./composables/schedule";
import {
  flatten,
  tableForSemester,
  type CellPreset,
  type ManagedCourse,
} from "./domain/schedule";
import { reconcileReminders } from "./services/reminders";
import {academicCache,schoolTerm,initAcademic,autoSyncAcademic,syncAcademic} from './composables/handan-academic';
import SchoolConnection from './components/SchoolConnection.vue';
import SchoolAcademicRecords from './components/SchoolAcademicRecords.vue';
import {
  loadPreferences,
  savePreferences,
  clearPreferences,
  defaults,
} from "./services/preferences";
import { useNavigation, type Page } from "./composables/navigation";
import AppHeader from "./components/AppHeader.vue";
import FloatingNavigation from "./components/FloatingNavigation.vue";
import SectionHeader from "./components/SectionHeader.vue";
import QuickAction from "./components/QuickAction.vue";
import ServiceGroup from "./components/ServiceGroup.vue";
import CourseCard from "./components/CourseCard.vue";
import AcademicDetail from "./components/AcademicDetail.vue";
import EmptyState from "./components/EmptyState.vue";
import LoadingState from "./components/LoadingState.vue";
import SettingsRow from "./components/SettingsRow.vue";
const {
  page,
  section,
  overlay: modal,
  move,
  open,
  close,
  back,
  canBack,
  setOverlayCloseGuard,
  setBeforeBack,
} = useNavigation();
const prefs = ref(loadPreferences()),
  draft = ref({ name: "", major: "" }),
  selected = ref<Course>(),
  loading = ref(true),
  error = ref(""),
  toast = ref(""),
  read = ref(false),
  now = ref(campusNow());
const localSemester = personalSemester;
const localTable = computed(() => tableForSemester(schedule.value));
const officialActive = computed(() => !!schoolTerm.value?.data);
const semester = computed(() => schoolTerm.value?.data?.semester ?? localSemester.value);
const table = computed(() => schoolTerm.value?.data?.table ?? localTable.value);
const data = computed<AcademicData>(() => {
 const cached=schoolTerm.value?.data;
 const personal=cached ? schedule.value.courses.filter(c=>{
   const t=schedule.value.semesters.find(t=>t.id===c.semesterId);
   return !isSchoolPageSemester(c.semesterId)&&t?.academicYear===cached.semester.academicYear&&t?.season===cached.semester.season;
 }) : schedule.value.courses;
 return {source:cached?'official':'personal',courses:cached?[...flatten(cached.courses,cached.semester.id,cached.table),...personal.flatMap(c=>flatten([c],c.semesterId,cached.table))]:flatten(personal,schedule.value.activeSemesterId,localTable.value),grades:[],exams:academicCache.value.exams.data??[]};
});
const editorRef = ref<InstanceType<typeof CourseEditor>>(),
  editorCourse = ref<ManagedCourse>(),
  editorPreset = ref<CellPreset>(),
  editorBusy = ref(false),
  editorError = ref(""),
  managerInitial = ref("courses"),
  deleteIntent = ref(""),
  detailError = ref(""),
  conflictCourses = ref<Course[]>([]);
async function createCourse(preset?: CellPreset) {
  if (schoolTerm.value?.data) {
    const school=schoolTerm.value.data;
    const match=schedule.value.semesters.find(s=>s.academicYear.replace(/[–—]/g,'-')===school.semester.academicYear.replace(/[–—]/g,'-')&&s.season===school.semester.season&&!isSchoolPageSemester(s.id));
    if(match){
      await changeSchedule(s=>{s.activeSemesterId=match.id;if(!s.timeTables.some(t=>t.id===school.table.id))s.timeTables.push(school.table);s.semesters.find(t=>t.id===match.id)!.timeTableId=school.table.id;s.mode='personal'});
    }
  }
  if (preset && preset.period > tableForSemester(schedule.value).slots.length) {
    notify("个人作息中没有该节次，请先设置作息");
    manage(undefined, "times");
    return;
  }
  editorCourse.value = undefined;
  editorPreset.value = preset;
  editorError.value = "";
  open("course-editor");
}
function openEditor(id: string) {
  const c = schedule.value.courses.find((c) => c.id === id);
  if (!c) {
    notify("课程不存在或已被删除");
    return;
  }
  editorCourse.value = JSON.parse(JSON.stringify(c));
  editorPreset.value = undefined;
  editorError.value = "";
  open("course-editor");
}
function manage(id?: string, initial = "courses") {
  if (id) {
    openEditor(id);
    return;
  }
  managerInitial.value = initial;
  open("manager");
}
async function saveCourse(course: ManagedCourse, allow: boolean) {
  editorBusy.value = true;
  editorError.value = "";
  try {
    await changeSchedule((s) => upsertCourse(s, course, allow));
      close();
    notify("课程已保存，首页与课表已同步");
  } catch (e) {
    editorError.value = (e as Error).message;
  } finally {
    editorBusy.value = false;
  }
}
const taskDetailRef=ref<InstanceType<typeof TaskDetail>>();
function planLearning(task:CampusTask){taskDetailRef.value?.edit(task)}
function editDailyTask(task?:CampusTask,day?:string){taskDetailRef.value?.edit(task,day)}
setBeforeBack(()=>!modal.value?taskDetailRef.value?.requestBack()??false:false);
setOverlayCloseGuard(() => {
  if (modal.value==='course'&&deleteIntent.value) {deleteIntent.value='';return false;}
  if (modal.value==='course-editor'&&editorRef.value?.hasChanges()) {
    editorRef.value.requestCancel();
    return false;
  }
  return true;
});
function requestClose() {
  if (modal.value === "course"&&deleteIntent.value) deleteIntent.value="";
  else if (modal.value === "course-editor") editorRef.value?.requestCancel();
  else close();
}
async function removeSelected(whole: boolean) {
  const c = selected.value;
  if (!c?.courseId) return;
  try {
    await changeSchedule((s) => {
      const target = s.courses.find((x) => x.id === c.courseId);
      if (!target) throw Error("课程已不存在");
      if (whole || target.arrangements.length === 1)
        s.courses = s.courses.filter((x) => x.id !== c.courseId);
      else
        target.arrangements = target.arrangements.filter(
          (a) => a.id !== c.arrangementId,
        );
    });
    close();
    notify("已删除，课表已更新");
  } catch (e) {
    detailError.value = (e as Error).message;
  }
}
function showConflicts(courses: Course[]) {
  conflictCourses.value = courses;
  open("course-conflicts");
}

const week = computed(() => currentWeek(now.value, semester.value)),
  todayCourses = computed(() =>
    coursesForDay(data.value.courses, dayNumber(now.value), week.value),
  );
const current = computed(() =>
  todayCourses.value.find((c) => courseState(c, now.value) === "current"),
);
const next = computed(() =>
  nextOccurrence(data.value.courses, now.value, semester.value),
);
const exams = computed(() => upcomingExams(data.value.exams, now.value));
const weekCount = computed(
  () => data.value.courses.filter((c) => c.weeks.includes(week.value)).length,
);
const entries = computed(() => [
  {
    id: "schedule",
    title: "课程表",
    subtitle: `本周 ${weekCount.value} 节`,
    icon: BookOpen,
  },
  {
    id: "grades",
    title: "成绩分析",
    subtitle: academicCache.value.grades.updatedAt ? `${academicCache.value.grades.data?.length??0} 门成绩` : "尚未同步",
    icon: ChartNoAxesColumnIncreasing,
  },
  {
    id: "exams",
    title: "考试安排",
    subtitle: academicCache.value.exams.updatedAt ? `${exams.value.length} 场考试` : "尚未同步",
    icon: CalendarDays,
  },
  {
    id: "study",
    title: "学业中心",
    subtitle: "已获学分、课程类型与学籍",
    icon: GraduationCap,
  },
]);
const academicServices=computed(()=>[...entries.value.filter(e=>e.id!=='schedule'),{id:'learning',title:'学习通',subtitle:'作业、课程、考试与通知',icon:BookOpen},{id:'agenda',title:'统一日程',subtitle:'课程、考试与个人待办',icon:CalendarDays},{id:'calendar',title:'学期校历',subtitle:'教学周与学期安排',icon:CalendarDays}]);
const official=[{id:'school',title:'邯郸学院官网',subtitle:'学校新闻与公开信息',icon:ArrowUpRight,href:'https://www.hdc.edu.cn/'}];
const settings = [
  {
    id: "notifications",
    title: "通知设置",
    subtitle: "应用内提醒与消息",
    icon: Bell,
  },
  {
    id: "cache",
    title: "缓存管理",
    subtitle: "查看数据存储状态",
    icon: Database,
  },
  {
    id: "manager",
    title: "课表与数据管理",
    subtitle: "课程、学期、备份与提醒",
    icon: Settings2,
  },
];
const about = [
  { id: "privacy", title: "隐私政策", icon: ShieldCheck },
  {
    id: "github",
    title: "GitHub 开源项目",
    icon: Github,
    href: "https://github.com/zthy3375-wq/fish",
  },
  {
    id: "feedback",
    title: "问题反馈",
    icon: MessageSquare,
    href: "https://github.com/zthy3375-wq/fish/issues",
  },
  { id: "about", title: "版本信息", subtitle: `邯郸校园 · v${appVersion}`, icon: Info },
];
const sectionNames: Record<string, string> = {
  overview: "学习",
  agenda: "统一日程",
  learning: "学习通",
  schedule: "课程表",
  grades: "成绩分析",
  exams: "考试安排",
  study: "学业中心",
  calendar: "学期校历",
  official: "官方教务",
};
const title = computed(() =>
  page.value === "home"
    ? "今天"
    : page.value === "tasks" ? "待办" : page.value === "schedule" ? "课程表" : page.value === "academic"
      ? sectionNames[section.value]
      : "我的",
);
const subtitle = computed(() =>
  page.value === "home"
    ? `${dateLabel(now.value)} 周${weekdays[dayNumber(now.value) - 1]} · ${week.value >= 1 && week.value <= semester.value.weekCount ? "第 " + week.value + " 周" : "学期外"} · ${officialActive.value ? "学校课表 · 已缓存" : isSchoolPageSemester(schedule.value.activeSemesterId) ? "已保存课表" : "个人课表"}`
    : page.value === "tasks" ? "今天、接下来，按自己的节奏" : page.value === 'academic' && section.value==='overview' ? '作业、课程与教务' : page.value === "academic" && section.value==='learning' ? "作业与课程" : page.value === "academic" || page.value === "schedule"
      ? `${semester.value.academicYear} ${semester.value.season} · ${officialActive.value ? "学校课表 · 已缓存" : isSchoolPageSemester(schedule.value.activeSemesterId) ? "已保存课表" : "个人课表"}`
      : "学校账号 · 本机设置",
);
const greeting = computed(() =>
  now.value.getHours() < 12
    ? "上午好"
    : now.value.getHours() < 18
      ? "下午好"
      : "晚上好",
);
watch(data, (d) => {
  if (modal.value === "course" && selected.value) {
    const fresh = d.courses.find((c) => c.id === selected.value?.id);
    if (fresh) selected.value = fresh;
    else close();
  }
});
watch(learningTasks,()=>{if(tasksReady.value)void reconcileTaskReminders()});
function go(id: string) {
  if(id==='due'){taskView.view='due';taskView.mode='list';taskView.source='all';taskView.course='';taskView.search='';move('tasks','agenda');return;}
  move(id==='agenda'?'tasks':id === 'schedule' ? 'schedule' : 'academic', id);
}
function nav(p: Page) { move(p, p === "schedule" ? "schedule" : "overview"); }
const content=ref<HTMLElement>();
const scrollPositions=new Map<string,number>();
watch(()=>`${page.value}/${section.value}`,async(key,oldKey)=>{scrollPositions.set(oldKey,content.value?.scrollTop??0);await nextTick();content.value?.scrollTo({top:scrollPositions.get(key)??0,behavior:'instant'})});
function details(c: Course) {
  selected.value = c;
  deleteIntent.value = "";
  detailError.value = "";
  open("course");
}
let toastTimer: ReturnType<typeof setTimeout>,
  clockTimer: ReturnType<typeof setInterval>,
  nativeForeground: PluginListenerHandle | undefined,
  nativeBack: PluginListenerHandle | undefined,
  focusBefore: HTMLElement | null = null,
  disposed = false;
function notify(s: string) {
  toast.value = s;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toast.value = ""), 3000);
}
async function load() {
  loading.value = true;
  error.value = "";
  try {
    await initSchedule();
    await initAcademic();
    void autoSyncAcademic();
    await reconcileReminders(schedule.value);
    void autoSyncAcademic();
  } catch (e) {
    error.value = storageError.value || "教务信息加载失败：" + String(e);
  } finally {
    loading.value = false;
  }
}
function saveProfile() {
  prefs.value.name = draft.value.name.trim() || "同学";
  prefs.value.major = draft.value.major.trim();
  close();
  notify("个人资料已保存在本机");
}
function reset() {
  if (clearPreferences()) {
    prefs.value = { ...defaults };
    close();
    notify("本机设置已恢复默认");
  } else notify("浏览器未允许清除本机设置");
}
watch(
  prefs,
  (p) => {
    if (!savePreferences(p)) notify("设置未保存：浏览器存储不可用");
  },
  { deep: true },
);
const media = window.matchMedia("(prefers-color-scheme: dark)"),
  systemDark = ref(media.matches);
const dark = computed(
  () =>
    prefs.value.theme === "dark" ||
    (prefs.value.theme === "system" && systemDark.value),
);
async function nativeTheme() {
  if (Capacitor.isNativePlatform())
    try {
      await StatusBar.setStyle({
        style: dark.value ? Style.Dark : Style.Light,
      });
      if (Capacitor.getPlatform() === "android")
        await StatusBar.setBackgroundColor({
          color: dark.value ? "#171c24" : "#f7f8fb",
        });
    } catch {
      /* Unsupported system-bar operations do not block the app. */
    }
}
watch(
  dark,
  () => {
    document.documentElement.dataset.theme = dark.value ? "dark" : "light";
    document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute("content", dark.value ? "#171c24" : "#f7f8fb");
    nativeTheme();
  },
  { immediate: true },
);
function systemChange(e: MediaQueryListEvent) {
  systemDark.value = e.matches;
}
watch(modal, async (value, old) => {
  if (value) {
    if (value === "edit")
      draft.value = { name: prefs.value.name, major: prefs.value.major };
    if (!old) focusBefore = document.activeElement as HTMLElement;
    await nextTick();
    document.querySelector<HTMLElement>("[data-overlay] button")?.focus();
    document.body.style.overflow = "hidden";
  } else {
    document.body.style.overflow = "";
    focusBefore?.focus();
  }
});
function trapFocus(e: KeyboardEvent) {
  const root =
    (e.currentTarget as HTMLElement).querySelector<HTMLElement>(
      "[role=alertdialog]",
    ) || (e.currentTarget as HTMLElement);
  const items = Array.from(
    root.querySelectorAll<HTMLElement>(
      "button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),a[href],summary",
    ),
  ).filter((el) => el.getClientRects().length > 0);
  if (e.shiftKey && document.activeElement === items[0]) {
    e.preventDefault();
    items.at(-1)?.focus();
  } else if (!e.shiftKey && document.activeElement === items.at(-1)) {
    e.preventDefault();
    items[0]?.focus();
  }
}
function escape(e: KeyboardEvent) {
  if(e.key === "Escape"){if(modal.value)requestClose();else if(agendaView.editor)taskDetailRef.value?.requestBack();}
}
async function recalibrate() {
  void syncLearning().catch(()=>{});
  void reloadTasks();
  now.value = campusNow();
  if (document.visibilityState === "visible") {
    await refreshSchedule();
    await reconcileReminders(schedule.value);
    void autoSyncAcademic();
  }
}
watch(schedule, (s) => reconcileReminders(s));
let pullY=0;
function pullStart(e:TouchEvent){pullY=(content.value?.scrollTop??0)<=0&&!((e.target as HTMLElement).closest('.schedule-page,button,select,input,textarea'))?e.changedTouches[0].clientY:-1}
function pullEnd(e:TouchEvent){if(pullY>=0&&e.changedTouches[0].clientY-pullY>100){if(page.value==='academic'&&['overview','learning'].includes(section.value))void syncLearning({force:true});else if(page.value!=='tasks')void syncAcademic()}}
function viewportChange() {
  const v = window.visualViewport;
  document.documentElement.classList.toggle(
    "keyboard-open",
    !!v && window.innerHeight - v.height > 150,
  );
}
onMounted(async () => {
  load();
  void initTasks().catch(()=>{});
  void initLearning().then(()=>syncLearning()).catch(()=>{});
  clockTimer = setInterval(() => (now.value = campusNow()), 30000);
  media.addEventListener("change", systemChange);
  window.addEventListener("keydown", escape);
  document.addEventListener("visibilitychange", recalibrate);
  window.addEventListener("focus", recalibrate);
  window.visualViewport?.addEventListener("resize", viewportChange);
  if (Capacitor.isNativePlatform()) {
    const h = await NativeApp.addListener("appStateChange", ({ isActive }) => {
      if (isActive) recalibrate();
    });
    if (disposed) h.remove();
    else nativeForeground = h;
  }
  if (Capacitor.getPlatform() === "android") {
    const h = await NativeApp.addListener("backButton", () => {
      if (modal.value === "course-editor") requestClose();
      else if (canBack()) back();
      else NativeApp.exitApp();
    });
    if (disposed) h.remove();
    else nativeBack = h;
  }
});
onUnmounted(() => {
  disposed = true;
  clearTimeout(toastTimer);
  clearInterval(clockTimer);
  nativeBack?.remove();
  nativeForeground?.remove();
  media.removeEventListener("change", systemChange);
  window.removeEventListener("keydown", escape);
  document.removeEventListener("visibilitychange", recalibrate);
  window.removeEventListener("focus", recalibrate);
  window.visualViewport?.removeEventListener("resize", viewportChange);
  document.body.style.overflow = "";
});
</script>
<template>
  <TaskDetail ref="taskDetailRef" @saved="notify"/>
  <div
    class="app-shell"
    :class="{ compact: prefs.compact, 'home-active': page === 'home' }"
  >
    <AppHeader
      :inert="!!modal || agendaView.editor"
      :title="title"
      :subtitle="subtitle"
      :back="page === 'academic' && section !== 'overview'"
      :add="page==='schedule'"
      :unread="!read && prefs.notifications"
      @back="back"
      @notifications="open('notifications')"
      @add="createCourse()"
    />
    <main ref="content" @touchstart.passive="pullStart" @touchend.passive="pullEnd" :inert="!!modal || agendaView.editor" tabindex="-1" aria-label="页面内容">
      <LoadingState v-if="loading" />
      <div v-else-if="error" class="error-state" role="alert">
        <Info />
        <h2>{{ error }}</h2>
        <p>读取失败时不会覆盖已有课表。请检查浏览器存储权限后重试。</p>
        <button class="primary" @click="load">重试</button>
      </div>
      <div v-else class="page-content">
          <template v-if="page === 'home'">
            <SchoolConnection compact @connected="move('home')" />
            <div class="home-greeting">
              <span>{{ greeting }}，{{ academicCache.profile.data?.name || prefs.name }}</span
              ><span class="quiet-label">北京时间 {{ timeOf(now) }}</span>
            </div>
            <button
              v-if="next"
              type="button"
              class="next-course compact-next-course"
              :aria-label="'查看下一节课程 ' + next.course.name"
              @click="details(next.course)"
            >
              <span class="next-top"
                ><span class="micro-label"><Clock3 :size="14" />下一节课程</span
                ><span class="time-until">{{
                  untilLabel(next.minutes)
                }}</span></span
              >
              <span class="next-main"
                ><strong :title="next.course.name">{{
                  next.course.name
                }}</strong
                ><span class="next-room"
                  ><MapPin :size="13" /><span>{{
                    next.course.room
                  }}</span></span
                ><ArrowRight :size="18"
              /></span>
              <span class="next-meta"
                ><span
                  ><CalendarDays :size="12" />{{ dateLabel(next.date) }} 周{{
                    weekdays[dayNumber(next.date) - 1]
                  }}</span
                ><span>{{ next.course.start }}–{{ next.course.end }}</span
                ><span
                  ><UserRound :size="12" />{{ next.course.teacher }}</span
                ></span
              >
            </button>
            <div v-else class="next-course">
              <EmptyState
                :title="academicCache.connected && !schoolTerm?.data ? '课表尚未同步成功' : '本学期没有后续课程'"
                :description="academicCache.connected && !schoolTerm?.data ? '当前无法判断课程安排，请查看上方连接状态。' : '可以在教务中心管理课程，或检查当前学期配置。'"
              />
            </div>
            <TodayTasks :now="now" @open="planLearning" @navigate="go" @create="editDailyTask(undefined,beijingDay(now))"/>
            <SectionHeader
              title="今日课程"
              :meta="`${todayCourses.length} 节${current ? ' · 正在上课' : ''}`"
              action="完整课表"
              @action="go('schedule')"
            />
            <div class="course-list home-course-list">
              <CourseCard
                grouped
                v-for="c in todayCourses"
                :key="c.id"
                :course="c"
                :status="courseState(c, now)"
                :next="
                  next?.course.id === c.id &&
                  next?.week === week &&
                  dayNumber(next.date) === dayNumber(now)
                "
                @select="details"
              /><EmptyState
                v-if="!todayCourses.length"
                :title="academicCache.connected && !schoolTerm?.data ? '尚未取得今日课程' : '今天没有课程'"
                :description="
                  next ? '下一次课程会显示在上方。' : '当前学期没有后续安排。'
                "
              />
            </div>
            <SectionHeader title="教务速览" meta="成绩与考试" />
            <div class="quick-grid home-quick">
              <QuickAction
                v-for="e in [
                  ...entries.slice(1, 3),
                ]"
                :key="e.id"
                :title="e.title"
                :subtitle="e.subtitle"
                :icon="e.icon"
                @select="go(e.id)"
              />
            </div>
            <SectionHeader
              title="近期安排"
              :meta="officialActive ? '学校缓存' : '个人安排'"
            />
            <div class="service-group upcoming-group">
              <button
                v-if="schedule.mode === 'personal'"
                class="service-row"
                @click="manage()"
              >
                <BookOpen class="row-icon" /><span class="row-copy"
                  ><strong>管理个人课表</strong
                  ><small>{{
                    !officialActive && next
                      ? next.course.name + " · " + dateLabel(next.date)
                      : "添加或导入课程，安排你的学期"
                  }}</small></span
                ><ChevronRight class="row-chevron" :size="18" /></button
              ><button
                v-for="e in exams.slice(0, 2)"
                :key="e.name"
                class="service-row"
                @click="go('exams')"
              >
                <CalendarDays class="row-icon" /><span class="row-copy"
                  ><strong>{{ e.name }} · 考试</strong
                  ><small
                    >{{ e.date.slice(5) }} · {{ e.time }} · {{ e.room }}</small
                  ></span
                ><ChevronRight class="row-chevron" :size="18" /></button
              ><button class="service-row" @click="go('official')">
                <Bell class="row-icon" /><span class="row-copy"
                  ><strong>公开教务通知</strong
                  ><small>未同步 · 前往官方入口查看</small></span
                ><ChevronRight class="row-chevron" :size="18" />
              </button>
            </div>
          </template>
          <template v-else-if="page === 'academic' || page === 'schedule' || page === 'tasks'">
            <CampusAgenda v-if="section==='agenda'" @course="details" @navigate="go" @edit="editDailyTask" />
            <LearningCenter v-else-if="section==='learning'" @plan="planLearning"/><SchoolAcademicRecords v-else-if="['grades','exams','study','official'].includes(section)" :section="section" />
            <template v-else-if="section === 'overview'">
              <LearningCenter @plan="planLearning"/>
              <SectionHeader title="学校教务" meta="本人数据"/><ServiceGroup :items="academicServices.filter(e=>!['learning','agenda'].includes(e.id))" @select="go"/>
              <SectionHeader title="学校服务" meta="官方外链"/><ServiceGroup :items="official" @select="go"/>
            </template>
            <AcademicDetail v-else
                :key="
                  section === 'calendar' || section === 'schedule'
                    ? 'schedule-family'
                    : section
                "
                :practice="schoolTerm?.data?.practice ?? []"
                :table="table"
                :semester="semester"
                :mode="data.source === 'official' ? 'official' : 'personal'"
                :section="section"
                :data="data"
                :now="now"
                @navigate="go"
                @course="details"
                @create="createCourse"
                @conflict="showConflicts"
            />
          </template>
          <template v-else>
            <button class="profile-strip" @click="open('edit')">
              <span class="avatar">{{ prefs.name.slice(0, 1) || "同" }}</span
              ><span class="profile-copy"
                ><strong>{{ academicCache.profile.data?.name || prefs.name }}</strong
                ><small>{{ academicCache.profile.data?.major || prefs.major }}</small
                ><span>{{academicCache.profile.data?.className || "本地资料"}}</span></span
              ><span class="edit-link">编辑 <ChevronRight :size="15" /></span>
            </button>
            <SchoolConnection /><button class="learning-page-link" @click="go('learning')"><BookOpen :size="20"/><strong>学习通</strong><span>作业、课程与账号管理</span><ChevronRight :size="16"/></button>
            <TaskSettings/>
            <SectionHeader title="外观设置" />
            <section class="settings-group">
              <div class="theme-row">
                <span class="setting-label"><Sun :size="21" />主题</span>
                <div class="theme-options" aria-label="主题选择">
                  <button
                    v-for="t in [
                      { id: 'light', name: '浅色', icon: Sun },
                      { id: 'dark', name: '深色', icon: Moon },
                      { id: 'system', name: '系统', icon: Monitor },
                    ]"
                    :key="t.id"
                    :class="{ selected: prefs.theme === t.id }"
                    :aria-pressed="prefs.theme === t.id"
                    @click="prefs.theme = t.id as typeof prefs.theme"
                  >
                    <component :is="t.icon" :size="16" />{{ t.name }}
                  </button>
                </div>
              </div>
              <SettingsRow
                title="紧凑布局"
                description="更少留白，更高信息密度"
                v-model="prefs.compact"
              />
            </section>
            <SectionHeader title="应用设置" /><ServiceGroup
              :items="settings"
              @select="(id) => (id === 'manager' ? manage() : open(id))"
            />
            <SectionHeader title="关于与隐私" /><ServiceGroup
              :items="about"
              @select="(id) => (id === 'manager' ? manage() : open(id))"
            />
            <p class="footnote source-footnote">
              <ShieldCheck :size="13" />不保存教务密码 · 没有广告与分析追踪
            </p>
          </template>
          <footer>
            邯郸校园 <span>·</span> 独立开源学生项目
            <span>·</span> 非学校官方应用
          </footer>
        </div>
    </main>
    <div class="navigation-dock" :inert="!!modal || agendaView.editor" :class="{ 'nav-suspended': !!modal }">
      <FloatingNavigation :page="page" @navigate="nav" />
    </div>
    <Transition name="toast"
      ><div v-if="toast" class="toast" role="status">
        <Check :size="17" />{{ toast }}
      </div></Transition
    >
    <Transition name="overlay"
      ><div
        v-if="modal"
        class="overlay-scrim"
        :class="{
          editorOpen: modal === 'course-editor',
        }"
        @click.self="requestClose"
        @keydown.tab="trapFocus"
      >
        <section
          data-overlay
          class="overlay-surface"
          :class="{
            'editor-fullscreen': modal === 'course-editor',
          }"
          role="dialog"
          aria-modal="true"
          :aria-label="
            modal === 'course'
              ? '课程详情'
              : '校园助手设置'
          "
        >
          <div class="sheet-grip" aria-hidden="true" />
          <button
            class="icon-button overlay-close"
            aria-label="关闭"
            @click="requestClose"
          >
            <X :size="22" />
          </button>
          <CourseEditor
            v-if="modal === 'course-editor'"
            ref="editorRef"
            :course="editorCourse"
            :preset="editorPreset"
            :semester="personalSemester"
            :table="tableForSemester(schedule)"
            :existing="schedule.courses"
            :saving="editorBusy"
            :save-error="editorError"
            @save="saveCourse"
            @cancel="close"
          />
          <ScheduleManager
            v-else-if="modal === 'manager'"
            :initial="managerInitial"
            @edit="openEditor"
            @create="createCourse()"
          />
          <template v-else-if="modal === 'course-conflicts'"
            ><h2>重叠的课程</h2>
            <p class="muted">
              {{ conflictCourses.length }}
              个安排在同一天发生时间重叠，逐门查看与编辑。
            </p>
            <div class="service-group">
              <button
                v-for="c in conflictCourses"
                :key="c.id"
                class="service-row"
                @click="details(c)"
              >
                <span class="row-copy"
                  ><strong>{{ c.name }}</strong
                  ><small
                    >{{ c.start }}–{{ c.end }} · {{ c.room }} ·
                    {{ c.teacher }}</small
                  ></span
                ><ChevronRight :size="18" />
              </button></div></template
          ><template v-else-if="modal === 'course' && selected"
            ><span class="micro-label"><BookOpen :size="17" />课程详情</span>
            <h2 class="course-detail-title">{{ selected.name }}</h2>
            <p class="muted">
              课程详情 ·
              {{selected.courseId?.startsWith('school-') ? '学校课程 · 只读' : '个人事项'}}
            </p>
            <dl>
              <dt>时间</dt>
              <dd>
                周{{ weekdays[selected.day - 1] }} {{ selected.start }}–{{
                  selected.end
                }}
              </dd>
              <dt>节次</dt>
              <dd>{{ selected.period }}</dd>
              <dt>教室</dt>
              <dd>{{ selected.room }}</dd>
              <dt>教师</dt>
              <dd>{{ selected.teacher }}</dd>
              <dt>教学周</dt>
              <dd>{{ selected.weeks.join("、") }} 周</dd>
              <dt>周规则</dt>
              <dd>
                {{
                  selected.courseId
                    ? {
                        all: "每周",
                        odd: "单周",
                        even: "双周",
                        custom: "自定义周",
                      }[
                        schedule.courses
                          .find((c) => c.id === selected?.courseId)
                          ?.arrangements.find(
                            (a) => a.id === selected?.arrangementId,
                          )?.rule || "custom"
                      ]
                    : officialActive
                      ? "授权周安排"
                      : "演示周安排"
                }}
              </dd>
              <dt v-if="selected.notes">备注</dt>
              <dd v-if="selected.notes">{{ selected.notes }}</dd>
            </dl>
            <div v-if="selected.courseId && !selected.courseId.startsWith('school-')" class="course-detail-actions">
              <button
                class="primary full"
                @click="openEditor(selected.courseId)"
              >
                编辑课程</button
              ><button class="text-button danger" @click="deleteIntent = 'ask'">
                删除安排或课程
              </button>
              <div v-if="deleteIntent" class="confirmation">
                <p>删除后无法撤销。可先在数据管理中导出备份。</p>
                <p v-if="detailError" role="alert">{{ detailError }}</p>
                <button
                  v-if="
                    (schedule.courses.find((c) => c.id === selected?.courseId)
                      ?.arrangements.length || 0) > 1
                  "
                  class="secondary full danger"
                  @click="removeSelected(false)"
                >
                  确认仅删除这个安排</button
                ><button
                  class="secondary full danger"
                  @click="removeSelected(true)"
                >
                  确认删除整门课程</button
                ><button class="text-button" @click="deleteIntent = ''">
                  取消删除
                </button>
              </div>
            </div>
            <button class="primary full" @click="close">完成</button></template
          >
          <template v-else-if="modal === 'notifications'"
            ><h2>通知设置</h2>
            <p class="muted">应用内消息与课程提醒分别设置</p>
            <button
              class="secondary full"
              @click="manage(undefined, 'reminders')"
            >
              设置课程提醒与系统权限</button
            ><SettingsRow
              title="应用内提醒"
              description="显示应用消息和顶部未读标记"
              v-model="prefs.notifications"
            /><EmptyState
              v-if="!prefs.notifications"
              title="提醒已关闭"
              description="你可以随时重新开启。"
            /><template v-else
              ><article class="notice">
                <Info :size="20" />
                <div>
                  <h3>欢迎使用邯郸校园</h3>
                  <p>
                    连接学校后自动同步，离线时可查看上次数据。公开通知请前往学校官网查看。
                  </p>
                  <small>{{ read ? "已读" : "未读" }} · 项目公告</small>
                </div>
              </article>
              <button
                class="secondary full"
                @click="
                  read = true;
                  notify('通知已标记为已读');
                "
              >
                <CheckCheck :size="17" />全部标为已读
              </button></template
            ></template
          >
          <form v-else-if="modal === 'edit'" @submit.prevent="saveProfile">
            <h2>编辑个人资料</h2>
            <p class="muted">无需填写真实学号和身份信息。</p>
            <label class="form-label"
              >昵称<input
                v-model="draft.name"
                maxlength="20"
                required
                autocomplete="nickname"
                placeholder="怎么称呼你" /></label
            ><label class="form-label"
              >专业 / 年级<input
                v-model="draft.major"
                maxlength="50"
                required /></label
            ><button class="primary full" type="submit">保存资料</button>
          </form>
          <template v-else-if="modal === 'cache'"
            ><Database :size="27" />
            <h2>缓存管理</h2>
            <div class="storage-line">
              <span>离线教务缓存</span><strong>已启用本机课表存储</strong>
            </div>

            <p>
              个人课表保存在 Web IndexedDB /
              原生设备偏好存储；应用资源缓存供离线查看。备份可在课表数据管理中导出。
            </p>
            <button
              class="secondary full"
              @click="
                load();
                close();
                notify('本机数据已重新加载');
              "
            >
              <RefreshCw :size="17" />重新加载本机数据
            </button></template
          >
          <template v-else-if="modal === 'reset'"
            ><Database :size="27" />
            <h2>重置本机数据？</h2>
            <p>
              恢复默认昵称、主题和偏好。模拟课程不受影响，操作后可重新设置。
            </p>
            <div class="modal-actions">
              <button class="secondary" @click="close">取消</button
              ><button class="primary" @click="reset">确认重置</button>
            </div></template
          >
          <template v-else-if="modal === 'privacy'"
            ><ShieldCheck :size="27" />
            <h2>隐私政策</h2>
            <p>
              学校密码只在官方页面输入。Android 原生模块使用系统密钥库加密保存学校会话，供本人数据查询复用。退出学校账号后清除会话与学校缓存。
            </p>
            <p>
              昵称、专业、主题和偏好保存在本机。个人课表通过
              IndexedDB（Web）或原生设备存储保存，导入文件仅在本机解析，不会上传服务器。学校数据保存在本机缓存，个人课表与备份独立保留。
            </p>
            <p>
              托管平台可能产生运行必需的访问日志。外部网站受其各自隐私政策约束。
            </p>
            <button class="primary full" @click="close">
              我知道了
            </button></template
          >
          <template v-else
            ><span class="brand-mark"><GraduationCap :size="27" /></span>
            <h2>邯郸校园 <small>v{{appVersion}}</small></h2>
            <p>
              为同学，由同学。独立开源的学生校园助手，未获邯郸学院官方认证或合作授权。
            </p>
            <p>
              原创代码采用 MIT 许可证。工程研究参考
              UBAA、HFUT-Schedule、DanXi、fzuhelper-app；设计吸收用户提供参考图的通用布局原则。
            </p>
            <a
              class="secondary full"
              href="https://github.com/zthy3375-wq/fish"
              target="_blank"
              rel="noopener noreferrer"
              ><Github :size="17" />查看开源项目</a
            ></template
          >
        </section>
      </div></Transition
    >
  </div>
</template>

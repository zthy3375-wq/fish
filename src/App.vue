<script setup lang="ts">
import {widgetSupported,widgetSnapshot,publishWidget,widgetTarget} from './services/course-widget';
import CourseWidgetSetup from './components/CourseWidgetSetup.vue';
import HomeCourseTimeline from './components/HomeCourseTimeline.vue';
import {courseProgress} from './domain/course-progress';
import {scheduleViews} from './composables/view-state';
import AnalyticsSettings from './components/AnalyticsSettings.vue';
import {initAnalytics,flushAnalytics,recordFeature,refreshAnalytics} from './composables/analytics';
import AppUpdateDialog from './components/AppUpdateDialog.vue';
import {initializeUpdates,checkUpdates,updatesOpen,dismissUpdate,updateDeferred,updateDeferredReason} from './composables/updates';
import {initPangguai,pangguai,pgBusy} from './composables/pangguai';
import LifeServices from './components/LifeServices.vue';
import CampusHero from './components/CampusHero.vue';
import CommunityGroup from './components/CommunityGroup.vue';
import FailureFeedback from './components/FailureFeedback.vue';
import {defineAsyncComponent} from 'vue';
const QuzhiWallet=defineAsyncComponent(()=>import('./components/QuzhiWallet.vue'));
const PangguaiWallet=defineAsyncComponent(()=>import('./components/PangguaiWallet.vue'));
const CampusMap=defineAsyncComponent(()=>import('./components/CampusMap.vue'));
import ParcelShortcuts from './components/ParcelShortcuts.vue';
import LearningCenter from './components/LearningCenter.vue';
import TaskDetail from './components/TaskDetail.vue';
import TaskSettings from './components/TaskSettings.vue';
import TodayTasks from './components/TodayTasks.vue';
import {beijingDay,type CampusTask} from './domain/agenda';
import {initLearning,syncLearning,learningTasks} from './composables/learning';
import CampusAgenda from './components/CampusAgenda.vue';
import {initTasks,reloadTasks,tasksReady,agendaView,taskView,reconcileTaskReminders} from './composables/tasks';
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
  MessageSquare,
} from "lucide-vue-next";
import type { AcademicData, Course } from "./domain/academic";
import { coursesForDay } from "./domain/academic";
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
import {initWeekCalibration,calibratedSemester} from "./composables/week-calibration";
import ScheduleManager from "./components/ScheduleManager.vue";
import CourseEditor from "./components/CourseEditor.vue";
import SchoolCourseAdjustment from './components/SchoolCourseAdjustment.vue';
import {schoolCourseKey,type CourseTimeChange} from './domain/school-course-adjustments';
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
import {academicCache,schoolTerm,schoolCourses,originalSchoolCourses,pausedCourseAdjustments,saveSchoolCourseAdjustment,restoreSchoolCourseAdjustment,initAcademic,autoSyncAcademic,syncAcademic} from './composables/handan-academic';
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
const semester = computed(() => calibratedSemester(schoolTerm.value?.data?.semester ?? localSemester.value));
const table = computed(() => schoolTerm.value?.data?.table ?? localTable.value);
const data = computed<AcademicData>(() => {
 const cached=schoolTerm.value?.data;
 const personal=cached ? schedule.value.courses.filter(c=>{
   const t=schedule.value.semesters.find(t=>t.id===c.semesterId);
   return !isSchoolPageSemester(c.semesterId)&&t?.academicYear===cached.semester.academicYear&&t?.season===cached.semester.season;
 }) : schedule.value.courses;
 return {source:cached?'official':'personal',courses:cached?[...schoolCourses.value,...personal.flatMap(c=>flatten([c],c.semesterId,cached.table))]:flatten(personal,schedule.value.activeSemesterId,localTable.value),grades:[],exams:academicCache.value.exams.data??[]};
});
let widgetQueue:Promise<unknown>=Promise.resolve();
watch(()=>!loading.value&&!error.value?widgetSnapshot(semester.value,data.value.courses,!!schoolTerm.value?.data||schedule.value.mode==='personal'||data.value.courses.length>0):null,()=>{
 if(!widgetSupported())return;
 widgetQueue=widgetQueue.catch(()=>{}).then(()=>{
  if(loading.value||error.value)return;
  return publishWidget(widgetSnapshot(semester.value,data.value.courses,!!schoolTerm.value?.data||schedule.value.mode==='personal'||data.value.courses.length>0));
 }).catch(()=>{});
});
function addCourseWidget(){open('course-widget');}
async function openWidgetTarget(){
 if(!widgetSupported()||loading.value)return;
 try{
  const {date}=await widgetTarget();
  if(!/^20\d{2}-\d{2}-\d{2}$/.test(date))return;
  const d=new Date(date+'T12:00:00');
  if(!Number.isFinite(+d))return;
  scheduleViews[semester.value.id]={week:Math.max(1,Math.min(semester.value.weekCount,currentWeek(d,semester.value))),day:dayNumber(d),view:'day'};
  close();move('schedule');
 }catch{}
}
const editorRef = ref<InstanceType<typeof CourseEditor>>(),
  editorCourse = ref<ManagedCourse>(),
  editorPreset = ref<CellPreset>(),
  editorBusy = ref(false),
  editorError = ref(""),
  managerInitial = ref("courses"),
  deleteIntent = ref(""),
  detailError = ref(""),
  conflictCourses = ref<Course[]>([]);
const adjustmentRef=ref<InstanceType<typeof SchoolCourseAdjustment>>(),adjustmentSource=ref<Course>(),adjustmentCurrent=ref<Course>(),adjustmentWeek=ref(1),adjustmentScope=ref(''),adjustmentTerm=ref('');
const selectedIsSchool=computed(()=>!!selected.value?.adjustmentSourceKey);
const selectedHasAdjustments=computed(()=>!!selected.value?.adjustmentSourceKey&&(academicCache.value.courseAdjustments??[]).some(a=>a.term===academicCache.value.selectedTerm&&a.sourceKey===selected.value!.adjustmentSourceKey));
function adjustSchoolCourse(){
 const c=selected.value,original=originalSchoolCourses.value.find(x=>schoolCourseKey(x)===c?.adjustmentSourceKey);
 if(!c||!original||!academicCache.value.localScope||!academicCache.value.selectedTerm){notify('学校课表已更新，请重新打开');return}
 adjustmentSource.value=JSON.parse(JSON.stringify(original));adjustmentCurrent.value=JSON.parse(JSON.stringify(c));
 adjustmentScope.value=academicCache.value.localScope;adjustmentTerm.value=academicCache.value.selectedTerm;editorError.value='';open('school-course-adjustment');
}
async function saveAdjustment(weeks:number[],change:CourseTimeChange,allow:boolean){
 if(!adjustmentSource.value||editorBusy.value)return;
 editorBusy.value=true;editorError.value='';
 try{await saveSchoolCourseAdjustment(adjustmentScope.value,adjustmentTerm.value,schoolCourseKey(adjustmentSource.value),weeks,change,allow);close();notify('调课已保存，首页、课表与日程已同步')}
 catch(e){editorError.value=(e as Error).message}finally{editorBusy.value=false}
}
async function restoreAdjustment(){
 const c=selected.value;if(!c?.adjustmentSourceKey||editorBusy.value)return;
 editorBusy.value=true;detailError.value='';
 try{await restoreSchoolCourseAdjustment(academicCache.value.localScope!,academicCache.value.selectedTerm!,c.adjustmentSourceKey);close();notify('已恢复这项课程的学校安排')}
 catch(e){detailError.value=(e as Error).message}finally{editorBusy.value=false}
}
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
  if (modal.value==='school-course-adjustment') {if(editorBusy.value)return false;if(adjustmentRef.value?.hasChanges()){adjustmentRef.value.requestCancel();return false;}}
  if (modal.value==='course-editor'&&editorRef.value?.hasChanges()) {
    editorRef.value.requestCancel();
    return false;
  }
  return true;
});
function requestClose() {
  if(modal.value==='school-course-adjustment'){adjustmentRef.value?.requestCancel();return;}
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
const currentProgress=computed(()=>current.value?courseProgress(current.value,now.value):undefined);
const next = computed(() =>
  nextOccurrence(data.value.courses, now.value, semester.value),
);
const homeFocus = computed(()=>current.value ?? next.value?.course);
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
    title: "成绩与学业",
    subtitle: academicCache.value.grades.updatedAt ? `${academicCache.value.grades.data?.length??0} 门成绩` : "尚未同步",
    icon: ChartNoAxesColumnIncreasing,
  },
  {
    id: "exams",
    title: "考试安排",
    subtitle: academicCache.value.exams.updatedAt ? `${exams.value.length} 场考试` : "尚未同步",
    icon: CalendarDays,
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
  { id: "app-update", title: "检查更新", subtitle: `当前版本 ${appVersion}`, icon: Info },
  { id: "privacy", title: "隐私政策", icon: ShieldCheck },
  {
    id: "feedback",
    title: "问题反馈",
    icon: MessageSquare,
  },
  { id: "about", title: "版本信息", subtitle: `邯院通 · v${appVersion}`, icon: Info },
];
const sectionNames: Record<string, string> = {
  overview: "学习",
  agenda: "统一日程",
  learning: "学习通",
  schedule: "课程表",
  grades: "成绩与学业",
  exams: "考试安排",
  study: "成绩与学业",
  calendar: "学期校历",
  official: "官方教务",
};
const title = computed(() =>
  page.value === "home"
    ? "今天"
    : page.value === "life" ? "校园生活" : page.value === "tasks" ? "待办" : page.value === "schedule" ? "课程表" : page.value === "academic"
      ? sectionNames[section.value]
      : "我的",
);
const subtitle = computed(() =>
  page.value === "home"
    ? `${dateLabel(now.value)} 周${weekdays[dayNumber(now.value) - 1]} · ${week.value >= 1 && week.value <= semester.value.weekCount ? "第 " + week.value + " 周" : "学期外"} · ${officialActive.value ? "学校课表 · 已缓存" : isSchoolPageSemester(schedule.value.activeSemesterId) ? "已保存课表" : "个人课表"}`
    : page.value === "life" ? "接水、洗衣与校园服务" : page.value === "tasks" ? "今天、接下来，按自己的节奏" : page.value === 'academic' && section.value==='overview' ? '作业、课程与教务' : page.value === "academic" && section.value==='learning' ? "作业与课程" : page.value === "academic" || page.value === "schedule"
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
  if(id==='study')id='grades';
  if(id==='due'){taskView.view='due';taskView.mode='list';taskView.source='all';taskView.course='';taskView.search='';move('tasks','agenda');return;}
  move(id==='agenda'?'tasks':id === 'schedule' ? 'schedule' : 'academic', id);
}
function nav(p: Page) { move(p, p === "schedule" ? "schedule" : "overview"); }
const content=ref<HTMLElement>();
const scrollPositions=new Map<string,number>();
watch(()=>`${page.value}/${section.value}`,async(key,oldKey)=>{scrollPositions.set(oldKey,content.value?.scrollTop??0);await nextTick();content.value?.scrollTo({top:scrollPositions.get(key)??0,behavior:'instant'})});
function details(c: Course, occurrenceWeek?:number) {
  adjustmentWeek.value=occurrenceWeek??c.occurrenceWeek??(page.value==='schedule'?(scheduleViews[semester.value.id]?.week??week.value):currentWeek(c===next.value?.course?next.value.date:now.value,semester.value));
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
    await initWeekCalibration();
    await initAcademic();
    void autoSyncAcademic();
    await reconcileReminders(schedule.value);
    void autoSyncAcademic();
  } catch (e) {
    error.value = storageError.value || "教务信息加载失败：" + String(e);
  } finally {
    loading.value = false;
    void openWidgetTarget();
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
          color: "#00000000",
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
  if(updatesOpen.value){if(e.key==='Escape')dismissUpdate();return;}
  if(e.key === "Escape"){if(modal.value)requestClose();else if(agendaView.editor)taskDetailRef.value?.requestBack();}
}
async function recalibrate() {
  void flushAnalytics();void refreshAnalytics();
  if(document.visibilityState==='visible')void checkUpdates();
  void syncLearning().catch(()=>{});
  void reloadTasks();
  now.value = campusNow();
  if (document.visibilityState === "visible") {
    await refreshSchedule();
    await openWidgetTarget();
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
watch(()=>[modal.value,agendaView.editor,pgBusy.value,pangguai.value.water?.phase] as const,()=>{
  const phase=pangguai.value.water?.phase;
  updateDeferred.value=!!modal.value||!!agendaView.editor||pgBusy.value||!!(phase&&!['settled','ended_zero','closed_unknown','archived_unverified'].includes(phase));
  updateDeferredReason.value=pgBusy.value?'正在处理接水或支付，请等待操作结束后再下载和安装。':phase&&!['settled','ended_zero','closed_unknown','archived_unverified'].includes(phase)?'检测到未结束的接水记录。请先在接水页面核对状态；若已在机身结算，可使用“已在机身结算，恢复扫码”。':updateDeferred.value?'请先完成当前操作或保存编辑，再下载和安装更新。':'';
},{immediate:true});
watch(()=>[page.value,section.value,modal.value] as const,([p,s,m])=>{
 if(m){const feature=({'quzhi-wallet':'shower','pangguai-wallet':'wallet',parcel:'parcel','campus-map':'map'} as const)[m as 'quzhi-wallet'];if(feature)void recordFeature(feature);return;}
 if(s==='learning')void recordFeature('learning');else if(s==='grades')void recordFeature('grades');else if(p==='schedule')void recordFeature('schedule');else if(p==='tasks')void recordFeature('tasks');
});
let analyticsTimer:ReturnType<typeof setInterval>;
onMounted(async () => {
  void initAnalytics();analyticsTimer=setInterval(()=>{if(document.visibilityState==='visible')void flushAnalytics()},60000);
  void initPangguai().then(()=>initializeUpdates());
  load();
  void initTasks().catch(()=>{});
  void initLearning().then(()=>syncLearning()).catch(()=>{});
  clockTimer = setInterval(() => {if(document.visibilityState!=='hidden')now.value=campusNow()}, 1000);
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
      if (updatesOpen.value) dismissUpdate();
      else if (["course-editor","school-course-adjustment"].includes(modal.value)) requestClose();
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
  clearInterval(analyticsTimer);
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
  <AppUpdateDialog/>
  <TaskDetail ref="taskDetailRef" @saved="notify"/>
  <div
    class="app-shell"
    :inert="updatesOpen"
    :class="{ compact: prefs.compact, 'home-active': page === 'home', 'schedule-active':page==='schedule' }"
  >
    <AppHeader v-if="page !== 'home'"
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
          <p v-if="pausedCourseAdjustments && (page==='schedule'||page==='home')" class="task-hint" role="status">学校原安排已变化，{{pausedCourseAdjustments}} 条按周调课记录已暂停，请按新课表重新核对。</p>
          <template v-if="page === 'home'">
            <CampusHero :date="`${dateLabel(now)} · 周${weekdays[dayNumber(now)-1]}`" :week="week>=1&&week<=semester.weekCount?`第 ${week} 教学周`:'学期外'" :unread="!read&&prefs.notifications" :obscured="!!modal||updatesOpen||agendaView.editor" @notifications="open('notifications')"/>
            <div class="home-body">
              <AnalyticsSettings prompt @policy="open('privacy')"/>
              <section class="home-course-panel" aria-label="课程速览">
                <button v-if="homeFocus" class="home-next" :aria-label="'查看'+(current?'当前':'下一节')+'课程 '+homeFocus.name" @click="details(homeFocus)">
                  <span class="home-next-head"><span><GraduationCap :size="18"/>{{current?'正在上课':'下一节课'}}</span><span class="home-countdown">{{current?'还剩'+currentProgress?.remainingMinutes+'分钟':next?untilLabel(next.minutes):''}}</span></span>
                  <strong class="home-next-title">{{homeFocus.name}}</strong>
                  <span class="home-next-meta"><span><MapPin/>{{homeFocus.room||'教室待定'}}</span><span><UserRound/>{{homeFocus.teacher||'教师待定'}}</span><time>{{homeFocus.start}}–{{homeFocus.end}}</time><span v-if="!current&&next&&dateLabel(next.date)!==dateLabel(now)">{{dateLabel(next.date)}} 周{{weekdays[dayNumber(next.date)-1]}}</span></span>
                </button>
                <div v-else class="home-next"><span class="home-next-head"><span><GraduationCap :size="18"/>课程安排</span></span><strong class="home-next-title">{{academicCache.connected&&!schoolTerm?.data?'课表等待同步':'暂时没有后续课程'}}</strong><p class="home-next-meta">{{!academicCache.connected||!schoolTerm?.data?'前往“我的”连接学校或刷新课表。':'查看课表，安排自己的校园时光。'}}</p></div>
                <div class="home-timeline-head"><span>今日课程 · {{todayCourses.length}} 节</span><button @click="go('schedule')">查看课表 <ChevronRight :size="13"/></button></div>
                <HomeCourseTimeline v-if="todayCourses.length" :courses="todayCourses" :now="now" @select="details"/>
              <div class="home-study-links"><button @click="go('learning')"><BookOpen :size="20"/><span><strong>学习通</strong><small>作业与考试</small></span><ChevronRight/></button><button @click="go('grades')"><ChartNoAxesColumnIncreasing :size="20"/><span><strong>成绩与学业</strong><small>成绩 · 学分 · 学籍</small></span><ChevronRight/></button></div>
              </section>
              <section aria-labelledby="home-life-title"><div class="home-service-heading"><h2 id="home-life-title">校园生活</h2><span>每天用得上的小事</span></div><LifeServices @open="open"/></section>
              <TodayTasks :now="now" @open="planLearning" @navigate="go" @create="editDailyTask(undefined,beijingDay(now))"/>


            </div>
          </template>
          <template v-else-if="page === 'life'"><LifeServices @open="open"/></template>
          <template v-else-if="page === 'academic' || page === 'schedule' || page === 'tasks'">
            <button v-if="section==='agenda'" class="learning-page-link" @click="go('learning')"><BookOpen :size="20"/><strong>学习通作业</strong><span>按课程查看与安排</span><ChevronRight :size="16"/></button>
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
            <div class="profile-page">
            <button class="profile-strip" @click="open('edit')">
              <span class="avatar">{{ prefs.name.slice(0, 1) || "同" }}</span
              ><span class="profile-copy"
                ><strong>{{ academicCache.profile.data?.name || prefs.name }}</strong
                ><small>{{ academicCache.profile.data?.major || prefs.major }}</small
                ><span>{{academicCache.profile.data?.className || "本地资料"}}</span></span
              ><span class="edit-link">编辑 <ChevronRight :size="15" /></span>
            </button>
            <SectionHeader title="账号与教务"/><section class="profile-accounts"><SchoolConnection collapsible /><button class="learning-page-link" @click="go('learning')"><BookOpen :size="20"/><strong>学习通</strong><span>作业、课程与账号管理</span><ChevronRight :size="16"/></button>
            </section>
            <div class="profile-academics"><ServiceGroup :items="academicServices.filter(e=>!['learning','agenda'].includes(e.id))" @select="go"/></div>
            <button class="learning-page-link" @click="addCourseWidget"><CalendarDays :size="20"/><strong>桌面课表</strong><span>添加今天与明天的小组件</span><ChevronRight :size="16"/></button>
            <SectionHeader title="偏好与数据" />
            <section class="profile-preferences">
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
            <ServiceGroup
              :items="settings"
              @select="(id) => (id === 'manager' ? manage() : open(id))"
            />
            <TaskSettings/>
            </section>
            <SectionHeader title="帮助与交流"/><section class="profile-support"><CommunityGroup/><details class="profile-feedback"><summary><span><MessageSquare :size="19"/>问题反馈</span><ChevronRight :size="16"/></summary><FailureFeedback/><ServiceGroup :items="about.filter(e=>e.id==='feedback').map(e=>({...e,title:'反馈说明'}))" @select="open"/></details></section>
            <SectionHeader title="关于与隐私" /><ServiceGroup
              :items="about.filter(e=>e.id!=='feedback').map(e=>e.id==='about'?{...e,title:'关于邯院通',subtitle:undefined}:e)"
              @select="(id) => (id === 'app-update' ? checkUpdates(true) : open(id))"
            />
            <p class="footnote source-footnote">
              <ShieldCheck :size="13" />不保存教务密码 · 无广告 · 匿名统计可关闭
            </p>
            </div>
          </template>
          <footer>
            邯院通 <span>·</span> 独立学生项目
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
          editorOpen: ['course-editor','school-course-adjustment'].includes(modal),
        }"
        @click.self="requestClose"
        @keydown.tab="trapFocus"
      >
        <section
          data-overlay
          class="overlay-surface"
          :class="{
            'editor-fullscreen': ['course-editor','school-course-adjustment'].includes(modal),
          }"
          role="dialog"
          aria-modal="true"
          :aria-label="
            modal === 'course'
              ? '课程详情'
              : modal === 'quzhi-wallet' ? '趣智校园钱包'
              : modal === 'pangguai-wallet' ? '胖乖生活钱包'
              : modal === 'campus-map' ? '校园平面图'
              : modal === 'parcel' ? '快递出库码'
              : modal === 'course-widget' ? '桌面课表'
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
          <QuzhiWallet v-if="modal === 'quzhi-wallet'"/>
          <PangguaiWallet v-else-if="modal === 'pangguai-wallet'"/>
          <CampusMap v-else-if="modal === 'campus-map'"/>
          <ParcelShortcuts v-else-if="modal === 'parcel'"/>
          <CourseWidgetSetup v-else-if="modal === 'course-widget'"/>
          <SchoolCourseAdjustment v-else-if="modal === 'school-course-adjustment' && adjustmentSource && adjustmentCurrent"
            ref="adjustmentRef" :source="adjustmentSource" :current="adjustmentCurrent" :week="adjustmentWeek" :table="table"
            :saving="editorBusy" :save-error="editorError" @save="saveAdjustment" @cancel="close"/>
          <CourseEditor
            v-else-if="modal === 'course-editor'"
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
              {{selectedIsSchool ? (selected.locallyAdjusted?'学校课程 · 已在本机调课':'学校课程 · 可在本机调课') : '个人事项'}}
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
            <div v-if="selectedIsSchool" class="course-detail-actions">
              <button class="primary full" @click="adjustSchoolCourse">调整时间/地点</button>
              <button v-if="selectedHasAdjustments" class="text-button" :disabled="editorBusy" @click="deleteIntent='restore'">恢复学校安排</button>
              <div v-if="deleteIntent==='restore'" class="confirmation"><p>恢复这项上课安排所有周次的学校时间和地点？其他课程保留。</p><p v-if="detailError" role="alert">{{detailError}}</p><button class="secondary full" :disabled="editorBusy" @click="restoreAdjustment">确认恢复</button><button class="text-button" :disabled="editorBusy" @click="deleteIntent=''">取消</button></div>
            </div>
            <div v-else-if="selected.courseId && !selected.courseId.startsWith('school-')" class="course-detail-actions">
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
                  <h3>欢迎使用邯院通</h3>
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
            <h2>使用说明与隐私政策</h2>
            <p>邯院通是免费的独立学生项目，提供课表、待办和校园生活服务。学校与生活服务数据以对应平台为准；付款前请核对设备、账户与金额。请勿分享账号密码、验证码或登录凭证。</p>
            <AnalyticsSettings/>
            <p>匿名使用统计需你主动允许。开启后上报随机安装标识、应用版本、北京时间日期和预定义功能的累计操作次数，用于统计活跃设备与改善体验；不上传学号、密码、课程内容、余额、订单或设备硬件标识。每日汇总统计近90天，过期明细随后续上报清理，匿名设备记录用于累计统计。可在“我的 → 隐私政策”关闭统计或删除已上报记录。为防滥用，服务端短期保留每日加盐后的网络地址摘要，不保存原始地址到统计数据库。</p>
            <p>
              学校密码只在官方页面输入。Android 原生模块使用系统密钥库加密保存学校会话，供本人数据查询复用。退出学校账号后清除会话与学校缓存。
            </p>
            <p>
              昵称、专业、主题和偏好保存在本机。个人课表通过
              IndexedDB（Web）或原生设备存储保存，导入文件仅在本机解析，不会上传服务器。学校数据保存在本机缓存，个人课表与备份独立保留。
            </p>
            <p>趣智校园使用本人账户连接。密码与验证码仅用于本次认证，不保存；会话、余额与账单由 Android 系统密钥库加密保存，退出趣智账户后清除。充值跳转支付宝官方小程序，付款前请核对学校和账户。</p>
            <p>
              托管平台可能产生运行必需的访问日志。外部网站受其各自隐私政策约束。
            </p>
            <button class="primary full" @click="close">
              我知道了
            </button></template
          >
          <template v-else-if="modal==='feedback'"><h2>问题反馈</h2><p>请将问题截图、发生步骤、手机型号和版本号发送给邀请你参加内测的开发者。不要发送密码或验证码。</p><p>邯院通 {{appVersion}}</p><button class="primary full" @click="close">我知道了</button></template>
          <template v-else
            ><img class="brand-mark" src="/icon.svg" alt="邯院通图标"/>
            <h2>邯院通 <small>v{{appVersion}}</small></h2>
            <p>
              为同学，由同学。独立开发的学生校园助手，未获邯郸学院官方认证或合作授权。
            </p>
            <p>
              当前为内测版本。第三方开源组件保留各自许可证。工程研究参考
              UBAA、HFUT-Schedule、DanXi、fzuhelper-app；设计吸收用户提供参考图的通用布局原则。
            </p>
</template
          >
        </section>
      </div></Transition
    >
  </div>
</template>

<script setup lang="ts">
import {ref,computed,watch,onMounted,onUnmounted,nextTick} from 'vue';
import {Capacitor,type PluginListenerHandle} from '@capacitor/core';
import {App as NativeApp} from '@capacitor/app';
import {StatusBar,Style} from '@capacitor/status-bar';
import {GraduationCap,BookOpen,CalendarDays,ChartNoAxesColumnIncreasing,ClipboardList,LibraryBig,UserRound,Settings2,ShieldCheck,Database,Sun,Moon,Monitor,X,Check,RefreshCw,Info,Bell,ChevronRight,ArrowRight,ArrowUpRight,Clock3,MapPin,CheckCheck,Download,Github,MessageSquare,Menu,House} from 'lucide-vue-next';
import type {AcademicData,Course} from './domain/academic';
import {coursesForDay,weightedAverage} from './domain/academic';
import {campusNow,currentWeek,dayNumber,timeOf,nextOccurrence,dateLabel,untilLabel,courseState,upcomingExams,weekdays} from './domain/presentation';
import {mockAcademicProvider} from './services/academic';
import {loadPreferences,savePreferences,clearPreferences,defaults} from './services/preferences';
import {useNavigation,type Page} from './composables/navigation';
import AppHeader from './components/AppHeader.vue';import FloatingNavigation from './components/FloatingNavigation.vue';import SectionHeader from './components/SectionHeader.vue';import QuickAction from './components/QuickAction.vue';import ServiceGroup from './components/ServiceGroup.vue';import CourseCard from './components/CourseCard.vue';import AcademicSummary from './components/AcademicSummary.vue';import AcademicDetail from './components/AcademicDetail.vue';import EmptyState from './components/EmptyState.vue';import LoadingState from './components/LoadingState.vue';import SettingsRow from './components/SettingsRow.vue';
const {page,section,overlay:modal,move,open,close,back,canBack}=useNavigation();
const prefs=ref(loadPreferences()),draft=ref({name:'',major:''}),selected=ref<Course>(),data=ref<AcademicData>({courses:[],grades:[],exams:[],source:'mock'}),loading=ref(true),error=ref(''),toast=ref(''),read=ref(false),now=ref(campusNow());
const week=computed(()=>currentWeek(now.value)),todayCourses=computed(()=>coursesForDay(data.value.courses,dayNumber(now.value),week.value));
const current=computed(()=>todayCourses.value.find(c=>courseState(c,now.value)==='current'));
const next=computed(()=>nextOccurrence(data.value.courses,now.value));
const exams=computed(()=>upcomingExams(data.value.exams,now.value));
const weekCount=computed(()=>data.value.courses.filter(c=>c.weeks.includes(week.value)).length);
const credits=computed(()=>data.value.grades.filter(g=>g.score>=60).reduce((s,g)=>s+g.credit,0));
const entries=computed(()=>[
{id:'schedule',title:'课程表',subtitle:`本周 ${weekCount.value} 节`,icon:BookOpen},
{id:'grades',title:'成绩查询',subtitle:`${data.value.grades.length} 门课程`,icon:ChartNoAxesColumnIncreasing},
{id:'exams',title:'考试安排',subtitle:`${exams.value.length} 场待考`,icon:CalendarDays},
{id:'study',title:'学业信息',subtitle:`已获 ${credits.value} 学分`,icon:GraduationCap}]);
const teaching=computed(()=>entries.value.slice(0,3));
const planning=[{id:'study',title:'学业信息',subtitle:'查看模拟培养方案与学分进度',icon:GraduationCap},{id:'calendar',title:'学期校历',subtitle:'教学周与学期安排',icon:CalendarDays}];
const official=[{id:'official',title:'官方教务系统',subtitle:'邯郸学院教学综合信息服务平台',icon:LibraryBig},{id:'school',title:'邯郸学院官网',subtitle:'学校新闻与公开信息',icon:ArrowUpRight,href:'https://www.hdc.edu.cn/'}];
const settings=[{id:'notifications',title:'通知设置',subtitle:'应用内提醒与消息',icon:Bell},{id:'cache',title:'缓存管理',subtitle:'查看数据存储状态',icon:Database},{id:'reset',title:'数据管理',subtitle:'重置本机资料与偏好',icon:Settings2}];
const about=[{id:'privacy',title:'隐私政策',icon:ShieldCheck},{id:'github',title:'GitHub 开源项目',icon:Github,href:'https://github.com/zthy3375-wq/fish'},{id:'feedback',title:'问题反馈',icon:MessageSquare,href:'https://github.com/zthy3375-wq/fish/issues'},{id:'about',title:'版本信息',subtitle:'邯郸校园 · v0.2.1',icon:Info}];
const sectionNames:Record<string,string>={overview:'教务中心',schedule:'课程表',grades:'成绩查询',exams:'考试安排',study:'学业信息',calendar:'学期校历',official:'官方教务'};
const title=computed(()=>page.value==='home'?'今日':page.value==='academic'?sectionNames[section.value]:'我的');
const subtitle=computed(()=>page.value==='home'?`${dateLabel(now.value)} 周${weekdays[dayNumber(now.value)-1]} · ${week.value>=1&&week.value<=18?'第 '+week.value+' 周':'学期外'} · 模拟教务`:page.value==='academic'?`${week.value>=1&&week.value<=18?'第 '+week.value+' 周 · ':''}2026–2027 秋 · 模拟`:'本地体验账号 · 资料仅保存在本机');
const greeting=computed(()=>now.value.getHours()<12?'上午好':now.value.getHours()<18?'下午好':'晚上好');
function go(id:string){move('academic',id)}function nav(p:Page){move(p)}function details(c:Course){selected.value=c;open('course')}
let toastTimer:ReturnType<typeof setTimeout>,clockTimer:ReturnType<typeof setInterval>,nativeBack:PluginListenerHandle|undefined,focusBefore:HTMLElement|null=null,disposed=false;
function notify(s:string){toast.value=s;clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.value='',3000)}
async function load(){loading.value=true;error.value='';try{data.value=await mockAcademicProvider.load()}catch{error.value='模拟教务信息加载失败'}finally{loading.value=false}}
function saveProfile(){prefs.value.name=draft.value.name.trim()||'同学';prefs.value.major=draft.value.major.trim();close();notify('个人资料已保存在本机')}
function reset(){if(clearPreferences()){prefs.value={...defaults};close();notify('本机设置已恢复默认')}else notify('浏览器未允许清除本机设置')}
watch(prefs,p=>{if(!savePreferences(p))notify('设置未保存：浏览器存储不可用')},{deep:true});
const media=window.matchMedia('(prefers-color-scheme: dark)'),systemDark=ref(media.matches);
const dark=computed(()=>prefs.value.theme==='dark'||prefs.value.theme==='system'&&systemDark.value);
async function nativeTheme(){if(Capacitor.isNativePlatform())try{await StatusBar.setStyle({style:dark.value?Style.Dark:Style.Light});if(Capacitor.getPlatform()==='android')await StatusBar.setBackgroundColor({color:dark.value?'#171c24':'#f7f8fb'})}catch{/* Unsupported system-bar operations do not block the app. */}}
watch(dark,()=>{document.documentElement.dataset.theme=dark.value?'dark':'light';document.querySelector('meta[name="theme-color"]')?.setAttribute('content',dark.value?'#171c24':'#f7f8fb');nativeTheme()},{immediate:true});
function systemChange(e:MediaQueryListEvent){systemDark.value=e.matches}
watch(modal,async(value,old)=>{if(value){if(value==='edit')draft.value={name:prefs.value.name,major:prefs.value.major};if(!old)focusBefore=document.activeElement as HTMLElement;await nextTick();document.querySelector<HTMLElement>('[data-overlay] button')?.focus();document.body.style.overflow='hidden'}else{document.body.style.overflow='';focusBefore?.focus()}});
function trapFocus(e:KeyboardEvent){const items=Array.from((e.currentTarget as HTMLElement).querySelectorAll<HTMLElement>('button:not([disabled]),input,select,a[href]'));if(e.shiftKey&&document.activeElement===items[0]){e.preventDefault();items.at(-1)?.focus()}else if(!e.shiftKey&&document.activeElement===items.at(-1)){e.preventDefault();items[0]?.focus()}}
function escape(e:KeyboardEvent){if(e.key==='Escape'&&modal.value)close()}
function viewportChange(){const v=window.visualViewport;document.documentElement.classList.toggle('keyboard-open',!!v&&window.innerHeight-v.height>150)}
onMounted(async()=>{load();clockTimer=setInterval(()=>now.value=campusNow(),30000);media.addEventListener('change',systemChange);window.addEventListener('keydown',escape);window.visualViewport?.addEventListener('resize',viewportChange);if(Capacitor.getPlatform()==='android'){const h=await NativeApp.addListener('backButton',()=>{if(canBack())back();else NativeApp.exitApp()});if(disposed)h.remove();else nativeBack=h}});
onUnmounted(()=>{disposed=true;clearTimeout(toastTimer);clearInterval(clockTimer);nativeBack?.remove();media.removeEventListener('change',systemChange);window.removeEventListener('keydown',escape);window.visualViewport?.removeEventListener('resize',viewportChange);document.body.style.overflow=''});
</script>
<template>
<div class="app-shell" :class="{compact:prefs.compact,'home-active':page==='home'}">
  <AppHeader :title="title" :subtitle="subtitle" :back="page==='academic'&&section!=='overview'" :academic="page==='academic'&&section==='overview'" :unread="!read&&prefs.notifications" @back="back" @menu="open('drawer')" @notifications="open('notifications')" @import="open('import')"/>
  <main :inert="!!modal" tabindex="-1" aria-label="页面内容">
    <LoadingState v-if="loading"/><div v-else-if="error" class="error-state" role="alert"><Info/><h2>{{error}}</h2><p>本次没有连接学校系统，你可以重新加载演示数据。</p><button class="primary" @click="load">重试</button></div>
    <Transition v-else name="page" mode="out-in"><div :key="page" class="page-content">
    <template v-if="page==='home'">
      <div class="home-greeting"><span>{{greeting}}，{{prefs.name}}</span><span class="quiet-label">北京时间 {{timeOf(now)}}</span></div>
      <button v-if="next" type="button" class="next-course compact-next-course" :aria-label="'查看下一节课程 '+next.course.name" @click="details(next.course)">
        <span class="next-top"><span class="micro-label"><Clock3 :size="14"/>下一节课程</span><span class="time-until">{{untilLabel(next.minutes)}}</span></span>
        <span class="next-main"><strong :title="next.course.name">{{next.course.name}}</strong><span class="next-room"><MapPin :size="13"/><span>{{next.course.room}}</span></span><ArrowRight :size="18"/></span>
        <span class="next-meta"><span><CalendarDays :size="12"/>{{dateLabel(next.date)}} 周{{weekdays[dayNumber(next.date)-1]}}</span><span>{{next.course.start}}–{{next.course.end}}</span><span><UserRound :size="12"/>{{next.course.teacher}}</span></span>
      </button>
      <div v-else class="next-course"><EmptyState title="本学期没有后续课程" description="当前模拟课表中没有后续安排，可查看其他教学周。"/></div>
      <SectionHeader title="今日课程" :meta="`${todayCourses.length} 节${current?' · 正在上课':''}`" action="完整课表" @action="go('schedule')"/>
      <div class="course-list home-course-list"><CourseCard grouped v-for="c in todayCourses" :key="c.id" :course="c" :status="courseState(c,now)" :next="next?.course.id===c.id&&next?.week===week&&dayNumber(next.date)===dayNumber(now)" @select="details"/><EmptyState v-if="!todayCourses.length" title="今天没有课程" :description="next?'下一次课程会显示在上方。':'当前模拟课表没有后续安排。'"/></div>
      <SectionHeader title="快捷入口" meta="教务常用"/><div class="quick-grid home-quick"><QuickAction v-for="e in [...entries.slice(0,3),{id:'calendar',title:'校历',subtitle:'学期安排',icon:LibraryBig}]" :key="e.id" :title="e.title" :subtitle="e.subtitle" :icon="e.icon" @select="go(e.id)"/></div>
      <SectionHeader title="近期安排" meta="模拟数据"/><div class="service-group upcoming-group"><button v-for="e in exams.slice(0,1)" :key="e.name" class="service-row" @click="go('exams')"><CalendarDays class="row-icon"/><span class="row-copy"><strong>{{e.name}} · 考试</strong><small>{{e.date.slice(5)}} · {{e.time}} · {{e.room}}</small></span><ChevronRight class="row-chevron" :size="18"/></button><button class="service-row" @click="go('study')"><GraduationCap class="row-icon"/><span class="row-copy"><strong>查看本学期学业进度</strong><small>模拟培养方案与学分记录</small></span><ChevronRight class="row-chevron" :size="18"/></button><button class="service-row" @click="go('official')"><Bell class="row-icon"/><span class="row-copy"><strong>公开教务通知</strong><small>未同步 · 前往官方入口查看</small></span><ChevronRight class="row-chevron" :size="18"/></button></div>
    </template>
    <template v-else-if="page==='academic'">
      <template v-if="section==='overview'">
      <AcademicSummary :average="weightedAverage(data.grades).toFixed(1)" :grades="data.grades.length" :credits="credits" :exams="exams.length" :exam-date="exams[0]?.date" :week="week" :courses="weekCount" @open="go"/>
      <div class="quick-grid academic-quick"><QuickAction v-for="e in entries" :key="e.id" :title="e.title" :subtitle="e.subtitle" :icon="e.icon" @select="go(e.id)"/></div>
      <SectionHeader title="教学管理" meta="3 项"/><ServiceGroup :items="teaching" @select="go"/>
      <SectionHeader title="学业与规划" meta="2 项"/><ServiceGroup :items="planning" @select="go"/>
      <SectionHeader title="校园教务入口" meta="官方外链"/><ServiceGroup :items="official" @select="go"/>
      <p class="footnote source-footnote"><ShieldCheck :size="13"/>模拟数据 · 未连接邯郸学院教务系统</p>
      </template>
      <Transition v-else name="content" mode="out-in"><AcademicDetail :key="section==='calendar'||section==='schedule'?'schedule-family':section" :section="section" :data="data" :now="now" :major="prefs.major" @navigate="go" @course="details"/></Transition>
    </template>
    <template v-else>
      <button class="profile-strip" @click="open('edit')"><span class="avatar">{{prefs.name.slice(0,1)||'同'}}</span><span class="profile-copy"><strong>{{prefs.name}}</strong><small>{{prefs.major}}</small><span>模拟学生 · 本地资料</span></span><span class="edit-link">编辑 <ChevronRight :size="15"/></span></button>
      <SectionHeader title="外观设置"/><section class="settings-group"><div class="theme-row"><span class="setting-label"><Sun :size="21"/>主题</span><div class="theme-options" aria-label="主题选择"><button v-for="t in [{id:'light',name:'浅色',icon:Sun},{id:'dark',name:'深色',icon:Moon},{id:'system',name:'系统',icon:Monitor}]" :key="t.id" :class="{selected:prefs.theme===t.id}" :aria-pressed="prefs.theme===t.id" @click="prefs.theme=t.id as typeof prefs.theme"><component :is="t.icon" :size="16"/>{{t.name}}</button></div></div><SettingsRow title="紧凑布局" description="更少留白，更高信息密度" v-model="prefs.compact"/></section>
      <SectionHeader title="应用设置"/><ServiceGroup :items="settings" @select="open"/>
      <SectionHeader title="关于与隐私"/><ServiceGroup :items="about" @select="open"/>
      <p class="footnote source-footnote"><ShieldCheck :size="13"/>没有学校账号 · 没有广告与分析追踪</p>
    </template>
    <footer>邯郸校园 <span>·</span> 独立开源学生项目 <span>·</span> 非学校官方应用</footer>
    </div></Transition>
  </main>
  <div class="navigation-dock" :class="{'nav-suspended':!!modal}"><FloatingNavigation :page="page" @navigate="nav"/></div>
  <Transition name="toast"><div v-if="toast" class="toast" role="status"><Check :size="17"/>{{toast}}</div></Transition>
  <Transition name="overlay"><div v-if="modal" class="overlay-scrim" :class="{drawerOpen:modal==='drawer'}" @click.self="close" @keydown.tab="trapFocus"><section data-overlay class="overlay-surface" :class="{drawer:modal==='drawer'}" role="dialog" aria-modal="true" :aria-label="modal==='course'?'课程详情':modal==='drawer'?'侧边导航':'校园助手设置'"><div class="sheet-grip" aria-hidden="true"/><button class="icon-button overlay-close" aria-label="关闭" @click="close"><X :size="22"/></button>
    <template v-if="modal==='drawer'"><div class="drawer-brand"><span class="brand-mark"><GraduationCap :size="25"/></span><strong>邯郸校园</strong><span>v0.2.1</span></div><button class="drawer-profile" @click="move('profile')"><span class="avatar">{{prefs.name.slice(0,1)||'同'}}</span><span><strong>{{prefs.name}}</strong><small>{{prefs.major}}</small></span><ChevronRight :size="17"/></button><SectionHeader title="我的校园"/><ServiceGroup :items="[{id:'home',title:'今日',icon:House},{id:'academic',title:'教务中心',icon:BookOpen},{id:'profile',title:'个人设置',icon:UserRound}]" @select="id=>nav(id as Page)"/><SectionHeader title="项目"/><ServiceGroup :items="about.slice(1,3)"/><button class="drawer-privacy" @click="open('privacy')"><ShieldCheck :size="17"/>本机存储 · 隐私说明</button><p class="footnote">为同学，由同学。<br>只保留校园里真正需要的信息。</p></template>
    <template v-else-if="modal==='course'&&selected"><span class="icon-tile"><BookOpen :size="25"/></span><h2>{{selected.name}}</h2><p class="muted">课程详情 · 模拟数据</p><dl><dt>时间</dt><dd>周{{weekdays[selected.day-1]}} {{selected.start}}–{{selected.end}}</dd><dt>节次</dt><dd>{{selected.period}}</dd><dt>教室</dt><dd>{{selected.room}}</dd><dt>教师</dt><dd>{{selected.teacher}}</dd><dt>教学周</dt><dd>{{selected.weeks.length===18?'1–18周':selected.weeks.join('、')+'周'}}</dd></dl><button class="primary full" @click="close">完成</button></template>
    <template v-else-if="modal==='notifications'"><h2>通知设置</h2><p class="muted">应用内提醒 · 不发送系统推送</p><SettingsRow title="应用内提醒" description="显示演示消息和顶部未读标记" v-model="prefs.notifications"/><EmptyState v-if="!prefs.notifications" title="提醒已关闭" description="你可以随时重新开启。"/><template v-else><article class="notice"><Info :size="20"/><div><h3>欢迎体验邯郸校园 v0.2</h3><p>课程、成绩和校历均为模拟；公开教务通知尚未同步，请前往学校官方入口查看。</p><small>{{read?'已读':'未读'}} · 项目公告</small></div></article><button class="secondary full" @click="read=true;notify('通知已标记为已读')"><CheckCheck :size="17"/>全部标为已读</button></template></template>
    <form v-else-if="modal==='edit'" @submit.prevent="saveProfile"><h2>编辑个人资料</h2><p class="muted">无需填写真实学号和身份信息。</p><label class="form-label">昵称<input v-model="draft.name" maxlength="20" required autocomplete="nickname" placeholder="怎么称呼你"/></label><label class="form-label">专业 / 年级<input v-model="draft.major" maxlength="50" required/></label><button class="primary full" type="submit">保存资料</button></form>
    <template v-else-if="modal==='cache'"><Database :size="27"/><h2>缓存管理</h2><div class="storage-line"><span>离线教务缓存</span><strong>未创建</strong></div><div class="storage-line"><span>模拟教务数据</span><strong>应用资源 / 内存</strong></div><p>未下载学校数据。个人资料和主题单独保存在当前浏览器，可在数据管理中重置。</p><button class="secondary full" @click="load();close();notify('演示数据已重新加载')"><RefreshCw :size="17"/>重新加载演示数据</button></template>
    <template v-else-if="modal==='reset'"><Database :size="27"/><h2>重置本机数据？</h2><p>恢复默认昵称、主题和偏好。模拟课程不受影响，操作后可重新设置。</p><div class="modal-actions"><button class="secondary" @click="close">取消</button><button class="primary" @click="reset">确认重置</button></div></template>
    <template v-else-if="modal==='privacy'"><ShieldCheck :size="27"/><h2>隐私政策</h2><p>本版本不连接学校教务系统，不采集学校账号、密码或学号，不包含广告与分析追踪代码。</p><p>昵称、专业、主题和偏好仅保存在本机 localStorage；模拟课程、成绩与考试属于虚构示例。</p><p>托管平台可能产生运行必需的访问日志。外部网站受其各自隐私政策约束。</p><button class="primary full" @click="close">我知道了</button></template>
    <template v-else-if="modal==='import'"><Download :size="27"/><h2>课表数据来源</h2><span class="source-label">当前：内置模拟数据</span><p>文件导入与学校系统同步尚未实现。本版保留完整演示课表，不要求输入学校账号。</p><p>真实数据接入将在获得授权并核对学校课节、教学周规则后开展。</p><button class="primary full" @click="close">继续体验</button></template>
    <template v-else><span class="brand-mark"><GraduationCap :size="27"/></span><h2>邯郸校园 <small>v0.2.1</small></h2><p>为同学，由同学。独立开源的学生校园助手，未获邯郸学院官方认证或合作授权。</p><p>原创代码采用 MIT 许可证。工程研究参考 UBAA、HFUT-Schedule、DanXi、fzuhelper-app；设计吸收用户提供参考图的通用布局原则。</p><a class="secondary full" href="https://github.com/zthy3375-wq/fish" target="_blank" rel="noopener noreferrer"><Github :size="17"/>查看开源项目</a></template>
  </section></div></Transition>
</div>
</template>

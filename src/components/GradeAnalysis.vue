<script setup lang="ts">
import {computed,ref,watch} from 'vue';
import {ArrowUpRight,ArrowDownRight,ChevronDown,Filter,RefreshCw,GraduationCap} from 'lucide-vue-next';
import {academicCache,academicBusy,syncAcademic} from '../composables/handan-academic';
import {gradeView} from '../composables/grade-analysis';
import {buildGradeReport,filterGradeRecords,gradeBands,bandOf,defaultGradeFilter,type GradeRecord} from '../domain/grade-analysis';
const props=defineProps<{center?:boolean}>();
const report=computed(()=>buildGradeReport(academicCache.value.grades.data||[]));
const f=gradeView.filter;
const missingCredits=computed(()=>report.value.records.filter(r=>r.credit===null).length),missingGpas=computed(()=>report.value.records.filter(r=>r.gpa===null).length);
const summary=computed(()=>report.value.summary(f.term));
const rows=computed(()=>filterGradeRecords(report.value.records,f));
const distribution=computed(()=>gradeBands.map(([id,label])=>({id,label,count:report.value.records.filter(r=>(f.term==='all'||r.termLabel===f.term)&&bandOf(r)===id).length})));
const distributionTotal=computed(()=>distribution.value.reduce((s,b)=>s+b.count,0));
const tab=computed(()=>props.center?'study':gradeView.tab);
const activeFilters=computed(()=>[f.query,f.kind==='all'?'':f.kind,f.band==='all'?'':f.band,f.state==='all'?'':f.state].filter(Boolean).length);
const metric=ref<'mean'|'gpa'>('mean'),showFilters=ref(false);
const dated=computed(()=>report.value.semesters.filter(t=>t.order!==null));
const maxY=computed(()=>metric.value==='mean'?100:Math.max(5,...dated.value.map(t=>t.gpa??0)));
const points=computed(()=>dated.value.map((t,i)=>({...t,value:t[metric.value],x:40+i*100,y:t[metric.value]===null?null:135-t[metric.value]!/maxY.value*105})));
const paths=computed(()=>{const paths:string[][]=[];let line:string[]=[],previous:number|null=null;for(const p of points.value){if(previous!==null&&p.order!==previous+(previous%10===1?1:9)){if(line.length)paths.push(line);line=[]}previous=p.order;if(p.y===null){if(line.length)paths.push(line);line=[]}else line.push(`${p.x},${p.y}`)}if(line.length)paths.push(line);return paths.map(p=>p.join(' '))});
const delta=computed(()=>{const t=dated.value;if(t.length<2)return null;const a=t[t.length-1][metric.value],b=t[t.length-2][metric.value];return a===null||b===null?null:a-b});
const fmt=(n:number|null,d=2)=>n===null?'—':n.toFixed(d).replace(/\.00$/,'');
const status={passed:'已通过',failed:'未通过',pending:'待公布',unknown:'待核对'};
const timestamp=computed(()=>{const v=academicCache.value.grades.updatedAt;return v&&!Number.isNaN(Date.parse(v))?new Date(v).toLocaleString('zh-CN',{hour12:false}):'尚未同步'});
function clear(){Object.assign(f,defaultGradeFilter());gradeView.limit=60}
function selectTerm(term:string){f.term=f.term===term?'all':term;gradeView.tab='details'}
function selectBand(band:string){f.band=f.band===band?'all':band;gradeView.tab='details'}
function showCourse(name:string){clear();f.query=name;gradeView.tab='details'}
const pendingFailures=computed(()=>report.value.failures.filter(g=>f.term==='all'||g.records.some(r=>r.termLabel===f.term)));
watch(()=>JSON.stringify(f),()=>{gradeView.limit=60});
watch(()=>report.value.terms.join('|'),()=>{if(f.term!=='all'&&!report.value.terms.includes(f.term))f.term='all'});
const groupFor=(r:GradeRecord)=>report.value.groups.find(g=>g.records.some(x=>x.key===r.key));
</script>
<template>
 <section class="grade-analysis" :aria-label="center?'学业中心':'成绩分析'">
  <div class="ga-heading"><div><h2>{{center?'已修课程与学分':'已同步成绩'}}</h2><p>{{timestamp}} · 本机统计</p></div><button class="icon-button" aria-label="刷新学校成绩" :disabled="academicBusy" @click="syncAcademic()"><RefreshCw :size="18" :class="{spinning:academicBusy}"/></button></div>
  <p v-if="academicCache.session==='expired'" class="ga-notice" role="status">学校登录已过期，下面是上次同步记录。请在「我的」重新连接。</p>
  <p v-if="academicCache.session==='unknown'" class="ga-notice" role="status">学校连接状态待确认，当前分析来自本机已保存记录。</p>
  <p v-if="academicCache.grades.error" class="ga-notice" role="status">{{academicCache.grades.error}} · 已保留上次成绩，不能代表最新发布情况。</p>
  <p v-if="academicCache.grades.scope!=='all'&&report.records.length" class="ga-notice">旧缓存或单学期记录，历史范围尚未确认。刷新后查询学校当前可见的全部成绩。</p>
  <p v-if="report.invalid" class="ga-notice">{{report.invalid}} 条异常记录未参与分析，请刷新核对。</p>
  <div v-if="!report.records.length" class="ga-empty"><GraduationCap :size="30"/><h3>{{academicCache.grades.updatedAt?'学校暂无可分析的成绩':'还没有本人已同步成绩'}}</h3><p>首次连接后自动读取。不会使用演示成绩或虚构学分。</p></div>
  <template v-else>
   <div v-if="!center" class="ga-tabs" role="tablist" aria-label="成绩视图"><button v-for="t in [['overview','分析概览'],['details','成绩明细']]" :key="t[0]" role="tab" :aria-selected="tab===t[0]" @click="gradeView.tab=t[0]">{{t[1]}}</button></div>
   <div class="ga-toolbar"><select v-model="f.term" aria-label="成绩学期"><option value="all">全部已同步学期</option><option v-for="t in report.terms" :key="t" :value="t">{{t}}</option></select><button v-if="!center" class="secondary" aria-label="筛选" :aria-expanded="showFilters" @click="showFilters=!showFilters;gradeView.tab='details'"><Filter :size="15"/>筛选<span v-if="activeFilters">({{activeFilters}})</span></button></div>
   <div v-if="center||tab==='details'" class="ga-search"><input v-model="f.query" aria-label="搜索成绩课程" placeholder="搜索课程名称"/><span>{{rows.length}} 条</span></div>
   <div v-if="center||(tab==='details'&&showFilters)" class="ga-filters">
    <p class="ga-filter-note">筛选仅作用于下方明细，概览统计按所选学期展示。</p>
    <label>课程性质<select v-model="f.kind" aria-label="课程性质"><option value="all">全部性质</option><option v-for="k in report.types" :key="k.kind" :value="k.kind">{{k.kind}}</option></select></label>
    <label>成绩区间<select v-model="f.band" aria-label="成绩区间"><option value="all">全部成绩类型</option><option v-for="[id,label] in gradeBands" :key="id" :value="id">{{label}}</option></select></label>
    <label>通过状态<select v-model="f.state" aria-label="通过状态"><option value="all">全部状态</option><option v-for="(label,id) in status" :key="id" :value="id">{{label}}</option></select></label>
    <label>排序<select v-model="f.sort" aria-label="成绩排序"><option value="term">学期从新到旧</option><option value="score-desc">分数从高到低</option><option value="score-asc">分数从低到高</option><option value="credit">学分从高到低</option><option value="name">课程名称</option></select></label><button class="text-button" @click="clear">重置全部筛选</button>
   </div>
   <template v-if="tab!=='details'">
    <p v-if="missingCredits||missingGpas" class="ga-notice"><template v-if="missingCredits">{{missingCredits}} 条记录未提供有效学分</template><template v-if="missingCredits&&missingGpas">，</template><template v-if="missingGpas">{{missingGpas}} 条记录未提供绩点</template>；相关统计仅覆盖已有字段。</p>
    <div class="ga-stats" aria-label="成绩概览">
     <div><small>课程数</small><strong>{{summary.courses}}</strong><span>{{summary.records}} 条去重记录</span></div>
     <div><small>算术平均分</small><strong>{{fmt(summary.mean)}}</strong><span>{{summary.numericCount}} 门百分制</span></div>
     <div><small>学分加权平均</small><strong>{{fmt(summary.weightedMean)}}</strong><span>{{summary.weightedCount}} 门有学分</span></div>
     <div><small>已获学分 · 参考</small><strong>{{fmt(summary.earnedCredits)}}</strong><span>{{summary.creditCount}} 门已确认通过</span></div>
     <div><small>最高 / 最低分</small><strong class="ga-minmax">{{fmt(summary.max)}} <i>/</i> {{fmt(summary.min)}}</strong><span>仅可确认的百分制成绩</span></div>
     <div><small>学校绩点加权</small><strong>{{fmt(summary.gpa)}}</strong><span>{{summary.gpaCount}} 门返回绩点及学分</span></div>
    </div>
    <details class="ga-method"><summary>统计口径与数据范围 <ChevronDown :size="14"/></summary><p>均分仅统计0–100的数值成绩，等级和通过制不换算分数。绩点采用学校返回值按学分加权，不推算公式，也不等同学校官方总GPA。</p><p>同一课程多次成绩不擅自取最高或最后一次，平均值暂不计入。学分按课程编号只累计一次；缺少编号的同名多记录、学分冲突和未知结果不累计。学期学分归入首次已确认通过的学期。</p><p>课程数按编号归并；无编号时同名记录暂归为待核对。{{summary.excluded}} 组多记录未参与均分，{{report.duplicates}} 条完全重复记录已折叠。当前统计仅覆盖学校已返回的记录，不代表培养方案审核。</p><p>数值及格线参考学校公开学籍办法第十八条（60分）。特殊课程以学校最终认定为准；补考/重修只有学校提供标记时才标注。</p></details>
    <section class="ga-chart-section"><div class="ga-section-title"><h3>学期趋势</h3><select v-model="metric" aria-label="趋势指标"><option value="mean">平均分</option><option value="gpa">学校绩点加权</option></select></div>
     <p v-if="delta!==null" class="ga-trend-note"><ArrowUpRight v-if="delta>=0" :size="16"/><ArrowDownRight v-else :size="16"/>较上一已同步学期 {{delta>=0?'+':''}}{{fmt(delta)}} <span>· 非连续学期不补线</span></p>
     <div v-if="points.length" class="ga-chart-scroll"><svg :width="Math.max(320,points.length*100)" height="180" role="img" :aria-label="metric==='mean'?'学期平均分趋势':'学校返回绩点加权趋势'"><line x1="20" y1="135" :x2="Math.max(300,points.length*100-20)" y2="135" class="ga-axis"/><line x1="20" y1="30" :x2="Math.max(300,points.length*100-20)" y2="30" class="ga-grid-line"/><text x="20" y="19">{{maxY}}</text><polyline v-for="(path,i) in paths" :key="i" :points="path" class="ga-trend-line"/><g v-for="p in points" :key="p.term" role="button" tabindex="0" :aria-label="'筛选学期 '+p.term" @click="selectTerm(p.term)" @keydown.enter.prevent="selectTerm(p.term)" @keydown.space.prevent="selectTerm(p.term)"><rect :x="p.x-24" y="22" width="48" height="154" fill="transparent" pointer-events="all"/><circle v-if="p.y!==null" :cx="p.x" :cy="p.y" r="4.5" class="ga-point"/><text :x="p.x" :y="p.y===null?124:p.y-12" text-anchor="middle">{{fmt(p.value)}}</text><text :x="p.x" y="157" text-anchor="middle">{{p.term.slice(0,4)}}</text><text :x="p.x" y="173" text-anchor="middle">{{p.term.includes('秋')?'秋季':'春季'}}</text></g></svg></div><p v-else class="muted">缺少可确认学期，暂不能绘制趋势。</p>
     <div class="ga-semesters"><button v-for="t in report.semesters" :key="t.term" :class="{selected:f.term===t.term}" @click="selectTerm(t.term)"><span>{{t.term}}<small>{{t.courses}} 门 · 已获 {{fmt(t.earnedCredits)}} 学分</small></span><span>{{fmt(t.mean)}}<small>绩点 {{fmt(t.gpa)}}</small></span></button></div>
    </section>
    <section class="ga-chart-section"><div class="ga-section-title"><h3>成绩分布</h3><small>按去重成绩记录 · {{distributionTotal}} 条</small></div><div class="ga-distribution"><button v-for="b in distribution" :key="b.id" :aria-label="'筛选成绩 '+b.label" @click="selectBand(b.id)"><span>{{b.label}}</span><span class="ga-bar-track"><i :style="{width:distributionTotal?`${b.count/distributionTotal*100}%`:'0%'}"/></span><small>{{b.count}} · {{distributionTotal?Math.round(b.count/distributionTotal*100):0}}%</small></button></div></section>
    <section class="ga-chart-section"><div class="ga-section-title"><h3>未通过与后续记录</h3><small>{{pendingFailures.length}} 门未通过</small></div><p v-if="!pendingFailures.length" class="muted">已同步且可确认的课程中暂无未通过项。</p><button v-for="g in pendingFailures" :key="g.key" class="ga-attention" @click="showCourse(g.name)"><span>{{g.name}}<small>{{g.records.map(r=>r.scoreText).join(' / ')}}</small></span><span>查看原始记录 ›</span></button><p v-if="report.resolved.length" class="ga-success">{{report.resolved.length}} 门曾未通过，已有通过记录。</p><p v-if="report.unknown.length" class="ga-notice">{{report.unknown.length}} 组课程结果待核对，其中 {{report.ambiguous.length}} 组缺少编号且有同名多记录。不会据此判为挂科已解决。</p></section>
    <section v-if="center" class="ga-chart-section"><div class="ga-section-title"><h3>课程性质与学分</h3><small>全部已同步记录</small></div><div v-for="k in report.types" :key="k.kind" class="ga-type"><span>{{k.kind}}</span><span>{{k.courses}} 门 · 已获 {{fmt(k.credits)}} 学分</span></div><div class="ga-graduation"><GraduationCap :size="22"/><div><h3>培养方案与毕业要求 · 待接入</h3><p>尚未取得适用本人年级、专业的培养方案及课程认定结果。暂不计算毕业完成比例或剩余学分。</p></div></div></section>
   </template>
   <section v-if="tab==='details'||center" class="ga-records" aria-label="原始成绩明细"><div class="ga-section-title"><h3>原始成绩明细</h3><small>{{rows.length}} 条</small></div><p class="muted">点开课程可查看学校原始成绩与补考、重修标记。</p>
    <details v-for="r in rows.slice(0,gradeView.limit)" :key="r.key" class="ga-record"><summary><span><strong>{{r.name}}</strong><small>{{r.termLabel}} · {{r.kind||'性质未提供'}} · {{r.credit??'—'}} 学分</small></span><span class="ga-score" :class="r.state">{{r.scoreText||'待公布'}}<small>{{status[r.state]}}</small></span></summary><dl><dt>学校原始成绩</dt><dd>{{r.scoreText||'未公布'}}</dd><dt>学校课程绩点</dt><dd>{{r.gpa??'未提供'}}</dd><dt>课程编号</dt><dd>{{r.courseCode||'未提供'}}</dd><dt>考试性质</dt><dd>{{r.examType||'未提供，不推测补考/重修'}}</dd><dt>原始学期</dt><dd>{{r.term||'未提供'}}</dd></dl><p v-if="groupFor(r)?.ambiguous" class="ga-notice">同名多记录，课程身份待核对，暂不累计学分或替换成绩。</p><p v-else-if="(groupFor(r)?.records.length??0)>1" class="ga-notice">该课程有多次成绩。学分只累计一次，平均分暂不选择替代成绩。</p></details>
    <p v-if="!rows.length" class="ga-empty">没有符合条件的已同步成绩。<button class="text-button" @click="clear">清除筛选</button></p><button v-if="rows.length>gradeView.limit" class="secondary full" @click="gradeView.limit+=60">加载更多（剩余 {{rows.length-gradeView.limit}} 条）</button>
   </section>
  </template>
 </section>
</template>

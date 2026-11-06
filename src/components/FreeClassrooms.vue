<script setup lang="ts">
import {computed,nextTick,onMounted,onUnmounted,reactive,ref,watch} from 'vue';
import {DoorOpen,ChevronDown,RefreshCw,Clock3} from 'lucide-vue-next';
import SchoolConnection from './SchoolConnection.vue';
import {academicCache} from '../composables/handan-academic';
import {classroomClient,classroomSupported,cachedClassrooms,ClassroomError} from '../services/classroom-client';
import {dateSelection,dateForWeek,currentRoomPeriod,freeRuns,ROOM_TTL,schoolDate,type ClassroomOptions,type ClassroomQuery,type ClassroomResults,type ClassroomDay,type Classroom} from '../domain/classrooms';
const supported=classroomSupported(),meta=ref<ClassroomOptions>(),loading=ref(false),busy=ref(false),error=ref(''),errorCode=ref('');
const filters=reactive({xnm:'',xqm:'',date:schoolDate(),campusId:'',buildingId:'',startPeriod:1,endPeriod:2});
const snapshot=ref<ClassroomResults>(),stamp=ref(''),fromCache=ref(false),now=ref(Date.now()),limit=ref(60);
const detailStamp=ref(0);
const detailExpired=computed(()=>now.value-detailStamp.value>=ROOM_TTL);
const selected=ref(''),detail=ref<ClassroomDay>(),detailBusy=ref(false),detailError=ref('');
let queryToken=0,metaToken=0,detailToken=0,disposed=false;
const expired=computed(()=>!!stamp.value&&now.value-Date.parse(stamp.value)>=ROOM_TTL);
const historical=computed(()=>fromCache.value||expired.value||!!error.value);
const needsLogin=computed(()=>!academicCache.value.connected||academicCache.value.session==='expired'||errorCode.value==='EXPIRED');
const dateInfo=computed(()=>{try{return meta.value?dateSelection(filters.date,meta.value):null}catch{return null}});
function query():ClassroomQuery{if(!meta.value)throw Error('请先加载学校筛选项');return {...filters,...dateSelection(filters.date,meta.value)}}
watch(filters,()=>{
 queryToken++;detailToken++;busy.value=false;detailBusy.value=false;selected.value='';detail.value=undefined;detailError.value='';error.value='';errorCode.value='';limit.value=60;
 try{const saved=cachedClassrooms(query());snapshot.value=saved?.data;stamp.value=saved?.updatedAt||'';fromCache.value=!!saved}catch{snapshot.value=undefined;stamp.value='';fromCache.value=false}
},{flush:'sync'});
function failure(e:unknown){error.value=(e as Error).message||'查询失败，本次空闲状态未知';errorCode.value=e instanceof ClassroomError?e.code:'';if(errorCode.value==='EXPIRED')academicCache.value.session='expired'}
async function loadOptions(q:Record<string,unknown>={}){
 if(!supported||!academicCache.value.connected)return;
 const token=++metaToken;queryToken++;detailToken++;loading.value=true;busy.value=false;snapshot.value=undefined;selected.value='';error.value='';errorCode.value='';
 try{const result=await classroomClient.options(q);if(disposed||token!==metaToken)return;meta.value=result;filters.xnm=result.term.xnm;filters.xqm=result.term.xqm;filters.campusId=result.campusId;filters.buildingId='';filters.startPeriod=Math.min(filters.startPeriod,result.periods.length);filters.endPeriod=Math.min(Math.max(filters.startPeriod,filters.endPeriod),result.periods.length)}catch(e){if(!disposed&&token===metaToken)failure(e)}finally{if(!disposed&&token===metaToken)loading.value=false}
}
async function search(){
 if(loading.value||busy.value)return;
 let q:ClassroomQuery;try{q=query();if(q.startPeriod>q.endPeriod)throw Error('结束节次不能早于开始节次')}catch(e){failure(e);return}
 const token=++queryToken;busy.value=true;error.value='';errorCode.value='';selected.value='';detail.value=undefined;detailToken++;
 try{const r=await classroomClient.query(q);if(disposed||token!==queryToken)return;snapshot.value=r.data;stamp.value=r.updatedAt;fromCache.value=false;limit.value=60}
 catch(e){if(!disposed&&token===queryToken){failure(e);fromCache.value=!!snapshot.value}}
 finally{if(!disposed&&token===queryToken)busy.value=false}
}
async function quick(kind:'now'|'two'){
 if(!meta.value)return;
 if(kind==='now'){
  const p=currentRoomPeriod(meta.value.periods);if(p===null){error.value='当前不在学校上课节次内，请选择节次查询';return}
  filters.date=schoolDate();filters.startPeriod=p;filters.endPeriod=p;
 }else{
  if(filters.startPeriod>=meta.value.periods.length){error.value='起始节次之后不足两节，请调整起始节次';return}filters.endPeriod=filters.startPeriod+1;
 }
 await nextTick();await search();
}
function chooseWeek(e:Event){if(meta.value)filters.date=dateForWeek(Number((e.target as HTMLSelectElement).value),dateInfo.value?.weekday||1,meta.value)}
function chooseDay(e:Event){if(meta.value)filters.date=dateForWeek(dateInfo.value?.week||1,Number((e.target as HTMLSelectElement).value),meta.value)}
function chooseTerm(e:Event){const [xnm,xqm]=(e.target as HTMLSelectElement).value.split('-');void loadOptions({xnm,xqm,campusId:filters.campusId})}
function chooseCampus(e:Event){void loadOptions({xnm:filters.xnm,xqm:filters.xqm,campusId:(e.target as HTMLSelectElement).value})}
async function openDay(room:Classroom){
 if(selected.value===room.id){selected.value='';detailToken++;detailBusy.value=false;return}
 if(!snapshot.value)return;
 selected.value=room.id;detail.value=undefined;detailError.value='';detailBusy.value=true;const token=++detailToken;
 try{const d=await classroomClient.day(snapshot.value.query,room.id,room.name);if(!disposed&&token===detailToken){detail.value=d;detailStamp.value=Date.now()}}
 catch(e){if(!disposed&&token===detailToken){detailError.value=(e as Error).message;if(e instanceof ClassroomError&&e.code==='EXPIRED')failure(e)}}
 finally{if(!disposed&&token===detailToken)detailBusy.value=false}
}
const groups=computed(()=>{const map=new Map<string,Classroom[]>();for(const r of snapshot.value?.rooms.slice(0,limit.value)||[]){const items=map.get(r.building)||[];items.push(r);map.set(r.building,items)}return [...map].map(([name,rooms])=>({name,rooms}))});
const times=computed(()=>{const s=snapshot.value;if(!s)return '';return `${s.periods.find(p=>p.number===s.query.startPeriod)?.start||''}–${s.periods.find(p=>p.number===s.query.endPeriod)?.end||''}`});
const timer=setInterval(()=>now.value=Date.now(),30000);
onMounted(()=>void loadOptions());
onUnmounted(()=>{disposed=true;queryToken++;metaToken++;detailToken++;clearInterval(timer)});
</script>
<template>
 <section class="classrooms-page" aria-label="空闲教室查询">
  <div v-if="!supported" class="panel"><DoorOpen/><h2>当前设备暂不支持学校教室直连</h2><p class="muted">请使用 Android 版查询真实空闲教室。不会根据个人课表推算全校结果。</p></div>
  <template v-else>
   <SchoolConnection v-if="needsLogin" compact @connected="loadOptions()" />
   <p class="room-source"><DoorOpen :size="16"/>邯郸学院教务 · 直接查询学校教室数据</p>
   <p v-if="loading" class="room-message" role="status">正在加载学校校区、教学楼和节次…</p>
   <form v-if="meta" class="room-filters" @submit.prevent="search">
    <fieldset :disabled="loading">
     <label class="room-wide">学期<select :value="`${filters.xnm}-${filters.xqm}`" aria-label="教室查询学期" @change="chooseTerm"><option v-for="t in meta.terms" :key="t.id" :value="t.id">{{t.name}}</option></select></label>
     <label>日期<input v-model="filters.date" type="date" :min="meta.minDate" :max="meta.maxDate" aria-label="查询日期" required /></label>
     <label>校区<select :value="filters.campusId" aria-label="教室校区" @change="chooseCampus"><option v-for="c in meta.campuses" :key="c.id" :value="c.id">{{c.name}}</option></select></label>
     <label>教学周<select :value="dateInfo?.week||''" aria-label="教室教学周" @change="chooseWeek"><option v-if="!dateInfo" value="" disabled>请选有效日期</option><option v-for="w in meta.weeks" :key="w" :value="w">第 {{w}} 周</option></select></label>
     <label>星期<select :value="dateInfo?.weekday||''" aria-label="教室星期" @change="chooseDay"><option v-if="!dateInfo" value="" disabled>—</option><option v-for="(d,i) in ['一','二','三','四','五','六','日']" :key="i" :value="i+1">星期{{d}}</option></select></label>
     <label class="room-wide">教学楼<select v-model="filters.buildingId" aria-label="教学楼"><option value="">全部教学楼</option><option v-for="b in meta.buildings" :key="b.id" :value="b.id">{{b.name}}</option></select></label>
     <label>开始节次<select v-model.number="filters.startPeriod" aria-label="开始节次"><option v-for="p in meta.periods" :key="p.number" :value="p.number">{{p.number}} 节 · {{p.start}}</option></select></label>
     <label>结束节次<select v-model.number="filters.endPeriod" aria-label="结束节次"><option v-for="p in meta.periods" :key="p.number" :value="p.number">{{p.number}} 节 · {{p.end}}</option></select></label>
    </fieldset>
    <div class="room-shortcuts"><button type="button" class="secondary" :disabled="loading||busy" @click="quick('now')"><Clock3 :size="14"/>现在空闲</button><button type="button" class="secondary" :disabled="loading||busy" @click="quick('two')">连续空闲两节及以上</button></div>
    <button class="primary room-submit" :disabled="loading||busy||needsLogin"><RefreshCw :size="15" :class="{spinning:busy}"/>{{busy?'正在查询…':'查询空闲教室'}}</button>
   </form>
   <div v-if="error" class="room-error" role="alert"><strong>{{error}}</strong><p v-if="snapshot">下方仅为上次查询记录，当前可用性未知。</p><button v-if="!meta&&!loading&&!needsLogin" class="text-button" @click="loadOptions()">重新加载筛选项</button></div>
   <template v-if="snapshot">
    <div class="room-result-heading"><h2>{{historical?'历史查询记录':'查询结果'}} <small>{{snapshot.total}} 间</small></h2><span :class="{'room-stale':historical}">{{expired?'缓存已过期':fromCache?'缓存 · 请重新查询':'学校实时返回'}}</span></div>
    <p class="room-query-caption">{{snapshot.query.date}} · 第 {{snapshot.query.week}} 周 · 星期{{['一','二','三','四','五','六','日'][snapshot.query.weekday-1]}} · 第 {{snapshot.query.startPeriod}}–{{snapshot.query.endPeriod}} 节 {{times}}</p>
    <p class="room-stamp">查询于 {{new Date(stamp).toLocaleString('zh-CN',{hour12:false})}} · 5 分钟后标记过期</p>
    <p v-if="historical" class="room-error">缓存仅供参考，当前空闲状态未知，请重新查询。</p>
    <p v-if="!snapshot.rooms.length" class="room-message">{{historical?'上次查询没有匹配记录；当前状态未知':'学校本次查询未返回符合条件的空闲教室。'}}</p>
    <section v-for="g in groups" :key="g.name" class="room-building"><h3>{{g.name}}</h3><div class="room-list">
     <article v-for="r in g.rooms" :key="r.id">
      <button class="room-card" :aria-expanded="selected===r.id" @click="openDay(r)"><span class="room-card-copy"><strong>{{r.name}}</strong><small>{{r.type||'类型未提供'}}<span v-if="r.capacity!==null"> · {{r.capacity}} 座</span></small><span class="room-range">{{historical?'历史记录':'查询范围内空闲'}} · 第 {{snapshot.query.startPeriod}}–{{snapshot.query.endPeriod}} 节 · {{snapshot.query.endPeriod-snapshot.query.startPeriod+1}} 节</span></span><ChevronDown :size="18"/></button>
      <section v-if="selected===r.id" class="room-day" :aria-label="r.name+'全天占用'">
       <p v-if="detailBusy" role="status">正在查询全天安排…</p><p v-else-if="detailError" class="room-error">{{detailError}} · 全天状态未知</p>
       <template v-else-if="detail"><p class="room-day-title">{{detail.date}} 全天占用 · {{detailExpired?'记录已过期，当前状态未知':'学校返回'}}</p><div class="room-day-grid"><div v-for="p in detail.slots" :key="p.number" :class="detailExpired?'unknown':p.state"><strong>{{p.number}} 节</strong><span>{{detailExpired?'未知':{free:'空闲',occupied:'占用',unknown:'未知'}[p.state]}}</span><small>{{p.start}}–{{p.end}}</small></div></div><p v-if="!detailExpired" class="room-runs">连续空闲：{{freeRuns(detail.slots).map(run=>`${run.start}–${run.end} 节（${run.count}节）`).join('、')||'未取得连续空闲时段'}}</p></template>
      </section>
     </article>
    </div></section>
    <button v-if="snapshot.rooms.length>limit" class="secondary room-submit" @click="limit+=60">继续显示（剩余 {{snapshot.rooms.length-limit}} 间）</button>
   </template>
   <p v-else-if="meta&&!busy&&!error" class="room-message">选择日期和节次，查询学校真实空闲教室。</p>
   <p class="room-footnote">结果反映学校已登记的安排，空闲不代表教室一定开放；临时占用和现场管理以学校为准。不同教学楼的缓存不混用。</p>
  </template>
 </section>
</template>

<script setup lang="ts">
import {computed,ref,watch} from 'vue';
import {Search,ChevronRight,ArrowLeft} from 'lucide-vue-next';
import {campusRooms,roomCatalogSource,roomCampus,roomFloor,searchRooms,type CampusRoom,type RoomCampus} from '../services/campus-rooms';
import {roomPlanTarget,type PlanTarget} from '../services/campus-plan';
const emit=defineEmits<{showPlan:[target:PlanTarget]}>();
function showPlan(room:CampusRoom){const target=roomPlanTarget(room);if(target)emit('showPlan',target)}
const query=ref(''),campus=ref<RoomCampus|'all'>('all'),building=ref(''),floor=ref(''),limit=ref(40),selected=ref<CampusRoom>();
const campusLabels={all:'全部',east:'东校区',west:'西校区',unknown:'待核对区域'};
const buildings=computed(()=>[...new Set(campusRooms.filter(r=>campus.value==='all'||roomCampus(r)===campus.value).map(r=>r.jxlmc))].sort((a,b)=>a.localeCompare(b,'zh-CN')));
const floors=computed(()=>[...new Set(campusRooms.filter(r=>r.jxlmc===building.value).map(r=>r.lch).filter(Boolean))].sort((a,b)=>Number(a)-Number(b)));
const results=computed(()=>searchRooms(query.value,campus.value,building.value,floor.value));
watch(campus,()=>{building.value='';selected.value=undefined});watch(building,()=>{floor.value='';selected.value=undefined});watch([query,campus,building,floor],()=>{limit.value=40});
</script>
<template>
 <section class="room-directory" aria-label="教室与场地目录">
  <p class="intro">查教室，先找到楼和楼层</p>
  <label class="search"><Search :size="18"/><input v-model="query" aria-label="搜索教室" placeholder="输入 A201、机器人、楼名…"/></label>
  <div class="tabs"><button v-for="(label,key) in campusLabels" :key="key" :class="{active:campus===key}" @click="campus=key">{{label}}</button></div>
  <div class="filters"><select v-model="building" aria-label="筛选楼栋"><option value="">全部楼栋 / 场地</option><option v-for="b in buildings" :key="b">{{b}}</option></select><select v-if="building&&!building.includes('室外')" v-model="floor" aria-label="筛选楼层"><option value="">全部楼层</option><option v-for="f in floors" :key="f" :value="f">{{f}} 层</option></select></div>
  <article v-if="selected" class="detail"><button class="back" @click="selected=undefined"><ArrowLeft :size="16"/>返回目录</button><h3>{{selected.cdmc}}</h3><p class="address">{{selected.jxlmc}} · {{roomFloor(selected)}}</p><button v-if="roomPlanTarget(selected)" class="more" @click="showPlan(selected)">在平面图查看楼栋</button><dl><dt>区域</dt><dd>{{campusLabels[roomCampus(selected)]}}</dd><dt>类型</dt><dd>{{selected.cdlbmc||'未登记'}}</dd><dt>座位</dt><dd>{{selected.zws||'未登记'}}</dd><dt>场地编号</dt><dd>{{selected.cdbh}}</dd></dl><p class="note">楼栋与楼层来自教务登记。室内门的位置、楼梯与入口尚未核实，暂不绘制到门路线。</p><p v-if="/不用|停用|废弃/.test(selected.cdmc)" class="notice">该名称包含停用提示，请向学校确认当前用途。</p></article>
  <template v-else><p class="count">找到 {{results.length}} 条教室与场地记录</p><div class="rows"><button v-for="r in results.slice(0,limit)" :key="r.cdbh" @click="selected=r"><span><strong>{{r.cdmc}}</strong><small>{{r.jxlmc}} · {{roomFloor(r)}}</small></span><ChevronRight :size="17"/></button></div><p v-if="!results.length" class="note">没有匹配记录。可清除楼栋筛选或搜索部分名称；目录仍在补充。</p><button v-if="results.length>limit" class="more" @click="limit+=40">继续显示（剩余 {{results.length-limit}} 条）</button></template>
  <details><summary>数据来源与覆盖范围</summary><p class="note">{{roomCatalogSource.date}} 从本人获准访问的教务页面整理 {{campusRooms.length}} 条场地记录，包含教室、实验室和室外场地。查询受时段筛选影响，未验证全校所有教室均已收录。</p><p class="note">教务“主校区”包含西区楼栋，区域按明确的东区/西区楼名划分；其他楼栋保留待核对。缺失楼层不从房间号猜测。</p></details>
 </section>
</template>
<style scoped>
.intro{font-size:15px;font-weight:650;margin:18px 0 12px}.search{display:flex;gap:8px;align-items:center;background:var(--color-bg);padding:12px;border-radius:12px}.search input{border:0;background:transparent;color:var(--color-text);outline:0;width:100%;min-width:0;font-size:14px}.tabs{display:flex;gap:5px;overflow:auto;margin:12px 0}.tabs button,.more{border:1px solid var(--color-border);background:var(--color-surface);color:var(--color-text);border-radius:10px;padding:10px;white-space:nowrap;font-size:12px}.tabs .active{background:var(--color-primary);color:white}.filters{display:flex;gap:8px}.filters select{min-width:0;flex:1;background:var(--color-surface);color:var(--color-text);border:1px solid var(--color-border);padding:10px;border-radius:10px}.count,.note,details{font-size:12px;color:var(--color-muted);line-height:1.7}.rows button{display:flex;align-items:center;justify-content:space-between;gap:10px;text-align:left;width:100%;padding:14px 0;background:transparent;color:var(--color-text);border:0;border-bottom:1px solid var(--color-border)}.rows span{min-width:0}.rows strong{font-size:14px;overflow-wrap:anywhere}.rows small{display:block;font-size:11px;color:var(--color-muted);margin-top:5px}.rows svg{flex-shrink:0}.more{width:100%;margin:14px 0}details{margin-top:20px}summary{cursor:pointer;padding:12px 0}.detail{padding:16px;background:var(--color-bg);border-radius:14px;margin-top:16px}.detail h3{font-size:18px;overflow-wrap:anywhere}.address{font-weight:600;font-size:14px}.detail dl{display:grid;grid-template-columns:72px 1fr;font-size:12px;gap:10px}.detail dd{margin:0;overflow-wrap:anywhere}.detail dt{color:var(--color-muted)}.back{display:flex;gap:6px;align-items:center;border:0;background:transparent;color:var(--color-primary);padding:0;min-height:32px}.notice{font-size:12px;color:#9b6024}
</style>

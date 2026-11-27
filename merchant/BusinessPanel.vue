<script setup lang="ts">
import {computed,onMounted,reactive,ref} from 'vue';
import {Activity,CalendarDays,ClipboardList,Flag,Image,Receipt,Settings,Store} from 'lucide-vue-next';
import {request,chinaTime,localTime,upload} from './api';
import {commerceError,dateLabel,type CommercePage} from '../src/services/commerce';
import {amount,assetName,contractState,placementName,stateName,type AdRecord,type Audit,type Contract,type Daily,type Plan,type Report,type Schedule,type ShopRecord} from './types';
import Stats from './Stats.vue';

const props=defineProps<{owner:boolean}>();
const emit=defineEmits<{expired:[]}>();
const sections=[{id:'shops',name:'商家审核',icon:Store},{id:'ads',name:'素材审核',icon:Image},{id:'schedule',name:'广告排期',icon:CalendarDays},
 {id:'contracts',name:'合同与收款',icon:Receipt},{id:'reports',name:'举报处理',icon:Flag},{id:'metrics',name:'推广统计',icon:Activity},
 {id:'settings',name:'定价与权限',icon:Settings},{id:'audit',name:'操作记录',icon:ClipboardList}] as const;
type Section=typeof sections[number]['id'];
type Row=ShopRecord|AdRecord|Schedule|Contract|Report|Audit;
const section=ref<Section>('shops'),busy=ref(false),error=ref(''),status=ref(''),rows=ref<Row[]>([]),next=ref<string|null>(null),filter=ref('pending');
const selected=ref(''),decision=ref(''),reason=ref(''),media=ref<Record<string,string>>({});
const plans=ref<Plan[]>([]),settings=reactive({ads_enabled:false,ios_ads_enabled:false}),settingsReason=ref('');
const plansReason=ref(''),identity=reactive({id:'',kind:'student',enabled:true,reason:''});
const days=ref<Daily[]>([]),statsShop=ref(''),asShop=ref('');
const periodStart=()=>localTime(new Date().toISOString());
const contract=reactive({id:crypto.randomUUID(),shopId:'',plan:'preferred',kind:'monthly',startsAt:periodStart(),endsAt:'',placements:[] as string[],cents:'',reference:'',attachment:'',renewedFrom:''});
const attachment=ref<File>();
const schedule=reactive({id:crypto.randomUUID(),adId:'',contractId:'',placement:'category',startsAt:periodStart(),endsAt:''});
const receipt=reactive({id:crypto.randomUUID(),contractId:'',yuan:'',reference:''});
const filters=computed(()=>section.value==='shops'?['pending','approved','rejected','suspended']:section.value==='ads'?['pending','approved','rejected','removed']:section.value==='reports'?['open','resolved']:[]);
const label=computed(()=>sections.find(s=>s.id===section.value)?.name||'');
const planSelected=computed(()=>plans.value.find(p=>p.id===contract.plan));
const slots=computed(()=>[
 ...(planSelected.value?.category_slot?['category']:[]),
 ...(planSelected.value?.banner_slot?['banner']:[]),
 ...(planSelected.value?.home_slot?['home']:[]),
]);

async function run(operation:()=>Promise<void>){
 if(busy.value)return;busy.value=true;error.value='';status.value='';
 try{await operation();}catch(cause){
  if((cause as Error).message==='session_expired')emit('expired');
  else error.value=commerceError(cause);
 }finally{busy.value=false;}
}
async function configuration(){
 const result=await request<{settings:typeof settings;plans:Plan[]}>('admin.config');
 Object.assign(settings,result.settings);plans.value=result.plans;
}
async function list(append=false){
 if(section.value==='settings'){await configuration();return;}
 if(section.value==='metrics'){days.value=(await request<{days:Daily[]}>('admin.stats',{shopId:statsShop.value||null})).days;return;}
 const result=await request<CommercePage<Row>>('admin.list',{
  section:section.value,filter:filter.value||null,shopId:section.value==='contracts'?asShop.value||null:null,next:append?next.value:null,
 });
 rows.value=append?[...rows.value,...result.items]:result.items;
 media.value={...(append?media.value:{}),...result.media};next.value=result.next;
}
function go(to:Section){
 if(busy.value)return;
 section.value=to;rows.value=[];next.value=null;selected.value='';reason.value='';decision.value='';
 filter.value=['shops','ads'].includes(to)?'pending':to==='reports'?'open':'';
 void run(()=>list());
}
onMounted(()=>void run(async()=>{await configuration();await list();}));
function begin(rowId:string,action:string){
 selected.value=rowId;decision.value=action;reason.value='';
}
function mutate(action:string,body:Record<string,unknown>){
 void run(async()=>{
  await request(action,body);selected.value='';decision.value='';reason.value='';await list();status.value='操作已保存';
 });
}
function newContract(shopId='',renewedFrom='',startsAt=periodStart(),plan='preferred'){
 Object.assign(contract,{id:crypto.randomUUID(),shopId,renewedFrom,startsAt,endsAt:'',plan,kind:'monthly',placements:[],cents:'',reference:'',attachment:''});
 attachment.value=undefined;
}
function applyContract(){
 void run(async()=>{
  if(attachment.value){
   contract.attachment=await upload(attachment.value,'contract');
   attachment.value=undefined;
  }
  await request('admin.contract',{...contract,startsAt:chinaTime(contract.startsAt),
   endsAt:contract.kind==='short'?chinaTime(contract.endsAt):null,
   cents:contract.cents===''?null:Math.round(Number(contract.cents)*100),attachment:contract.attachment||null,
   renewedFrom:contract.renewedFrom||null,
  });
  newContract(contract.shopId);await list();status.value='合同已登记，所选广告位已预留';
 });
}
function applySchedule(){
 void run(async()=>{
  await request('admin.schedule',{...schedule,startsAt:chinaTime(schedule.startsAt),endsAt:chinaTime(schedule.endsAt)});
  Object.assign(schedule,{id:crypto.randomUUID(),adId:'',contractId:'',placement:'category',startsAt:periodStart(),endsAt:''});
  await list();status.value='广告排期已保存';
 });
}
function applyReceipt(){
 void run(async()=>{
  await request('admin.receipt',{id:receipt.id,contractId:receipt.contractId,cents:Math.round(Number(receipt.yuan)*100),reference:receipt.reference});
  Object.assign(receipt,{id:crypto.randomUUID(),contractId:'',yuan:'',reference:''});
  await list();status.value='线下账款已登记';
 });
}
function savePlan(plan:Plan){
 mutate('admin.plan',{plan:plan.id,name:plan.name,cents:plan.cents,categorySlot:plan.category_slot,bannerSlot:plan.banner_slot,homeSlot:plan.home_slot,reports:plan.reports,reason:plansReason.value});
}
function detailLabel(row:Schedule){
 if(row.state==='removed')return '已下架';
 if(Date.parse(row.endsAt)<=Date.now())return '已到期';
 if(row.state==='paused')return '已暂停';
 return Date.parse(row.startsAt)>Date.now()?'待开始':'已启用';
}
</script>

<template>
 <div class="workspace">
  <aside><p class="side-title">{{owner?'项目所有者':'商务管理员'}}</p><nav aria-label="商业管理菜单">
   <button v-for="item in sections" :key="item.id" :aria-current="section===item.id?'page':undefined" :disabled="busy" @click="go(item.id)"><component :is="item.icon" :size="18"/>{{item.name}}</button>
  </nav></aside>
  <div class="workspace-main surface" :aria-busy="busy">
   <h1>{{label}}</h1>
   <p v-if="status" class="status" role="status">{{status}}</p><p v-if="error" class="status error" role="alert">{{error}}</p>
   <p v-if="busy" class="subtle" role="status">正在处理…</p>
   <label v-if="filters.length" class="inline">状态<select v-model="filter" :disabled="busy" @change="run(()=>list())"><option value="">全部</option><option v-for="item in filters" :key="item" :value="item">{{stateName[item]||(item==='open'?'待处理':'已处理')}}</option></select></label>
   <template v-if="section==='shops'">
    <article v-for="row in rows as ShopRecord[]" :key="row.id" class="record stack">
     <div><h2>{{row.draft.name}}</h2><p class="subtle">{{stateName[row.state]}} · {{row.draft.address}}</p></div>
     <p>{{row.draft.description}}</p><p class="subtle">{{row.draft.hours}} · {{row.draft.phone}} · {{row.draft.category}}</p>
     <div class="photos"><img v-for="key in row.draft.images.filter(id=>media[id])" :key="key" :src="media[key]" alt="待审门店照片"/></div>
     <dl class="summary-list"><dt>登记主体</dt><dd>{{row.draft.legalName}}</dd><dt>资质编号</dt><dd>{{row.draft.businessId}}</dd><dt>登记信息</dt><dd>{{row.draft.legalAddress}} · {{row.draft.legalPhone}}</dd><dt>说明</dt><dd>{{row.draft.qualification}}</dd></dl>
     <a v-if="media[row.draft.qualificationImage]" :href="media[row.draft.qualificationImage]" target="_blank" rel="noopener noreferrer">核对资质材料</a>
     <p v-if="row.decision" class="subtle">{{row.decision}}</p>
     <div class="buttons">
      <button v-if="row.state==='pending'||row.state==='suspended'" class="secondary" @click="begin(row.id,'approved')">{{row.state==='suspended'?'恢复展示':'通过审核'}}</button>
      <button v-if="row.state==='pending'" class="secondary" @click="begin(row.id,'rejected')">退回</button>
      <button v-if="row.published&&row.state!=='suspended'" class="secondary" @click="begin(row.id,'suspended')">违规下架</button>
      <button v-if="row.state==='approved'" class="secondary" @click="newContract(row.id);go('contracts')">登记合同</button>
     </div>
     <form v-if="selected===row.id" class="stack" @submit.prevent="mutate('admin.shop',{id:row.id,revision:row.revision,decision,reason})">
      <label>{{stateName[decision]}}处理说明<textarea v-model.trim="reason" required minlength="2" maxlength="500" rows="2"/></label><button class="primary" :disabled="busy">确认处理</button>
     </form>
    </article>
   </template>
   <template v-else-if="section==='ads'">
    <article v-for="row in rows as AdRecord[]" :key="row.id" class="record stack">
     <img v-if="media[row.image]" class="record-image" :src="media[row.image]" alt="待审核广告素材"/>
     <div><h2>{{row.title}}</h2><p>{{row.subtitle}}</p><p class="subtle">{{row.shopName}} · {{stateName[row.state]}} {{row.decision}}</p></div>
     <div class="buttons">
      <button v-if="row.state==='pending'" class="secondary" @click="begin(row.id,'approved')">通过审核</button>
      <button v-if="row.state==='pending'" class="secondary" @click="begin(row.id,'rejected')">退回</button>
      <button v-if="row.state==='approved'" class="secondary" @click="schedule.adId=row.id;go('schedule')">安排投放</button>
      <button v-if="row.state==='approved'" class="secondary" @click="begin(row.id,'removed')">违规下架</button>
     </div>
     <form v-if="selected===row.id" class="stack" @submit.prevent="mutate('admin.ad',{id:row.id,decision,reason})">
      <label>{{stateName[decision]}}处理说明<textarea v-model.trim="reason" required minlength="2" maxlength="500" rows="2"/></label><button class="primary" :disabled="busy">确认处理</button>
     </form>
    </article>
   </template>
   <template v-else-if="section==='schedule'">
    <form class="fields" @submit.prevent="applySchedule">
     <h2 class="wide">新增排期</h2>
     <label>已审核素材 ID<input v-model.trim="schedule.adId" required/></label>
     <label>预留库存的合同 ID<input v-model.trim="schedule.contractId" required/></label>
     <label>广告位置<select v-model="schedule.placement"><option v-for="(name,id) in placementName" :key="id" :value="id">{{name}}</option></select></label>
     <label>开始（北京时间）<input v-model="schedule.startsAt" required type="datetime-local"/></label>
     <label>结束（北京时间）<input v-model="schedule.endsAt" required type="datetime-local"/></label>
     <button class="primary wide" :disabled="busy">保存排期</button>
    </form>
    <article v-for="row in rows as Schedule[]" :key="row.id" class="record stack">
     <div><h3>{{row.title}} · {{assetName(row.placement)}}</h3><p>{{dateLabel(row.startsAt)}} 至 {{dateLabel(row.endsAt)}} · {{detailLabel(row)}}</p></div>
     <div v-if="row.state!=='removed'&&Date.parse(row.endsAt)>Date.now()" class="buttons">
      <button class="secondary" @click="begin(row.id,row.state==='paused'?'active':'paused')">{{row.state==='paused'?'恢复':'暂停'}}</button><button class="secondary" @click="begin(row.id,'removed')">下架</button>
     </div>
     <form v-if="selected===row.id" class="stack" @submit.prevent="mutate('admin.schedule.state',{id:row.id,decision,reason})">
      <label>{{stateName[decision]}}说明<textarea v-model.trim="reason" required minlength="2" maxlength="500" rows="2"/></label><button class="primary" :disabled="busy">确认</button>
     </form>
    </article>
   </template>
   <template v-else-if="section==='contracts'">
    <form class="fields" @submit.prevent="applyContract">
     <h2 class="wide">{{contract.renewedFrom?'续期登记':'登记线下合同'}}</h2>
     <label>门店 ID<input v-model.trim="contract.shopId" required/></label>
     <label>套餐<select v-model="contract.plan" @change="contract.placements=[]"><option v-for="plan in plans" :key="plan.id" :value="plan.id">{{plan.name}} · {{amount(plan.cents)}}</option></select></label>
     <label>合作方式<select v-model="contract.kind" @change="contract.cents=''"><option value="monthly">月度</option><option value="trial">14 天免费试用</option><option value="short" :disabled="!owner">短期推广</option></select></label>
     <label>签约编号或说明<input v-model.trim="contract.reference" required minlength="2" maxlength="200"/></label>
     <label>开始（北京时间）<input v-model="contract.startsAt" type="datetime-local" required/></label>
     <label v-if="contract.kind==='short'">结束（北京时间）<input v-model="contract.endsAt" type="datetime-local" required/></label>
     <p v-if="contract.kind!=='short'" class="subtle">结束时间按{{contract.kind==='trial'?'14 天':'一个自然月'}}自动计算。</p>
     <label v-if="owner&&contract.kind!=='trial'">自定义金额（元）<input v-model.trim="contract.cents" type="number" placeholder="默认套餐价" min="0" max="100000" step=".01"/></label>
     <label>合同附件（选填）<input type="file" accept="image/jpeg,image/png,image/webp" @change="attachment=($event.target as HTMLInputElement).files?.[0]"/></label>
     <fieldset v-if="slots.length" class="wide"><legend>预留广告位</legend><label v-for="slot in slots" :key="slot" class="check"><input v-model="contract.placements" type="checkbox" :value="slot"/>{{placementName[slot]}}</label></fieldset>
     <div class="buttons wide"><button class="primary" :disabled="busy">登记并预留</button><button v-if="contract.renewedFrom" type="button" class="secondary" @click="newContract()">取消续期</button></div>
    </form>
    <form v-if="receipt.contractId" class="fields" @submit.prevent="applyReceipt">
     <h2 class="wide">登记实际线下收款或退款</h2>
     <label>金额（元，退款填负数）<input v-model.trim="receipt.yuan" required type="number" step=".01" min="-100000" max="100000"/></label>
     <label>收据或流水编号<input v-model.trim="receipt.reference" required minlength="2" maxlength="200"/></label>
     <button class="primary wide" :disabled="busy">添加财务记录</button>
    </form>
    <form class="inline" @submit.prevent="run(()=>list())"><label>按门店 ID 查找<input v-model.trim="asShop" placeholder="全部门店"/></label><button class="secondary" :disabled="busy">查找</button></form>
    <article v-for="row in rows as Contract[]" :key="row.id" class="record stack">
     <div><h3>{{row.snapshot.name}} · {{stateName[row.kind]}} · {{contractState(row)}}</h3><p>{{dateLabel(row.startsAt)}} 至 {{dateLabel(row.endsAt)}}</p>
      <p class="subtle">{{row.reference}} · 已登记 {{amount(row.paid)}} / {{amount(row.cents)}}</p><p class="subtle">{{row.placements.map(assetName).join('、')||'基础权益'}}</p></div>
     <p class="identifier">合同 ID <code>{{row.id}}</code></p>
     <a v-if="row.attachment&&media[row.attachment]" :href="media[row.attachment]" target="_blank" rel="noopener noreferrer">查看合同附件</a>
     <details v-if="row.receipts.length"><summary>财务凭证</summary><p v-for="entry in row.receipts" :key="entry.id">{{dateLabel(entry.recorded_at)}} · {{amount(entry.cents)}} · {{entry.reference}}</p></details>
     <div class="buttons">
      <button class="secondary" @click="receipt.contractId=row.id">登记款项</button>
      <button v-if="!row.cancelled_at" class="secondary" @click="newContract(row.shop_id,row.id,localTime(row.endsAt),row.snapshot.id)">续期</button>
      <button v-if="!row.cancelled_at&&row.placements.length" class="secondary" @click="schedule.contractId=row.id;go('schedule')">绑定排期</button>
      <button v-if="!row.cancelled_at" class="secondary" @click="begin(row.id,'cancel')">取消合同</button>
     </div>
     <form v-if="selected===row.id" class="stack" @submit.prevent="mutate('admin.cancel',{id:row.id,reason})"><label>取消原因<textarea v-model.trim="reason" required minlength="2" maxlength="500" rows="2"/></label><button class="primary" :disabled="busy">确认取消并释放库存</button></form>
    </article>
   </template>
   <template v-else-if="section==='reports'">
    <article v-for="row in rows as Report[]" :key="row.id" class="record stack">
     <div><h3>{{row.ad_id?'广告举报':'门店举报'}}</h3><p>{{row.reason}}</p><p class="subtle">{{dateLabel(row.created_at)}}</p></div>
     <p class="identifier">门店 ID <code>{{row.shop_id}}</code></p><p v-if="row.ad_id" class="identifier">素材 ID <code>{{row.ad_id}}</code></p>
     <p v-if="row.resolution">处理结果 · {{row.resolution}}</p>
     <button v-else class="secondary" @click="begin(row.id,'resolve')">填写处理结果</button>
     <form v-if="selected===row.id" class="stack" @submit.prevent="mutate('admin.report',{id:row.id,reason})"><label>处理结果<textarea v-model.trim="reason" required minlength="2" maxlength="500" rows="2"/></label><button class="primary" :disabled="busy">保存结果</button></form>
    </article>
   </template>
   <template v-else-if="section==='metrics'">
    <form class="inline" @submit.prevent="run(()=>list())"><label>门店 ID<input v-model.trim="statsShop" placeholder="全部门店"/></label><button class="secondary" :disabled="busy">查看</button></form>
    <Stats v-if="!error" :days="days"/>
   </template>
   <template v-else-if="section==='settings'">
    <form class="stack" @submit.prevent="mutate('admin.'+identity.kind,{id:identity.id,enabled:identity.enabled,reason:identity.reason})">
     <h2>账号授权</h2><label>邯院通账号标识<input v-model.trim="identity.id" required placeholder="输入账号 UUID"/></label>
     <label>权限<select v-model="identity.kind"><option value="student">已核验学生</option><option v-if="props.owner" value="role">商务管理员</option></select></label>
     <label class="check"><input v-model="identity.enabled" type="checkbox"/> 授予选中权限</label>
     <label>操作说明<input v-model.trim="identity.reason" required minlength="2" maxlength="500" placeholder="记录核验结论，避免填写学生证号码"/></label>
     <button class="primary" :disabled="busy">保存权限</button>
    </form>
    <template v-if="props.owner">
     <form class="stack" @submit.prevent="mutate('admin.settings',{adsEnabled:settings.ads_enabled,iosAdsEnabled:settings.ios_ads_enabled,reason:settingsReason})">
      <h2>广告总开关</h2><label class="check"><input v-model="settings.ads_enabled" type="checkbox"/> 开启广告展示</label>
      <label class="check"><input v-model="settings.ios_ads_enabled" type="checkbox"/> 同时在 iOS 展示</label>
      <label>操作说明<input v-model.trim="settingsReason" required minlength="2" maxlength="500"/></label><button class="primary" :disabled="busy">保存开关</button>
     </form>
     <h2>套餐定价与权益</h2><label>定价调整说明<input v-model.trim="plansReason" maxlength="500"/></label>
     <form v-for="plan in plans" :key="plan.id" class="fields record" @submit.prevent="savePlan(plan)">
      <label>套餐名<input v-model.trim="plan.name" required minlength="2" maxlength="24"/></label>
      <label>月费（分）<input v-model.number="plan.cents" required :disabled="plan.id==='basic'" type="number" min="0" max="10000000"/></label>
      <div v-if="plan.id!=='basic'" class="buttons wide"><label class="check"><input v-model="plan.category_slot" type="checkbox"/>分类推荐</label>
       <label class="check"><input v-model="plan.banner_slot" type="checkbox"/>周边 Banner</label>
       <label class="check"><input v-model="plan.home_slot" type="checkbox"/>首页广告</label>
       <label class="check"><input v-model="plan.reports" type="checkbox"/>推广报告</label></div>
      <button class="primary wide" :disabled="busy||plansReason.length<2">更新 {{plan.name}}</button>
     </form>
    </template>
   </template>
   <template v-else>
    <article v-for="row in rows as Audit[]" :key="row.id" class="record"><h3>{{row.action}}</h3><p class="subtle">{{dateLabel(row.created_at)}}</p><p v-if="row.subject" class="identifier"><code>{{row.subject}}</code></p></article>
   </template>
   <p v-if="!busy&&!error&&!rows.length&&section!=='metrics'&&section!=='settings'" class="empty">当前没有记录</p>
   <button v-if="next" class="secondary more" :disabled="busy" @click="run(()=>list(true))">加载更多</button>
  </div>
 </div>
</template>

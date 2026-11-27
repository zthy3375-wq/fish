<script setup lang="ts">
import {computed,onMounted,reactive,ref} from 'vue';
import {Bolt,ChartNoAxesColumn,Image,ScanLine,Store,Ticket,WalletCards} from 'lucide-vue-next';
import {request,upload,chinaTime,localTime} from './api';
import {commerceError,dateLabel,type Access,type Catalog,type Category,type CommercePage} from '../src/services/commerce';
import {amount,assetName,contractState,stateName,type AdRecord,type Contract,type Daily,type Draft,type OfferRecord,type Plan,type ShopReview} from './types';
import Scanner from './Scanner.vue';
import Stats from './Stats.vue';

defineProps<{access:Access}>();
const emit=defineEmits<{expired:[]}>();
const tabs=[{id:'shop',name:'门店资料',icon:Store},{id:'offers',name:'优惠活动',icon:Ticket},{id:'redeem',name:'核销台',icon:ScanLine},
 {id:'ads',name:'广告素材',icon:Image},{id:'stats',name:'推广报告',icon:ChartNoAxesColumn},{id:'contracts',name:'我的合作',icon:WalletCards}] as const;
type Tab=typeof tabs[number]['id'];
const tab=ref<Tab>('shop'),status=ref(''),error=ref(''),busy=ref(false);
const review=ref<ShopReview['shop']>(),plans=ref<Plan[]>([]),categories=ref<Category[]>([]);
const draft=reactive<Draft>({name:'',category:'',description:'',hours:'',phone:'',address:'',latitude:null,longitude:null,images:[],legalName:'',businessId:'',legalAddress:'',legalPhone:'',qualification:'',qualificationImage:''});
const media=ref<Record<string,string>>({}),shopFiles=ref<File[]>([]),qualificationFile=ref<File>();
const offers=ref<OfferRecord[]>([]),ads=ref<AdRecord[]>([]),contracts=ref<Contract[]>([]),days=ref<Daily[]>([]),next=ref<string|null>(null);
const active=ref(''),starts=localTime(new Date().toISOString());
const offer=reactive({id:crypto.randomUUID(),title:'',terms:'',quota:30,startsAt:starts,endsAt:''}),editingOffer=ref('');
const ad=reactive({id:crypto.randomUUID(),title:'',subtitle:''}),adImage=ref<File>();
const code=ref('');
const title=computed(()=>tabs.find(t=>t.id===tab.value)?.name||'');
function reportFailure(cause:unknown){
 if((cause as Error).message==='session_expired')emit('expired');
 else error.value=commerceError(cause);
}
async function run(operation:()=>Promise<void>){
 if(busy.value)return;busy.value=true;status.value='';error.value='';
 try{await operation();}catch(cause){reportFailure(cause);}
 finally{busy.value=false;}
}
async function readShop(){
 const r=await request<ShopReview>('merchant.read');
 review.value=r.shop;plans.value=r.plans;media.value=r.media||{};
 if(r.shop)Object.assign(draft,r.shop.draft);
}
async function load(append=false){
 if(tab.value==='shop'){await readShop();return;}
 if(tab.value==='stats'){days.value=(await request<{days:Daily[]}>('merchant.stats')).days;return;}
 if(tab.value==='redeem')return;
 const r=await request<CommercePage<OfferRecord|AdRecord|Contract>>('merchant.'+tab.value,{next:append?next.value:null});
 if(tab.value==='offers')offers.value=[...(append?offers.value:[]),...r.items as OfferRecord[]];
 if(tab.value==='ads')ads.value=[...(append?ads.value:[]),...r.items as AdRecord[]];
 if(tab.value==='contracts')contracts.value=[...(append?contracts.value:[]),...r.items as Contract[]];
 media.value={...(append?media.value:{}),...r.media};
 next.value=r.next;
}
function select(value:Tab){if(busy.value)return;tab.value=value;next.value=null;active.value='';void run(()=>load());}
onMounted(()=>void run(async()=>{
 await readShop();
 categories.value=(await request<Catalog>('catalog')).categories;
 if(!draft.category)draft.category=categories.value[0]?.id||'';
}));
function chooseFiles(event:Event){return Array.from((event.target as HTMLInputElement).files||[]);}
function submitShop(){
 void run(async()=>{
  if(shopFiles.value.length>4)throw Error('invalid_image');
  if(shopFiles.value.length){const photos:string[]=[];for(const file of shopFiles.value)photos.push(await upload(file,'shop'));draft.images=photos;shopFiles.value=[];}
  if(qualificationFile.value){draft.qualificationImage=await upload(qualificationFile.value,'qualification');qualificationFile.value=undefined;}
  await request('merchant.apply',{...draft});await readShop();status.value='已提交审核';
 });
}
function offerEdit(row:OfferRecord){
 editingOffer.value=row.id;Object.assign(offer,{title:row.title,terms:row.terms,quota:row.quota,startsAt:localTime(row.startsAt),endsAt:localTime(row.endsAt)});
}
function offerReset(){
 editingOffer.value='';Object.assign(offer,{id:crypto.randomUUID(),title:'',terms:'',quota:30,startsAt:starts,endsAt:''});
}
function submitOffer(){
 void run(async()=>{
  const result=await request<{id:string}>(editingOffer.value?'merchant.offer.edit':'merchant.offer',
   {...offer,id:editingOffer.value||offer.id,startsAt:chinaTime(offer.startsAt),endsAt:chinaTime(offer.endsAt)});
  offerReset();await load();active.value=result.id;status.value='优惠已保存';
 });
}
function submitAd(){
 void run(async()=>{
  if(!adImage.value)throw Error('invalid_image');
  const image=await upload(adImage.value,'ad');
  await request('merchant.ad',{...ad,image});
  Object.assign(ad,{id:crypto.randomUUID(),title:'',subtitle:''});adImage.value=undefined;await load();status.value='素材已提交审核';
 });
}
function redeem(){
 void run(async()=>{
  const result=await request<{title:string;usedAt:string}>('merchant.redeem',{code:code.value.trim()});
  code.value='';status.value='已核销「'+result.title+'」 · '+dateLabel(result.usedAt);
 });
}
</script>
<template>
 <div class="workspace">
  <aside><p class="side-title">{{review?.draft.name||'商家工作台'}}</p><nav aria-label="商家菜单">
   <button v-for="item in tabs" :key="item.id" :aria-current="tab===item.id?'page':undefined" :disabled="busy||(!review&&item.id!=='shop')" @click="select(item.id)">
    <component :is="item.icon" :size="18"/>{{item.name}}
   </button></nav>
  </aside>
  <div class="workspace-main surface" :aria-busy="busy">
   <h1>{{title}}</h1>
   <p v-if="status" class="status" role="status">{{status}}</p><p v-if="error" class="status error" role="alert">{{error}}</p>
   <p v-if="busy" class="subtle" role="status">正在处理…</p>
   <template v-if="tab==='shop'">
    <p class="subtle">{{review?stateName[review.state]:'提交资质后，审核通过即可展示门店。'}} <span v-if="review?.decision">{{review.decision}}</span></p>
    <form class="stack" @submit.prevent="submitShop">
     <fieldset class="fields"><legend>门店公开资料</legend>
      <label>门店名称<input v-model.trim="draft.name" required minlength="2" maxlength="50"/></label>
      <label>分类<select v-model="draft.category" required><option v-for="item in categories" :key="item.id" :value="item.id">{{item.name}}</option></select></label>
      <label class="wide">介绍<textarea v-model.trim="draft.description" required minlength="2" maxlength="500" rows="3"/></label>
      <label>营业时间<input v-model.trim="draft.hours" required maxlength="120" placeholder="周一至周日 10:00–21:00"/></label>
      <label>门店电话<input v-model.trim="draft.phone" type="tel" required maxlength="32"/></label>
      <label class="wide">导航地址<input v-model.trim="draft.address" required maxlength="200"/></label>
      <label>高德纬度（选填）<input v-model.number="draft.latitude" type="number" min="-90" max="90" step="any"/></label>
      <label>高德经度（选填）<input v-model.number="draft.longitude" type="number" min="-180" max="180" step="any"/></label>
      <label class="wide">门店照片 · 最多 4 张<input type="file" multiple accept="image/jpeg,image/png,image/webp" :required="!draft.images.length" @change="shopFiles=chooseFiles($event)"/></label>
      <div class="wide photos"><img v-for="key in draft.images.filter(id=>media[id])" :key="key" :src="media[key]" alt="已上传的门店照片"/></div>
     </fieldset>
     <fieldset class="fields"><legend>主体资质 · 供运营审核</legend>
      <label>登记名称<input v-model.trim="draft.legalName" required maxlength="120"/></label>
      <label>统一社会信用代码或资质编号<input v-model.trim="draft.businessId" required maxlength="32"/></label>
      <label>登记地址<input v-model.trim="draft.legalAddress" required maxlength="200"/></label>
      <label>审核联系号码<input v-model.trim="draft.legalPhone" type="tel" required maxlength="32"/></label>
      <label class="wide">资质说明<textarea v-model.trim="draft.qualification" required maxlength="500" rows="2"/></label>
      <label class="wide">营业执照或资质照片<input type="file" accept="image/jpeg,image/png,image/webp" :required="!draft.qualificationImage" @change="qualificationFile=chooseFiles($event)[0]"/></label>
      <div v-if="media[draft.qualificationImage]" class="wide"><a :href="media[draft.qualificationImage]" target="_blank" rel="noopener noreferrer">查看当前资质材料</a></div>
     </fieldset>
     <button class="primary" :disabled="busy||review?.state==='suspended'">提交资质审核</button>
    </form>
   </template>
   <template v-else-if="tab==='offers'">
    <form class="fields" @submit.prevent="submitOffer">
     <h2 class="wide">{{editingOffer?'编辑优惠':'创建优惠'}}</h2>
     <label>标题<input v-model.trim="offer.title" required minlength="2" maxlength="64"/></label>
     <label>发放张数<input v-model.number="offer.quota" type="number" required min="1" max="10000"/></label>
     <label class="wide">使用条件<textarea v-model.trim="offer.terms" required maxlength="500" rows="2"/></label>
     <label>开始（北京时间）<input v-model="offer.startsAt" type="datetime-local" required/></label>
     <label>结束（北京时间）<input v-model="offer.endsAt" type="datetime-local" required/></label>
     <div class="wide buttons"><button class="primary" :disabled="busy">{{editingOffer?'保存修改':'创建优惠'}}</button><button v-if="editingOffer" type="button" class="secondary" @click="offerReset">取消编辑</button></div>
    </form>
    <h2>已创建优惠</h2><p v-if="!offers.length&&!busy" class="empty">暂无优惠活动</p>
    <article v-for="row in offers" :key="row.id" class="record" :class="{highlight:row.id===active}">
     <h3>{{row.title}}</h3><p>{{row.terms}}</p><p class="subtle">{{dateLabel(row.startsAt)}} 至 {{dateLabel(row.endsAt)}} · 已领取 {{row.claimed}} / {{row.quota}}</p>
     <div class="buttons"><button v-if="!row.claimed" class="secondary" @click="offerEdit(row)">编辑</button><button class="secondary" :disabled="busy" @click="run(async()=>{await request('merchant.offerstate',{id:row.id,enabled:!row.active});await load();status=row.active?'已暂停领取':'已恢复领取';})">{{row.active?'暂停领取':'恢复领取'}}</button></div>
    </article>
   </template>
   <template v-else-if="tab==='redeem'">
    <p class="subtle">扫描学生出示的二维码，或输入数字码。核对后确认核销。</p>
    <form class="stack compact-form" @submit.prevent="redeem">
     <label>12 位核销码<input v-model="code" type="text" maxlength="19" inputmode="numeric" autocomplete="off" placeholder="0000 0000 0000" required/></label>
     <Scanner @scan="code=$event"/>
     <button class="primary" :disabled="busy||code.replace(/[ -]/g,'').length!==12"><Bolt :size="17"/>确认核销</button>
    </form>
   </template>
   <template v-else-if="tab==='ads'">
    <form class="stack" @submit.prevent="submitAd">
     <label>素材标题<input v-model.trim="ad.title" required minlength="2" maxlength="36"/></label>
     <label>补充说明<input v-model.trim="ad.subtitle" maxlength="80"/></label>
     <label>广告图片<input type="file" accept="image/jpeg,image/png,image/webp" :required="!adImage" @change="adImage=chooseFiles($event)[0]"/></label>
     <button class="primary" :disabled="busy">提交素材审核</button>
    </form>
    <h2>已提交素材</h2><p v-if="!ads.length&&!busy" class="empty">暂无广告素材</p>
    <article v-for="row in ads" :key="row.id" class="record"><img v-if="media[row.image]" class="record-image" :src="media[row.image]" alt="广告素材"/><div><h3>{{row.title}}</h3><p>{{row.subtitle}}</p><p class="subtle">{{stateName[row.state]}} {{row.decision}}</p></div></article>
   </template>
   <Stats v-else-if="tab==='stats'&&!error" :days="days"/>
   <template v-else-if="tab==='contracts'">
    <h2>合作有效期</h2><p v-if="!contracts.length&&!busy" class="empty">暂无推广合同。已审核门店可使用基础版。</p>
    <article v-for="row in contracts" :key="row.id" class="record"><h3>{{row.snapshot.name}} · {{stateName[row.kind]}} · {{contractState(row)}}</h3>
     <p>{{dateLabel(row.startsAt)}} 至 {{dateLabel(row.endsAt)}}</p><p class="subtle">{{row.placements.map(assetName).join('、')||'基础权益'}} · 已登记 {{amount(row.paid)}} / {{amount(row.cents)}}</p>
    </article>
    <h2>合作套餐</h2><p class="subtle">推广需线下签约。具体档期以确认后的合同为准。</p>
    <div class="plan-grid"><article v-for="plan in plans" :key="plan.id"><h3>{{plan.name}}</h3><p>{{plan.cents?amount(plan.cents)+' / 月':'免费'}}</p><p class="subtle">{{[plan.category_slot?'分类推荐':'',plan.banner_slot?'周边 Banner':'',plan.home_slot?'首页广告':'',plan.reports?'推广报告':''].filter(Boolean).join('、')||'门店与优惠券核销'}}</p></article></div>
   </template>
   <button v-if="next&&['offers','ads','contracts'].includes(tab)" class="secondary more" :disabled="busy" @click="run(()=>load(true))">加载更多</button>
  </div>
 </div>
</template>

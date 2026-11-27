<script setup lang="ts">
import {nextTick,onBeforeUnmount,onMounted,ref} from 'vue';
import {ArrowLeft,ChevronRight,Heart,MapPin,Phone,Search,Ticket,Flag} from 'lucide-vue-next';
import CommerceAds from './CommerceAds.vue';
import {commerceError,commerceRequest,dateLabel,mapURL,trackCommerce,type Access,type Ad,type Catalog,type Category,type CommercePage,type Coupon,type Media,type Offer,type Shop} from '../../services/commerce';

const props=defineProps<{initialShop?:string;initialReport?:Ad}>();
const emit=defineEmits<{account:[]}>();
type Screen='catalog'|'detail'|'favorites'|'wallet'|'coupon'|'report';
const stack:Screen[]=[];
const screen=ref<Screen>('catalog'),header=ref<HTMLElement>();
const shops=ref<Shop[]>([]),categories=ref<Category[]>([]),ads=ref<Ad[]>([]);
const category=ref(''),search=ref(''),query=ref(''),cursor=ref<string|null>(),catalogMedia=ref<Record<string,string>>({});
const favoriteShops=ref<Shop[]>([]),favoriteMedia=ref<Record<string,string>>({}),favoriteCursor=ref<string|null>();
const detail=ref<Shop>(),detailMedia=ref<Media['media']>(),offers=ref<Offer[]>([]),favorites=ref(false),favoriteKnown=ref(false);
const coupons=ref<Coupon[]>([]),couponCursor=ref<string|null>(),coupon=ref<Coupon>(),qr=ref(''),recentlyClaimed=ref('');
const access=ref<Access>(),report=ref<{shopId:string;id?:string}>(),reason=ref('');
const busy=ref(false),error=ref(''),errorCode=ref(''),notice=ref(''),loadedCatalog=ref(false);
let generation=0;
function focusTitle(){void nextTick(()=>header.value?.focus());}
function enter(next:Screen){generation++;stack.push(screen.value);screen.value=next;error.value='';notice.value='';busy.value=false;focusTitle();}
function requestBack(){
 const prior=stack.pop();
 if(!prior)return false;
 generation++;screen.value=prior;error.value='';errorCode.value='';notice.value='';busy.value=false;
 if(prior==='catalog'&&!loadedCatalog.value)void loadCatalog();
 if(prior==='wallet')void loadWallet();
 focusTitle();return true;
}
defineExpose({requestBack});
onBeforeUnmount(()=>{generation++;});
async function run(operation:(valid:()=>boolean)=>Promise<void>){
 if(busy.value)return;
 const current=++generation,valid=()=>generation===current;
 busy.value=true;error.value='';errorCode.value='';
 try{await operation(valid);}
 catch(cause){if(valid()){error.value=commerceError(cause);const value=cause as {code?:string;message?:string};errorCode.value=value.code||value.message||'';}}
 finally{if(valid())busy.value=false;}
}
async function loadCatalog(append=false){
 await run(async valid=>{
  const r=await commerceRequest<Catalog>('catalog',{category:category.value,query:query.value,next:append?cursor.value:null});
  if(!valid())return;
  shops.value=append?[...shops.value,...r.items]:r.items;
  catalogMedia.value=append?{...catalogMedia.value,...r.media}:r.media||{};
  categories.value=r.categories;cursor.value=r.next;if(!append)ads.value=r.ads;loadedCatalog.value=true;
 });
}
function updateCatalog(nextCategory:string){
 category.value=nextCategory;query.value=search.value.trim();ads.value=[];shops.value=[];cursor.value=null;
 void loadCatalog();
}
async function showShop(shopId:string){
 enter('detail');detail.value=undefined;offers.value=[];favoriteKnown.value=false;recentlyClaimed.value='';
 await run(async valid=>{
  const r=await commerceRequest<Media&{shop:Shop;offers:Offer[]}>('shop',{shopId});
  if(!valid())return;
  detail.value=r.shop;detailMedia.value=r.media;offers.value=r.offers;
  trackCommerce('visit',shopId);
  void commerceRequest<{favorited:boolean}>('shop.status',{shopId}).then(s=>{
   if(screen.value==='detail'&&detail.value?.id===shopId){favorites.value=s.favorited;favoriteKnown.value=true;}
  }).catch(()=>{});
 });
}
async function toggleFavorite(){
 if(!detail.value)return;
 const shopId=detail.value.id,enabled=!favoriteKnown.value||!favorites.value;
 await run(async valid=>{
  await commerceRequest('favorite',{shopId,enabled});
  if(valid()){favoriteKnown.value=true;favorites.value=enabled;notice.value=enabled?'已收藏':'已取消收藏';}
 });
}
async function loadFavorites(append=false){
 await run(async valid=>{
  const r=await commerceRequest<CommercePage<Shop>>('favorites',{next:append?favoriteCursor.value:null});
  if(!valid())return;
  favoriteShops.value=append?[...favoriteShops.value,...r.items]:r.items;
  favoriteMedia.value=append?{...favoriteMedia.value,...r.media}:r.media||{};favoriteCursor.value=r.next;
 });
}
async function loadWallet(append=false){
 await run(async valid=>{
  const r=await commerceRequest<CommercePage<Coupon>>('wallet',{next:append?couponCursor.value:null});
  if(valid()){coupons.value=append?[...coupons.value,...r.items]:r.items;couponCursor.value=r.next;}
 });
}
async function claim(offer:Offer){
 await run(async valid=>{
  try{
   const r=await commerceRequest<{id:string}>('claim',{id:offer.id});
   if(valid()){recentlyClaimed.value=r.id;notice.value='优惠券已放入「我的优惠券」';}
  }catch(cause){
   const value=cause as {code?:string;message?:string};
   if((value.code||value.message)==='student_verification_required'){
    const profile=await commerceRequest<Access>('access');if(valid())access.value=profile;
   }
   throw cause;
  }
 });
}
async function showCoupon(id:string){
 enter('coupon');coupon.value=undefined;qr.value='';
 await run(async valid=>{
  const r=await commerceRequest<{coupon:Coupon}>('coupon',{id});
  if(!valid())return;
  coupon.value=r.coupon;
  if(r.coupon.code){
   const {toDataURL}=await import('qrcode');
   const image=await toDataURL('HYT1:'+r.coupon.code,{margin:3,width:240,errorCorrectionLevel:'M'});
   if(valid())qr.value=image;
  }
 });
}
function beginReport(shopId:string,id?:string){enter('report');reason.value='';report.value={shopId,id};}
async function sendReport(){
 await run(async valid=>{
  await commerceRequest('report',{...report.value,reason:reason.value.trim()});
  if(valid()){requestBack();notice.value='举报已提交';}
 });
}
function retry(){
 if(screen.value==='favorites')void loadFavorites();
 else if(screen.value==='wallet')void loadWallet();
 else if(screen.value==='catalog')void loadCatalog();
}
onMounted(()=>{
 if(props.initialReport)beginReport(props.initialReport.shopId,props.initialReport.id);
 else if(props.initialShop)void showShop(props.initialShop);
 else void loadCatalog();
});
</script>
<template>
 <section class="commerce-student" :aria-busy="busy">
  <header class="commerce-heading">
   <button v-if="screen!=='catalog'" aria-label="返回上一级" @click="requestBack"><ArrowLeft :size="21"/></button>
   <h2 ref="header" tabindex="-1">{{screen==='detail'?(detail?.name||'门店详情'):screen==='favorites'?'收藏的门店':screen==='wallet'?'我的优惠券':screen==='coupon'?'优惠券详情':screen==='report'?(report?.id?'举报广告':'举报门店'):'校园周边'}}</h2>
  </header>
  <p v-if="notice" class="commerce-feedback" role="status">{{notice}}</p>
  <div v-if="error" class="commerce-feedback error" role="alert">
   <p>{{error}}</p>
   <button v-if="errorCode==='session_expired'" type="button" @click="emit('account')">登录邯院通</button>
   <p v-else-if="errorCode==='student_verification_required'&&access">请向邯院通运营管理员出示学生证和此账号标识，核验后可领券。<br/><code>{{access.memberId}}</code></p>
   <button v-else-if="['catalog','wallet','favorites'].includes(screen)" type="button" @click="retry">重新加载</button>
  </div>
  <template v-if="screen==='catalog'">
   <form class="commerce-search" @submit.prevent="updateCatalog(category)">
    <Search :size="18"/><input v-model="search" aria-label="搜索门店" maxlength="64" placeholder="搜索门店或地址"/><button :disabled="busy">搜索</button>
   </form>
   <div class="commerce-actions">
    <button @click="enter('favorites');loadFavorites()"><Heart :size="17"/> 收藏</button>
    <button @click="enter('wallet');loadWallet()"><Ticket :size="17"/> 我的优惠券</button>
   </div>
   <div v-if="categories.length" class="commerce-categories" aria-label="门店分类">
    <button v-for="item in [{id:'',name:'全部'},...categories]" :key="item.id" :aria-pressed="category===item.id" :disabled="busy" @click="updateCatalog(item.id)">{{item.name}}</button>
   </div>
   <CommerceAds :ads="ads" :media="catalogMedia" :rotate="!category" :label="category?'分类广告':'校园周边广告'" @select="showShop($event.shopId)" @report="beginReport($event.shopId,$event.id)"/>
  </template>
  <template v-if="screen==='catalog'||screen==='favorites'">
   <p v-if="!busy&&!error&&!(screen==='catalog'?shops:favoriteShops).length" class="commerce-empty">{{screen==='favorites'?'还没有收藏门店':query?'没有找到相关门店':'这个分类暂时没有门店'}}</p>
   <button v-for="s in (screen==='catalog'?shops:favoriteShops)" :key="s.id" class="commerce-row" @click="showShop(s.id)">
    <img v-if="(screen==='catalog'?catalogMedia:favoriteMedia)[s.images[0]]" :src="(screen==='catalog'?catalogMedia:favoriteMedia)[s.images[0]]" alt="" loading="lazy" referrerpolicy="no-referrer"/>
    <span><strong>{{s.name}}</strong><small>{{s.address}}</small></span><ChevronRight :size="17"/>
   </button>
   <button v-if="screen==='catalog'?cursor:favoriteCursor" class="commerce-more" :disabled="busy" @click="screen==='catalog'?loadCatalog(true):loadFavorites(true)">加载更多</button>
  </template>
  <template v-if="screen==='detail'&&detail">
   <div class="commerce-photos">
    <img v-for="image in detail.images.filter(id=>detailMedia?.[id])" :key="image" :src="detailMedia?.[image]" alt="门店照片" loading="lazy" referrerpolicy="no-referrer"/>
   </div>
   <div class="commerce-actions">
    <button :disabled="busy" :aria-pressed="favoriteKnown&&favorites" @click="toggleFavorite"><Heart :size="17"/> {{favoriteKnown&&favorites?'已收藏':'收藏门店'}}</button>
    <button @click="beginReport(detail.id)"><Flag :size="17"/> 举报</button>
   </div>
   <p class="commerce-body">{{detail.description}}</p>
   <dl class="commerce-info">
    <dt>营业时间</dt><dd>{{detail.hours}}</dd>
    <dt>联系电话</dt><dd><a :href="'tel:'+detail.phone.replace(/[^+0-9]/g,'')"><Phone :size="15"/>{{detail.phone}}</a></dd>
    <dt>门店地址</dt><dd><a :href="mapURL(detail)" target="_blank" rel="noopener noreferrer"><MapPin :size="16"/>{{detail.address}} · 导航</a></dd>
   </dl>
   <h3>学生专属优惠</h3>
   <p v-if="!offers.length" class="commerce-empty">这家门店暂时没有优惠。</p>
   <article v-for="o in offers" :key="o.id" class="commerce-offer">
    <div><strong>{{o.title}}</strong><p>{{o.terms}}</p><small>{{dateLabel(o.endsAt)}} 截止</small></div>
    <button :disabled="busy||o.soldOut" @click="claim(o)">{{o.soldOut?'已领完':'领取'}}</button>
   </article>
   <button v-if="recentlyClaimed" class="commerce-more" @click="showCoupon(recentlyClaimed)">查看刚领取的优惠券</button>
  </template>
  <template v-if="screen==='wallet'">
   <p v-if="!busy&&!error&&!coupons.length" class="commerce-empty">还没有领取优惠券</p>
   <button v-for="c in coupons" :key="c.id" class="commerce-row" @click="showCoupon(c.id)"><span><strong>{{c.title}}</strong><small>{{c.shopName}}</small></span><small>{{c.state==='used'?'已核销':c.state==='expired'?'已失效':'待使用'}}</small><ChevronRight :size="16"/></button>
   <button v-if="couponCursor" class="commerce-more" :disabled="busy" @click="loadWallet(true)">加载更多</button>
  </template>
  <article v-if="screen==='coupon'&&coupon" class="commerce-coupon">
   <h3>{{coupon.title}}</h3><p>{{coupon.shopName}}</p><p>{{coupon.terms}}</p><p>领取于 {{dateLabel(coupon.claimedAt)}} · {{dateLabel(coupon.endsAt)}} 截止</p>
   <template v-if="coupon.code"><img v-if="qr" :src="qr" width="200" height="200" alt="到店核销二维码"/><strong class="commerce-code">{{coupon.code.match(/.{1,4}/g)?.join(' ')}}</strong><small>到店出示给店员，优惠券仅可使用一次</small></template>
   <strong v-else>{{coupon.usedAt?'已核销 · '+dateLabel(coupon.usedAt):'已失效'}}</strong>
  </article>
  <form v-if="screen==='report'" class="commerce-report" @submit.prevent="sendReport">
   <p v-if="report?.id" class="commerce-body">这张广告按所在页面和门店分类投放。</p>
   <label>举报原因<textarea v-model="reason" required minlength="2" maxlength="500" rows="4" placeholder="请说明遇到的问题，避免填写个人信息"/></label>
   <button :disabled="busy||reason.trim().length<2">提交举报</button>
  </form>
  <p v-if="busy" class="commerce-loading" role="status">正在加载…</p>
 </section>
</template>
<style scoped>
.commerce-student{display:grid;gap:12px;padding-block:8px 24px;color:var(--color-text);overflow-wrap:anywhere}.commerce-heading{display:flex;align-items:center;gap:8px;padding-right:40px;min-height:44px}.commerce-heading h2{margin:0;font-size:22px}.commerce-heading button{min-width:44px;color:var(--color-primary)}.commerce-student button{min-height:44px}.commerce-actions,.commerce-categories{display:flex;gap:8px;flex-wrap:wrap}.commerce-actions button,.commerce-categories button,.commerce-offer button,.commerce-more,.commerce-report button{display:inline-flex;align-items:center;justify-content:center;gap:6px;border-radius:10px;background:var(--color-tint);color:var(--color-primary-strong);padding:8px 12px}.commerce-categories button[aria-pressed=true],.commerce-report button{color:var(--color-raised,#fff);background:var(--color-primary)}
.commerce-search{display:flex;align-items:center;gap:8px;background:var(--color-bg);border:1px solid var(--color-border);border-radius:10px;padding-inline:10px}.commerce-search input{min-height:44px;min-width:0;flex:1;border:0;background:none;color:inherit}.commerce-search button{color:var(--color-primary)}.commerce-row{display:flex;align-items:center;gap:10px;text-align:left;padding:10px 0;border-bottom:1px solid var(--color-divider);color:inherit;min-width:0}.commerce-row img{width:54px;height:46px;border-radius:8px;object-fit:cover}.commerce-row span{flex:1}.commerce-row small,.commerce-row strong{display:block}.commerce-row small,.commerce-offer small,.commerce-coupon small{color:var(--color-muted)}.commerce-empty,.commerce-loading{text-align:center;margin-block:18px;color:var(--color-muted)}.commerce-feedback{padding:10px;border-radius:10px;background:var(--color-tint)}.commerce-feedback button,.commerce-info a{color:var(--color-primary);font-weight:600}.commerce-feedback.error{color:var(--color-danger)}.commerce-info{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:10px 12px;margin:0}.commerce-info dt{color:var(--color-muted)}.commerce-info dd{margin:0}.commerce-info a{display:inline-flex;align-items:center;gap:5px}.commerce-photos{display:flex;gap:8px;overflow:auto;scroll-snap-type:x mandatory}.commerce-photos:empty{display:none}.commerce-photos img{width:min(88%,320px);height:150px;object-fit:cover;border-radius:12px;scroll-snap-align:start;flex:none}.commerce-body,.commerce-offer p,.commerce-coupon p{white-space:pre-wrap}.commerce-offer{display:flex;gap:10px;align-items:center;justify-content:space-between;border:1px solid var(--color-border);padding:12px;border-radius:12px}.commerce-offer button{flex:none}.commerce-coupon{text-align:center;display:grid;gap:8px;justify-items:center}.commerce-code{font-size:21px;font-variant-numeric:tabular-nums;letter-spacing:2px}.commerce-report label{display:grid;gap:8px}.commerce-report textarea{padding:10px;color:inherit;background:var(--color-bg);border:1px solid var(--color-border);border-radius:10px;resize:vertical}.commerce-report button{margin-top:10px}
</style>

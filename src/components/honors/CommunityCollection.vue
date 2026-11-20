<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { Award, ChevronRight, LockKeyhole } from "lucide-vue-next";
import CollectionBadge from "./CollectionBadge.vue";
import { archiveSections, collectionKind, definitionCode, displayCollectionName, honorName, honorRarities, type CollectionItem, type CollectionProfile, type HonorArchiveItem } from "../../domain/honorCollection";
import { catalog } from "../../domain/globalAchievements";
import { clearHonorCollectionCache, getHonorCollection } from "../../services/honorCollectionCache";
import { treeholeError, type TreeholeResult } from "../../services/treehole";
import { badges, honorDate, type BadgeCode } from "../../domain/communityHonors";

type Card = CollectionItem & { legacy?: BadgeCode; base?: boolean; unreleased?: boolean };
const props = defineProps<{
  viewer: string; member: string; archive?: boolean; reducedMotion?: boolean; initialCode?: string;
  request: (action: string, body?: Record<string, unknown>) => Promise<TreeholeResult>;
}>();
const emit = defineEmits<{ updated: [TreeholeResult]; person: [string] }>();
const self = computed(() => props.viewer === props.member);
const profile = ref<CollectionProfile>();
const items = ref<CollectionItem[]>([]);
const archivists = ref<HonorArchiveItem[]>([]);
const section = ref<keyof typeof archiveSections>("legend");
const year = ref<number | null>(null);
const years = ref<number[]>([]);
const panel = ref<"honor" | "achievement">("honor");
const filter = ref("all");
const filters = { all:"全部", daily:"日常", milestone:"里程碑", season:"季节纪念", hidden:"隐藏" };
const loading = ref(false);
const changing = ref(false);
const more = ref(false);
const error = ref("");
const dialog = ref<HTMLDialogElement>();
const selected = ref<Card | HonorArchiveItem>();
const unlocked = ref(false);
const useTitle = ref(false);
const received = new Set<string>();
const identityCodes = ["developer", "moderator"] as const;
const wearableLegacy = ["seed", "creator", "contributor"] as const;
const original = catalog.filter(a => a.source === "community");
let alive = true, revision = 0;
onBeforeUnmount(() => { alive = false; revision++; });

const organized = computed(() => (profile.value?.layoutVersion ?? 0) >= 2);
const slots = computed(() => profile.value?.showcase ?? []);
const oldCards = computed<Card[]>(() => {
  if (!profile.value) return [];
  return wearableLegacy.flatMap(code => {
    const grant = profile.value?.legacyHonors?.find(b => b.code === code);
    const earned = !!grant || profile.value?.identities.includes(code) === true;
    if (!earned && !self.value) return [];
    const { name, method, description } = badges[code];
    return [{ id:code, code, name, category:"identity", rarity:"rare", legacy:code,
      awardId:earned ? code : null, at:grant?.at, criteria:method,
      story:earned ? (code === "seed" ? "最初的相遇 · " : "") + description : null,
      archived:false, publicHidden:false }];
  });
});
const baseCards = computed<Card[]>(() => {
  if (!profile.value) return [];
  return original.flatMap(a => {
    const at = profile.value?.baseAwards?.[a.code];
    if (!at && !self.value) return [];
    return [{ id:a.code, code:a.code, name:a.name, category:"contribution", displayKind:"achievement", base:true,
      rarity:a.tier==="稀有" ? "rare" : a.tier==="史诗" ? "epic" : "common", awardId:at ? a.code : null,
      at, criteria:a.condition, story:at ? a.description : null, archived:false, publicHidden:false }];
  });
});
const pending: Array<Pick<Card, "code" | "name" | "category" | "rarity" | "criteria">> = [
  {code:"person-of-year",name:"年度人物",category:"limited",rarity:"legendary",criteria:"按年份评选年度社区人物。"},
  {code:"creator-of-year",name:"年度最佳创作者",category:"limited",rarity:"epic",criteria:"按年份评选年度最佳创作者。"},
  {code:"photo-of-year",name:"年度摄影师",category:"limited",rarity:"epic",criteria:"按年份评选年度摄影作品。"},
  {code:"warmth-of-year",name:"年度最温暖的人",category:"limited",rarity:"epic",criteria:"按年份选出值得纪念的互助事迹。"},
  {code:"graduation-keepsake",name:"毕业季青春纪念章",category:"limited",rarity:"rare",criteria:"按年份核实毕业季参与记录。"},
  {code:"welcome-guide",name:"带新同学认路",category:"limited",rarity:"rare",criteria:"按年份核实参与迎新和互助的记录。"},
  {code:"first-feature",name:"第一次上墙",category:"contribution",rarity:"rare",criteria:"第一篇原创作品入选官方精选。"},
  {code:"hundred-likes",name:"一百个赞",category:"contribution",rarity:"legendary",criteria:"同一篇公开帖子收到 100 位不同同学的有效赞。"},
  {code:"full-page",name:"写满这一页",category:"contribution",rarity:"epic",criteria:"累计解锁 15 项不同的常规社区成就。"},
];
const catalogCards = computed<Card[]>(() => {
  const definitions = items.value.map(item => ({ ...item, name:displayCollectionName(item) }));
  if (!self.value || !profile.value) return definitions;
  const known = new Set(definitions.map(item => definitionCode(item.code)));
  const templates = pending.filter(item => !known.has(item.code) && (item.category === "limited" || !organized.value));
  return [...definitions, ...templates.map(item => ({...item,id:item.code,awardId:null,archived:false,publicHidden:false,unreleased:true}))];
});
const honors = computed(() => [...oldCards.value, ...catalogCards.value.filter(i => collectionKind(i) === "honor")]);
const achievements = computed(() => [...baseCards.value, ...catalogCards.value.filter(i => collectionKind(i) === "achievement")]);
function group(item: Card) {
  if (item.base) return "daily";
  if (item.category === "limited") return "season";
  if (item.category === "hidden") return "hidden";
  return "milestone";
}
const visible = computed(() => panel.value === "honor" ? honors.value : achievements.value.filter(item => filter.value === "all" || filter.value === group(item)));
const mystery = computed(() => self.value && !!profile.value && panel.value === "achievement" && ["all","hidden"].includes(filter.value)
  ? Math.max(0, 6 - achievements.value.filter(item => item.category === "hidden" && item.awardId).length) : 0);
const total = computed(() => (panel.value==="honor" ? honors.value : achievements.value).filter(i=>i.awardId).length);
const equipped = computed(() => {
  const own = profile.value?.badges;
  if (own?.collection && collectionKind({...own.collection,category:"contribution"})==="honor") return honorName({...own.collection,name:own.collection.title || own.collection.name});
  return own?.worn && wearableLegacy.some(code=>code===own.worn?.code) ? badges[own.worn.code].name : "";
});

async function openInitial() {
  if (!props.initialCode) return;
  const item = [...honors.value,...achievements.value].find(i=>i.code===props.initialCode || i.awardId===props.initialCode);
  if (!item) return;
  panel.value = collectionKind(item)==="achievement" ? "achievement" : "honor";
  filter.value = "all";
  await show(item);
}
watch(()=>props.initialCode, (next, old)=>{ if (next && next!==old && profile.value) void openInitial(); });

async function load(append = false, fresh = false, announce = true) {
  const request = ++revision;
  loading.value = true;
  error.value = "";
  try {
    if (props.archive) {
      const result = await props.request("collection.archive", { section: section.value, year: year.value, offset: append ? archivists.value.length : 0 });
      if (!alive || request !== revision) return;
      const rows = result.honorArchive ?? [];
      years.value = result.honorYears ?? [];
      archivists.value = [...(append ? archivists.value : []), ...rows.slice(0, 20)];
      more.value = rows.length > 20;
    } else {
      let data = append ? (await props.request("collection.profile", { memberId: props.member, offset: items.value.length })).collection :
        await getHonorCollection(props.viewer, props.member, props.request, fresh);
      if (!alive || request !== revision) return;
      if (!data || data.id !== props.member) throw Error("invalid_response");
      if (!append && !data.baseAwards) {
        const legacy = (await props.request("honors.hall", {memberId:props.member})).hall;
        if (!alive || request !== revision) return;
        if (!legacy || legacy.id !== props.member) throw Error("invalid_response");
        data = { ...data, baseAwards:legacy.awards, legacyHonors:legacy.honors, showcase:legacy.showcase };
      }
      profile.value = append && profile.value ? { ...profile.value,...data } : data;
      items.value = [...(append ? items.value : []), ...data.items.slice(0, 40)];
      more.value = data.items.length > 40;
      if (self.value && !append && announce && !dialog.value?.open && !props.initialCode) {
        const reward = catalogCards.value.find(i => collectionKind(i)!=='history' && i.awardId && data.unseen.includes(i.awardId) && !received.has(i.awardId));
        if (reward) void show(reward, true);
      }
    }
  } catch (e) {
    if (alive && request === revision) error.value = treeholeError(e);
  } finally {
    if (alive && request === revision) loading.value = false;
  }
}

async function show(item: Card | HonorArchiveItem, newAward = false) {
  selected.value = item;
  unlocked.value = newAward;
  useTitle.value = profile.value?.badges.collection?.id === item.awardId && profile.value?.useTitle === true;
  await nextTick();
  if (alive && dialog.value && !dialog.value.open) dialog.value.showModal();
}

async function closeDetail() {
  const award = selected.value?.awardId;
  const announced = unlocked.value;
  dialog.value?.close();
  selected.value = undefined;
  unlocked.value = false;
  if (announced && award && self.value) {
    received.add(award);
    try {
      await props.request("collection.ack", { awardIds: [award] });
      clearHonorCollectionCache();
    } catch (e) { if (alive) error.value = treeholeError(e); }
  }
}

async function update(action: string, body: Record<string, unknown>) {
  if (changing.value || !selected.value?.awardId) return;
  const index = selected.value.id;
  changing.value = true;
  error.value = "";
  try {
    const update = await props.request(action, body);
    if (!alive || (!update.updatedIdentity && !update.user)) throw Error("invalid_response");
    emit("updated", update);
    clearHonorCollectionCache();
    await load(false, true, false);
    if (alive && selected.value) selected.value = [...honors.value,...achievements.value].find(item => item.id === index);
  } catch (e) {
    if (alive) error.value = treeholeError(e);
  } finally { if (alive) changing.value = false; }
}
function currentWear(item: Card) {
  return item.legacy ? item.legacy===profile.value?.badges.worn?.code : item.awardId===profile.value?.badges.collection?.id;
}
function wear(item: Card, remove = false) {
  if (!organized.value && item.legacy) {
    void update("honors.wear",{honor:remove ? null : item.legacy,showcase:slots.value});
    return;
  }
  void update("collection.wear",{awardId:item.legacy || remove ? null : item.awardId,
    legacyCode:item.legacy && !remove ? item.legacy : null,useTitle:useTitle.value,organized:true});
}
function pin(item: Card) {
  if (!item.awardId) return;
  const key = item.awardId;
  const next = slots.value.includes(key) ? slots.value.filter(value=>value!==key) : [...slots.value,key];
  if (next.length>3) { error.value=treeholeError(Error("showcase_limit")); return; }
  if (organized.value) void update("collection.showcase",{items:next});
  else if (item.base) void update("honors.wear",{honor:profile.value?.badges.worn?.code ?? null,showcase:next});
}
onMounted(async () => { await load(); if (alive) await openInitial(); });
</script>

<template>
  <section class="hc" :class="{ 'hc-archive-page': archive, 'hc-reduced': reducedMotion }">
    <header class="hc-heading">
      <div><h2>{{ archive ? "社区荣誉殿堂" : self ? "我的荣誉收藏" : (profile?.nickname ?? "同学") + "的荣誉收藏" }}</h2>
      <p v-if="archive">收藏历届荣誉，阅读获奖者留下的校园故事。</p>
      <p v-else-if="profile">已获得 {{ total }} 枚<span v-if="panel==='honor' && equipped"> · 佩戴 {{ equipped }}</span></p></div>
      <Award :size="27" aria-hidden="true" />
    </header>

    <template v-if="archive">
      <nav class="hc-tabs" aria-label="荣誉档案">
        <button v-for="(name, key) in archiveSections" :key="key" :aria-pressed="section === key" @click="section = key; year = null; archivists = []; load()">{{ name }}</button>
      </nav>
      <label v-if="section === 'annual' && years.length" class="hc-year">年份
        <select v-model="year" @change="archivists = []; load()"><option :value="null">全部年份</option><option v-for="y in years" :key="y" :value="y">{{ y }}</option></select>
      </label>
      <ul class="hc-archive">
        <li v-for="record in archivists" :key="record.awardId ?? record.id">
          <button @click="show(record)">
            <CollectionBadge :rarity="record.rarity" :category="record.category" :code="record.code" earned />
            <span><strong>{{ record.nickname }}</strong><small>{{ honorName(record) }}</small><span v-if="record.story" class="hc-story">{{ record.story }}</span></span>
            <ChevronRight :size="16" aria-hidden="true" />
          </button>
        </li>
      </ul>
      <p v-if="!loading && !error && !archivists.length" class="hc-empty">这里还没有公开的授予记录。</p>
    </template>

    <template v-else>
      <nav class="hc-tabs hc-sections" aria-label="社区收藏分类">
        <button :aria-pressed="panel==='honor'" @click="panel='honor'">荣誉</button>
        <button :aria-pressed="panel==='achievement'" @click="panel='achievement'">社区成就</button>
      </nav>
      <section v-if="panel==='honor' && profile" class="hc-identity" aria-label="身份标识">
        <h3>身份标识</h3>
        <div class="hc-existing">
          <span v-for="code in identityCodes.filter(c=>self || profile?.badges.official?.code===c)" :key="code"
            :class="{active:profile?.badges.official?.code===code}">
            <component :is="badges[code].icon" :size="14" aria-hidden="true" />{{ badges[code].name }}
          </span>
          <span v-if="!self && !identityCodes.some(c=>profile?.badges.official?.code===c)">社区成员</span>
        </div>
        <h3>可佩戴荣誉</h3>
      </section>
      <nav v-if="panel==='achievement'" class="hc-tabs" aria-label="社区成就类型">
        <button v-for="(label,key) in filters" :key="key" :aria-pressed="filter===key" @click="filter=key">{{ label }}</button>
      </nav>
      <ul class="hc-gallery">
        <li v-for="item in visible" :key="item.id">
          <button @click="show(item)">
            <CollectionBadge :rarity="item.rarity" :category="item.category" :code="item.code" :earned="!!item.awardId" />
            <strong>{{ item.name }}</strong>
            <small>{{ item.year ? item.year + ' · ' : '' }}{{ honorRarities[item.rarity] }}
              <LockKeyhole v-if="!item.awardId" :size="10" aria-label="待获得" />
            </small>
          </button>
        </li>
        <li v-for="i in mystery" :key="'hidden-'+i" class="hc-mystery">
          <div><CollectionBadge rarity="common" category="hidden" />
            <strong>隐藏成就</strong><small><LockKeyhole :size="10" aria-hidden="true" /> 尚未发现</small>
          </div>
        </li>
      </ul>
      <p v-if="!loading && !error && !visible.length && !mystery" class="hc-empty">这里还没有可展示的藏品。</p>
    </template>

    <p v-if="loading" role="status" class="hc-empty">正在读取荣誉记录…</p>
    <p v-if="error && !selected" role="alert" class="hc-empty">{{ error }} <button class="hc-retry" @click="load(false, true)">重试</button></p>
    <button v-if="more" :disabled="loading" class="hc-more" @click="load(true)">查看更多</button>

    <dialog ref="dialog" class="hc-dialog" :class="{ 'hc-unlock': unlocked && !reducedMotion }" aria-labelledby="hc-dialog-name" @cancel.prevent="closeDetail" @close="selected && closeDetail()">
      <div v-if="selected">
        <CollectionBadge :rarity="selected.rarity" :category="selected.category" :code="selected.code" :earned="archive || !!selected.awardId" />
        <p v-if="unlocked" class="hc-new">{{ collectionKind(selected)==="achievement" ? "新成就已解锁" : "新荣誉已获得" }}</p>
        <h3 id="hc-dialog-name">{{ honorName({...selected,name:displayCollectionName(selected)}) }}</h3>
        <p v-if="'nickname' in selected">授予 {{ selected.nickname }}</p>
        <p>{{ selected.story || selected.criteria }}</p>
        <small>{{ honorRarities[selected.rarity] }}<template v-if="selected.at"> · {{ honorDate(selected.at) }}</template><template v-if="selected.archived"> · 已绝版</template></small>
        <p v-if="'unreleased' in selected && selected.unreleased" class="hc-empty">{{ selected.category==="limited" ? "发行对应年份后可获得。" : "新版后台启用后可解锁。" }}</p>
        <div v-if="self && !archive && selected.awardId" class="hc-dialog-controls">
          <template v-if="collectionKind(selected)==='honor'">
            <label v-if="!('legacy' in selected)"><input v-model="useTitle" type="checkbox" />使用称号{{ profile?.customTitle ? '「' + profile.customTitle + '」' : '' }}</label>
            <button :disabled="changing" @click="wear(selected)">{{ currentWear(selected) ? "更新佩戴" : "佩戴荣誉" }}</button>
            <button v-if="currentWear(selected)" :disabled="changing" @click="wear(selected,true)">取下荣誉</button>
          </template>
          <template v-if="collectionKind(selected)==='achievement'">
            <button v-if="selected.category==='hidden'" :disabled="changing" @click="update('collection.visibility', {awardId:selected.awardId,public:!selected.publicHidden})">{{ selected.publicHidden ? "仅自己可见" : "公开这枚隐藏成就" }}</button>
            <button v-if="(organized || 'base' in selected) && (selected.category!=='hidden' || selected.publicHidden)"
              :disabled="changing" @click="pin(selected)">{{ slots.includes(selected.awardId) ? "从主页取下" : "展示到个人主页" }}</button>
          </template>
        </div>
        <button v-if="'memberId' in selected" class="hc-more" @click="emit('person', selected.memberId); closeDetail()">打开荣誉档案</button>
        <p v-if="error" role="alert" class="hc-empty">{{ error }}</p>
        <button class="hc-close" @click="closeDetail">完成</button>
      </div>
    </dialog>
  </section>
</template>

<style>
.hc {display:grid;gap:13px;padding:12px 0 24px;min-width:0}
.hc-heading {
  display:flex;align-items:center;justify-content:space-between;gap:12px;
  padding:18px;border-radius:16px;border:1px solid var(--color-divider);
  background:var(--color-raised,var(--color-surface));color:var(--color-text)
}
.hc-archive-page .hc-heading {
  padding:24px 18px;min-height:96px;border-color:#615071;color:#fff3d9;
  background:radial-gradient(ellipse at 100% 0%,#6d4e69 0,transparent 55%),linear-gradient(125deg,#2b203d,#3b2d54);
}
.hc-archive-page .hc-heading h2 {font-family:"Noto Serif CJK SC","Songti SC",serif;font-weight:700}
.hc-archive-page .hc-heading p {color:#e8d7c7}
.hc-archive-page .hc-heading svg {color:#edce94}
.hc-heading h2 {font-size:20px;margin:0;line-height:1.35}
.hc-heading p {font-size:12px;margin:5px 0 0;color:var(--color-muted)}
.hc-heading svg {color:#9b742f;flex:none}
.hc-tabs {display:flex;gap:4px;overflow-x:auto;padding:3px 0 5px;scrollbar-width:none}
.hc-tabs button {min-height:44px;flex:none;border-radius:9px;padding:0 9px;color:var(--color-muted);font-size:13px}
.hc-tabs button[aria-pressed=true] {background:var(--color-tint);color:var(--color-text);font-weight:650}
.hc-rarity {display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:4px;text-align:center;color:var(--color-muted);font-size:11px}
.hc-rarity b {display:block;color:var(--color-text);font-size:18px;font-variant-numeric:tabular-nums}
.hc-existing {display:flex;gap:6px;flex-wrap:wrap}
.hc-existing span {color:var(--color-text);background:var(--color-tint);padding:5px 8px;border-radius:6px;font-size:12px}
.hc-gallery,.hc-archive {list-style:none;padding:0;margin:0}
.hc-gallery {display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}
.hc-gallery button,.hc-mystery>div {
  display:grid;justify-items:center;align-content:start;gap:6px;width:100%;height:100%;
  min-height:123px;padding:10px 4px;color:var(--color-text);
  border:1px solid var(--color-divider);border-radius:11px;background:var(--color-raised,var(--color-surface));
}
.hc-sections {border-bottom:1px solid var(--color-divider)}
.hc-sections button {min-width:88px}
.hc-identity {display:grid;gap:7px}
.hc-identity h3 {margin:0;font-size:14px;color:var(--color-text)}
.hc-identity h3:last-child {margin-top:5px}
.hc-existing span {display:inline-flex;align-items:center;gap:5px}
.hc-existing span:not(.active) {background:transparent;color:var(--color-muted);border:1px solid var(--color-divider)}
.hc-mystery {opacity:.75}
.hc-gallery strong {font-size:12px;line-height:1.35;overflow-wrap:anywhere}
.hc-gallery small {display:flex;align-items:center;gap:2px;color:var(--color-muted);font-size:10px}
.hc-archive {display:grid;gap:7px}
.hc-archive button {display:flex;align-items:center;gap:11px;width:100%;padding:8px 11px;color:var(--color-text);text-align:left;border:1px solid var(--color-divider);border-radius:11px}
.hc-archive .collection-medal {width:43px;height:48px}
.hc-archive button > span:nth-child(2) {flex:1;min-width:0}
.hc-archive strong,.hc-archive small {display:block;overflow-wrap:anywhere}
.hc-story {display:-webkit-box;overflow:hidden;-webkit-line-clamp:2;-webkit-box-orient:vertical;margin-top:5px;font-size:12px;color:var(--color-muted);line-height:1.5;overflow-wrap:anywhere}
.hc-archive small,.hc-year,.hc-empty {font-size:13px;color:var(--color-muted)}
.hc-year select {margin-inline-start:8px;padding:6px 8px;border:1px solid var(--color-divider);border-radius:8px;color:var(--color-text);background:var(--color-surface)}
.hc-more,.hc-close,.hc-dialog-controls button,.hc-retry {min-height:44px;padding:8px 13px;border-radius:10px;color:var(--color-text);background:var(--color-tint)}
.hc button:focus-visible {outline:2px solid var(--color-primary);outline-offset:2px}
.hc-dialog {
  box-sizing:border-box;width:min(390px,calc(100vw - 28px));max-height:calc(100dvh - 26px);
  overflow:auto;padding:19px;border:1px solid var(--color-divider);border-radius:16px;
  color:var(--color-text);background:var(--color-surface);text-align:center;
}
.hc-dialog::backdrop {background:#18152780}
.hc-dialog h3 {margin:8px 0;font-size:21px}
.hc-dialog p {margin:7px 0;overflow-wrap:anywhere;font-size:14px;line-height:1.5}
.hc-dialog small {color:var(--color-muted)}
.hc-dialog-controls {display:grid;gap:6px;margin:10px 0}
.hc-dialog-controls label {padding:5px;font-size:13px}
.hc-dialog button.hc-close,.hc-dialog button.hc-more {margin-top:9px}
.hc-new {color:#875c26;font-weight:700}
.hc-unlock .collection-medal {animation:hc-award-in .62s cubic-bezier(.2,.7,.15,1) both}
@keyframes hc-award-in {from {opacity:0;transform:scale(.72) rotate(-9deg);filter:brightness(1.6)} to {opacity:1;transform:scale(1);filter:none}}
@media(prefers-reduced-motion:reduce){.hc-unlock .collection-medal {animation:none}}
</style>

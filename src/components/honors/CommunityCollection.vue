<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import { Award, ChevronRight, LockKeyhole } from "lucide-vue-next";
import CollectionBadge from "./CollectionBadge.vue";
import { archiveSections, honorCategories, honorName, honorRarities, type CollectionItem, type CollectionProfile, type HonorArchiveItem } from "../../domain/honorCollection";
import { clearHonorCollectionCache, getHonorCollection } from "../../services/honorCollectionCache";
import { treeholeError, type TreeholeResult } from "../../services/treehole";
import { badges, honorDate } from "../../domain/communityHonors";

const props = defineProps<{
  viewer: string; member: string; archive?: boolean; reducedMotion?: boolean;
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
const category = ref("all");
const loading = ref(false);
const changing = ref(false);
const more = ref(false);
const error = ref("");
const dialog = ref<HTMLDialogElement>();
const selected = ref<CollectionItem | HonorArchiveItem>();
const unlocked = ref(false);
const useTitle = ref(false);
const received = new Set<string>();
let alive = true, revision = 0;
onBeforeUnmount(() => { alive = false; revision++; });
const visible = computed(() => items.value.filter(i => category.value === "all" || i.category === category.value));
const identities = computed(() => [...(profile.value?.badges.official ? [profile.value.badges.official.code] : []), ...(profile.value?.identities ?? [])]);
const oldCount = computed(() => identities.value.length);
const count = computed(() => (profile.value?.total ?? 0) + oldCount.value);

async function load(append = false, fresh = false) {
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
      const data = append ? (await props.request("collection.profile", { memberId: props.member, offset: items.value.length })).collection :
        await getHonorCollection(props.viewer, props.member, props.request, fresh);
      if (!alive || request !== revision) return;
      if (!data || data.id !== props.member) throw Error("invalid_response");
      profile.value = data;
      items.value = [...(append ? items.value : []), ...data.items.slice(0, 40)];
      more.value = data.items.length > 40;
      if (self.value && !append && !dialog.value?.open) {
        const reward = data.items.find(i => i.awardId && data.unseen.includes(i.awardId) && !received.has(i.awardId));
        if (reward) void show(reward, true);
      }
    }
  } catch (e) {
    if (alive && request === revision) error.value = treeholeError(e);
  } finally {
    if (alive && request === revision) loading.value = false;
  }
}

async function show(item: CollectionItem | HonorArchiveItem, newAward = false) {
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
    if (!alive || !update.updatedIdentity) throw Error("invalid_response");
    emit("updated", update);
    clearHonorCollectionCache();
    await load(false, true);
    if (alive) selected.value = items.value.find(item => item.id === index);
  } catch (e) {
    if (alive) error.value = treeholeError(e);
  } finally { if (alive) changing.value = false; }
}
onMounted(() => load());
</script>

<template>
  <section class="hc" :class="{ 'hc-archive-page': archive, 'hc-reduced': reducedMotion }">
    <header class="hc-heading">
      <div><h2>{{ archive ? "社区荣誉殿堂" : self ? "我的荣誉收藏" : (profile?.nickname ?? "同学") + "的荣誉收藏" }}</h2>
      <p v-if="archive">收藏历届荣誉，阅读获奖者留下的校园故事。</p>
      <p v-else-if="profile">已收藏 {{ count }} 枚<span v-if="profile.badges.collection"> · 佩戴 {{ profile.badges.collection.title || profile.badges.collection.name }}</span></p></div>
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
      <div v-if="profile" class="hc-rarity">
        <span v-for="(label, key) in honorRarities" :key="key"><b>{{ (profile.rarities[key] ?? 0) + (key === 'common' ? oldCount : 0) }}</b>{{ label }}</span>
      </div>
      <div v-if="identities.length" class="hc-existing" aria-label="已佩戴的身份与荣誉">
        <span v-for="code in identities" :key="code">{{ badges[code].name }}</span>
      </div>
      <nav v-if="self || items.length" class="hc-tabs" aria-label="荣誉分类">
        <button :aria-pressed="category === 'all'" @click="category = 'all'">全部</button>
        <button v-for="(name, key) in honorCategories" :key="key" :aria-pressed="category === key" @click="category = key">{{ name }}</button>
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
      </ul>
      <p v-if="!loading && !error && !visible.length" class="hc-empty">{{ self && category === "hidden" ? "隐藏荣誉会在获得后出现。" : "这里还没有可展示的荣誉。" }}</p>
    </template>

    <p v-if="loading" role="status" class="hc-empty">正在读取荣誉记录…</p>
    <p v-if="error && !selected" role="alert" class="hc-empty">{{ error }} <button class="hc-retry" @click="load(false, true)">重试</button></p>
    <button v-if="more" :disabled="loading" class="hc-more" @click="load(true)">查看更多</button>

    <dialog ref="dialog" class="hc-dialog" :class="{ 'hc-unlock': unlocked && !reducedMotion }" aria-labelledby="hc-dialog-name" @cancel.prevent="closeDetail" @close="selected && closeDetail()">
      <div v-if="selected">
        <CollectionBadge :rarity="selected.rarity" :category="selected.category" :code="selected.code" :earned="!!selected.awardId" />
        <p v-if="unlocked" class="hc-new">新荣誉已获得</p>
        <h3 id="hc-dialog-name">{{ honorName(selected) }}</h3>
        <p v-if="'nickname' in selected">授予 {{ selected.nickname }}</p>
        <p>{{ selected.story || selected.criteria }}</p>
        <small>{{ honorRarities[selected.rarity] }}<template v-if="selected.at"> · {{ honorDate(selected.at) }}</template><template v-if="selected.archived"> · 已绝版</template></small>
        <div v-if="self && !archive && selected.awardId" class="hc-dialog-controls">
          <label v-if="selected.category !== 'hidden' || selected.publicHidden"><input v-model="useTitle" type="checkbox" />使用称号{{ profile?.customTitle ? '「' + profile.customTitle + '」' : '' }}</label>
          <button v-if="selected.category === 'hidden'" :disabled="changing" @click="update('collection.visibility', { awardId:selected.awardId, public:!selected.publicHidden })">{{ selected.publicHidden ? "对他人隐藏" : "公开这枚隐藏荣誉" }}</button>
          <button v-if="selected.category !== 'hidden' || selected.publicHidden" :disabled="changing" @click="update('collection.wear', { awardId:selected.awardId, useTitle })">{{ profile?.badges.collection?.id === selected.awardId ? "更新佩戴" : "佩戴荣誉" }}</button>
          <button v-if="profile?.badges.collection?.id === selected.awardId" :disabled="changing" @click="update('collection.wear', { awardId:null })">取下荣誉</button>
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
.hc-gallery button {
  display:grid;justify-items:center;align-content:start;gap:6px;width:100%;height:100%;
  min-height:123px;padding:10px 4px;color:var(--color-text);
  border:1px solid var(--color-divider);border-radius:11px;background:var(--color-raised,var(--color-surface));
}
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

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { honorCategories, honorName, honorRarities, type CollectionAudit, type CollectionDefinition, type CollectionGrant, type CollectionMember, type HonorCategory, type HonorRarity } from "../../domain/honorCollection";
import { honorDate } from "../../domain/communityHonors";
import { clearHonorCollectionCache } from "../../services/honorCollectionCache";
import { treeholeError, type TreeholeResult } from "../../services/treehole";
const props = defineProps<{ request: (a: string, b?: Record<string, unknown>) => Promise<TreeholeResult> }>();
const emit = defineEmits<{ changed: [TreeholeResult] }>();
const operations: Record<string, string> = { auto_grant:"自动发放", save:"保存定义", archive:"封存年度", title:"设置称号", grant:"授予荣誉", revoke:"撤销授予" };
const mode = ref("definitions");
const definitions = ref<CollectionDefinition[]>([]);
const definitionOffset = ref(0);
const moreDefinitions = ref(false);
const members = ref<CollectionMember[]>([]);
const grants = ref<CollectionGrant[]>([]);
const audit = ref<CollectionAudit[]>([]);
const exceptions = ref(false);
const auditOffset = ref(0);
const moreAudit = ref(false);
const grantOffset = ref(0);
const moreGrants = ref(false);
const member = ref<CollectionMember>();
const query = ref("");
const issued = computed(() => definitions.value.filter(d => d.mode === "review" && !d.archived));
const busy = ref(false), error = ref(""), notice = ref("");
const editing = ref<CollectionDefinition>(), formOpen = ref(false);
const fields = ref({
  code:"",name:"",category:"contribution" as HonorCategory,rarity:"rare" as HonorRarity,
  year:new Date().getFullYear(), criteria:"", story:"", capacity:0, reason:"",
});
const awardId = ref(""), evidence = ref(""), awardingStory = ref(""), reason = ref(""), title = ref("");
const pending = ref<{ label: string; payload: Record<string, unknown> }>();
let last: { key:string; id:string } | undefined;

async function load() {
  const result = await props.request("collection.admin", {
    query:query.value, memberId:member.value?.id, exceptions:exceptions.value, offset:auditOffset.value,
    definitionOffset:definitionOffset.value,grantOffset:grantOffset.value,
  });
  if (!result.honorDefinitions || !result.honorAudit || !result.honorMembers) throw Error("invalid_response");
  definitions.value = result.honorDefinitions.slice(0,100);
  moreDefinitions.value = result.honorDefinitions.length > 100;
  members.value = result.honorMembers;
  grants.value = (result.honorGrants ?? []).slice(0,50);
  moreGrants.value = (result.honorGrants?.length ?? 0)>50;
  audit.value = result.honorAudit.slice(0,20);
  moreAudit.value = result.honorAudit.length > 20;
}
async function run(action: () => Promise<void>) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try { await action(); } catch(e) { error.value = treeholeError(e); }
  finally { busy.value = false; }
}
function edit(definition?: CollectionDefinition) {
  editing.value = definition?.mode === "review" ? definition : undefined;
  fields.value = {
    code:definition?.code ?? "", name:definition?.name ?? "", category:definition?.category ?? "contribution",
    rarity:definition?.rarity ?? "rare", year:definition?.year ?? new Date().getFullYear(),
    criteria:definition?.criteria ?? "",story:definition?.defaultStory ?? "",capacity:definition?.capacity ?? 0,reason:"",
  };
  formOpen.value = true;
}
function choose(person: CollectionMember) {
  member.value = person; title.value = person.customTitle ?? ""; reason.value = "";
  grantOffset.value=0; mode.value="grants";
  void run(load);
}
function prompt(label: string, payload: Record<string, unknown>) {
  error.value = ""; notice.value = "";
  pending.value = { label, payload };
}
function save() {
  const value = fields.value;
  const code = !editing.value && value.category === "limited" && !value.code.endsWith("-" + value.year) ? value.code + "-" + value.year : value.code;
  prompt("保存荣誉定义", {
    ...value, operation:"save", code, definitionId:editing.value?.id,
    capacity:value.capacity || null,year:value.category === "limited" ? value.year : null,
  });
}
function grant() {
  prompt("授予 " + (member.value?.nickname ?? ""), {
    operation:"grant", memberId:member.value?.id, definitionId:awardId.value,
    evidence:evidence.value, story:awardingStory.value, reason:reason.value,
  });
}
async function confirm() {
  const action = pending.value;
  if (!action) return;
  await run(async() => {
    const key = JSON.stringify(action.payload);
    if (last?.key !== key) last = { key, id:crypto.randomUUID() };
    const result = await props.request("collection.change", { ...action.payload, requestId:last.id });
    clearHonorCollectionCache();
    emit("changed", result);
    pending.value = undefined;
    last = undefined;
    notice.value = action.label + "已完成";
    if (action.payload.operation === "save") formOpen.value = false;
    try { await load(); }
    catch { error.value = "操作已保存。请刷新列表读取最新记录。"; }
  });
}
onMounted(() => run(load));
</script>
<template>
 <section class="hc hc-admin">
  <nav class="hc-tabs" aria-label="社区荣誉管理">
   <button v-for="(label,key) in {definitions:'荣誉与年度',grants:'授予与称号',audit:'发放记录'}" :key="key" :aria-pressed="mode===key" @click="mode=key">{{ label }}</button>
  </nav>
  <p v-if="notice" role="status" class="hc-empty">{{notice}}</p>
  <p v-if="error" role="alert" class="hc-empty">{{error}} <button v-if="!pending" class="hc-retry" @click="run(load)">刷新</button></p>
  <section v-if="pending" class="hc-management-confirm" role="region" aria-label="确认管理操作">
   <h3>{{ pending.label }}</h3><p>操作会进入管理审计。</p>
   <button class="hc-more" :disabled="busy" @click="pending=undefined">返回编辑</button>
   <button class="hc-more" :disabled="busy" @click="confirm">{{busy ? "正在保存…" : "确认执行"}}</button>
  </section>
  <template v-if="mode==='definitions'">
   <button class="hc-more" @click="edit()">创建荣誉</button>
   <form v-if="formOpen" @submit.prevent="save">
    <label>编号<input v-model="fields.code" :disabled="!!editing" required pattern="[a-z][a-z0-9-]{1,47}" /></label>
    <label>名称<input v-model="fields.name" required minlength="2" maxlength="24" /></label>
    <label>分类<select v-model="fields.category" :disabled="!!editing"><option v-for="(v,k) in honorCategories" :key="k" :value="k">{{v}}</option></select></label>
    <label>稀有度<select v-model="fields.rarity" :disabled="!!editing"><option v-for="(v,k) in honorRarities" :key="k" :value="k">{{v}}</option></select></label>
    <label v-if="fields.category==='limited'">年份<input v-model.number="fields.year" type="number" min="2020" :max="new Date().getFullYear()+1" :disabled="!!editing" /></label>
    <label>发放上限（0 为不限）<input v-model.number="fields.capacity" type="number" min="0" max="10000" /></label>
    <label>获取条件<textarea v-model="fields.criteria" required minlength="2" maxlength="240" /></label>
    <label>默认事迹<textarea v-model="fields.story" required minlength="2" maxlength="240" /></label>
    <label>管理原因<input v-model="fields.reason" required minlength="2" maxlength="240" /></label>
    <button class="hc-more" :disabled="busy">核对并保存</button>
   </form>
   <ul class="hc-manage-list">
    <li v-for="d in definitions" :key="d.id">
      <strong>{{honorName(d)}}</strong>
      <p>{{ honorRarities[d.rarity] }} · {{ d.mode==='template' ? "待创建年份" : d.archived ? "绝版" : d.mode==='automatic' ? "系统判定" : "审核授予" }}<span v-if="d.mode!=='template'"> · 已发 {{d.issued}}{{d.capacity ? " / " + d.capacity : ""}}</span></p>
      <button v-if="d.mode==='template'" class="hc-more" @click="edit(d)">创建年度版本</button>
      <button v-if="d.mode==='review'&&!d.archived" class="hc-more" @click="edit(d)">编辑</button>
      <button v-if="d.year&&!d.archived" class="hc-more" @click="prompt('封存 '+honorName(d),{operation:'archive',definitionId:d.id,reason:'确认封存此年度版本'})">封存</button>
    </li>
   </ul>
   <div class="hc-page-controls"><button v-if="definitionOffset>0" class="hc-more" @click="definitionOffset-=100; run(load)">上一页</button><button v-if="moreDefinitions" class="hc-more" @click="definitionOffset+=100; run(load)">下一页定义</button></div>
  </template>
  <template v-else-if="mode==='grants'">
   <form @submit.prevent="run(load)"><label>查找成员<input v-model="query" placeholder="完整昵称或成员 ID" maxlength="64" required /></label><button class="hc-more" :disabled="busy">搜索</button></form>
   <button v-for="person in members" :key="person.id" class="hc-more" @click="choose(person)">{{person.nickname}} · {{person.id.slice(0,8)}}</button>
   <template v-if="member">
    <h3>{{member.nickname}}的授予记录</h3>
    <form @submit.prevent="grant">
      <label>待授荣誉<select v-model="awardId" required @change="awardingStory=issued.find(d=>d.id===awardId)?.defaultStory??''"><option value="">选择荣誉</option><option v-for="d in issued" :value="d.id" :key="d.id">{{honorName(d)}}</option></select></label>
      <label>审核依据（仅开发者可见）<textarea v-model="evidence" required minlength="4" maxlength="400" /></label>
      <label>公开事迹<textarea v-model="awardingStory" required minlength="2" maxlength="240" /></label>
      <label>管理原因<input v-model="reason" required minlength="2" maxlength="240" /></label>
      <button class="hc-more" :disabled="busy">核对并授予</button>
    </form>
    <form @submit.prevent="prompt('保存专属称号',{operation:'title', memberId:member.id, title, reason:'管理专属称号'})">
      <label>专属称号（留空清除）<input v-model="title" maxlength="16" /></label><button class="hc-more">保存称号</button>
    </form>
    <ul class="hc-manage-list"><li v-for="g in grants" :key="g.id"><strong>{{honorName(g)}}</strong><p>{{honorDate(g.at)}} · {{g.revoked?'已撤销':'有效'}}</p><p v-if="g.evidence">{{g.evidence}}</p>
      <button v-if="!g.revoked" class="hc-more" @click="prompt('撤销 '+honorName(g),{operation:'revoke',awardId:g.id,reason:'开发者复核后撤销荣誉'})">撤销</button>
    </li></ul>
    <div class="hc-page-controls"><button v-if="grantOffset>0" class="hc-more" @click="grantOffset-=50; run(load)">上一页</button><button v-if="moreGrants" class="hc-more" @click="grantOffset+=50; run(load)">下一页授予</button></div>
   </template>
  </template>
  <template v-else>
    <label><input v-model="exceptions" type="checkbox" @change="auditOffset=0; run(load)" />只查看异常发放</label>
    <ul class="hc-manage-list"><li v-for="row in audit" :key="row.id"><strong>{{operations[row.operation] || row.operation}} · {{row.outcome==='ok'?'成功':treeholeError({code:row.outcome})}}</strong><p>{{honorDate(row.at)}} {{row.nickname}} {{row.reason}}</p><p v-if="row.evidence">{{row.evidence}}</p></li></ul>
    <p v-if="!audit.length&&!busy" class="hc-empty">暂无记录。</p>
    <div class="hc-page-controls"><button v-if="auditOffset>0" class="hc-more" @click="auditOffset-=20; run(load)">上一页</button><button v-if="moreAudit" class="hc-more" @click="auditOffset+=20; run(load)">下一页记录</button></div>
  </template>
 </section>
</template>
<style scoped>
.hc-admin form,.hc-management-confirm{display:grid;gap:9px;padding:13px;border:1px solid var(--color-divider);border-radius:12px}
.hc-admin form label{display:grid;gap:4px;font-size:13px}
.hc-admin input:not([type=checkbox]),.hc-admin textarea,.hc-admin select{width:100%;min-height:42px;padding:8px;border:1px solid var(--color-divider);border-radius:7px;color:var(--color-text);background:var(--color-surface);font-size:16px}
.hc-management-confirm{background:var(--color-raised,var(--color-surface))}
.hc-management-confirm h3,.hc-management-confirm p{margin:0}
.hc-manage-list{list-style:none;padding:0;margin:0}
.hc-manage-list li{border-bottom:1px solid var(--color-divider);padding:9px 0;overflow-wrap:anywhere}
.hc-manage-list p{font-size:12px;color:var(--color-muted);margin:4px 0}
.hc-page-controls{display:flex;gap:8px}
</style>

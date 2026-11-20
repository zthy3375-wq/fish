<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { Search, Users } from 'lucide-vue-next';
import { treeholeError, treeholeErrorCode, type RegisteredCommunityMember, type TreeholeResult } from '../services/treehole';

const props = defineProps<{ request: (action: string, body: Record<string, unknown>) => Promise<TreeholeResult> }>();
const emit = defineEmits<{ expired: [] }>();
const input = ref('');
const search = ref('');
const total = ref<number>();
const members = ref<RegisteredCommunityMember[]>([]);
const next = ref<Record<string, string> | null>(null);
const loading = ref(false);
const error = ref('');
const retryPage = ref(false);
let active = true;

onBeforeUnmount(() => { active = false; });

async function load(append = false) {
  if (loading.value || (append && !next.value)) return;
  loading.value = true;
  error.value = '';
  retryPage.value = append;
  if (!append) {
    members.value = [];
    next.value = null;
  }
  try {
    const result = await props.request('admin.members', { query: search.value, ...(append ? next.value : {}) });
    if (!active) return;
    if (!result.registeredMembers) throw Error('invalid_response');
    members.value = [...members.value, ...result.registeredMembers];
    next.value = result.next ?? null;
    if (typeof result.registeredMemberCount === 'number') total.value = result.registeredMemberCount;
  } catch (failure) {
    if (!active) return;
    const code = treeholeErrorCode(failure);
    if (code === 'session_expired') emit('expired');
    if (code === 'forbidden') {
      members.value = [];
      total.value = undefined;
      next.value = null;
    }
    error.value = code === 'not_found' ? '当前社区后台尚未启用注册成员列表。' : treeholeError(failure);
  } finally {
    if (active) loading.value = false;
  }
}

function find() {
  search.value = input.value.trim();
  void load();
}

onMounted(() => void load());
</script>

<template>
  <section class="th-directory" aria-label="注册成员列表">
    <header class="th-directory-count">
      <Users :size="22" aria-hidden="true" />
      <div><h2>注册用户总数</h2><small>不含已注销账号</small></div>
      <strong v-if="total !== undefined">{{ total }}</strong>
    </header>
    <form class="th-directory-search" @submit.prevent="find">
      <label><Search :size="16" aria-hidden="true" /><input v-model="input" maxlength="32" type="search" aria-label="搜索账号或昵称" placeholder="搜索账号或昵称" :disabled="loading" /></label>
      <button type="submit" :disabled="loading">搜索</button>
    </form>
    <p v-if="loading" role="status">正在读取成员…</p>
    <p v-if="error" role="alert">{{ error }} <button @click="load(retryPage && !!next)">重试</button></p>
    <p v-if="!loading && !error && !members.length">{{ search ? '没有找到匹配的成员。' : '还没有注册成员。' }}</p>
    <ul v-if="members.length" class="th-directory-members">
      <li v-for="member in members" :key="member.id">
        <strong>{{ member.nickname }}</strong>
        <small>登录账号 <span>{{ member.username }}</span></small>
      </li>
    </ul>
    <button v-if="next && !error" class="th-directory-more" :disabled="loading" @click="load(true)">加载更多</button>
  </section>
</template>

<style scoped>
.th-directory {display:grid;gap:12px;padding:10px 0 30px}
.th-directory-count {display:flex;align-items:center;gap:12px;padding:16px;background:var(--color-tint);border-radius:14px;color:var(--color-text)}
.th-directory-count svg {color:var(--color-primary);flex:none}
.th-directory-count div {flex:1}
.th-directory-count h2 {font-size:16px;margin:0}
.th-directory-count small,.th-directory-members small,.th-directory p {color:var(--color-muted);font-size:13px}
.th-directory-count strong {font-size:24px;font-variant-numeric:tabular-nums}
.th-directory-search {display:flex;gap:6px}
.th-directory-search label {flex:1;display:flex;align-items:center;gap:6px;min-width:0;padding:0 10px;border:1px solid var(--color-divider);border-radius:10px;color:var(--color-muted)}
.th-directory-search input {width:100%;min-width:0;min-height:44px;color:var(--color-text);border:0;background:transparent}
.th-directory button {min-height:44px;border-radius:10px;padding:0 12px;background:var(--color-tint);color:var(--color-text)}
.th-directory-members {list-style:none;padding:0 12px;margin:0;border:1px solid var(--color-divider);border-radius:12px}
.th-directory-members li {display:grid;gap:3px;padding:11px 0;overflow-wrap:anywhere}
.th-directory-members li+li {border-top:1px solid var(--color-divider)}
.th-directory-members small span {color:var(--color-text)}
</style>

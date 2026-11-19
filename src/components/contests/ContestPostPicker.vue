<script setup lang="ts">
import { ref, onBeforeUnmount } from "vue";
import {
  treeholeRequest,
  treeholeError,
  type TreeholePost,
} from "../../services/treehole";
const props = defineProps<{ imageOnly?: boolean; disabled?: boolean }>();
const emit = defineEmits<{ choose: [post: TreeholePost] }>();
const posts = ref<TreeholePost[]>([]),
  next = ref<Record<string, string> | null>(),
  open = ref(false),
  busy = ref(false),
  error = ref("");
let live = true;
onBeforeUnmount(() => (live = false));
async function load(append = false) {
  if (busy.value || props.disabled) return;
  busy.value = true;
  open.value = true;
  error.value = "";
  try {
    const result = await treeholeRequest("posts.list", {
      scope: "mine",
      ...(append ? next.value || {} : {}),
    });
    if (!live) return;
    const rows = (result.posts || []).filter(
      (post) => !post.anonymous && (!props.imageOnly || !!post.images?.length),
    );
    posts.value = append ? [...posts.value, ...rows] : rows;
    next.value = result.next;
  } catch (e) {
    if (live) error.value = treeholeError(e);
  } finally {
    if (live) busy.value = false;
  }
}
</script>
<template>
  <div class="contest-post-picker">
    <button type="button" :disabled="busy || disabled" @click="load()">
      {{ imageOnly ? "从我的图文帖选择封面" : "选择我的帖子参赛" }}
    </button>
    <section v-if="open">
      <p>选择自己的非匿名{{ imageOnly ? "图文" : "文字或图文" }}帖子。</p>
      <p v-if="error" role="alert">{{ error }}</p>
      <button
        v-for="post in posts"
        :key="post.id"
        type="button"
        class="pick-post"
        @click="
          emit('choose', post);
          open = false;
        "
      >
        <img
          v-if="post.images?.[0]?.url"
          :src="post.images[0].url"
          loading="lazy"
          alt=""
        /><span
          >{{ post.title || post.body || "图片作品"
          }}<small>{{
            new Date(post.createdAt).toLocaleDateString("zh-CN")
          }}</small></span
        >
      </button>
      <p v-if="!busy && !posts.length">本页没有符合要求的帖子。</p>
      <button
        v-if="next"
        type="button"
        :disabled="busy || disabled"
        @click="load(true)"
      >
        更多我的帖子</button
      ><button type="button" :disabled="busy || disabled" @click="open = false">
        收起选择
      </button>
    </section>
  </div>
</template>
<style scoped>
.contest-post-picker {
  margin: 12px 0;
}
.contest-post-picker button {
  min-height: 44px;
  color: var(--color-primary);
  font-size: 13px;
}
.contest-post-picker section {
  padding: 12px;
  background: var(--color-bg);
  border-radius: 12px;
  max-height: 50vh;
  overflow: auto;
}
.contest-post-picker p {
  font-size: 12px;
  color: var(--color-muted);
  margin: 8px 0;
}
.pick-post {
  display: flex;
  align-items: center;
  width: 100%;
  gap: 10px;
  text-align: left;
  padding: 8px 0;
  border-bottom: 1px solid var(--color-divider);
}
.pick-post img {
  width: 48px;
  height: 48px;
  object-fit: cover;
  border-radius: 8px;
}
.pick-post span {
  flex: 1;
  min-width: 0;
  overflow-wrap: anywhere;
  color: var(--color-text);
  line-height: 1.7;
}
.pick-post small {
  display: block;
  color: var(--color-muted);
  font-size: 11px;
}
</style>

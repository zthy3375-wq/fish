<script setup lang="ts">
import TreeholeImages from "../TreeholeImages.vue";
import { Check, Trophy, Flag } from "lucide-vue-next";
import type { ContestEntry } from "../../services/contests";
import { awardLabels } from "../../services/contests";
const props = defineProps<{
  entry: ContestEntry;
  voting: boolean;
  submitting: boolean;
  busy: boolean;
  admin: boolean;
}>();
defineEmits<{
  image: [index: number];
  vote: [];
  edit: [];
  withdraw: [];
  report: [];
  review: [];
  profile: [];
  post: [];
}>();
</script>
<template>
  <article
    class="contest-work"
    :class="{
      'is-winner': entry.awards.some((a) => a.kind === 'champion'),
      'is-selected': entry.voted,
    }"
  >
    <div
      v-if="entry.awards.some((a) => a.kind !== 'participation')"
      class="work-award"
    >
      <Trophy :size="18" />{{
        entry.awards
          .filter((a) => a.kind !== "participation")
          .map((a) => awardLabels[a.kind])
          .join(" · ")
      }}
    </div>
    <TreeholeImages
      :key="entry.version"
      :images="entry.images"
      :post-id="entry.postId || entry.id"
      :contest-id="entry.contestId"
      :entry-id="entry.id"
      @open="$emit('image', $event)"
    />
    <div class="work-copy">
      <small v-if="entry.status !== 'approved'">{{
        entry.status === "removed" ? "已下架" : "已撤回"
      }}</small>
      <h3>{{ entry.title }}</h3>
      <p>{{ entry.body }}</p>
      <button class="work-author" @click="$emit('profile')">
        {{ entry.author }}{{ entry.mine ? " · 我" : "" }}
      </button>
      <footer>
        <button
          v-if="voting && !entry.mine && entry.status === 'approved'"
          class="work-vote"
          :class="{ 'is-voted': entry.voted }"
          :aria-pressed="entry.voted"
          :disabled="busy"
          @click="$emit('vote')"
        >
          <Check v-if="entry.voted" :size="15" />{{
            entry.voted ? "已投票 · 撤回" : "投一票"
          }}</button
        ><span v-if="entry.votes !== null">{{ entry.votes }} 票</span
        ><button
          v-if="entry.mine && submitting && entry.status === 'approved'"
          :disabled="busy"
          @click="$emit('edit')"
        >
          编辑</button
        ><button
          v-if="entry.mine && submitting && entry.status === 'approved'"
          :disabled="busy"
          @click="$emit('withdraw')"
        >
          撤回</button
        ><button v-if="entry.postId" @click="$emit('post')">原帖</button
        ><button v-if="admin" :disabled="busy" @click="$emit('review')">
          审核</button
        ><button
          v-else
          :disabled="busy"
          aria-label="举报作品"
          @click="$emit('report')"
        >
          <Flag :size="16" />
        </button>
      </footer>
    </div>
  </article>
</template>
<style scoped>
.contest-work {
  border: 1px solid var(--color-divider);
  border-radius: 18px;
  overflow: hidden;
  background: var(--color-raised, #fff);
  margin-bottom: 14px;
}
.work-copy {
  padding: 16px;
}
.work-copy h3 {
  font-size: 18px;
  margin-bottom: 8px;
}
.work-copy p {
  white-space: pre-wrap;
  line-height: 1.8;
  font-size: 14px;
  overflow-wrap: anywhere;
}
.work-author {
  font-size: 12px;
  color: var(--color-muted);
  min-height: 44px;
}
.work-copy footer {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
  border-top: 1px solid var(--color-divider);
  padding-top: 8px;
  font-size: 12px;
}
.work-copy footer button {
  min-height: 44px;
}
.work-vote {
  padding: 0 15px;
  border-radius: 10px;
  background: var(--color-tint);
  color: var(--color-primary);
  display: flex;
  align-items: center;
  gap: 6px;
}
.is-voted {
  background: var(--color-primary);
  color: white;
  animation: vote-confirm 0.22s ease-out;
}
.is-selected {
  border-color: var(--color-primary);
}
.is-winner {
  border-color: #b2b5d9;
}
.work-award {
  padding: 12px 16px;
  background: #f0eff9;
  color: #595d8c;
  font-size: 13px;
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 8px;
}
@keyframes vote-confirm {
  50% {
    transform: scale(1.05);
  }
}
@media (prefers-reduced-motion: reduce) {
  .is-voted {
    animation: none;
  }
}
</style>

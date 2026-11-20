<script setup lang="ts">
import { computed } from "vue";
import { Check, Trophy, Flag } from "lucide-vue-next";
import TreeholeImages from "../TreeholeImages.vue";
import {
  contestStage,
  awardLabels,
  type Contest,
  type ContestEntry,
} from "../../services/contests";
const props = defineProps<{
  contest: Contest;
  entry: ContestEntry;
  now: number;
  votesUsed: number;
  pending?: boolean;
  readonly?: boolean;
}>();
defineEmits<{
  vote: [];
  edit: [];
  withdraw: [];
  report: [];
  profile: [];
  post: [];
  image: [index: number];
}>();
const phase = computed(() => contestStage(props.contest, props.now));
</script>
<template>
  <article class="ct-work-detail">
    <div v-if="entry.awards.length" class="ct-award-strip">
      <Trophy :size="22" /><strong>{{
        entry.awards.map((a) => awardLabels[a.kind]).join(" · ")
      }}</strong>
    </div>
    <TreeholeImages
      :key="entry.version"
      :images="entry.images"
      :post-id="entry.postId || entry.id"
      :contest-id="entry.contestId"
      :entry-id="entry.id"
      @open="$emit('image', $event)"
    />
    <h1>{{ entry.title }}</h1>
    <button class="ct-author" @click="$emit('profile')">
      {{ entry.author }}{{ entry.mine ? " · 我的作品" : "" }}
    </button>
    <p class="ct-work-body">{{ entry.body }}</p>
    <p v-if="entry.status !== 'approved'" class="ct-muted">
      {{ entry.status === "withdrawn" ? "作品已撤回" : "作品已下架" }}
    </p>
    <p v-if="phase === 'ended' && entry.votes !== null" class="ct-final-votes">
      最终 {{ entry.votes }} 票
    </p>
    <div
      v-if="
        phase === 'voting' && !contest.paused && entry.status === 'approved'
      "
      class="ct-vote-panel"
    >
      <template v-if="entry.mine"
        ><p>这是你的作品，期待同学们的选择。</p></template
      ><template v-else
        ><p>
          还可投 {{ Math.max(0, contest.votesPerUser - votesUsed) }} /
          {{ contest.votesPerUser }} 票
        </p>
        <button
          class="ct-primary ct-vote"
          :class="{ 'is-voted': entry.voted }"
          :aria-pressed="entry.voted"
          :disabled="
            readonly || pending || (!entry.voted && votesUsed >= contest.votesPerUser)
          "
          @click="$emit('vote')"
        >
          <Check v-if="entry.voted" :size="18" />{{
            pending ? "确认中…" : entry.voted ? "已投票 · 撤回" : "投一票"
          }}</button
        ><small>投票截止前可撤回，实时票数不公开</small></template
      >
    </div>
    <div
      v-if="
        !readonly && entry.mine &&
        phase === 'submitting' &&
        !contest.paused &&
        entry.status === 'approved'
      "
      class="ct-pair"
    >
      <button class="ct-primary" @click="$emit('edit')">编辑作品</button
      ><button class="ct-secondary" @click="$emit('withdraw')">撤回作品</button>
    </div>
    <footer class="ct-work-links">
      <button v-if="entry.postId" class="ct-link" @click="$emit('post')">
        查看原帖</button
      ><button v-if="!readonly && !entry.mine" class="ct-link" @click="$emit('report')">
        <Flag :size="15" />举报作品
      </button>
    </footer>
  </article>
</template>

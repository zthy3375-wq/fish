<script setup lang="ts">
import { computed } from "vue";
import { Clock, Users, ChevronRight, Trophy } from "lucide-vue-next";
import {
  contestStage,
  contestRemaining,
  contestLabels,
  type Contest,
  type ContestEntry,
} from "../../services/contests";
import { primaryContestAction, contestDate } from "../../domain/contests";
import ContestEntryCard from "./ContestEntryCard.vue";
const props = defineProps<{
  contest: Contest;
  entries: ContestEntry[];
  mine: ContestEntry[];
  now: number;
  votesUsed: number;
  loading?: boolean;
  more?: boolean;
  winners?: boolean;
  admin?: boolean;
  home?: boolean;
  mineReady?: boolean;
}>();
const emit = defineEmits<{
  primary: [];
  entry: [entry: ContestEntry];
  more: [];
  filter: [winners: boolean];
  manage: [];
}>();
const phase = computed(() => contestStage(props.contest, props.now));
const pictures = computed(() =>
  props.contest.formats.some((x) => ["image", "mixed"].includes(x)),
);
</script>
<template>
  <section class="ct-event">
    <div class="ct-hero" :class="{ 'has-cover': contest.cover?.url }">
      <img
        v-if="contest.cover?.url"
        :src="contest.cover.url"
        alt="赛事封面"
        class="ct-hero-image"
      />
      <div class="ct-hero-copy">
        <div class="ct-eyebrow">
          <span>{{ home ? "正在邯院发生" : contest.type }}</span
          ><span class="ct-status">{{
            contest.paused ? "已暂停" : contestLabels[phase]
          }}</span>
        </div>
        <h1>{{ contest.title }}</h1>
        <p>{{ contest.description }}</p>
        <div class="ct-meta">
          <span
            ><Clock :size="14" />{{
              contestRemaining(contest, now) || contestLabels[phase]
            }}</span
          ><span
            ><Users :size="14" />{{ contest.participantCount }}人 ·
            {{ contest.entryCount }}件</span
          >
        </div>
        <button
          class="ct-primary ct-main-action"
          :disabled="contest.paused"
          @click="emit('primary')"
        >
          {{
            mineReady === false
              ? "确认我的参赛状态"
              : primaryContestAction(contest, mine, now)
          }}<ChevronRight :size="17" />
        </button>
      </div>
    </div>
    <details class="ct-rules">
      <summary>比赛规则、日程与奖励</summary>
      <p class="ct-pre">{{ contest.rules }}</p>
      <p>
        每人{{ contest.maxEntries }}件作品、{{
          contest.votesPerUser
        }}票；自己不能给自己投票。实时票数默认隐藏，同票并列。满{{
          contest.minEntries
        }}件有效作品且有有效票时颁发前三名。
      </p>
      <p>
        {{
          contest.minAccountHours > 0
            ? `投票开始前需注册满${contest.minAccountHours}小时。`
            : "普通社区账号均可参与，异常票可复核。"
        }}投稿截止前可以编辑或撤回。
      </p>
      <dl>
        <div
          v-for="item in [
            ['投稿开始', contest.startsAt],
            ['投稿截止', contest.submissionEnds],
            ['投票开始', contest.votingStarts],
            ['投票截止', contest.votingEnds],
            ['结果公布', contest.awardAt],
          ]"
          :key="item[0]"
        >
          <dt>{{ item[0] }}</dt>
          <dd>{{ contestDate(item[1]) }}</dd>
        </div>
      </dl>
      <small>以上日程均为北京时间</small>
    </details>
    <div v-if="phase === 'ended'" class="ct-result-note">
      <Trophy :size="26" />
      <div>
        <h2>结果已公布</h2>
        <p>获奖与每一次认真参与，都留在这里。</p>
      </div>
    </div>
    <div class="ct-wall-heading" id="contest-wall">
      <h2>{{ phase === "ended" ? "作品与获奖记录" : "参赛作品" }}</h2>
      <span v-if="phase === 'voting'"
        >还可投{{ Math.max(0, contest.votesPerUser - votesUsed) }}票</span
      ><span v-else>{{ contest.entryCount }}件</span>
    </div>
    <div v-if="phase === 'ended'" class="ct-segments" aria-label="作品筛选">
      <button :aria-pressed="!winners" @click="emit('filter', false)">
        全部作品</button
      ><button :aria-pressed="!!winners" @click="emit('filter', true)">
        获奖作品
      </button>
    </div>
    <div class="ct-wall" :class="{ 'ct-photo-wall': pictures }">
      <ContestEntryCard
        v-for="entry in entries"
        :key="entry.id"
        :entry="entry"
        @open="emit('entry', entry)"
      />
    </div>
    <p v-if="loading" role="status" class="ct-loading">作品加载中…</p>
    <div v-else-if="!entries.length" class="ct-empty">
      <h3>{{ winners ? "暂无获奖作品" : "第一件作品，也许来自你" }}</h3>
      <p>
        {{
          winners
            ? "作品不足门槛或没有有效票时，保留参赛纪念。"
            : "分享一份校园生活，让这场比赛热闹起来。"
        }}
      </p>
    </div>
    <button
      v-if="more"
      class="ct-secondary ct-more"
      :disabled="loading"
      @click="emit('more')"
    >
      查看更多作品</button
    ><button
      v-if="admin"
      class="ct-link ct-manage-link"
      @click="emit('manage')"
    >
      管理这场比赛<ChevronRight :size="16" />
    </button>
  </section>
</template>

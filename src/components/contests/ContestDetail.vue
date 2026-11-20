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
import ContestProgress from "./ContestProgress.vue";
import ContestCover from "./ContestCover.vue";
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
  legacyEligibility?: boolean;
  readonly?: boolean;
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
      <ContestCover v-if="contest.cover" :contest="contest" class="ct-hero-image"/>
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
          :disabled="contest.paused || readonly"
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
    <ContestProgress :contest="contest" :now="now"/>
    <details id="contest-rules" class="ct-rules">
      <summary>主题介绍、规则与奖励</summary>
      <h3>完整主题</h3>
      <p class="ct-pre">{{ contest.description }}</p>
      <h3>参赛规则</h3>
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
            : legacyEligibility
              ? "本场需在投票开始前注册，投票资格由后台确认。"
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
      <h3>{{ winners ? "暂无正式获奖作品" : phase === "reviewing" ? "作品正在审核" : phase === "draft" || phase === "upcoming" ? "投稿开始后，在这里看见作品" : phase === "ended" || phase === "cancelled" ? "本场没有公开作品" : "还没有作品，来投第一件" }}</h3>
      <p>
        {{
          winners
            ? "作品不足门槛或没有有效票时，保留参赛纪念。"
            : phase === "draft" || phase === "upcoming"
              ? "投稿开始：" + contestDate(contest.startsAt) + "（北京时间）"
              : phase === "reviewing" ? "审核完成后会公布结果。"
              : phase === "ended" || phase === "cancelled" ? "已撤回或下架的记录仍由后台保留。"
              : "查看规则后，提交你的校园作品。"
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

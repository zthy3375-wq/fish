<script setup lang="ts">
import { computed } from "vue";
import { Check, Clock } from "lucide-vue-next";
import { contestDate } from "../../domain/contests";
import { contestStage, type Contest } from "../../services/contests";

const props = defineProps<{ contest: Contest; now: number }>();
const phase = computed(() => contestStage(props.contest, props.now));
const steps = computed(() => {
  const state = phase.value;
  return [
    {
      label: "投稿",
      active: state === "submitting",
      done: ["waiting", "voting", "reviewing", "ended"].includes(state),
    },
    {
      label: "投票",
      active: state === "voting",
      done: ["reviewing", "ended"].includes(state),
    },
    { label: "公布", active: state === "reviewing", done: state === "ended" },
  ];
});
const next = computed(() => {
  const { startsAt, submissionEnds, votingStarts, votingEnds, awardAt } = props.contest;
  switch (phase.value) {
    case "draft":
    case "upcoming":
      return { label: "投稿开始", time: startsAt };
    case "submitting":
      return { label: "投稿截止", time: submissionEnds };
    case "waiting":
      return { label: "投票开始", time: votingStarts };
    case "voting":
      return { label: "投票截止", time: votingEnds };
    case "reviewing":
      return props.now < Date.parse(awardAt)
        ? { label: "预计公布", time: awardAt }
        : { label: "结果审核中，公布后可查看" };
    default:
      return undefined;
  }
});
</script>

<template>
  <section v-if="phase !== 'cancelled'" class="ct-progress" aria-label="赛事日程">
    <ol aria-label="赛事阶段">
      <li
        v-for="step in steps"
        :key="step.label"
        :class="{ current: step.active, done: step.done }"
        :aria-current="step.active ? 'step' : undefined"
      >
        <span class="ct-progress-marker" aria-hidden="true">
          <Check v-if="step.done" :size="11" :stroke-width="2.5" />
        </span>
        <span>
          {{ step.label }}
          <span v-if="step.done" class="th-sr-only">（已完成）</span>
        </span>
      </li>
    </ol>
    <div v-if="next" class="ct-milestone">
      <Clock :size="14" aria-hidden="true" />
      <span>{{ next.label }}</span>
      <time v-if="next.time" :datetime="next.time">{{ contestDate(next.time) }}</time>
      <small v-if="next.time">北京时间</small>
    </div>
  </section>
</template>

<style scoped>
.ct-progress {
  margin: 14px 0 6px;
  padding: 13px 14px;
  border: 1px solid var(--color-divider);
  border-radius: 12px;
  background: var(--color-raised, var(--color-card, #fff));
}
.ct-progress ol {
  display: flex;
  list-style: none;
  padding: 0;
  margin: 0;
  gap: 8px;
}
.ct-progress li {
  display: flex;
  align-items: center;
  gap: 5px;
  flex: 1;
  font-size: 12px;
  color: var(--color-muted);
}
.ct-progress li::after {
  content: "";
  height: 1px;
  background: var(--color-divider);
  flex: 1;
  margin-inline-start: 3px;
}
.ct-progress li.done::after {
  background: var(--color-primary);
}
.ct-progress li:last-child {
  flex: none;
}
.ct-progress li:last-child::after {
  display: none;
}
.ct-progress-marker {
  display: grid;
  place-items: center;
  flex: none;
  width: 16px;
  height: 16px;
  border: 1px solid var(--color-border);
  border-radius: 50%;
}
.ct-progress li.current,
.ct-progress li.done {
  color: var(--color-primary);
}
.ct-progress li.current {
  font-weight: 700;
}
.current .ct-progress-marker {
  border: 4px solid var(--color-tint);
  background: var(--color-primary);
}
.done .ct-progress-marker {
  border-color: transparent;
  background: var(--color-tint);
  color: var(--color-primary);
}
.ct-milestone {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 5px 7px;
  border-top: 1px solid var(--color-divider);
  margin-top: 10px;
  padding-top: 9px;
  color: var(--color-muted);
  font-size: 12px;
}
.ct-milestone time {
  color: var(--color-text);
  font-weight: 650;
  font-variant-numeric: tabular-nums;
}
</style>

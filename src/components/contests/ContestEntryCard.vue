<script setup lang="ts">
import { ref, watch } from "vue";
import { treeholeRequest } from "../../services/treehole";
import { Trophy, Check } from "lucide-vue-next";
import type { ContestEntry } from "../../services/contests";
import { awardLabels } from "../../services/contests";
const props = defineProps<{ entry: ContestEntry }>();
const renewed = ref<string | null>();
let attempted = false;
watch(
  () => props.entry.images[0]?.url,
  () => {
    renewed.value = undefined;
    attempted = false;
  },
);
async function renew() {
  if (attempted) {
    renewed.value = null;
    return;
  }
  attempted = true;
  try {
    renewed.value =
      (
        await treeholeRequest("contests.image", {
          contestId: props.entry.contestId,
          entryId: props.entry.id,
          imageId: props.entry.images[0].id,
        })
      ).image?.url || null;
  } catch {
    renewed.value = null;
  }
}
defineEmits<{ open: [] }>();
</script>
<template>
  <article
    class="ct-work"
    :class="{
      'ct-work-photo': entry.images.length,
      'ct-work-winner': entry.awards.some((a) => a.kind === 'champion'),
    }"
  >
    <button
      class="ct-work-open"
      @click="$emit('open')"
      :aria-label="`查看作品：${entry.title}`"
    >
      <div v-if="entry.images.length" class="ct-work-cover">
        <img
          v-if="renewed !== null"
          :src="renewed || entry.images[0].url || undefined"
          @error="renew"
          referrerpolicy="no-referrer"
          loading="lazy"
          :width="entry.images[0].width"
          :height="entry.images[0].height"
          alt="作品封面"
        /><span v-if="renewed === null" class="ct-image-missing"
          >打开作品重试图片</span
        ><span v-if="entry.images.length > 1" class="ct-image-count"
          >{{ entry.images.length }}张</span
        >
      </div>
      <div class="ct-work-copy">
        <span v-if="entry.status !== 'approved'" class="ct-medal"
          >{{ entry.status === "withdrawn" ? "已撤回" : "已下架" }} ·
          {{ entry.mine ? "仅你和管理者可见" : "管理记录" }}</span
        >
        <span
          v-if="entry.awards.some((a) => a.kind !== 'participation')"
          class="ct-medal"
          ><Trophy :size="13" />{{
            awardLabels[
              entry.awards.find((a) => a.kind !== "participation")!.kind
            ]
          }}</span
        >
        <h3>{{ entry.title }}</h3>
        <p v-if="!entry.images.length" class="ct-work-excerpt">
          {{ entry.body }}
        </p>
        <footer>
          <span>{{ entry.author }}{{ entry.mine ? " · 我" : "" }}</span
          ><Check v-if="entry.voted" :size="15" aria-label="已投票" />
        </footer>
      </div>
    </button>
  </article>
</template>

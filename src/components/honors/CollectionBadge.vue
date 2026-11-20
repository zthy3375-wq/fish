<script setup lang="ts">
import { Archive, BookOpen, Bug, Camera, Compass, Crown, Feather, Flag, Gem, GraduationCap,
  HandHeart, HeartHandshake, Landmark, MapPin, MoonStar, Network, Orbit, Pencil, Smile, Sparkles,
  Star, Sunrise, Trophy, Waypoints } from "lucide-vue-next";
import { computed, type Component } from "vue";
import type { HonorCategory, HonorRarity } from "../../domain/honorCollection";
const props = defineProps<{ rarity: HonorRarity; category: HonorCategory; code?: string; earned?: boolean; small?: boolean }>();
const emblems: Record<string, Component> = {
  "handan-light":Sunrise, "that-person":Star, "community-classic":Trophy, "campus-legend":Crown, "first-hundred":Flag,
  architect:Compass, "landmark-post":BookOpen, "gold-creator":Feather, "bug-hunter":Bug, "early-resident":Landmark,
  "answer-guide":HandHeart, "campus-photographer":Camera, "campus-observer":MapPin, "good-company":Smile,
  "person-of-year":Trophy, "creator-of-year":Pencil, "photo-of-year":Camera, "warmth-of-year":HandHeart,
  "graduation-keepsake":GraduationCap, "welcome-guide":Compass, "before-dawn":MoonStar,
  "developer-noticed":Sparkles, "world-lines":Orbit, archivist:Archive, "crossed-paths":Waypoints, "no-island":Network,
};
const icons = { identity: Landmark, contribution: Feather, legend: Crown, limited: Gem, hidden: HeartHandshake };
const emblem = computed(() => emblems[props.code?.replace(/-[0-9]{4}$/, "") ?? ""] ?? icons[props.category]);
</script>
<template>
  <span class="collection-medal" :class="[rarity, { earned, small }]" aria-hidden="true">
    <span class="collection-medal-face"><component :is="emblem" :size="small ? 14 : 26" :stroke-width="1.7" /></span>
  </span>
</template>
<style>
.collection-medal {
  --rim:#929399;--light:#f1f0ee;--shade:#d2d0cb;--ink:#44464d;
  display:inline-grid;place-items:center;width:61px;height:68px;flex:none;
  clip-path:polygon(50% 0,94% 18%,94% 68%,75% 88%,50% 100%,25% 88%,6% 68%,6% 18%);
  background:linear-gradient(147deg,var(--rim),var(--light) 42%,var(--rim) 72%,var(--shade));
  filter:grayscale(.9);opacity:.62;color:var(--ink);
}
.collection-medal.earned {filter:none;opacity:1}
.collection-medal.fine {--rim:#537da0;--light:#dceefa;--shade:#92b6d2;--ink:#1c3c61}
.collection-medal.rare {--rim:#7b63aa;--light:#ece0fb;--shade:#b0a0ce;--ink:#4a2c75}
.collection-medal.epic {--rim:#a97932;--light:#fff2c8;--shade:#d5a860;--ink:#64400e}
.collection-medal.legendary {clip-path:polygon(50% 0,66% 10%,93% 15%,87% 36%,94% 65%,77% 79%,69% 91%,50% 100%,31% 91%,23% 79%,6% 65%,13% 36%,7% 15%,34% 10%);--rim:#99604c;--light:#fff2d0;--shade:#c59766;--ink:#5d2924}
.collection-medal-face {
  display:grid;place-items:center;width:85%;height:85%;clip-path:inherit;
  background:radial-gradient(ellipse at 30% 18%,var(--light),var(--shade));
}
.collection-medal.legendary.earned .collection-medal-face {animation:collection-metal 5s ease-in-out 1}
@keyframes collection-metal {0%,100%{filter:brightness(1)} 50%{filter:brightness(1.16)}}
.hc-reduced .collection-medal.legendary.earned .collection-medal-face {animation:none}
@media(prefers-reduced-motion:reduce){.collection-medal.legendary.earned .collection-medal-face {animation:none}}
.collection-medal.small .collection-medal-face {
  background:var(--light);
}
.collection-medal.small {width:24px;height:27px}
</style>

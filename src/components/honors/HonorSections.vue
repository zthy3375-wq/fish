<script setup lang="ts">
defineProps<{modelValue:string}>();defineEmits<{'update:modelValue':[value:string]}>();
</script>
<template><nav class="honor-sections" aria-label="荣誉收藏区域"><button v-for="(label,key) in {identity:'身份与荣誉',achievements:'成就收藏',medals:'赛事奖牌'}" :key="key" :aria-pressed="modelValue===key" @click="$emit('update:modelValue',key)">{{label}}</button></nav></template>
<style scoped>.honor-sections{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:4px;border-bottom:1px solid var(--color-divider);padding-bottom:8px}.honor-sections button{min-height:44px;border-radius:9px;font-size:13px;color:var(--color-muted);cursor:pointer}.honor-sections button[aria-pressed=true]{color:var(--color-text);background:var(--color-background);font-weight:600}.honor-sections button:hover{background:var(--color-background)}.honor-sections button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}</style>

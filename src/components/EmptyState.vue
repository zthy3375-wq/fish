<script setup lang="ts">import {Coffee} from 'lucide-vue-next';defineProps<{title:string;description?:string}>();</script>
<template><div class="empty-state"><Coffee :size="29"/><h3>{{title}}</h3><p v-if="description">{{description}}</p></div></template>

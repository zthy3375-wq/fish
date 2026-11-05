<script setup lang="ts">
import type {Component} from 'vue';defineProps<{title:string;subtitle:string;icon:Component}>();defineEmits<{select:[]}>();
</script>
<template><button class="quick-action" @click="$emit('select')"><span class="icon-tile"><component :is="icon" :size="23"/></span><strong>{{title}}</strong><small>{{subtitle}}</small></button></template>

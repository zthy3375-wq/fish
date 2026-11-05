<script setup lang="ts">
import {ChevronRight,ArrowUpRight} from 'lucide-vue-next';
import type {Component} from 'vue';
export interface ServiceItem {id:string;title:string;subtitle?:string;icon:Component;href?:string}
defineProps<{items:ServiceItem[]}>();defineEmits<{select:[id:string]}>();
</script>
<template><div class="service-group"><template v-for="item in items" :key="item.id"><a v-if="item.href" class="service-row" :href="item.href" target="_blank" rel="noopener noreferrer"><component :is="item.icon" class="row-icon"/><span class="row-copy"><strong>{{item.title}}</strong><small v-if="item.subtitle">{{item.subtitle}}</small></span><ArrowUpRight class="row-chevron" :size="18"/></a><button v-else class="service-row" @click="$emit('select',item.id)"><component :is="item.icon" class="row-icon"/><span class="row-copy"><strong>{{item.title}}</strong><small v-if="item.subtitle">{{item.subtitle}}</small></span><ChevronRight class="row-chevron" :size="18"/></button></template></div></template>

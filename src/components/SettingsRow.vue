<script setup lang="ts">
defineProps<{title:string;description:string;modelValue:boolean}>();defineEmits<{'update:modelValue':[value:boolean]}>();
</script>
<template><label class="setting-row"><span><strong>{{title}}</strong><small>{{description}}</small></span><input type="checkbox" role="switch" class="switch" :checked="modelValue" @change="$emit('update:modelValue',($event.target as HTMLInputElement).checked)"/></label></template>

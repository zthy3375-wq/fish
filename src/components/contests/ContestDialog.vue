<script setup lang="ts">
import { ref, watch, nextTick, onBeforeUnmount } from "vue";
const props = defineProps<{
  open: boolean;
  title: string;
  confirm?: string;
  busy?: boolean;
  confirmDisabled?: boolean;
  danger?: boolean;
}>();
const emit = defineEmits<{ confirm: []; cancel: [] }>();
const element = ref<HTMLDialogElement>();
const labelId = "ct-dialog-" + crypto.randomUUID();
watch(
  () => props.open,
  async (value) => {
    await nextTick();
    if (!element.value) return;
    if (value && !element.value.open) element.value.showModal();
    else if (!value && element.value.open) element.value.close();
  },
  { immediate: true },
);
onBeforeUnmount(() => element.value?.close());
</script>
<template>
  <dialog
    ref="element"
    class="ct-dialog"
    :aria-labelledby="labelId"
    @cancel.prevent="!busy && emit('cancel')"
  >
    <h2 :id="labelId">{{ title }}</h2>
    <div class="ct-dialog-body"><slot /></div>
    <footer>
      <button
        class="ct-secondary"
        :disabled="busy"
        autofocus
        @click="emit('cancel')"
      >
        返回</button
      ><button
        class="ct-primary"
        :class="{ 'ct-danger': danger }"
        :disabled="busy || confirmDisabled"
        @click="emit('confirm')"
      >
        {{ busy ? "处理中…" : confirm || "确认" }}
      </button>
    </footer>
  </dialog>
</template>

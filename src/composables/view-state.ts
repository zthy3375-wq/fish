import { reactive, ref } from 'vue';
/** UI preferences only; school/personal course storage remains independent. */
export const scheduleViews = reactive<Record<string, {week:number; day:number; view:'day'|'week'}>>({});
export const gradeTerm = ref('all');
export const gradeQuery = ref('');

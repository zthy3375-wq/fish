import {reactive} from 'vue';
export const scheduleViews=reactive<Record<string,{week:number;day:number;view:'day'|'week'}>>({});

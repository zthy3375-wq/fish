import {reactive,watch} from 'vue';
import {defaultGradeFilter} from '../domain/grade-analysis';
import {academicCache} from './handan-academic';
// In-memory view state survives tab changes; no student data copied to a new store.
export const gradeView=reactive({tab:'overview',filter:defaultGradeFilter(),limit:60});
watch(()=>academicCache.value.connected,connected=>{if(!connected){gradeView.tab='overview';Object.assign(gradeView.filter,defaultGradeFilter());gradeView.limit=60}});

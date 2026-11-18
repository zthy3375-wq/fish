import type {AcademicCache} from './academic-sync-engine';
import type {LearningCache} from '../domain/learning';
import type {TaskSnapshot} from '../domain/agenda';
import {activate,record,subject} from './achievementJournal';

export function observeSchool(c:AcademicCache,historical:boolean){
  const id=c.connected?c.localScope||'':'', scope=subject('school',id);
  activate('school',id);
  if(!scope)return;
  if(c.session==='valid')void record('identity',scope,undefined,historical);
  const term=c.selectedTerm?c.terms[c.selectedTerm]:null;
  if(term?.data?.courses.length&&term.updatedAt)void record('schedule',scope,term.updatedAt,historical);
  if(c.grades.data?.length&&c.grades.updatedAt)void record('grade',scope,c.grades.updatedAt,historical);
}
export function schoolView(c:AcademicCache,screen:string,offline:boolean){
  if(!c.connected||!c.localScope)return;
  const scope=subject('school',c.localScope),term=c.selectedTerm?c.terms[c.selectedTerm]:null;
  if(screen==='schedule'&&offline&&term?.data?.courses.length&&term.updatedAt)void record('offline',scope);
  if(screen==='exams'&&c.exams.updatedAt&&c.exams.data?.length)void record('exam',scope);
}
export function observeLearning(c:LearningCache,historical:boolean){
  const id=c.connected?c.accountKey:'';
  activate('learning',id);
  if(c.courses.length&&c.session==='valid'&&!c.issues.courses&&c.lastAttempt)
    void record('learning',subject('learning',id),c.lastAttempt,historical);
}
export function observeTasks(c:TaskSnapshot,historical:boolean){
  const task=c.tasks.find(t=>!t.source&&t.completed&&t.completedAt&&(t.steps?.length??0)>=2&&t.steps!.every(s=>s.completed));
  if(task?.completedAt)void record('tasks','device',task.completedAt,historical);
}

import {Preferences} from '@capacitor/preferences';
import {emptyTasks,validateTaskSnapshot,mergeTaskBackup,type TaskSnapshot,type CampusTask} from '../domain/agenda';
export const TASK_KEY='handan.personal.tasks.v1';
export class TaskStore {
 private queue:Promise<unknown>=Promise.resolve();
 constructor(private read:()=>Promise<string|null>,private write:(value:string)=>Promise<void>){}
 async load(){const value=await this.read();return value===null?emptyTasks():validateTaskSnapshot(JSON.parse(value))}
 async reload(){await this.queue.catch(()=>{});return this.load()}
 change(mutate:(draft:TaskSnapshot)=>void){const commit=async()=>{const next=await this.load();mutate(next);next.updatedAt=new Date().toISOString();const clean=validateTaskSnapshot(next);await this.write(JSON.stringify(clean));return clean};const job=this.queue.catch(()=>{}).then(async()=>{let value:TaskSnapshot|undefined;if(typeof navigator!=='undefined'&&navigator.locks)await navigator.locks.request('handan-task-write',async()=>{value=await commit()});else value=await commit();return value!});this.queue=job;return job}
 upsert(task:CampusTask){return this.change(s=>{const index=s.tasks.findIndex(t=>t.id===task.id);if(index<0)s.tasks.push(task);else s.tasks[index]=task})}
 complete(id:string,completed:boolean){return this.change(s=>{const t=s.tasks.find(t=>t.id===id);if(!t)throw Error('待办已不存在，请重新加载');t.completed=completed;t.updatedAt=new Date().toISOString()})}
 remove(id:string){return this.change(s=>{s.tasks=s.tasks.filter(t=>t.id!==id)})}
 restore(backup:unknown){return this.change(s=>{s.tasks=mergeTaskBackup(s,backup).tasks})}
}
export const taskStore=new TaskStore(async()=>{const {value}=await Preferences.get({key:TASK_KEY});return value},async value=>{await Preferences.set({key:TASK_KEY,value})});

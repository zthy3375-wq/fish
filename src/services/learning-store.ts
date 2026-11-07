import {Preferences} from '@capacitor/preferences';
import {emptyLearning,validateLearningCache,type LearningCache} from '../domain/learning';
export const LEARNING_KEY='handan.learning.chaoxing.v1';
export class LearningStore {
 private queue:Promise<unknown>=Promise.resolve();
 constructor(private read:()=>Promise<string|null>,private write:(value:string)=>Promise<void>){}
 async load(){await this.queue.catch(()=>{});const value=await this.read();return value===null?emptyLearning():validateLearningCache(JSON.parse(value))}
 change(update:(cache:LearningCache)=>LearningCache){const job=this.queue.catch(()=>{}).then(async()=>{const raw=await this.read();const current=raw===null?emptyLearning():validateLearningCache(JSON.parse(raw));const next=validateLearningCache(update(current));await this.write(JSON.stringify(next));return next});this.queue=job;return job}
}
export const learningStore=new LearningStore(async()=>{const {value}=await Preferences.get({key:LEARNING_KEY});return value},async value=>{await Preferences.set({key:LEARNING_KEY,value})});

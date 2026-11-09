import {Capacitor, registerPlugin} from '@capacitor/core';
import type {Course} from '../domain/academic';
import type {Semester} from '../domain/schedule';
export interface WidgetStatus {supported:boolean;ids:number[]}
export interface WidgetPinResult {requested:boolean;baselineIds:number[]}
const widget=registerPlugin<{
 publish(options:{snapshot:string}):Promise<void>;
 target():Promise<{date:string}>;
 pin():Promise<WidgetPinResult>;
 status():Promise<WidgetStatus>;
 openHome():Promise<void>;
}>('CourseWidget');
export const widgetSupported=()=>Capacitor.getPlatform()==='android'&&Capacitor.isPluginAvailable('CourseWidget');
export function widgetSnapshot(semester:Semester,courses:Course[],ready=true){return JSON.stringify({ready,monday:semester.weekStartDate,weekCount:semester.weekCount,courses:courses.map(({name,room,teacher,day,start,end,weeks,color})=>({name,room,teacher,day,start,end,weeks,color}))});}
export const publishWidget=(snapshot:string)=>widget.publish({snapshot});
export const widgetTarget=()=>widget.target();
export const pinCourseWidget=()=>widget.pin();
export const courseWidgetStatus=()=>widget.status();
export const openWidgetHome=()=>widget.openHome();
export function hasNewCourseWidget(baseline:readonly number[],current:readonly number[]){
 return current.some(id=>Number.isInteger(id)&&id>0&&!baseline.includes(id));
}

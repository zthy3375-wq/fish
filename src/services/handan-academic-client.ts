import {Capacitor,registerPlugin} from '@capacitor/core';
export type SessionState='valid'|'expired'|'unknown'|'disconnected';
export interface SchoolTerm {xnm:string;xqm:string}
export interface SchoolProfile {name:string;major:string;className:string;year:string}
export interface SchoolGrade {name:string;scoreText:string;credit:number|null;gpa:number|null;term:string;kind:string;courseCode?:string;recordId?:string;year?:string;termCode?:string;examType?:string;passed?:boolean}
export interface SchoolExam {name:string;date:string;time:string;room:string;seat:string}
export interface SchoolTimetable {periods?:{number:number;start:string;end:string}[];term:SchoolTerm;kbList:unknown[];practice:{name:string;teacher:string;weeks:string}[];endpoint:string;method:string}
export interface ModuleResult {status:'ok'|'error';httpStatus?:number;stage?:'page'|'query';data?:unknown;updatedAt?:string;code?:string;scope?:'all'|'term'}
export interface NativeAcademicResult {session:SessionState;modules?:Record<string,ModuleResult>}
export interface HandanAcademicClient {
 login():Promise<NativeAcademicResult>; getSessionState():Promise<NativeAcademicResult>;
 getProfile():Promise<NativeAcademicResult>;getSemesters():Promise<NativeAcademicResult>;
 getTimetable(term?:SchoolTerm):Promise<NativeAcademicResult>;getGrades(term?:SchoolTerm):Promise<NativeAcademicResult>;
 getExams(term?:SchoolTerm):Promise<NativeAcademicResult>;syncAll(term?:SchoolTerm):Promise<NativeAcademicResult>;logout():Promise<NativeAcademicResult>;
}
const native=registerPlugin<HandanAcademicClient>('HandanAcademicClient');
export const schoolConnectionSupported=()=>Capacitor.getPlatform()==='android';
export const handanAcademicClient:HandanAcademicClient=native;

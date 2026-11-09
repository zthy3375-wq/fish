import {ref} from 'vue';
import {Preferences} from '@capacitor/preferences';
import type {Semester} from '../domain/schedule';
import {calendarKey,validWeekMonday,correctLegacyCalendar} from '../domain/week-calibration';
const KEY='handan.calendar.overrides.v1';
const dates=ref<Record<string,string>>({});
export async function initWeekCalibration(){const {value}=await Preferences.get({key:KEY});if(!value)return;const raw=JSON.parse(value);if(!raw||typeof raw!=='object'||Array.isArray(raw))throw Error('教学周设置读取失败');dates.value=Object.fromEntries(Object.entries(raw).filter((entry):entry is [string,string]=>/^20\d\d-20\d\d\/(春季|秋季)$/.test(entry[0])&&validWeekMonday(entry[1])));}
export function calibratedSemester(s:Semester):Semester{const base=correctLegacyCalendar(s);return {...base,weekStartDate:dates.value[calendarKey(s)]||base.weekStartDate}}
export async function saveWeekCalibration(s:Semester,date:string){if(!validWeekMonday(date))throw Error('第一教学周必须从周一开始');const next={...dates.value,[calendarKey(s)]:date};await Preferences.set({key:KEY,value:JSON.stringify(next)});dates.value=next;}

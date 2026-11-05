import type { AcademicData, Course } from '../domain/academic';
const all=Array.from({length:18},(_,i)=>i+1);
const c=(id:string,name:string,day:number,start:string,end:string,period:string,room:string,color:string,teacher:string,weeks=all):Course=>({id,name,day,start,end,period,room,color,teacher,weeks});
const data:AcademicData={source:'mock',courses:[
 c('1','高等数学 A',1,'08:00','09:35','1–2节','主教楼 A302','blue','王老师'),c('2','大学英语',1,'10:00','11:35','3–4节','公共教学楼 206','orange','李老师'),
 c('3','工程制图',2,'08:00','09:35','1–2节','实验楼 305','green','张老师'),c('4','线性代数',2,'14:00','15:35','5–6节','主教楼 A208','purple','赵老师'),
 c('5','大学英语',3,'10:00','11:35','3–4节','公共教学楼 206','orange','李老师'),c('6','体育',3,'16:00','17:35','7–8节','东区操场','green','刘老师'),
 c('7','高等数学 A',4,'08:00','09:35','1–2节','主教楼 A302','blue','王老师'),c('8','程序设计基础',4,'10:00','11:35','3–4节','实验楼 B205','purple','陈老师'),c('9','中国近现代史纲要',4,'14:00','15:35','5–6节','公共教学楼 401','orange','周老师'),
 c('10','工程制图',5,'08:00','09:35','1–2节','实验楼 305','green','张老师'),c('11','程序设计实验',5,'14:00','15:35','5–6节','计算机中心 302','purple','陈老师',[2,4,6,8,10,12,14,16,18])],
 grades:[{name:'高等数学 A',credit:5,score:89,term:'2025–2026 春季',kind:'必修'},{name:'大学英语',credit:3,score:92,term:'2025–2026 春季',kind:'必修'},{name:'工程制图',credit:3,score:86,term:'2025–2026 春季',kind:'必修'},{name:'大学体育',credit:1,score:95,term:'2025–2026 春季',kind:'必修'},{name:'计算机基础',credit:2,score:91,term:'2025–2026 春季',kind:'必修'},{name:'艺术鉴赏',credit:2,score:88,term:'2025–2026 秋季',kind:'选修'}],
 exams:[{name:'高等数学 A',date:'2027-01-11',time:'09:00–11:00',room:'主教楼 A302',seat:'16'},{name:'大学英语',date:'2027-01-13',time:'14:00–16:00',room:'公共教学楼 206',seat:'08'},{name:'程序设计基础',date:'2027-01-15',time:'09:00–11:00',room:'实验楼 B205',seat:'23'}]};
export interface AcademicProvider { load():Promise<AcademicData> }
export const mockAcademicProvider:AcademicProvider={async load(){return structuredClone(data)}};
// A real provider must be explicitly authorized and normalize data to AcademicData.

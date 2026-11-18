import type { Component } from 'vue';
import { BookOpen, CalendarCheck, CalendarDays, ClipboardCheck, Droplets, Fish, Flower2, GraduationCap, KeyRound, Map as MapIcon, NotebookPen, RadioTower, Shell, ShowerHead, Sunrise, WashingMachine, Waves, WifiOff } from 'lucide-vue-next';
import { awards } from './communityHonors';

export type Source = 'device' | 'school' | 'learning' | 'community';
export const groups = ['全部','初识','学习','生活','社区','时光','隐藏'] as const;
export type Group = typeof groups[number];
export type Tier = '普通' | '稀有' | '史诗' | '传奇';
export interface Collectible {
  code:string; name:string; group:Group; tier:Tier; source:Source; icon:Component;
  color:string; condition:string; description:string; metric?:string; goal:number; hidden?:boolean;
}
function local(code:string,name:string,group:Group,tier:Tier,source:Source,icon:Component,color:string,condition:string,description:string,goal=1):Collectible {
  return {code,name,group,tier,source,icon,color,condition,description,goal,hidden:group==='隐藏'};
}
export const catalog:Collectible[] = [
  local('welcome','你好，邯院','初识','普通','device',Sunrise,'#d58a26','首次打开带有收藏馆的邯院通','小金鱼为你留了一张空白纪念册。'),
  ...awards.filter(a=>a.code==='arrival').map(community),
  local('identity','身份确认','初识','普通','school',KeyRound,'#bd861d','成功连接学校教务系统','通往教务处的小门打开了。'),
  local('profile','小金鱼的朋友','初识','普通','device',Fish,'#d27655','在本机填写昵称与专业，并保存资料','以后就这样称呼你。'),
  local('schedule','我的第一张课表','学习','普通','school',CalendarDays,'#527ab2','成功获取并保存一张含课程的学校课表','新学期有了坐标。'),
  local('offline','断网也不怕','学习','稀有','school',WifiOff,'#526faa','断网时打开已缓存的学校课表','信号消失，下一节课还在。'),
  local('exam','考试将至','学习','普通','school',CalendarCheck,'#a46930','打开考试安排，并看到学校返回的考试','在学期末的日历上圈一个日期。'),
  local('grade','成绩揭晓','学习','普通','school',GraduationCap,'#6879b3','从教务系统成功读取成绩','这一页，记着你的努力。'),
  local('learning','学习通已连接','学习','普通','learning',RadioTower,'#497f9c','成功同步学习通的课程列表','散落的课程有了同一个书架。'),
  local('tasks','任务清零','学习','稀有','device',ClipboardCheck,'#498376','完成一个自建待办和其中至少两个子任务','最后一个勾，留给自己。'),
  local('water','生命之源','生活','稀有','device',Droplets,'#4087af','成功扫描并识别直饮水设备','一杯水的故事，从这里开始。'),
  local('bath','洗去疲惫','生活','普通','device',ShowerHead,'#587bb6','进入趣智校园钱包','忙完一天，给自己留一点热气。'),
  local('laundry','生活技能 +1','生活','普通','device',WashingMachine,'#5c8b77','进入胖乖生活钱包','校园生活，又熟悉了一点。'),
  local('map','校园探险家','生活','普通','device',MapIcon,'#508b70','成功加载一张校园平面图','下一次迷路，就来找这张图。'),
  local('life','生活家','生活','稀有','device',Flower2,'#bf715d','体验趣智、胖乖和校园地图三个功能','熟悉校园，从这些小事开始。',3),
  ...awards.filter(a=>a.code!=='arrival').map(community),
  {...local('month','时光初见','时光','稀有','community',Shell,'#ab8070','邯院通社区账号注册满 30 天','从初见，到熟悉的日常。',30),metric:'days'},
  {...local('year','四季流转','时光','史诗','community',Waves,'#8b70ab','邯院通社区账号注册满 365 天','你与邯院，已经走过春夏秋冬。',365),metric:'days'},
  local('goldfish','你发现我了','隐藏','稀有','device',Fish,'#cc8054','在关于页唤醒小金鱼','它悄悄在纪念册里吐了一个泡泡。'),
];
function community(a:typeof awards[number]):Collectible {
  const names:Record<string,string>={arrival:'破壳而出',hello:'搭个话吧',neighbor:'温暖的回应'};
  return {...a,name:names[a.code]??a.name,source:'community',group:a.code==='arrival'?'初识':'社区',color:a.code==='liked'?'#c76c79':'#8670a7'};
}
export const byCode = new Map(catalog.map(a=>[a.code,a]));
export const lifeCodes=['bath','laundry','map'];
export const sourceNames:Record<Source,string>={device:'本机',school:'当前教务连接',learning:'当前学习通账号',community:'邯院通账号'};
export const tierIcons={普通:BookOpen,稀有:NotebookPen,史诗:Shell,传奇:GraduationCap};

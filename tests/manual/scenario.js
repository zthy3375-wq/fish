import {createApp} from 'vue';import App from '../../src/App.vue';import '../../src/style.css';import '../../src/home-courses.css';import {mockAcademicProvider} from '../../src/services/academic';
const p=new URLSearchParams(location.search), scenario=p.get('scenario')||'six';
const load=mockAcademicProvider.load.bind(mockAcademicProvider);
mockAcademicProvider.load=async()=>{const data=await load();const today=data.courses.filter(c=>c.day===4);if(scenario==='zero')data.courses=[];if(scenario==='one')data.courses=[today[1]];if(scenario==='six'||scenario==='long'){data.courses=Array.from({length:6},(_,i)=>({...today[i%3],id:'qa-'+i,day:4,start:['08:00','09:00','10:00','11:00','14:00','16:00'][i],end:['08:50','09:50','10:50','11:50','15:35','17:35'][i],name:scenario==='long'?'智能制造装备与系统集成课程设计及应用实践 AdvancedManufacturingSystemsIntegrationSuperLongCourseName '+(i+1):today[i%3].name,weeks:[9]}))}return data};
const BaseDate=Date,frozen=BaseDate.parse('2026-11-05T02:15:00Z');globalThis.Date=class extends BaseDate{constructor(...args){super(...(args.length?args:[frozen]))}static now(){return frozen}};
if(p.get('theme'))localStorage.setItem('handan-campus.preferences.v1',JSON.stringify({name:'同学',major:'智能制造工程 · 2026级（模拟）',theme:p.get('theme'),notifications:true,compact:false}));
createApp(App).mount('#app');

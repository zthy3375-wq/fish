/** Integration UI check with synthetic native responses; NEVER school-account verification. */
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {chromium} from 'playwright';
const root=path.resolve('dist'),output='/tmp/handan-v050-qa';await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file))}catch{res.writeHead(404);res.end()}});
await new Promise(resolve=>server.listen(4175,'127.0.0.1',resolve));
const browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined,args:['--no-sandbox']});const checks=[];
function assert(value,label){if(!value)throw Error(label);checks.push(label)}
try{
 for(const width of [360,390,430]){
  const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
  await context.addInitScript(()=>{
   const methods={HandanAcademicClient:['login','syncAll','getTimetable','getGrades','getExams','getSessionState','logout','getClassroomOptions','getFreeClassrooms','getClassroomDay'],Preferences:['get','set'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
   window.androidBridge={};window.__academicCalls=[];
   window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),nativePromise:async(plugin,method,args)=>{
    if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set'){localStorage.setItem(args.key,args.value);return {}}}
    if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};
    if(plugin==='HandanAcademicClient'){
     window.__academicCalls.push(method);
     if(method==='logout')return {session:'disconnected'};
     if(method==='getClassroomOptions')return {session:'valid',classrooms:{status:'ok',data:{term:{xnm:'2026',xqm:'3'},campusId:'1',terms:[{id:'2026-3',name:'人工学期'}],campuses:[{id:'1',name:'人工校区'}],buildings:[{id:'b1',name:'人工教学楼'},{id:'b2',name:'另一教学楼'}],periods:[{number:1,start:'08:00',end:'08:40'},{number:2,start:'08:45',end:'09:25'},{number:3,start:'09:45',end:'10:25'}],weeks:Array.from({length:19},(_,i)=>i+1),weekStartDate:'2026-09-14',minDate:'2026-09-14',maxDate:'2027-01-24'}}};
     if(method==='getFreeClassrooms'){
      if(window.__roomFailure)throw Error('network');
      return {session:'valid',classrooms:{status:'ok',data:{query:args,total:1,periods:[{number:1,start:'08:00',end:'08:40'},{number:2,start:'08:45',end:'09:25'},{number:3,start:'09:45',end:'10:25'}],rooms:[{id:'r1',termRoomId:'tr1',number:'R001',name:'人工测试教室',buildingId:'b1',building:'人工教学楼',campus:'人工校区',type:'测试类型',capacity:40}]}}};
     }
     if(method==='getClassroomDay')return {session:'valid',classrooms:{status:'ok',data:{roomId:args.roomId,date:args.date,slots:[{number:1,start:'08:00',end:'08:40',state:'free'},{number:2,start:'08:45',end:'09:25',state:'occupied'},{number:3,start:'09:45',end:'10:25',state:'unknown'}]}}};
     const timetable={term:{xnm:'2026',xqm:'3'},kbList:[{kcmc:'人工 UI 链路课程',xm:'教师',cdmc:'教室',xqj:'1',jcs:'1-2',zcd:'1-18周'}],practice:[]};
     return {session:'valid',modules:method==='getGrades'?{grades:{status:'ok',data:[{name:'人工 UI 链路成绩',scoreText:'优秀',credit:2,gpa:4,term:'2026 秋季',kind:'必修'}]}}:method==='getExams'?{exams:{status:'ok',data:[]}}:{timetable:{status:'ok',data:timetable}}};
    }return {};
   }};
  });
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:4175');
  await page.getByRole('button',{name:'连接邯郸学院',exact:true}).click();
  await page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'课表',exact:true}).click();
  await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();
  assert(await page.locator('.floating-nav button').count()===4,`${width}: four navigation tabs`);
  await page.reload();await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();
  assert(await page.evaluate(()=>!!localStorage.getItem('handan.academic.cache.v050')),`${width}: school cache survives reload`);
  await page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'教务',exact:true}).click();
  await page.getByRole('button',{name:/成绩查询/}).first().click();
  await page.getByText('人工 UI 链路成绩',{exact:true}).waitFor();
  assert(await page.getByText('优秀',{exact:true}).count()===1,`${width}: native grade text displayed without fake score`);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${width}: no horizontal overflow`);
  await page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'首页',exact:true}).click();
  const homeRoomEntry=page.getByRole('button',{name:'空闲教室',exact:true});await homeRoomEntry.waitFor();
  assert(await homeRoomEntry.evaluate(el=>el.getBoundingClientRect().top)<180,`${width}: classroom shortcut at top of home`);
  await page.screenshot({path:path.join(output,`classroom-home-entry-${width}.png`),fullPage:true,animations:'disabled'});
  await homeRoomEntry.click();await page.getByLabel('查询日期',{exact:true}).waitFor();await page.getByRole('button',{name:'返回上一页',exact:true}).click();await homeRoomEntry.waitFor();
  assert(await page.locator('.floating-nav button.active').innerText()==='首页',`${width}: classroom shortcut returns to home`);
  await page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'教务',exact:true}).click();
  await page.getByRole('button',{name:/管理个人课表/}).waitFor();
  const academicRoomEntry=page.getByRole('button',{name:'空闲教室',exact:true});await academicRoomEntry.waitFor();
  assert(await academicRoomEntry.evaluate(el=>el.getBoundingClientRect().top)<180,`${width}: classroom first entry in academic`);
  assert(await page.getByRole('button',{name:/空闲教室/}).count()===1,`${width}: no duplicate academic classroom row`);
  await page.screenshot({path:path.join(output,`classroom-academic-entry-${width}.png`),fullPage:true,animations:'disabled'});
  await academicRoomEntry.click();
  await page.getByLabel('查询日期',{exact:true}).fill('2026-11-06');
  await page.getByRole('combobox',{name:'教学楼',exact:true}).selectOption('b1');
  await page.getByRole('button',{name:'查询空闲教室',exact:true}).click();
  await page.getByText('人工测试教室',{exact:true}).waitFor();
  assert(await page.getByText(/查询范围内空闲/).count()===1,`${width}: school query ranges displayed`);
  await page.getByRole('button',{name:/人工测试教室/}).click();
  await page.getByText('占用',{exact:true}).waitFor();
  assert(await page.getByText('未知',{exact:true}).count()===1,`${width}: unknown day slots stay unknown`);
  assert(await page.getByRole('combobox',{name:'教室教学周'}).inputValue()==='8',`${width}: uses school rather than personal week`);
  await page.screenshot({path:path.join(output,`classrooms-results-${width}.png`),fullPage:true,animations:'disabled'});
  await page.evaluate(()=>window.__roomFailure=true);
  await page.getByRole('button',{name:'查询空闲教室',exact:true}).click();
  await page.getByRole('alert').waitFor();
  assert(await page.getByText(/当前空闲状态未知/).count()>0,`${width}: failed refresh labels old results unknown`);
  await page.getByRole('combobox',{name:'教学楼',exact:true}).selectOption('b2');
  assert(await page.getByText('人工测试教室',{exact:true}).count()===0,`${width}: different filters invalidate old results`);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${width}: classrooms no horizontal overflow`);
  await page.screenshot({path:path.join(output,`classrooms-${width}.png`),fullPage:true});
  assert(!errors.length,`${width}: no runtime errors`);
  await page.screenshot({path:path.join(output,`records-${width}.png`),fullPage:true});await context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({source:'synthetic-native-ui-test',schoolAccountVerified:false,checks},null,2));console.log(checks.join('\n'));
}finally{await browser.close();server.close()}

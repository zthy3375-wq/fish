/** Integration UI check with synthetic native responses; NEVER school-account verification. */
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {chromium} from 'playwright';
const root=path.resolve('dist'),output='/tmp/handan-v050-qa';await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file))}catch{res.writeHead(404);res.end()}});
await new Promise(resolve=>server.listen(4175,'127.0.0.1',resolve));
const browser=await chromium.launch({args:['--no-sandbox']});const checks=[];
function assert(value,label){if(!value)throw Error(label);checks.push(label)}
try{
 for(const width of [360,390,430]){
  const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
  await context.addInitScript(()=>{
   const methods={HandanAcademicClient:['login','syncAll','getTimetable','getGrades','getExams','getSessionState','logout'],Preferences:['get','set'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
   window.androidBridge={};window.__academicCalls=[];
   window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),nativePromise:async(plugin,method,args)=>{
    if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set'){localStorage.setItem(args.key,args.value);return {}}}
    if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};
    if(plugin==='HandanAcademicClient'){
     window.__academicCalls.push(method);
     if(method==='logout')return {session:'disconnected'};
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
  assert(!errors.length,`${width}: no runtime errors`);
  await page.screenshot({path:path.join(output,`records-${width}.png`),fullPage:true});await context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({source:'synthetic-native-ui-test',schoolAccountVerified:false,checks},null,2));console.log(checks.join('\n'));
}finally{await browser.close();server.close()}

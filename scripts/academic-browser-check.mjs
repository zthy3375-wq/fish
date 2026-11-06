/** Synthetic native UI regression; no school account or credentials are used. */
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {chromium} from 'playwright';
const root=path.resolve('dist'),output='/tmp/handan-v051-qa';await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file))}catch{res.writeHead(404);res.end()}});
await new Promise(resolve=>server.listen(4175,'127.0.0.1',resolve));
let browser;const checks=[];
function assert(value,label){if(!value)throw Error(label);checks.push(label)}
try{
 browser=await chromium.launch({args:['--no-sandbox']});
 for(const width of [360,390,430]){
  const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
  await context.addInitScript(()=>{
   const methods={HandanAcademicClient:['login','syncAll','getTimetable','getGrades','getExams','getSessionState','logout'],Preferences:['get','set'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
   window.androidBridge={};window.__academicCalls=[];window.__nativeListeners={};window.__appExits=0;window.__offline=false;
   window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:name==='addListener'?'callback':'promise'}))})),
    nativeCallback:(_plugin,_method,args,callback)=>{window.__nativeListeners[args.eventName]=callback;return args.eventName},
    nativePromise:async(plugin,method,args)=>{
     if(plugin==='App'&&method==='exitApp'){window.__appExits++;return {}}
     if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set'){localStorage.setItem(args.key,args.value);return {}}}
     if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};
     if(plugin==='HandanAcademicClient'){
      window.__academicCalls.push(method);if(window.__offline)throw Error('offline');
      if(method==='logout')return {session:'disconnected'};
      const timetable={term:args?.xnm?args:{xnm:'2026',xqm:'3'},kbList:[{kcmc:'人工 UI 链路课程',xm:'教师',cdmc:'教室',xqj:'1',jcs:'1-2',zcd:'1-18周'}],practice:[]};
      return {session:'valid',modules:method==='getGrades'?{grades:{status:'ok',data:[{name:'人工 UI 链路成绩',scoreText:'优秀',credit:2,gpa:4,term:'2026 秋季',kind:'必修'},{name:'历史测试成绩',scoreText:'90',credit:1,gpa:4,term:'2025 秋季',kind:'必修'}]}}:method==='getExams'?{exams:{status:'ok',data:[]}}:{timetable:{status:'ok',data:timetable},semesters:{status:'ok',data:[{xnm:'2026',xqm:'3'},{xnm:'2025',xqm:'3'}]}}};
     }return {};
    }};
  });
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  const tab=name=>page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name,exact:true});
  const frame=()=>page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const nativeBack=()=>page.evaluate(()=>window.__nativeListeners.backButton({canGoBack:true}));
  const shot=async name=>{await frame();await page.waitForFunction(()=>document.getAnimations().every(a=>a.playState==='finished'));await page.screenshot({path:path.join(output,`${name}-${width}.png`),fullPage:true,animations:'disabled'})};
  await page.goto('http://127.0.0.1:4175');
  await page.getByRole('button',{name:'连接邯郸学院',exact:true}).click();
  await tab('课表').click();await page.getByRole('combobox',{name:'课表学期'}).waitFor();
  await page.getByRole('combobox',{name:'跳转教学周'}).selectOption('2');
  await page.getByRole('button',{name:'日视图',exact:true}).click();await page.locator('.week-days button').first().click();
  await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();
  assert(await page.locator('.floating-nav button').count()===4,`${width}: four tabs`);
  assert(await page.getByRole('button',{name:'打开侧边栏'}).count()===0,`${width}: no drawer`);
  assert(await page.locator('.schedule-actions').count()===0,`${width}: no schedule action strip`);
  const historyLength=await page.evaluate(()=>history.length);
  await tab('我的').click();await tab('课表').click();
  assert(await page.getByRole('combobox',{name:'跳转教学周'}).inputValue()==='2',`${width}: week survives tabs`);
  assert(await page.getByRole('button',{name:'日视图',exact:true}).getAttribute('aria-pressed')==='true',`${width}: day view survives tabs`);
  assert(await page.locator('.week-days button').first().getAttribute('aria-pressed')==='true',`${width}: selected day survives tabs`);
  await page.getByRole('combobox',{name:'课表学期'}).selectOption('2025-3');
  await page.getByRole('combobox',{name:'跳转教学周'}).selectOption('5');await tab('首页').click();await tab('课表').click();
  assert(await page.getByRole('combobox',{name:'课表学期'}).inputValue()==='2025-3',`${width}: selected semester survives tabs`);
  await page.getByRole('combobox',{name:'课表学期'}).selectOption('2026-3');
  await page.waitForFunction(()=>document.querySelector('[aria-label="跳转教学周"]').value==='2');
  await page.getByRole('button',{name:'周视图',exact:true}).click();
  await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();await shot('schedule');
  const gridTop=await page.locator('.period-grid').evaluate(el=>el.getBoundingClientRect().top);
  assert(gridTop<330,`${width}: grid visible in first screen`);
  await page.locator('main').evaluate(el=>el.scrollTop=280);const scroll=await page.locator('main').evaluate(el=>el.scrollTop);
  await tab('我的').click();await tab('课表').click();await frame();
  assert(Math.abs(await page.locator('main').evaluate(el=>el.scrollTop)-scroll)<3,`${width}: timetable scroll restored`);
  assert(await page.evaluate(()=>history.length)===historyLength,`${width}: tab switches do not accumulate browser history`);
  await page.getByRole('button',{name:'查看通知'}).click();await nativeBack();
  await page.getByRole('dialog').waitFor({state:'hidden'});
  assert(await page.locator('.floating-nav button.active').innerText()==='课表',`${width}: Android back closes overlay before leaving tab`);
  await page.getByRole('button',{name:'添加个人事项',exact:true}).click();await page.getByRole('dialog').waitFor();
  await page.getByLabel('课程名称').fill('未保存测试事项');await nativeBack();await page.getByRole('alertdialog').waitFor();
  await nativeBack();await page.getByRole('alertdialog').waitFor({state:'hidden'});
  assert(await page.getByRole('dialog').isVisible(),`${width}: back closes discard confirmation first`);
  await nativeBack();await page.getByRole('button',{name:'放弃修改',exact:true}).click();await page.getByRole('dialog').waitFor({state:'hidden'});
  await tab('教务').click();await frame();assert(await page.locator('main').evaluate(el=>el.scrollTop)===0,`${width}: new root starts at top`);await shot('academic');
  assert(await page.getByRole('button',{name:/成绩查询/}).count()===1,`${width}: one academic grade entry`);
  await page.getByRole('button',{name:/成绩查询/}).click();
  await page.getByRole('combobox',{name:'成绩学期'}).selectOption('2026 秋季');await page.getByRole('textbox',{name:'搜索成绩课程'}).fill('人工 UI');
  assert(await page.getByText('优秀',{exact:true}).count()===1,`${width}: native grade text retained`);
  await tab('我的').click();await shot('profile');await tab('教务').click();await page.getByRole('button',{name:/成绩查询/}).click();
  assert(await page.getByRole('combobox',{name:'成绩学期'}).inputValue()==='2026 秋季'&&await page.getByRole('textbox',{name:'搜索成绩课程'}).inputValue()==='人工 UI',`${width}: grade filters survive tabs`);
  await nativeBack();assert(await page.locator('h1').innerText()==='教务中心',`${width}: Android back returns academic origin`);
  await tab('首页').click();await shot('home');await page.getByRole('button',{name:/成绩查询/}).click();
  await page.getByRole('button',{name:'返回上一页',exact:true}).click();assert(await page.locator('.floating-nav button.active').innerText()==='首页',`${width}: grade shortcut returns home origin`);
  await tab('课表').click();await page.reload();await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();
  assert(await page.evaluate(()=>!!localStorage.getItem('handan.academic.cache.v050')),`${width}: school cache survives reload`);
  // A failed native refresh must retain the previously committed school data.
  await page.evaluate(()=>window.__offline=true);await tab('首页').click();await page.getByRole('button',{name:'刷新',exact:true}).click();await tab('课表').click();
  await page.getByText('人工 UI 链路课程',{exact:true}).first().waitFor();
  assert(await page.evaluate(()=>window.__appExits)===0,`${width}: no accidental native exit`);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${width}: no horizontal overflow`);
  assert(await page.locator('main').evaluate(el=>el.getBoundingClientRect().bottom<=document.querySelector('.navigation-dock').getBoundingClientRect().top+1),`${width}: dock does not cover scroll area`);
  assert(!errors.length,`${width}: no runtime errors`);await context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({source:'synthetic-native-ui-test',schoolAccountVerified:false,checks},null,2));console.log(checks.join('\n'));
}finally{await browser?.close();server.close()}

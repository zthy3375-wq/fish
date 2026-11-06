/** Run after normal + diagnostic builds. Browser bridge is a test double, NOT Android/school login verification. */
import {createServer} from 'node:http';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import path from 'node:path';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root=process.cwd(), output=process.env.QA_OUTPUT || '/tmp/handan-v042-qa';
await mkdir(output,{recursive:true});
async function serve(directory,port){
 const server=createServer(async(req,res)=>{try{
   const file=new URL(req.url,'http://localhost').pathname;
   const resolved=path.resolve(directory,'.'+(file==='/'?'/index.html':file));
   if(!resolved.startsWith(path.resolve(directory)+path.sep))throw Error('path');
   const data=await readFile(resolved);
   const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'};
   res.setHeader('Content-Type',mime[path.extname(resolved)]||'application/octet-stream');res.end(data);
 }catch{res.statusCode=404;res.end('not found')}});
 await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));return server;
}
const diagnostic=await serve(process.env.DIAGNOSTIC_DIST || path.join(root,'dist'),4173);
const normal=await serve(process.env.NORMAL_DIST || '/tmp/handan-normal-web',4174);
const browser=await chromium.launch({...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{}),args:['--no-sandbox']});
let checks=[];
function assert(value,label){if(!value)throw Error(label);checks.push(label);}
async function pageFor(viewport,options={}){
 const context=await browser.newContext({viewport,serviceWorkers:'block',colorScheme:options.dark?'dark':'light'});
 await context.addInitScript((options)=>{
  window.__nativeCalls=[];window.__files=[];window.__shared=[];window.__prefs={};
  window.androidBridge={};
  const definitions={AcademicDiagnostics:['getCapabilities','openOfficialBrowser','checkCurrentPage','openSchoolWindow'],
   App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setOverlaysWebView','setBackgroundColor'],
   Preferences:['get','set'],LocalNotifications:['getPending','cancel','checkPermissions'],
   Filesystem:['writeFile','deleteFile'],Share:['share']};
  window.Capacitor={PluginHeaders:Object.entries(definitions).map(([name,methods])=>({name,methods:methods.map(name=>({name,rtype:'promise'}))})),
   nativePromise:async(plugin,method,args)=>{
    window.__nativeCalls.push({plugin,method});
    if(plugin==='AcademicDiagnostics'){
     if(method==='openSchoolWindow') return {observation:{container:'kbList',fields:{courseName:true,teacher:true,room:true,weekday:true,periods:true,weeks:true},recordCount:1,invalidCount:0,specialArrangements:false,exportControl:false,frameLimit:false},kbList:[{kcmc:'本地 UI 测试课程',xm:'测试教师',cdmc:'测试位置',xqj:'1',jcs:'1-2',zcd:'1-16周(单)'}]};
     if(method==='getCapabilities')return {enabled:options.nativeEnabled!==false,canReadPage:false,schoolPermission:'unverified',browser:'external-system-browser'};
     if(method==='openOfficialBrowser'){if(options.failBrowser)throw {code:'NETWORK_UNAVAILABLE',message:'PRIVATE'};return {opened:true,loginStatus:'not-observable'}}
     if(method==='checkCurrentPage'){if(options.stallCheck)return new Promise(()=>{});return {readPerformed:false,reason:'permission-and-browser-isolation'}}
    }
    if(plugin==='Preferences'){
     if(method==='get')return {value:window.__prefs[args.key]??null};
     if(method==='set'){window.__prefs[args.key]=args.value;return {}}
    }
    if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};
    if(plugin==='Filesystem'){window.__files.push({method,args});return {uri:'content://qa/report'}}
    if(plugin==='Share'){window.__shared.push(args);return {}}
    return {};
   }};
  Object.defineProperty(navigator,'clipboard',{value:{writeText:async(text)=>{window.__copied=text}}});
 },options);
 const page=await context.newPage();return {context,page};
}
async function enter(page){
 await page.goto('http://127.0.0.1:4173/#/academic/official');
 await page.getByRole('button',{name:'测试教务连接 · 开发者诊断'}).click();
 await page.getByRole('heading',{name:'连接学校教务',exact:true}).waitFor();
 await page.getByText('我了解登录不等于授权 fish').click();
}
try {
 for(const [width,height]of [[360,800],[390,844],[430,932]]){
  const {context,page}=await pageFor({width,height},{dark:width===390});
  const outbound=[];page.on('request',r=>{if(!r.url().startsWith('http://127.0.0.1'))outbound.push(r.url())});
  await enter(page);
  assert(await page.getByRole('button',{name:'检测当前课表页面',exact:true}).isDisabled(),`${width}: check requires browser handoff`);
  await page.getByRole('button',{name:'打开学校官方网页',exact:true}).click();
  await page.getByRole('button',{name:'检测当前课表页面',exact:true}).click();
  await page.getByLabel('脱敏 JSON 报告').waitFor();
  const report=JSON.parse(await page.getByLabel('脱敏 JSON 报告').innerText());
  assert(report.pageRead===false&&report.officialLogin==='not-observable',`${width}: browser is not authentication`);
  assert(report.result==='blocked'&&report.fields.courseName==='unknown',`${width}: unknown structure stays unknown`);
  const prefs=await page.evaluate(()=>JSON.stringify(window.__prefs));
  await page.getByRole('button',{name:'运行人工样本解析自检',exact:true}).click();
  const fixture=JSON.parse(await page.getByLabel('脱敏 JSON 报告').innerText());
  assert(fixture.source==='synthetic-offline-self-test'&&fixture.result==='passed',`${width}: synthetic parser test clearly labeled`);
  assert(await page.evaluate(()=>JSON.stringify(window.__prefs))===prefs,`${width}: personal timetable unchanged`);
  assert(await page.getByRole('button',{name:'导出 JSON',exact:true}).isDisabled(),`${width}: export requires review`);
  await page.getByText('我已审核以上脱敏 JSON').click();
  await page.getByRole('button',{name:'复制',exact:true}).click();
  assert(await page.evaluate(()=>JSON.parse(window.__copied).source==='synthetic-offline-self-test'),`${width}: reviewed copy`);
  await page.getByRole('button',{name:'导出 JSON',exact:true}).click();
  await page.waitForFunction(()=>window.__files.some(x=>x.method==='deleteFile'));
  assert(await page.evaluate(()=>window.__shared.length===1&&window.__files.length===2),`${width}: explicit export then temporary file cleanup`);
  await page.screenshot({path:path.join(output,`diagnostic-${width}.png`),fullPage:true});
  const bounds=await page.evaluate(()=>{const main=document.querySelector('main');main.scrollTop=main.scrollHeight;
   return {page:document.documentElement.scrollWidth<=innerWidth,main:main.scrollWidth<=main.clientWidth+1,
    last:document.querySelector('.diagnostic-footer').getBoundingClientRect().bottom,
    nav:document.querySelector('.floating-navigation, .floating-nav, nav')?.getBoundingClientRect().top}});
  assert(bounds.page&&bounds.main,`${width}: no horizontal overflow`);
  assert(!bounds.nav||bounds.last<=bounds.nav,`${width}: final controls clear navigation`);
  await page.getByRole('button',{name:'取消本次诊断',exact:true}).click();
  assert(await page.getByRole('button',{name:'打开学校官方网页',exact:true}).isDisabled(),`${width}: consent cancellation resets actions`);
  await page.getByRole('button',{name:'删除报告',exact:true}).click();
  assert(await page.getByLabel('脱敏 JSON 报告').count()===0,`${width}: report deleted`);
  await page.getByRole('button',{name:'返回官方教务',exact:true}).click();
  assert(page.url().endsWith('/academic/official'),`${width}: back navigation`);
  assert(outbound.length===0,`${width}: no automatic remote upload/request`);
  // Test actual Vue preview/save path with an explicitly synthetic native bridge result.
  await page.getByRole('button',{name:'测试教务连接 · 开发者诊断'}).click();
  await page.getByText('我了解登录不等于授权 fish').click();
  await page.getByRole('button',{name:'登录邯郸学院教务系统 · 实验窗口',exact:true}).click();
  await page.getByText('本地 UI 测试课程',{exact:true}).waitFor();
  assert(await page.getByRole('button',{name:'确认保存独立学校课表',exact:true}).isDisabled(),`${width}: course import requires explicit review`);
  await page.getByText('我已逐门核对官方课表').click();
  await page.getByRole('button',{name:'确认保存独立学校课表',exact:true}).click();
  await page.getByText('学校网页导入 · 已保存到独立本机学期').waitFor();
  assert(await page.evaluate(()=>Object.values(window.__prefs).some(v=>v.includes('school-page-'))),`${width}: school data saved in new semester partition`);
  await context.close();
 }
 for(const [port,nativeEnabled,label]of [[4174,true,'production build'],[4173,false,'native gate disabled']]){
  const {context,page}=await pageFor({width:390,height:844},{nativeEnabled});
  await page.goto(`http://127.0.0.1:${port}/#/academic/official`);
  await page.waitForTimeout(200);
  assert(await page.getByRole('button',{name:'测试教务连接 · 开发者诊断'}).count()===0,`${label}: entry hidden`);
  await page.goto(`http://127.0.0.1:${port}/#/academic/diagnostics`);
  await page.waitForTimeout(150);
  assert(await page.getByRole('heading',{name:'连接学校教务',exact:true}).count()===0,`${label}: direct route blocked`);
  await context.close();
 }
 const failure=await pageFor({width:360,height:800},{failBrowser:true});await enter(failure.page);
 await failure.page.getByRole('button',{name:'打开学校官方网页',exact:true}).click();
 await failure.page.getByRole('alert').waitFor();
 assert(!(await failure.page.getByRole('alert').innerText()).includes('PRIVATE'),'browser error is sanitized');await failure.context.close();
 const stalled=await pageFor({width:390,height:844},{stallCheck:true});await enter(stalled.page);
 await stalled.page.getByRole('button',{name:'打开学校官方网页',exact:true}).click();
 await stalled.page.getByRole('button',{name:'检测当前课表页面',exact:true}).click();
 await stalled.page.getByRole('button',{name:'取消本次诊断',exact:true}).click();
 assert(await stalled.page.getByLabel('脱敏 JSON 报告').count()===0,'cancelled in-flight diagnosis creates no report');await stalled.context.close();
 await writeFile(path.join(output,'browser-results.json'),JSON.stringify({bridge:'test-double',realAndroidLogin:false,checks},null,2));
 console.log(JSON.stringify({checks:checks.length,passed:true,output}));
} finally {await browser.close();await new Promise(r=>diagnostic.close(r));await new Promise(r=>normal.close(r));}

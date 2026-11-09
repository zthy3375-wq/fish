/** Integration UI check with synthetic native responses; NEVER school-account verification. */
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {chromium} from 'playwright';
import {checkParcelShortcuts} from './parcel-browser-check.mjs';
import {checkNativeLife} from './native-life-browser-check.mjs';
const root=path.resolve('dist'),output='/tmp/handan-v050-qa';await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file))}catch{res.writeHead(404);res.end()}});
await new Promise(resolve=>server.listen(4175,'127.0.0.1',resolve));
const browser=await chromium.launch({args:['--no-sandbox'],executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined});const checks=[];let activePage;
const syntheticLearning=JSON.parse(await readFile('tests/fixtures/learning/synthetic.json','utf8'));
const syntheticGrades=JSON.parse(await readFile('tests/fixtures/grades/synthetic.json','utf8'));
function assert(value,label){if(!value)throw Error(label);checks.push(label)}
try{
 for(const width of [360,390,430]){
  const context=await browser.newContext({viewport:{width,height:740},serviceWorkers:'block'});
  await context.addInitScript(learning=>{window.__learningFixture=learning},syntheticLearning);
  await context.addInitScript(grades=>{
   const methods={AppUpdate:['getState','check','download','install'],PangguaiCampus:['getSnapshot','login','refresh','logout','scan','openRecharge','quoteLaundry','startLaundry','pollLaundry','cancelLaundry','prepareWater','startWater','pollWater','endWater','confirmPhysicalWaterEnd','openWaterPaymentSetup'],PangguaiOfficial:['open'],ParcelShortcuts:['open'],QuzhiCampus:['getSnapshot','login','refresh','logout','openRecharge'],ChaoxingClient:['login','syncAll','getSessionState','openItem','openPortal','logout'],HandanAcademicClient:['login','syncAll','getTimetable','getGrades','getExams','getSessionState','logout'],Preferences:['get','set'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
   window.androidBridge={};window.__parcelCalls=[];window.__academicCalls=[];window.__learningCalls=[];window.__quzhiCalls=[];window.__quzhiState={connected:false,expired:false,phone:''};
   window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),nativePromise:async(plugin,method,args)=>{
    if(plugin==='AppUpdate'){
     window.__updateState??={currentVersion:'1.0.1',currentCode:101,stage:'idle',progress:0,error:'',available:false,mandatory:false,checkedAt:Date.now()};
     if(method==='download'){window.__updateState.stage='ready';window.__updateDownloaded=true}
     if(method==='install')return {status:'permission'};
     return JSON.parse(JSON.stringify(window.__updateState));
    }
    if(plugin==='PangguaiCampus'){
     (window.__pgCalls??=[]).push({method,args});
     window.__pgState??={connected:false,expired:false,phone:''};
     if(method==='login')window.__pgState={connected:true,expired:false,phone:'138****0000',balance:'18.50',walletUpdatedAt:Date.now()};
     if(method==='logout')window.__pgState={connected:false,expired:false,phone:''};
     if(method==='refresh'){if(window.__pgFailure)window.__pgState.issues={wallet:'NETWORK',tickets:'NETWORK',orders:'NETWORK'};else Object.assign(window.__pgState,{tickets:[{id:'synthetic-water-merchant',name:'邯郸学院直饮水机',balance:'257',principal:'257',gift:'0'},{id:'synthetic-merchant',name:'人工测试商户',balance:'120',principal:'100',gift:'20'}],ticketsUpdatedAt:Date.now(),orders:[{id:'synthetic-order',name:'人工测试洗衣机',amount:'3.50',status:'测试状态',time:'2026-11-08 10:00'}],ordersUpdatedAt:Date.now(),issues:{}})}
     if(method==='openRecharge')return {opened:true};
     if(method==='scan'&&window.__pgWater)return {id:'synthetic-water',name:'人工测试饮水机',operator:'人工测试商户',category:'04',payment:'after',issue:'',skus:[{id:'synthetic-outlet',name:'常温水',feature:'按实际用量计费',price:'1',available:true}]};
     if(method==='scan')return {id:'synthetic-device',name:'人工测试设备',operator:'人工测试商户',category:'00',payment:'before',issue:'',skus:[{id:'synthetic-sku',name:'标准洗',price:'3.50',feature:'约40分钟',available:true}]};
     if(method==='quoteLaundry')return {id:'synthetic-quote',expiresAt:Date.now()+60000,deviceName:'人工测试设备',program:'标准洗',amount:'3.50',channels:[{id:'2',name:'余额支付',available:true,reason:''}]};
     if(method==='startLaundry')window.__pgState.laundry={id:'synthetic-session',deviceId:'synthetic-device',deviceName:'人工测试设备',program:'标准洗',amount:'3.50',phase:'paid',orderNo:'synthetic-order-no',updatedAt:Date.now(),paySent:true};
     if(method==='prepareWater')return {id:'water-quote',expiresAt:Date.now()+60000,deviceId:'synthetic-water',deviceName:'人工测试饮水机',outlet:'常温水',feature:'按实际用量计费',price:'1',remoteEnd:true,paymentName:'支付宝免密',canStart:true,reason:''};
     if(method==='startWater')window.__pgState.water={id:'water-session',deviceId:'synthetic-water',deviceName:'人工测试饮水机',outlet:'常温水',feature:'按实际用量计费',paymentName:'支付宝免密',phase:'using',orderNo:'synthetic-water-order',remoteEnd:true,updatedAt:Date.now(),startedAt:Date.now()};
     if(method==='endWater')Object.assign(window.__pgState.water,{phase:'ending',endSent:true});
     if(method==='pollWater'&&window.__pgWaterEnded)Object.assign(window.__pgState.water,{phase:'settled',amount:'0.13',endedAt:Date.now()});
     return JSON.parse(JSON.stringify(window.__pgState));
    }
    if(plugin==='PangguaiOfficial'){
     (window.__pangguaiCalls??=[]).push({method,args});
     return {page:args.page,status:window.__pangguaiStatus||'opened'};
    }
    if(plugin==='ParcelShortcuts'){
     window.__parcelCalls.push({method,args});
     if(window.__parcelDelayed)return new Promise(resolve=>{window.__parcelFinish=()=>resolve({provider:args.provider,status:'opened'})});
     return {provider:args.provider,status:window.__parcelStatus||'opened'};
    }
    if(plugin==='QuzhiCampus'){
     window.__quzhiCalls.push({method,args});
     if(method==='login')window.__quzhiState={connected:true,expired:false,phone:'138****0000',school:'人工测试学校',wallet:{total:'12.34',cash:null,gift:null},walletUpdatedAt:Date.now()};
     if(method==='logout')window.__quzhiState={connected:false,expired:false,phone:''};
     if(method==='openRecharge'){window.__quzhiOpened=true;return {opened:true}}
     if(method==='refresh'){
      if(window.__quzhiFailure)window.__quzhiState.issues={wallet:'NETWORK',bills:'NETWORK'};
      else if(window.__quzhiExpired){window.__quzhiState.expired=true;window.__quzhiState.issues={wallet:'AUTH',bills:'AUTH'}}
      else Object.assign(window.__quzhiState,{bills:[{id:'synthetic-1',date:'2026-11-06 08:00',amount:'1.25',description:'人工测试浴室'}],billsMonth:args.month,billsUpdatedAt:Date.now(),issues:{}});
     }
     return JSON.parse(JSON.stringify(window.__quzhiState));
    }
    if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set'){localStorage.setItem(args.key,args.value);return {}}}
    if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};
    if(plugin==='ChaoxingClient'){
     window.__learningCalls.push(method);
     if(method==='logout')return {session:'disconnected'};
     if(method==='openItem'){window.__learningOpened=args.id;window.__learningSubmitted=true;return {closed:true}};
     if(window.__learningFailure)throw Error('network');if(window.__learningExpired)return {session:'expired',code:'AUTH'};
     const data=JSON.parse(JSON.stringify(window.__learningFixture));
     if(method==='login')return {session:'valid',accountKey:data.accountKey,courses:data.courses};
     if(method==='syncAll'&&!args?.courseKeys?.length)return {session:'valid',accountKey:data.accountKey,courses:data.courses,code:'COURSE_SELECTION',nextCursor:null};
     if(window.__learningSubmitted){data.items[0].status='submitted';data.items[0].statusText='待批阅'}return data;
    }
    if(plugin==='HandanAcademicClient'){
     window.__academicCalls.push(method);
     if(method==='logout')return {session:'disconnected'};
     if(method==='getGrades'&&window.__gradeFailure)throw Error('network');
     if(window.__gradeExpired)return {session:'expired'};
     const timetable={term:{xnm:'2026',xqm:'3'},kbList:[{kcmc:'人工 UI 链路课程',xm:'教师',cdmc:'教室',xqj:'1',jcs:'1-2',zcd:'1-18周'},...['高等数学','大学英语','工程制图','大学物理','机械设计'].map((kcmc,i)=>({kcmc,xm:'测试教师',cdmc:'天枢楼'+(201+i),xqj:String(i+2),jcs:i%2?'5-6':'3-4',zcd:'1-18周'}))],practice:[]};
     return {session:'valid',modules:method==='getGrades'?{grades:{status:'ok',scope:'all',data:grades}}:method==='getExams'?{exams:{status:'ok',data:[{name:'人工 UI 考试',date:'2026-11-07',time:'09:00-11:00',room:'测试考场',seat:''}]}}:{timetable:{status:'ok',data:timetable}}};
    }return {};
   }};
  },syntheticGrades);
  const page=await context.newPage(),errors=[];page.setDefaultTimeout(12000);activePage=page;page.on('pageerror',e=>errors.push(e.message));
  await page.clock.setFixedTime(new Date('2026-11-06T04:00:00Z'));
  await page.goto('http://127.0.0.1:4175');
  await page.locator('.life-laundry').click();
  const dialog=page.getByRole('dialog',{name:'胖乖生活钱包'});
  await dialog.getByRole('button',{name:'连接胖乖生活',exact:true}).click();
  await dialog.getByText('人工测试商户',{exact:true}).waitFor();
  await page.evaluate(()=>{window.__pgWater=true;window.__pgState.water={id:'old-session',deviceId:'synthetic-water',deviceName:'上次使用的饮水机',outlet:'常温水',paymentName:'支付宝免密',phase:'settled',amount:'0.13',orderNo:'old-order',startedAt:Date.now()-34000,endedAt:Date.now(),updatedAt:Date.now()}});
  await dialog.getByRole('button',{name:'刷新胖乖余额与记录'}).click();
  const history=dialog.locator('.water-history');
  await history.waitFor();
  assert(await history.getAttribute('open')===null,`${width}: previous settlement collapsed`);
  await history.locator('summary').click();
  assert(await history.innerText().then(s=>s.includes('old-order')),`${width}: previous bill remains accessible`);
  await history.locator('summary').click();
  await dialog.getByRole('button',{name:'扫码识别设备',exact:true}).click();
  const start=dialog.getByRole('button',{name:'接水',exact:true});
  await start.waitFor();
  const visible=await start.evaluate(el=>{const r=el.getBoundingClientRect(),s=el.closest('.overlay-surface').getBoundingClientRect();return r.top>=s.top&&r.bottom<=Math.min(s.bottom,innerHeight)});
  assert(visible,`${width}: water action visible after scan without scrolling`);
  assert(await page.evaluate(()=>window.__pgCalls.filter(c=>c.method==='startWater').length)===0,`${width}: scanning does not start water`);
  await page.screenshot({path:path.join(output,`water-priority-${width}.png`)});
  await start.click();
  const confirm=dialog.getByRole('button',{name:'确认开始接水',exact:true});
  await confirm.waitFor();
  await page.waitForTimeout(500);
  assert(await confirm.evaluate(el=>{const r=el.getBoundingClientRect(),s=el.closest('.overlay-surface').getBoundingClientRect();return r.top>=s.top&&r.bottom<=Math.min(s.bottom,innerHeight)}),`${width}: confirmation visible without manual scrolling`);
  await confirm.click();
  await dialog.getByRole('heading',{name:'接水中',exact:true}).waitFor();
  await dialog.getByRole('button',{name:'结束接水并结算',exact:true}).click();
  await page.evaluate(()=>window.__pgWaterEnded=true);
  await dialog.locator('.water-progress').getByRole('button',{name:'查询状态',exact:true}).click();
  await history.waitFor();
  assert(!(await history.getAttribute('open')),`${width}: new settlement collapses`);
  await dialog.getByRole('button',{name:'扫码识别设备',exact:true}).click();
  await start.waitFor();
  assert(await start.evaluate(el=>{const r=el.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight}),`${width}: repeat scan keeps water action visible`);
  assert(errors.length===0,`${width}: no browser errors`);
  await context.close();
 }
 console.log(JSON.stringify(checks,null,2));
}finally{await browser.close();server.close()}

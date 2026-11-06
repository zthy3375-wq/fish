import {beforeEach,afterEach,it,expect,vi} from 'vitest';
const mocks = vi.hoisted(()=>({platform:'android', native:{
  getCapabilities:vi.fn(),openOfficialBrowser:vi.fn(),checkCurrentPage:vi.fn()},
  writeFile:vi.fn(),deleteFile:vi.fn(),share:vi.fn()}));
vi.mock('@capacitor/core',()=>({Capacitor:{getPlatform:()=>mocks.platform},registerPlugin:()=>mocks.native}));
vi.mock('@capacitor/filesystem',()=>({Filesystem:{writeFile:mocks.writeFile,deleteFile:mocks.deleteFile},Directory:{Cache:'CACHE'},Encoding:{UTF8:'utf8'}}));
vi.mock('@capacitor/share',()=>({Share:{share:mocks.share}}));
let memory:Map<string,string>;
beforeEach(()=>{
  vi.resetModules();vi.clearAllMocks();vi.stubEnv('VITE_ANDROID_DIAGNOSTICS','true');mocks.platform='android';
  mocks.native.getCapabilities.mockResolvedValue({enabled:true});
  mocks.native.openOfficialBrowser.mockResolvedValue({opened:true,loginStatus:'not-observable'});
  mocks.native.checkCurrentPage.mockResolvedValue({readPerformed:false,reason:'permission-and-browser-isolation'});
  mocks.writeFile.mockResolvedValue({uri:'content://local/report'});mocks.deleteFile.mockResolvedValue({});mocks.share.mockResolvedValue({});
  memory=new Map();vi.stubGlobal('localStorage',{getItem:(k:string)=>memory.get(k)??null,setItem:(k:string,v:string)=>memory.set(k,v),removeItem:(k:string)=>memory.delete(k)});
});
afterEach(()=>{vi.unstubAllEnvs();vi.unstubAllGlobals();vi.useRealTimers();});
const service=()=>import('../src/services/academic-diagnostics');
it.each([[false,'android',true],[true,'web',true],[true,'ios',true],[true,'android',false]] as const)('requires both build and native Android gates: %j %s %j',async(build,platform,native)=>{
  const s=await service();expect(s.mayUseDiagnostics(build,platform,native)).toBe(false);
});
it('blocks formal builds before any native call',async()=>{
  vi.stubEnv('VITE_ANDROID_DIAGNOSTICS','false');const s=await service();
  expect(await s.diagnosticAvailability()).toBe(false);
  await expect(s.openDiagnosticBrowser()).rejects.toThrow('专用测试构建');
  expect(mocks.native.getCapabilities).not.toHaveBeenCalled();expect(mocks.native.openOfficialBrowser).not.toHaveBeenCalled();
});
it('blocks an altered web flag if native build has diagnostics disabled',async()=>{
  mocks.native.getCapabilities.mockResolvedValue({enabled:false});const s=await service();
  await expect(s.checkDiagnosticPage()).rejects.toThrow('专用测试构建');
  expect(mocks.native.checkCurrentPage).not.toHaveBeenCalled();
});
it('never treats a browser handoff as authentication or a page read',async()=>{
  const s=await service();expect(await s.openDiagnosticBrowser()).toMatchObject({loginStatus:'not-observable'});
  const report=await s.checkDiagnosticPage();expect(report).toMatchObject({result:'blocked',pageRead:false,personalCoursesParsed:false,
    thirdPartySyncAuthorized:false,automaticSync:false,parserCompatibility:'not-verified'});
  expect(mocks.native.openOfficialBrowser).toHaveBeenCalledWith();
});
it('stops on an unexpected raw/native response rather than exporting it',async()=>{
  mocks.native.checkCurrentPage.mockResolvedValue({readPerformed:true,html:'secret'});
  await expect((await service()).checkDiagnosticPage()).rejects.toThrow('停止生成报告');
});
it.each(['NETWORK_UNAVAILABLE','BROWSER_UNAVAILABLE','BROWSER_BLOCKED','OTHER'])('sanitizes %s browser failures without credentials or raw exception text',async code=>{
  mocks.native.openOfficialBrowser.mockRejectedValue({code,message:'https://evil.invalid/?token=PASSWORD'});
  try{await (await service()).openDiagnosticBrowser();throw Error('missing rejection')}
  catch(e){expect(String(e)).not.toContain('PASSWORD');expect(String(e)).not.toContain('evil.invalid');}
});
it('bounds stalled native operations without labeling school login as failed',async()=>{
  vi.useFakeTimers();const s=await service();const result=s.boundedNative(new Promise(()=>{}),20);
  const expected=expect(result).rejects.toThrow('未判断学校登录状态');await vi.advanceTimersByTimeAsync(25);await expected;
});
it('serializes only closed structural templates, discarding injected identities and credentials everywhere',async()=>{
  const s=await service();const raw={...s.createBoundaryReport(),url:'https://jwgl.hdc.edu.cn/?token=SECRET',
    name:'SECRET',cookie:'SECRET',fields:{courseName:'SECRET'},unknownFieldCount:'SECRET',html:'SECRET',
    reasons:['SECRET'],personalCoursesParsed:true,automaticSync:true};
  const json=s.reportJSON(raw);expect(json).not.toContain('SECRET');expect(JSON.parse(json)).toEqual(s.createBoundaryReport());
  expect(()=>s.reportJSON({...raw,source:'full-html'})).toThrow('停止导出');
  expect(()=>s.reportJSON({...raw,schemaVersion:2})).toThrow('版本');
});
it('saves, restores and deletes only a separate local report key',async()=>{
  const s=await service();memory.set('student-timetable','DO-NOT-MODIFY');
  s.saveDiagnosticReport(s.createBoundaryReport());expect(s.loadDiagnosticReport()).toEqual(s.createBoundaryReport());
  s.deleteDiagnosticReport();expect(s.loadDiagnosticReport()).toBeNull();expect(memory.get('student-timetable')).toBe('DO-NOT-MODIFY');
  expect(mocks.writeFile).not.toHaveBeenCalled();expect(mocks.share).not.toHaveBeenCalled();
});
it('handles corrupt cache and storage failures explicitly',async()=>{
  const s=await service();memory.set('handan-campus.diagnostic-report.v1','{');expect(()=>s.loadDiagnosticReport()).toThrow('无法安全读取');
  memory.set('handan-campus.diagnostic-report.v1','x'.repeat(12001));expect(()=>s.loadDiagnosticReport()).toThrow('异常');
  vi.stubGlobal('localStorage',{setItem:()=>{throw Error('Quota')}});expect(()=>s.saveDiagnosticReport(s.createBoundaryReport())).toThrow('Quota');
});
it('exports only on explicit call and removes the temporary file after share',async()=>{
  const s=await service();const r=s.createBoundaryReport();s.saveDiagnosticReport(r);expect(mocks.share).not.toHaveBeenCalled();
  await s.exportDiagnosticReport(r);expect(mocks.writeFile.mock.calls[0][0].data).toBe(s.reportJSON(r));
  expect(mocks.share).toHaveBeenCalledOnce();expect(mocks.deleteFile).toHaveBeenCalledWith({path:'academic-diagnostic-report.json',directory:'CACHE'});
});
it('cleans the temporary file even when the user cancels export',async()=>{
  mocks.share.mockRejectedValue(Error('cancelled'));const s=await service();await expect(s.exportDiagnosticReport(s.createBoundaryReport())).rejects.toThrow('cancelled');
  expect(mocks.deleteFile).toHaveBeenCalledOnce();
});
it('runs only synthetic offline parser checks and labels every result as non-school data',async()=>{
  const fetch=vi.fn();vi.stubGlobal('fetch',fetch);const {runDiagnosticSelfTest}=await import('../src/services/diagnostic-self-test');
  const result=runDiagnosticSelfTest();expect(result).toMatchObject({source:'synthetic-offline-self-test',result:'passed',pageRead:false,personalCoursesParsed:false});
  expect(fetch).not.toHaveBeenCalled();expect(memory.size).toBe(0);
  expect(JSON.stringify(result)).not.toContain('人工教师');
});

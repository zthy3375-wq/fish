"""Explicitly authorized deployment support; secrets never enter logs/artifacts in plaintext."""
import base64, hashlib, hmac, io, json, os, sys, time, urllib.request
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from tencentcloud.common.credential import Credential
from tencentcloud.scf.v20180416 import models, scf_client
ENV='hanyuantong-d8gjzt1jh12370215'
FUNCTION='hyt-contest-settlement'
KEY=os.environ['CLOUDBASE_API_KEY'].strip()
BACKUP=Path('artifacts/community-rollback.enc')
enc_key=hmac.new(KEY.encode(),b'hyt-community-rollback-v1',hashlib.sha256).digest()
def request(action, data):
    if action=='CreateFunction':
        from tencentcloud.tcb.v20180608 import tcb_client
        control=tcb_client.TcbClient(credential,'ap-shanghai')
        result=json.loads(control.call(action,{'EnvId':ENV,'Stamp':'MINI_QCBASE',**data}))['Response']
        if result.get('SCFErrorCode'): raise RuntimeError('CloudBase function creation: '+result['SCFErrorCode'])
        return result
    return json.loads(client.call(action,{'Namespace':ENV,**data}))['Response']
def wait(name):
    for attempt in range(30):
        try: data=request('GetFunction',{'FunctionName':name})
        except Exception as e:
            if 'ResourceNotFound' not in str(e): raise
            time.sleep(2); continue
        if data.get('Status')=='Active': return
        if data.get('Status') in ('CreateFailed','UpdateFailed'): raise RuntimeError('Function activation failed')
        time.sleep(2)
    raise RuntimeError('Function activation timeout')
req=urllib.request.Request(f'https://{ENV}.ap-shanghai.tcb-api.tencentcloudapi.com/capi/credential',data=json.dumps({'env':ENV}).encode(),headers={'Authorization':'Bearer '+KEY,'Content-Type':'application/json'})
with urllib.request.urlopen(req,timeout=20) as response: creds=json.load(response)['data']
credential=Credential(creds['TmpSecretId'],creds['TmpSecretKey'],creds['Token'])
client=scf_client.ScfClient(credential,'ap-shanghai')
mode=sys.argv[1]
if mode=='backup':
    if os.environ.get('HYT_CONTEST_SCHEMA15_UPGRADE')=='1':
        wait(FUNCTION)
        triggers=request('ListTriggers',{'FunctionName':FUNCTION,'Limit':100}).get('Triggers',[])
        if not any(t['TriggerName']=='hytc-daily-recovery' and (t.get('BindStatus')=='on' or t.get('Enable')==1) for t in triggers):
            raise RuntimeError('Expected an active daily contest recovery trigger')
    config=request('GetFunction',{'FunctionName':'hyt-community'})
    location=request('GetFunctionAddress',{'FunctionName':'hyt-community'})
    with urllib.request.urlopen(location['Url'],timeout=60) as response: code=response.read()
    saved={'config':config,'code':base64.b64encode(code).decode()}
    nonce=os.urandom(12); BACKUP.parent.mkdir(exist_ok=True)
    BACKUP.write_bytes(nonce+AESGCM(enc_key).encrypt(nonce,json.dumps(saved).encode(),None))
    private=Path('/tmp/hyt-existing-environment.json');private.write_text(json.dumps({v['Key']:v['Value'] for v in config.get('Environment',{}).get('Variables',[])}));private.chmod(0o600)
    print('Encrypted deployed code/configuration backup saved')
elif mode in ('prepare-honors','publish-honors-code','restore-honors-code'):
    if os.environ.get('GITHUB_HEAD_REF')!='deploy/community-honors-members-20261120' or os.environ.get('GITHUB_EVENT_NAME')!='pull_request':
        raise RuntimeError('Unexpected community honors deployment context')
    marker=Path('/tmp/hyt-community-honors-code-started')
    staged=Path('/tmp/hyt-community-honors-code.zip')
    if mode=='restore-honors-code' and not marker.exists():
        print('Community function code was unchanged')
        sys.exit(0)
    data=BACKUP.read_bytes()
    backup=json.loads(AESGCM(enc_key).decrypt(data[:12],data[12:],None))
    if mode=='prepare-honors':
        live=base64.b64decode(backup['code'])
        root=Path('cloudbase/functions/community')
        core=(root/'core.mjs').read_bytes()
        baseline=Path('/tmp/hyt-honors-live-before-core.mjs').read_bytes()
        helper=(root/'honor-collection.mjs').read_bytes()
        output=io.BytesIO()
        with ZipFile(io.BytesIO(live)) as previous, ZipFile(output,'w',ZIP_DEFLATED) as candidate:
            matches=[n for n in previous.namelist() if n=='core.mjs' or n.endswith('/core.mjs')]
            if len(matches)!=1: raise RuntimeError('Could not locate the deployed community entry module')
            core_path=matches[0]
            old_core=previous.read(core_path)
            if old_core not in (baseline,core):
                print('Unexpected deployed community source revision:',hashlib.sha256(old_core).hexdigest())
                raise RuntimeError('Community function source differs from the reviewed baseline')
            prefix=core_path.removesuffix('core.mjs')
            helper_path=prefix+'honor-collection.mjs'
            for name in ['server.mjs','database.mjs','contests.mjs','scf_bootstrap']:
                if previous.read(prefix+name)!=(root/name).read_bytes():
                    raise RuntimeError('Baseline gateway component differs: '+name)
            for item in previous.infolist():
                if item.filename==helper_path: continue
                candidate.writestr(item,core if item.filename==core_path else previous.read(item))
            candidate.writestr(helper_path,helper)
        staged.write_bytes(output.getvalue())
        staged.chmod(0o600)
        print('Deployment preserves existing function dependencies, configuration and trigger settings')
    else:
        content=base64.b64encode(staged.read_bytes()).decode() if mode=='publish-honors-code' else backup['code']
        if mode=='publish-honors-code': marker.touch(mode=0o600)
        request('UpdateFunctionCode',{'FunctionName':'hyt-community','CodeSource':'ZipFile','ZipFile':content})
        wait('hyt-community')
        print('Community function code is active' if mode=='publish-honors-code' else 'Previous community function code restored')
elif mode=='worker':
    archive=io.BytesIO(); root=Path('cloudbase/functions/community')
    with ZipFile(archive,'w',ZIP_DEFLATED) as z:
        for name in ['database.mjs','scf.mjs','contest-scheduler.mjs','contest-worker.mjs']: z.write(root/name,name)
        z.writestr('index.js',"let worker;exports.main=async event=>{worker??=(await import('./contest-worker.mjs')).createContestWorker();return worker(event)};")
    code=base64.b64encode(archive.getvalue()).decode()
    variables={'CLOUDBASE_ENV_ID':ENV,'CLOUDBASE_APIKEY':KEY,'CONTEST_CRON_OFFSET_HOURS':'8'}
    environment={'Variables':[{'Key':k,'Value':v} for k,v in variables.items()]}
    try: request('GetFunction',{'FunctionName':FUNCTION}); exists=True
    except Exception as e:
        if 'ResourceNotFound' not in str(e): raise
        exists=False
    if exists:
        request('UpdateFunctionCode',{'FunctionName':FUNCTION,'CodeSource':'ZipFile','ZipFile':code});wait(FUNCTION)
        request('UpdateFunctionConfiguration',{'FunctionName':FUNCTION,'Environment':environment,'MemorySize':128,'Timeout':60});wait(FUNCTION)
    else:
        encrypted=BACKUP.read_bytes()
        original=json.loads(AESGCM(enc_key).decrypt(encrypted[:12],encrypted[12:],None))['config']
        role=original.get('Role') or 'TCB_QcsRole'
        request('CreateFunction',{'FunctionName':FUNCTION,'Type':'Event','Role':role,'Runtime':'Nodejs20.19','Handler':'index.main','MemorySize':128,'Timeout':60,'Code':{'ZipFile':code},'Environment':environment,'Description':'Theme contest one-off settlement and daily recovery; no frequent idle polling'});wait(FUNCTION)
    triggers=request('ListTriggers',{'FunctionName':FUNCTION,'Limit':100}).get('Triggers',[])
    if not any(t['TriggerName']=='hytc-daily-recovery' for t in triggers):
        request('CreateTrigger',{'FunctionName':FUNCTION,'TriggerName':'hytc-daily-recovery','Type':'timer','Enable':'OPEN','TriggerDesc':'0 5 4 * * ? *'})
    print('Settlement worker active; daily recovery installed')
elif mode=='rollback':
    community_only=os.environ.get('HYT_CONTEST_SCHEMA15_UPGRADE')=='1'
    if community_only and not Path('/tmp/hyt-community-v15-code-deployment-started').exists():
        print('Community code deployment did not start')
        sys.exit(0)
    if not BACKUP.exists(): raise RuntimeError('No deployment backup')
    data=BACKUP.read_bytes();saved=json.loads(AESGCM(enc_key).decrypt(data[:12],data[12:],None));c=saved['config']
    request('UpdateFunctionCode',{'FunctionName':'hyt-community','CodeSource':'ZipFile','ZipFile':saved['code']});wait('hyt-community')
    request('UpdateFunctionConfiguration',{'FunctionName':'hyt-community','Environment':c['Environment'],'MemorySize':c['MemorySize'],'Timeout':c['Timeout']});wait('hyt-community')
    if community_only:
        print('Previous community code/configuration restored')
        sys.exit(0)
    # Disable only settlement timers owned by this deployment; preserve all other services.
    try: triggers=request('ListTriggers',{'FunctionName':FUNCTION,'Limit':100}).get('Triggers',[])
    except Exception as e:
        if 'ResourceNotFound' not in str(e): raise
        triggers=[]
    for t in triggers:
        if t['TriggerName'].startswith('hytc-'): request('DeleteTrigger',{'FunctionName':FUNCTION,'TriggerName':t['TriggerName'],'Type':'timer'})
    print('Previous community code/configuration restored; contest timers removed')
else: raise RuntimeError('Unknown operation')

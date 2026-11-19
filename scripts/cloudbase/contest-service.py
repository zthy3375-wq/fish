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
    config=request('GetFunction',{'FunctionName':'hyt-community'})
    location=request('GetFunctionAddress',{'FunctionName':'hyt-community'})
    with urllib.request.urlopen(location['Url'],timeout=60) as response: code=response.read()
    saved={'config':config,'code':base64.b64encode(code).decode()}
    nonce=os.urandom(12); BACKUP.parent.mkdir(exist_ok=True)
    BACKUP.write_bytes(nonce+AESGCM(enc_key).encrypt(nonce,json.dumps(saved).encode(),None))
    private=Path('/tmp/hyt-existing-environment.json');private.write_text(json.dumps({v['Key']:v['Value'] for v in config.get('Environment',{}).get('Variables',[])}));private.chmod(0o600)
    print('Encrypted deployed code/configuration backup saved')
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
        request('CreateTrigger',{'FunctionName':FUNCTION,'TriggerName':'hytc-daily-recovery','Type':'timer','Enable':'OPEN','TriggerDesc':json.dumps({'cron':'0 5 4 * * ? *'})})
    print('Settlement worker active; daily recovery installed')
elif mode=='rollback':
    if not BACKUP.exists(): raise RuntimeError('No deployment backup')
    data=BACKUP.read_bytes();saved=json.loads(AESGCM(enc_key).decrypt(data[:12],data[12:],None));c=saved['config']
    request('UpdateFunctionCode',{'FunctionName':'hyt-community','CodeSource':'ZipFile','ZipFile':saved['code']});wait('hyt-community')
    request('UpdateFunctionConfiguration',{'FunctionName':'hyt-community','Environment':c['Environment'],'MemorySize':c['MemorySize'],'Timeout':c['Timeout']});wait('hyt-community')
    # Disable only settlement timers owned by this deployment; preserve all other services.
    try: triggers=request('ListTriggers',{'FunctionName':FUNCTION,'Limit':100}).get('Triggers',[])
    except Exception as e:
        if 'ResourceNotFound' not in str(e): raise
        triggers=[]
    for t in triggers:
        if t['TriggerName'].startswith('hytc-'): request('DeleteTrigger',{'FunctionName':FUNCTION,'TriggerName':t['TriggerName'],'Type':'timer'})
    print('Previous community code/configuration restored; contest timers removed')
else: raise RuntimeError('Unknown operation')

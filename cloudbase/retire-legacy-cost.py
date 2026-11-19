"""Stop only the retired usage-collection endpoints/timer, preserving historic data and delete APIs."""
import base64,hashlib,hmac,io,json,os,time,urllib.request
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from tencentcloud.common.credential import Credential
from tencentcloud.scf.v20180416 import scf_client
ENV='hanyuantong-d8gjzt1jh12370215';KEY=os.environ['CLOUDBASE_API_KEY'].strip()
req=urllib.request.Request(f'https://{ENV}.ap-shanghai.tcb-api.tencentcloudapi.com/capi/credential',data=json.dumps({'env':ENV}).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+KEY})
with urllib.request.urlopen(req,timeout=20) as r:c=json.load(r)['data']
client=scf_client.ScfClient(Credential(c['TmpSecretId'],c['TmpSecretKey'],c['Token']),'ap-shanghai')
def call(action,data):return json.loads(client.call(action,{'Namespace':ENV,**data}))['Response']
def read_health(name):
 try:
  with urllib.request.urlopen(f'https://{ENV}-1527874185.ap-shanghai.app.tcloudbase.com/{name}/health',timeout=15) as r:return json.load(r)
 except Exception:return {}
def active(name):
 for i in range(30):
  if call('GetFunction',{'FunctionName':name}).get('Status')=='Active':return
  time.sleep(2)
 raise RuntimeError('Analytics update activation timeout')
root=Path('cloudbase/functions/analytics');archive=io.BytesIO()
with ZipFile(archive,'w',ZIP_DEFLATED) as z:
 for p in sorted(root.rglob('*')):
  if p.is_file() and not p.is_symlink():z.write(p,p.relative_to(root))
code=base64.b64encode(archive.getvalue()).decode();backups={};proof={'functions':[],'timer':{},'historicalDataDeleted':False,'communityChanged':False}
for name in ['hyt-analytics','hyt-analytics-canary']:
 try:config=call('GetFunction',{'FunctionName':name})
 except Exception as e:
  if 'ResourceNotFound' not in str(e):raise
  proof['functions'].append({'name':name,'exists':False});continue
 retired=read_health(name).get('collection') is False
 proof['functions'].append({'name':name,'exists':True,'alreadyRetired':retired})
 if not retired:
  location=call('GetFunctionAddress',{'FunctionName':name})
  with urllib.request.urlopen(location['Url'],timeout=60) as r:old_code=r.read()
  backups[name]={'code':base64.b64encode(old_code).decode(),'config':config}
try:
 triggers=call('ListTriggers',{'FunctionName':'hyt-analytics-hourly','Limit':100}).get('Triggers',[])
except Exception as e:
 if 'ResourceNotFound' not in str(e):raise
 triggers=[]
matching=[t for t in triggers if t['TriggerName']=='hyt-hourly' and t['Type']=='timer']
proof['timer']={'name':'hyt-hourly','function':'hyt-analytics-hourly','found':bool(matching),'configuration':[{'schedule':t.get('TriggerDesc'),'enabled':t.get('Enable'),'binding':t.get('BindStatus')} for t in matching]}
Path('artifacts').mkdir(exist_ok=True)
nonce=os.urandom(12);enc_key=hmac.new(KEY.encode(),b'hyt-legacy-retirement-backup-v1',hashlib.sha256).digest()
Path('artifacts/legacy-retirement-rollback.enc').write_bytes(nonce+AESGCM(enc_key).encrypt(nonce,json.dumps({'functions':backups,'triggers':matching}).encode(),None))
for t in matching:call('DeleteTrigger',{'FunctionName':'hyt-analytics-hourly','TriggerName':'hyt-hourly','Type':'timer'})
changed=[]
try:
 for item in proof['functions']:
  if not item['exists']:continue
  name=item['name']
  if name in backups:
   changed.append(name);call('UpdateFunctionCode',{'FunctionName':name,'CodeSource':'ZipFile','ZipFile':code});active(name)
  assert read_health(name).get('collection') is False,'Usage collection must be retired'
  req=urllib.request.Request(f'https://{ENV}-1527874185.ap-shanghai.app.tcloudbase.com/{name}/api/metrics/record',data=b'{}',headers={'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=15) as r:assert json.load(r).get('collection') is False
  item['retiredVerified']=True
except Exception:
 for name in changed:
  call('UpdateFunctionCode',{'FunctionName':name,'CodeSource':'ZipFile','ZipFile':backups[name]['code']});active(name)
 raise
proof['timer']['removed']=bool(matching)
Path('artifacts/legacy-cost-verification.json').write_text(json.dumps(proof,indent=2))
print(json.dumps(proof))

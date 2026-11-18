"""Update just the HTTP code of the existing campus community function."""
import base64
import io
import os
import urllib.request
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from tencentcloud.common.credential import Credential
from tencentcloud.scf.v20180416 import models, scf_client

env = "hanyuantong-d8gjzt1jh12370215"
region = "ap-shanghai"
exchange = urllib.request.Request(
    f"https://{env}.{region}.tcb-api.tencentcloudapi.com/capi/credential",
    headers={"Content-Type": "application/json", "Authorization": "Bearer " + os.environ["CLOUDBASE_API_KEY"]},
    data=json.dumps({"env": env}).encode(),
)
with urllib.request.urlopen(exchange, timeout=20) as response:
    c = json.load(response)["data"]
client = scf_client.ScfClient(Credential(c["TmpSecretId"], c["TmpSecretKey"], c["Token"]), region)
root = Path("cloudbase/functions/community")
archive = io.BytesIO()
with ZipFile(archive, "w", ZIP_DEFLATED) as bundle:
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink():
            bundle.write(p, p.relative_to(root))
request = models.UpdateFunctionCodeRequest()
request.Namespace = env
request.FunctionName = "hyt-community"
request.CodeSource = "ZipFile"
request.ZipFile = base64.b64encode(archive.getvalue()).decode("ascii")
print("SCF accepted community code update", client.UpdateFunctionCode(request).RequestId)

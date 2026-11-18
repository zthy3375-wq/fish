import os
import json
import secrets
import subprocess
import urllib.error
import urllib.request

name = "8" + secrets.token_hex(7)
password = secrets.token_hex(16)
api = "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/"
def call(action, body, token=""):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    with urllib.request.urlopen(urllib.request.Request(api + action, headers=headers, data=json.dumps(body).encode()),timeout=25) as response:
        return json.load(response)

try:
    for mode in ("signup", "upgrade", "reopen"):
        if mode=="upgrade":
            subprocess.run(["adb","install","-r",os.path.join(os.environ["RUNNER_TEMP"],"emulator-app.apk")],check=True)
        subprocess.run(["adb","shell","am","force-stop","org.handancampus.app"],check=True)
        result = subprocess.run(["adb","shell","am","instrument","-w","-e","mode",mode,"-e","login",name,"-e","pass",password,
                                 "org.handancampus.releasecheck/.ReleaseCheck"],capture_output=True,text=True,timeout=160)
        print(result.stdout.replace(name,"[account]").replace(password,"[password]"),flush=True)
        if result.returncode or ("qa=PASS "+mode) not in result.stdout:
            raise RuntimeError("Android release check failed at "+mode)
finally:
    try:
        session=call("login",{"username":name,"password":password})
    except urllib.error.HTTPError as error:
        if error.code!=401: raise
    else:
        if not session.get("sessionToken"):
            raise RuntimeError("Missing cleanup session")
        call("account.delete",{"password":password},session["sessionToken"])
        print("Disposable Android QA account removed")

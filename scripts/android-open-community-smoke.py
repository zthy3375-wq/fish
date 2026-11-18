"""Exercise the release UI via Android accessibility, with a disposable account."""
import json
import re
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

PACKAGE = "org.handancampus.app"
API = "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/"
def adb(*args):
    return subprocess.check_output(["adb", *args], stderr=subprocess.DEVNULL, timeout=25)
def nodes():
    adb("shell","uiautomator","dump","/data/local/tmp/campus-qa.xml")
    data = adb("exec-out","cat","/data/local/tmp/campus-qa.xml")
    return list(ET.fromstring(data).iter("node"))
def label(node):
    return " ".join(node.get(k,"") for k in ("text","content-desc")).strip()
def bounds(node):
    return [int(i) for i in re.findall(r"\d+",node.get("bounds",""))]
def wait_for(fn, name, timeout=40):
    until = time.monotonic()+timeout
    while time.monotonic()<until:
        try:
            items=nodes()
            for n in items:
                if n.get("resource-id","") in ("com.android.permissioncontroller:id/permission_deny_button", "com.google.android.permissioncontroller:id/permission_deny_button"):
                    tap(n)
                    break
            else:
                value=fn(items)
                if value:return value
        except (ET.ParseError,subprocess.SubprocessError):pass
        time.sleep(0.25)
    raise RuntimeError("Timed out waiting for "+name)
def target(name, exact=True):
    def find(items):
        hits=[n for n in items if (label(n)==name if exact else name in label(n)) and len(bounds(n))==4]
        return sorted(hits,key=lambda n:bounds(n)[1],reverse=True)[0:1] or None
    return wait_for(find,name)[0]
def tap(node):
    x,y,r,b=bounds(node)
    adb("shell","input","tap",str((x+r)//2),str((y+b)//2))
def launch():
    adb("shell","am","start","-W","-n",PACKAGE+"/.MainActivity")
def api(action,body,token=""):
    headers={"Content-Type":"application/json"}
    if token: headers["Authorization"]="Bearer "+token
    req=urllib.request.Request(API+action,headers=headers,data=json.dumps(body).encode())
    with urllib.request.urlopen(req,timeout=25) as result:return json.load(result)
def feed_visible(items):
    return any(label(n) in ("搜索帖子","互动消息","刷新树洞") for n in items) and not any(n.get("class")=="android.widget.EditText" for n in items)
username="8"+str(secrets.randbelow(10**16)).zfill(16)
password=secrets.token_hex(16)
submitted=False
try:
    launch()
    shower=target("趣智校园",False)
    water=target("胖乖生活",False)
    left, right=bounds(shower),bounds(water)
    assert left[0]<right[0] and abs(left[1]-right[1])<75, "Wallet cards not side by side"
    print("Android home: two side-by-side wallet entries",flush=True)
    tap(target("社区"))
    tap(target("注册账号"))
    fields=wait_for(lambda items:[n for n in items if n.get("class")=="android.widget.EditText"],"signup fields")
    assert len(fields)==2, "Expected exactly two signup fields"
    tap(fields[0]);adb("shell","input","text",username)
    password_field=wait_for(lambda items:next(([n] for n in items if n.get("class")=="android.widget.EditText" and n.get("password")=="true"),None),"password field")[0]
    tap(password_field);adb("shell","input","text",password)
    adb("shell","input","keyevent","KEYCODE_BACK")
    tap(target("创建账号"));submitted=True
    wait_for(feed_visible,"community feed after signup")
    adb("shell","am","force-stop",PACKAGE);launch()
    tab=target("社区")
    start=time.monotonic();tap(tab);wait_for(feed_visible,"persisted session feed")
    print("Android live: two-field numeric signup, feed visible, session survived process restart; accessibility observation ms =",round((time.monotonic()-start)*1000),flush=True)
finally:
    if submitted:
        try: session=api("login",{"username":username,"password":password})
        except urllib.error.HTTPError as err:
            if err.code!=401: raise
        else:
            api("account.delete",{"password":password},session["sessionToken"])
            print("Disposable Android QA account removed",flush=True)

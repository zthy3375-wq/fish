"""Exercise the release UI via Android accessibility, with a disposable account."""
import json
import uiautomator2 as u2
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
    return " ".join(dict.fromkeys(node.get(k,"").strip() for k in ("text","content-desc") if node.get(k,"").strip()))
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
    known = ("登录邯院通","登录树洞","说说校园里的那些事","创建账号","社区规则","注册账号","搜索帖子","忘记密码","暂未开放","正在连接","连接失败","刷新树洞","请登录","连接账户","无网络","重试","请先登录","社区服务","注册","等待")
    if name in ("community feed after signup","signup fields","password field","confirmed credentials"):
        adb("shell","input","swipe","500","800","500","1650","350")
        items=nodes()
        if any(n.get("class")=="android.widget.EditText" for n in items) and any("邯院通账号" in label(n) or "社区规则" in label(n) for n in items):
            safe=[re.sub(r"[0-9a-f]{12,}", "[test value]", label(n))[:100] for n in items if n.get("class")!="android.widget.EditText" and label(n)]
            print("Auth form status:", safe[:45],flush=True)
    print("Known UI markers:", [word for word in known if any(word in label(n) for n in items)],flush=True)
    raise RuntimeError("Timed out waiting for "+name)
def target(name, exact=True, scroll=False):
    attempts=0
    def find(items):
        nonlocal attempts
        hits=[n for n in items if any(value==name if exact else name in value for value in (n.get("text",""),n.get("content-desc",""))) and len(bounds(n))==4 and bounds(n)[2]>bounds(n)[0] and bounds(n)[3]>bounds(n)[1]]
        if hits: return [max(hits,key=lambda n:(n.get("clickable")=="true",bounds(n)[1]))]
        attempts+=1
        if scroll and attempts in (2,4,8):
            adb("shell","input","swipe","520","1750","520","780","400")
        return None
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
    tap(target("注册账号",scroll=True))
    fields=wait_for(lambda items:[n for n in items if n.get("class")=="android.widget.EditText"],"signup fields")
    assert len(fields)==2, "Expected exactly two signup fields"
    device=u2.connect()
    editable=device(className="android.widget.EditText")
    editable[0].set_text(username)
    editable[1].set_text(password)
    if device(focused=True,className="android.widget.EditText").exists:
        if b"mInputShown=true" in adb("shell","dumpsys","input_method"):
            adb("shell","input","keyevent","KEYCODE_BACK")
    tap(target("显示密码",False,scroll=True))
    def credentials_match(items):
        values={n.get("text","") for n in items if n.get("class")=="android.widget.EditText"}
        return username in values and password in values
    wait_for(credentials_match,"confirmed credentials",15)
    print("Android form contains exact synthetic numeric username and password",flush=True)
    submit=target("创建账号",True,True)
    assert submit.get("enabled")=="true", "Signup disabled"
    tap(submit);submitted=True
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

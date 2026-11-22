import os,re,subprocess,time
from pathlib import Path
from xml.etree import ElementTree as ET
pkg="org.handancampus.app"
base=Path(os.environ["RUNNER_TEMP"])
def adb(*args):
 return subprocess.check_output(["adb",*map(str,args)],timeout=75,text=True,stderr=subprocess.STDOUT).strip()
def install(name,replace=False):
 args=["install"]+(["-r"] if replace else [])+[base/"packages"/f"{name}.apk"]
 result=adb(*args)
 assert "Success" in result,result
 print("Installed",name, "upgrade" if replace else "fresh",flush=True)
def appver(code):
 s=adb("shell","dumpsys","package",pkg)
 assert re.search(r"versionCode="+str(code)+r"\b",s)
 return re.search(r"firstInstallTime=(.*)",s)[1]
def ui():
 adb("shell","uiautomator","dump","/sdcard/hyt-install.xml")
 return ET.fromstring(adb("exec-out","cat","/sdcard/hyt-install.xml"))
def find(label,tap=False,seconds=60):
 end=time.monotonic()+seconds
 nodes=[]
 while time.monotonic()<end:
  try:
   nodes=list(ui().iter("node"))
   for n in nodes:
    if label not in [n.get("text"),n.get("content-desc")]:continue
    raw=list(map(int,re.findall(r"-?\d+",n.get("bounds",""))))
    if len(raw)!=4 or raw[0]==raw[2] or raw[1]==raw[3]:continue
    if tap:adb("shell","input","tap",(raw[0]+raw[2])//2,(raw[1]+raw[3])//2)
    return
  except (ET.ParseError,subprocess.SubprocessError):pass
 print("UI package", sorted(set(n.get("package","") for n in nodes)), "labels",[n.get("text","")[:60] for n in nodes if n.get("text")][:24])
 raise RuntimeError("Missing UI "+label)
def run():
 print("WebView", next((x for x in adb("shell","dumpsys","webviewupdate").splitlines() if "Current WebView package" in x),"unknown"),flush=True)
 install(192)
 appver(192)
 adb("shell","input","keyevent","KEYCODE_WAKEUP")
 adb("shell","wm","dismiss-keyguard")
 print(adb("shell","am","start","-W","-n",pkg+"/.MainActivity"),flush=True)
 find("首页",seconds=95)
 print("Fresh cold launch exposed home",flush=True)
 pid=adb("shell","pidof",pkg)
 find("我的",True)
 for count in range(2):
  find("连接",True)
  find("取消",seconds=20)
  assert pid and adb("shell","pidof",pkg)==pid
  find("取消",True,seconds=10)
  find("连接",seconds=25)
  print("School dialog opened and returned",count+1,"same pid",pid,flush=True)
 crash=adb("logcat","-b","crash","-d")
 assert pkg not in crash,crash[-1800:]
try:
 run()
except Exception:
 print(adb("logcat","-d","-s","chromium:E","Capacitor/Console:E","AndroidRuntime:E")[-3500:])
 raise

"""Capture this branch's unmodified Android debug build on a clean offline emulator."""
import hashlib
import re
import subprocess
import sys
import time
from pathlib import Path
from xml.etree import ElementTree as ET

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)

def adb(*args):
    return subprocess.check_output(["adb", *args], timeout=25)

def tree():
    adb("shell", "uiautomator", "dump", "/sdcard/parity-window.xml")
    return ET.fromstring(adb("exec-out", "cat", "/sdcard/parity-window.xml"))

def locate(label, bottom=False, timeout=35):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches = []
        try:
            nodes = list(tree().iter("node"))
            # The cold emulator can show a Pixel Launcher ANR above our app.
            launcher_error = any("pixel launcher" in node.get("text", "").lower() and
                                 node.get("resource-id") == "android:id/alertTitle" for node in nodes)
            if launcher_error:
                close = next((node for node in nodes if node.get("resource-id") == "android:id/aerr_close"), None)
                if close is not None:
                    left, top, right, bottom_edge = map(int, re.findall(r"-?\d+", close.get("bounds", "")))
                    adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom_edge) // 2))
                    continue
            for node in nodes:
                text = node.get("text","") or node.get("content-desc","")
                if (text == label if bottom else label in text):
                    x1,y1,x2,y2 = map(int,re.findall(r"-?\d+",node.get("bounds","")))
                    if x2>x1 and y2>y1: matches.append(((y1+y2)//2,(x1+x2)//2))
        except (ET.ParseError,ValueError,subprocess.SubprocessError):
            pass
        if matches: return (max if bottom else min)(matches)
        time.sleep(1)
    (output / "failed-screen.png").write_bytes(adb("exec-out", "screencap", "-p"))
    raise RuntimeError("Android screen did not expose " + label)

def tap(label, bottom=False):
    y,x=locate(label,bottom)
    adb("shell","input","tap",str(x),str(y))
    time.sleep(0.7)

def capture(name):
    data=adb("exec-out","screencap","-p")
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
    (output/(name+".png")).write_bytes(data)

adb("shell","cmd","connectivity","airplane-mode","enable")
adb("shell","input","keyevent","KEYCODE_WAKEUP")
adb("shell","wm","dismiss-keyguard")
adb("shell","am","start","-n","org.handancampus.app/.MainActivity")
# A newly installed WebView can take longer to expose its accessibility tree on a cold emulator.
locate("首页", bottom=True, timeout=100)
screens = [("首页","home","校园生活"),("课表","schedule","课程表"),("社区","community","重试"),
           ("待办","tasks","任务清单"),("我的","profile","查看全部荣誉殿堂藏品")]
digests=set()
for label,name,marker in screens:
    tap(label,True)
    locate(marker)
    capture(name)
    digest=hashlib.sha256((output/(name+".png")).read_bytes()).digest()
    if digest in digests: raise RuntimeError("Previous screen was captured twice: " + name)
    digests.add(digest)
tap("设置与帮助")
locate("偏好与数据")
capture("settings")
adb("shell", "input", "keyevent", "KEYCODE_BACK")
tap("查看全部荣誉殿堂藏品")
locate("成就收藏馆")
capture("gallery")

"""Capture this branch's unmodified Android debug build on a clean offline emulator."""
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

def locate(label, bottom=False):
    for attempt in range(8):
        matches = []
        try:
            for node in tree().iter("node"):
                text = node.get("text","") or node.get("content-desc","")
                if (text == label if bottom else label in text):
                    x1,y1,x2,y2 = map(int,re.findall(r"-?\d+",node.get("bounds","")))
                    if x2>x1 and y2>y1: matches.append(((y1+y2)//2,(x1+x2)//2))
        except (ET.ParseError,ValueError,subprocess.SubprocessError):
            pass
        if matches: return (max if bottom else min)(matches)
        time.sleep(1)
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
adb("shell","am","start","-n","org.handancampus.app/.MainActivity")
for label,name in [("首页","home"),("课表","schedule"),("社区","community"),("待办","tasks"),("我的","profile")]:
    tap(label,True)
    capture(name)
tap("查看全部荣誉殿堂藏品")
locate("成就收藏馆")
capture("gallery")

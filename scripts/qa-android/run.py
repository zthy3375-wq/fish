import os
import subprocess

def adb(*args):
    return subprocess.run(["adb",*args],check=True,capture_output=True,text=True,timeout=180).stdout

adb("shell","cmd","connectivity","airplane-mode","enable")
adb("shell","svc","wifi","disable")
adb("shell","svc","data","disable")
for mode in ("previous","upgrade","reopen"):
    if mode=="upgrade":
        print(adb("install","-r",os.path.join(os.environ["RUNNER_TEMP"],"emulator-app.apk")),flush=True)
    adb("shell","am","force-stop","org.handancampus.app")
    output=adb("shell","am","instrument","-w","-e","mode",mode,"org.handancampus.releasecheck/.ReleaseCheck")
    print(output,flush=True)
    if "qa=PASS "+mode not in output: raise RuntimeError(mode)

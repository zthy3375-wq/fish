set -eu
d="$RUNNER_TEMP/probe"
mkdir -p "$d/classes" "$d/dex"
cd "$d"
t="$ANDROID_HOME/build-tools/35.0.0"
platform="$ANDROID_HOME/platforms/android-35/android.jar"
cat > AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.example.archivecheck">
  <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="28"/>
  <application android:debuggable="true"/>
  <instrumentation android:name=".Probe" android:targetPackage="org.example.archivecheck"/>
</manifest>
XML
cat > Probe.java <<'JAVA'
package org.example.archivecheck;
import android.app.Instrumentation;
import android.content.pm.*;
import android.os.Bundle;
import java.io.*;
public class Probe extends Instrumentation {
  @Override public void onCreate(Bundle args) {
    super.onCreate(args); start();
  }
  @Override public void onStart() {
    Bundle b = new Bundle();
    try {
      int flags = android.os.Build.VERSION.SDK_INT >= 28 ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
      File apk = new File(getContext().getCacheDir(), "download.apk");
      File part = new File(getContext().getCacheDir(), "download.part");
      for (File f : new File[]{apk,part}) {
        PackageInfo p = getContext().getPackageManager().getPackageArchiveInfo(f.toString(),flags);
        b.putString(f.getName(),p==null?"unreadable":p.packageName+" "+p.versionCode);
      }
    } catch(Exception e){b.putString("error",e.getClass().getName());}
    finish(-1,b);
  }
}
JAVA
javac -source 8 -target 8 -cp "$platform" -d classes Probe.java
"$t/d8" --lib "$platform" --output dex classes/org/example/archivecheck/Probe.class
"$t/aapt2" link -o unsigned.apk --manifest AndroidManifest.xml -I "$platform"
(cd dex && zip -q ../unsigned.apk classes.dex)
"$t/zipalign" -f 4 unsigned.apk aligned.apk
keytool -genkeypair -keystore "$d/qa.jks" -storepass localonly -keypass localonly -alias probe -dname CN=DisposableProbe -keyalg RSA -validity 2
"$t/apksigner" sign --ks "$d/qa.jks" --ks-pass pass:localonly --out "$d/probe.apk" aligned.apk

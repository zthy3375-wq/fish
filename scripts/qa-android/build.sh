set -eu
buildtools="$ANDROID_HOME/build-tools/35.0.0"
androidjar="$ANDROID_HOME/platforms/android-35/android.jar"
out="$RUNNER_TEMP/campus-qa"
mkdir -p "$out/classes" "$out/dex"
javac -source 8 -target 8 -cp "$androidjar" -d "$out/classes" scripts/qa-android/ReleaseCheck.java
(cd "$out/classes" && jar cf "$out/classes.jar" .)
"$buildtools/d8" --min-api 26 --lib "$androidjar" --output "$out/dex" "$out/classes.jar"
"$buildtools/aapt" package -f -M scripts/qa-android/AndroidManifest.xml -I "$androidjar" -F "$out/raw.apk"
(cd "$out/dex" && zip -q "$out/raw.apk" classes.dex)
"$buildtools/zipalign" -f 4 "$out/raw.apk" "$out/aligned.apk"
java -jar "$RUNNER_TEMP/release-input/apksigner.jar" sign --ks "$RUNNER_TEMP/emulator.jks" --ks-pass pass:emulatoronly --out "$RUNNER_TEMP/qa.apk" "$out/aligned.apk"

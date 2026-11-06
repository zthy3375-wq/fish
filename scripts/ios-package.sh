#!/usr/bin/env bash
# macOS/Xcode only. Device build for later signing; NEVER a signed distribution IPA.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iPhone packaging requires macOS and Xcode.' >&2
  exit 1
fi
version="$(node -p "require('./package.json').version")"
output="$PWD/build/ios"
archive="$output/HandanCampus.xcarchive"
package="$output/handan-campus-v${version}-unsigned.ipa"
mkdir -p "$output"
xcodebuild -workspace ios/App/App.xcworkspace -scheme App \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$output/DerivedData" -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' archive
app="$archive/Products/Applications/App.app"
test -f "$app/Info.plist"
xcrun lipo -verify_arch arm64 "$app/App"
# Remove only the previous staging directory owned by this script.
rm -rf "$output/Payload"
mkdir -p "$output/Payload"
ditto "$app" "$output/Payload/App.app"
(cd "$output" && ditto -c -k --keepParent Payload "$(basename "$package")")
python3 - "$package" "$output" <<'PY'
import hashlib,json,pathlib,plistlib,subprocess,sys,zipfile
ipa=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2])
with zipfile.ZipFile(ipa) as z:
    info=plistlib.loads(z.read('Payload/App.app/Info.plist'))
    assert info['CFBundleSupportedPlatforms']==['iPhoneOS'], 'Not an iPhone device build'
    assert info['CFBundleIdentifier']=='org.handancampus.app'
    assert 'Payload/App.app/embedded.mobileprovision' not in z.namelist(), 'Unexpected signing profile'
    assert 'Payload/App.app/public/index.html' in z.namelist(), 'Missing bundled web UI'
    binary=info['CFBundleExecutable']
    assert 'Payload/App.app/'+binary in z.namelist(), 'Missing native executable'
manifest={'file':ipa.name,'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundleId':info['CFBundleIdentifier'],'platform':'iPhoneOS','signed':False,'directlyInstallable':False,'academicClientImplemented':False,'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest()}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(out/'README.txt').write_text('邯郸校园 '+manifest['version']+' iPhone 待签名测试包\n\n此包是 iPhoneOS 设备构建，不是模拟器包，但尚未签名，不能直接点击安装，也不是 TestFlight 包。需要适用的 Apple 签名和安装渠道。\n\n可测试：导航、界面、个人事项、备份与本地功能。\n尚未实现：iOS 原生 HandanAcademicClient。学校登录、真实课表/成绩/考试自动同步和学校会话保持不能在 iPhone 上使用；Android 已实现功能不等于 iOS 已支持。\n\n不要把 Apple ID 密码、签名私钥或证书密码放进仓库。\n')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
PY

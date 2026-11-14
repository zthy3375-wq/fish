# 不依赖 GitHub Actions 的测试构建

GitHub 托管构建额度耗尽不影响源码或已安装的应用。Android 可在 Windows、Linux 或 Mac 本地构建；iOS 原生编译需要安装 Xcode 的 Mac。这里的构建命令不会发布更新。

## Android 环境

- Node.js 22.12 或更高版本，依赖使用仓库锁文件。
- **完整 JDK 21**：`java -version` 和 `javac -version` 都应能运行。只有 JRE 会在 Java 编译任务创建阶段失败。
- Android SDK Platform 35、Build Tools 35.0.0、Platform Tools。本项目 AGP 8.7.2 默认编译还会使用 Build Tools 34.0.0，SDK Manager 可自动安装。
- 为自己的电脑配置 `JAVA_HOME`、`ANDROID_HOME`；不要把本机 SDK 路径、签名文件或密码提交到仓库。
- 首次构建需要下载 Gradle、Maven 和 Robolectric 测试依赖。有代理时需同时配置 Gradle 和测试 JVM 的网络访问，保留 HTTPS 校验。

在项目根目录运行：

```sh
npm ci
npm run check
npm run android:check
npm run android:apk
```

`android:apk` 会重新构建网页资源、同步 Capacitor、运行 Debug 原生测试并生成 `android/app/build/outputs/apk/debug/app-debug.apk`。第一次下载依赖较慢，后续复用本机缓存。

## 与正式版同时安装的预览包

完成以上检查后，进入 `android` 目录执行：

```sh
./gradlew --no-daemon -PlearningPreview=true :app:assembleDebug
```

Windows 将 `./gradlew` 换为 `gradlew.bat`。生成位置仍为 `app/build/outputs/apk/debug/app-debug.apk`，会覆盖上一次生成的普通 Debug 文件，需要提前复制留存。

预览包名称为“邯院通·预览版”，包名 `org.handancampus.app.preview`，与正式版的数据独立，需要重新登录。Debug 签名不等于正式发布签名；不要为解决签名冲突卸载正式版。正式覆盖升级仍需原签名和明确发布授权。

## 页面操作回归

```sh
npx playwright install chromium
npm run test:ui
```

检查使用合成学校与生活服务响应，覆盖 360/390/430 三种屏宽，不会向教务系统或设备发送真实操作。它不能替代真机学校登录、扫码接水或支付验收。

## iOS 免费构建的替代途径

可使用自己的或借用的 Mac，按 `ios-native/README.md` 运行 Xcode 测试。另一条可选路线是 Codemagic：截至 2026-11-14，官方个人免费套餐提供每月 500 分钟 macOS M2 构建额度，每月 1 日重置；Team、Linux/Windows 构建不享有这一额度。保留免费套餐，不启用额外付费。

当前项目尚未接入 Codemagic。连接私有仓库需所有者注册并授权，后续再配置原生 Swift 工作流；不应仅为构建免费而把仓库改成公开。未签名 iPhone 构建不能直接安装，TestFlight/商店分发仍需相应签名和开发者账号配置。

参考：[Android 命令行构建](https://developer.android.com/build/building-cmdline)、[Codemagic 免费额度](https://docs.codemagic.io/billing/pricing/)、[原生 iOS 工作流](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/)。

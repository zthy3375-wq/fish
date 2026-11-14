# 邯院通 · Hanyuantong

面向邯郸学院学生的独立校园应用。当前维护 Android 和原生 iPhone 两端。

## 当前开发基线

| 项目 | 状态 |
| --- | --- |
| Android 线上版本 | 1.2.2 / 146，按此前授权发布；最新线上状态以更新服务为准 |
| 本分支 Android | 1.2.3-test.2 / 148，整合 test.1 接水修复与本轮优化；仅测试 |
| iPhone | `ios-native/` 原生 Swift/SwiftUI，最低 iOS 16；模拟器与未签名构建验证，不等于真机可安装 |
| 开发分支 | `improve/android-ios-20261114`，基于接水修复和 iOS 原生分支整合；尚未合入 main |

[本轮改动与验收](docs/ANDROID-IOS-REVIEW-20261114.md) · [状态与历史](docs/STATUS.md) · [文档导航](docs/README.md) · [苹果构建](ios-native/README.md)

## 功能与架构

| 模块 | Android | iPhone |
| --- | --- | --- |
| 界面 | Vue 3 / TypeScript / Capacitor；原生 Kotlin 服务 | SwiftUI 原生界面，官方认证使用 WKWebView |
| 教务 | 官方登录、课表、成绩、考试、离线缓存 | 对应原生实现；真实账号与设备待验收 |
| 学习通 | 官方登录、按课程读取、验证码恢复 | 原生读取与本机计划；真实完整性待验收 |
| 校园生活 | 趣智、胖乖、扫码与订单状态 | 原生钱包与扫码；支付 SDK、签约和蓝牙走官方入口 |
| 个人安排 | 多学期课表、待办、备份、提醒、小组件 | 课表、待办、兼容备份、通知与 WidgetKit；真机能力配置待验收 |
| 快递与地图 | 官方 App 出库入口、离线校园平面图 | 官方页面与原生取件展示试验、校园平面图；真实取件待验收 |

学校缓存和个人数据独立。登录密码在官方页面输入，原生会话不暴露给界面。读取失败保留同账号、同学期的成功记录。考试按学期隔离，成绩历史独立于课表学期。不会通过查询状态自动创建新订单或重复启动设备。

当前 Android 架构继续维护，iPhone 使用 Swift，Flutter 验证分支停止开发。社区功能尚未实现。正式 Android 包名 `org.handancampus.app`，覆盖升级必须使用原签名。

## 开发与验证

Node.js 22+，依赖以锁文件为准：

```sh
npm ci
npm run dev
npm run check
npm run test:ui
```

`check` 包括前端测试、两端共享教务脚本和 iOS 页面读取协议回归、TypeScript、生产构建。页面回归使用合成账号与数据，需要 Playwright Chromium。

Android 需要 JDK 21、SDK 35 和 build-tools 35.0.0：

```sh
npm run android:check
npm run android:apk
```

iPhone 需要 Mac / Xcode：

```sh
python3 ios-native/Scripts/generate_project.py
xcodebuild -project ios-native/Hanyuantong.xcodeproj -scheme Hanyuantong -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

共享教务脚本在两端保持逐字节一致。新增 Swift 文件后重新生成工程；CI 同时检查工程可复现性、模拟器回归和未签名设备编译。通知、小组件、官方登录、支付到账和物理设备出水仍需真机验收。

## 分支、测试包和发布

功能开发使用短期分支与 PR。仅在所有者明确要求推送时才更新蒲公英和腾讯云线上版本。构建成功、提交代码、交付测试 APK 均不代表发布授权。CI debug APK 使用测试签名；不能拿它覆盖正式签名包，勿为解决签名冲突卸载用户数据。

历史分支保留追溯；暂停的原生快递与统计试验不自动合入。详细状态以本轮代码和验证记录为准，旧版测试数量不代表本轮通过。

## 贡献与许可

原创代码采用 [MIT](LICENSE)，保留 [第三方声明](THIRD_PARTY_NOTICES.md)。这是独立学生项目，非学校或服务商官方应用。请勿提交密码、Cookie、令牌、个人响应或未脱敏截图。参见 [安全说明](SECURITY.md) 与 [贡献规范](CONTRIBUTING.md)。

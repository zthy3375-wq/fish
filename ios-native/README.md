# 邯院通 iPhone 原生开发版

基于正式 Android 1.2.1 对应 main `780bbc8`，独立 Swift + SwiftUI 工程，最低 iOS 16，仅 iPhone。没有 Flutter、Capacitor、Vue 运行时依赖。复用现有应用图标、校园头图、平面图以及已核验的学校协议读取脚本；WebKit 只用于官方学校认证与页面查询，产品页面为原生 SwiftUI。

## 构建

在装有 Xcode 的 Mac 打开 `Hanyuantong.xcodeproj`，选 Hanyuantong scheme 和 iPhone 模拟器。

```sh
python3 Scripts/generate_project.py
xcodebuild -project Hanyuantong.xcodeproj -scheme Hanyuantong -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

新增 Swift 文件后重新生成工程。工程生成器只使用 Python 标准库，不需要 CocoaPods、Flutter、XcodeGen 或第三方 Swift 包。真机需要在 Xcode 选择自己的签名团队、可用 Bundle ID 与已信任设备；没有替用户配置签名、发布 IPA 或商店提交。CI 的 Simulator app 不能安装到真实 iPhone。

## 当前实现与边界

- 首页、课表、待办、我的四导航，原配色与现有图像资源；日/周课表、课程详情、个人课程创建/删除、待办创建/完成/删除。
- 学校官方 WKWebView 登录，现有 `syncAll` 查询和渲染页课表回退，成绩、考试、实践课、学期选择。密码只在学校官方页面输入。账号、查询、取消、超时与退出流程原生管理。
- 登录 Cookie 保存在设备专属 Keychain，WebKit 使用非持久化数据仓库；仅允许学校 HTTPS 主机及 443 端口，不忽略 TLS 错误，不向产品 UI 提供 Cookie。
- 学校记录与个人记录分开，以 CryptoKit AES-GCM 和设备专属 Keychain 密钥加密，排除系统备份。查询失败保留同账号同学期旧数据；账号替换、过期、退出移除学校缓存，保留个人安排。
- 东西校区平面图、缩放和全图复位。教学周按北京时间计算，起点沿用 2026-09-14 并允许手动校准；默认13节作息沿用用户提供表，不声称学校实时校历。
- 生活钱包/洗澡码/接水/洗衣/支付、学习通、快递跳转、CSV/XLSX/ICS 导入、备份恢复、WidgetKit、系统提醒和应用使用统计尚未完成。入口明确标注待接入，不能据此称功能齐平或正式可用。不会接入 Android 在线更新配置。

## 验证原则

单元测试覆盖来源限制、学期校验、账号隔离、失败缓存保护、周次解析和校区时间；UI 测试覆盖四导航、重复打开/取消编辑器、退出重开并保留截图。它们均使用合成输入和空账号，不等于真实学校登录验收。需在真实 iPhone 手工核对学校登录、验证码、学期切换、课表完整性、成绩、考试、离线重开与退出再登录。

所有工作留在独立功能分支，不更改现有 Android、线上服务或发布元数据。阶段验证记录见 `VALIDATION.md`。

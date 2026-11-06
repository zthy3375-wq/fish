# iPhone 测试包与当前限制

当前 iOS 包基于 v0.5.1 界面，版本号 0.5.1 / build 56，标识符 org.handancampus.app。iOS 14及以上，iPhone/iPad设备架构。

## 当前功能

可用于签名后测试四Tab导航、个人事项、本地课表管理及备份。iOS 的 Swift HandanAcademicClient 尚未实现，学校登录、真实课表/成绩/考试自动同步、学校会话保持暂不可用。Android 的真机验证不能作为 iOS 的验证。

## 构建

在 macOS（Xcode、CocoaPods、Node.js 22+）运行：

```sh
npm ci
npm run ios:package
```

CI 使用 macos-15，先测试/类型检查/网页构建及Capacitor同步，再对 generic/platform=iOS 执行无签名设备archive。脚本验证打包平台、包标识、原生可执行文件和网页资源。成功后输出 build/ios/handan-campus-v0.5.1-unsigned.ipa、README.txt 和 manifest.json。编译与产物检查不是 iPhone 真机功能验收。

## 安装前提

该 IPA 尚未签名，不能直接点击下载后安装，也不能当作 TestFlight 包。可以使用自己的签名流程处理；通过 TestFlight 分发则需要 Apple Developer Program 和 App Store Connect 配置。开发或 Ad Hoc 分发需要相应证书及包含目标设备的描述文件。官方说明：

- https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases

仓库目前未配置开发团队或签名描述文件。请勿将 Apple ID 密码、证书私钥或密码提交到GitHub。后续签名仅使用专门的私密凭据存储和用户明确指定的分发渠道。

## 仍待完成

- Apple 签名与实际安装。
- Swift 学校连接实现和真实学校账号联调。
- iPhone 真机的返回、键盘、安全区、备份与离线冷启动回归。

# Flutter第一阶段验证记录

日期：2026-11-11。最终应用源码：`7cf857159c49d6fe6892b66b43c62c35595673bd`。基线：`780bbc85c0b70e8d9273129eca666d7141e21e42`。

## 已执行

| 层次 | 结果 | 不代表什么 |
| --- | --- | --- |
| Flutter analyze | 通过，零问题 | 不代表真实账号验证 |
| Flutter单元/Widget | 22项通过 | 模拟原生接口、合成课表 |
| 编译内置学校JS适配器 | 10项通过 | 合成HTML/JSON，不使用账号数据 |
| Android原生域名策略 | 2项JUnit通过 | 不覆盖真实WebView全部网络行为 |
| Android Debug编译 | 成功 | 未在手机安装运行 |
| Android Release测试签名ARM64编译 | 成功 | 不是正式发布签名/更新包 |
| iOS模拟器编译 | macOS CI成功 | 不等于iPhone安装/真实账号通过 |
| iOS原生域名边界 | 5项XCTest通过、0失败（e3b2e64，原生iOS代码未再改变） | 不测试真实学校页面/账号 |
| 窄屏布局 | 320px、1.3倍文字测试通过并人工查看3张渲染图 | 渲染用合成数据，无真实学籍信息 |

首轮双端CI：[42988876845](https://github.com/zthy3375-wq/fish/actions/runs/42988876845)，两端构建成功。新增原生测试的双端CI（全部成功）：[42989894945](https://github.com/zthy3375-wq/fish/actions/runs/42989894945)。两处最终边界补丁（完整删除旧scope缓存、Android过期清理错误受控返回）又通过本地analyze、22项测试和ARM64 Release编译。最终源码远端复验：[42991997383](https://github.com/zthy3375-wq/fish/actions/runs/42991997383)，报告写入时仍在运行，以各job真实状态为准，不把前一提交的CI当作后一提交结果。

覆盖：单双周与全角表达、多节跨度、实践课、学期边界、离线重开、失败/空返回保留缓存、拒绝部分周次解析、账号scope隔离、迟到请求/写入取消、退出清理失败与重试、官方域名边界、重复点击、页面显示。未触碰旧生产项目或在线更新清单。

## 交付Android测试APK

- 文件：`Hanyuantong-Flutter-Core-0.1.0-ARM64-Test.apk`
- 包名：`org.handancampus.fluttercore`；应用名：邯院通·Flutter验证。
- versionName：`0.1.0`；分ABI versionCode：`2001`（基础版本1 + ARM64偏移2000）。
- Android 7.0/API24及以上，**仅ARM64**。如设备仅支持32位，需要单独构建，不能把本包当作通用架构包。
- 大小：18,105,118字节。
- SHA-256：`69cedb42bd284b18bd4371a09a2ac66e60e45cee76cf5fb8e089e6e1d799964d`。
- 测试证书SHA-256：`acd5d790e26569aed1c540145b0ae90e862438afcfac276c606d95ea6a5fdec5`。不是正式版证书。
- APK签名v2验证通过；4字节/16KB对齐检查通过；仅含arm64-v8a；两个学校适配脚本与源码逐字节一致；不打包测试fixtures或模拟课程。
- 构建命令：`flutter build apk --release --target-platform android-arm64 --split-per-abi`。虽然使用Release优化，仍是独立包名/测试证书的验证包，不构成发布授权。

可与正式包并装，保留原App即可。此包不含生产更新接口，不会收到或覆盖正式更新。

## 尚未执行、必须由本人设备补验

- 真实官方登录、错误密码与实际验证码。
- 本人真实课表的完整性逐项核对；学校真实空课的对照核验。
- 安卓实际安装、关闭重开、飞行模式、Wi-Fi/移动网络切换、系统杀进程。
- 学校会话真实过期、长期Cookie恢复、账号A/B实切换。
- iPhone开发签名安装、真实WKWebView登录/Keychain恢复与离线查看。

没有提供已签名iPhone IPA：需要macOS/Xcode及用户开发者签名和设备授权。iOS工程和CI模拟器产物已具备，不上传TestFlight/App Store。

## 安全与回退

Android WebView临时Cookie存储及子资源重定向的剩余限制已明确列于 [核心说明](FLUTTER-CORE.md#安全边界与待验收限制)。未知HTML/部分数据不当作无课，不覆盖缓存。切换/重新登录会确认清理当前离线课表，取消不恢复上一账号。清理失败明确提示并保持重试入口。

退出本验证版并保留/使用原正式App即可回退；未改main、仓库可见性、蒲公英、TestFlight、App Store、腾讯线上服务或正式更新通道。

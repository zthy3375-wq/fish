# 本轮验证记录

源码基线 62e6d80；本地产品 tree 0a307ee6684142a605fd66e04205d29409c48f37 与云端 60f55205e7234bbd9f6cc4405d7b030458030447 一致，后续品牌清单、文档及 CI SDK 安装修正另行记录。

| 检查 | 实际结果 |
| --- | --- |
| npm run check | 507 前端、78共享、101后端通过；TypeScript/生产构建通过 |
| 新增前台/键盘回归 | 3项通过，包含重复事件、隐藏、失败恢复和缩放 |
| Android 本地 | Debug/Release各193项通过；Release Kotlin与Java编译通过 |
| 依赖审计 | 0 high/critical，2 moderate，未强制降级ExcelJS |
| 浅色语义文字对比度 | 正文14.36:1，辅助5.29:1，faint4.62:1（最不利背景） |
| DESIGN.md lint | 0 errors、15 warnings |
| UI严格静态检查 | 22项保留，见STATIC-AUDIT；不记为通过 |
| 云端浏览器（优化前/后各一组） | 每组629主应用、209社区、27私信、72触控，共937项；两组全部通过 |
| 本地 Chromium | 两种可用二进制均启动失败，系统套接字权限受限 |

Android本地：先npm build和cap sync，wrapper网络失败，改用已有Gradle8.11.1/JDK21/SDK35直接执行testDebugUnitTest、testReleaseUnitTest、compileReleaseKotlin成功；301项Gradle任务。未assemble APK、未签名、未分发。

云端43910628869：优化前/后检查独立运行。原生首轮setup-android默认安装已废弃tools包失败，已修正为platform-tools；保留失败记录，后续结果独立追加。

所有UI使用合成账号/内容或本地PGlite，只验证组件/接口契约，不能替代学校登录、验证码、手机输入法/相册、支付到账、物理设备出水或真实管理员操作。没有生产数据写入或迁移。

截图使用43910628869中before/after同一套自动化步骤、字体和390px视口；社区等动态账号名与时间可能不同，非像素级金图比较。对比见[截图索引](SCREENSHOTS.md)。该工作流Android首轮失败不掩盖；两组浏览器job分别成功。

云端原生复核43911803779 / job133455377116成功：SDK配置修正为platform-tools后Android测试和Release Kotlin/Java编译通过。ADB列出的设备为空；SDK无system-images，未运行模拟器。没有APK分发或更新发布。

视觉复核要求修正发帖页浅灰文字和社区图标点击宽度；已将指定颜色替换为语义muted，并将.th-icon与工具栏按钮设为44×44px。第二轮UI验证43912538358对应ecc95e7，结果与最终复核在收尾补充。

最终UI复测43912538358 / ecc95e77b2e5adea604b614e94531ad148c24f6c成功：629主应用、209社区、27私信、72触控，共937项。两处视觉问题经独立复核均已解决，结论仅覆盖浏览器修正，不扩展为Android真机通过。最终文档与截图不更改产品代码。

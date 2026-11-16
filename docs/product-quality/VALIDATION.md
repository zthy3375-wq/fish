# 本轮验证记录（待补截图结果）

源码基线 62e6d80；本地产品 tree 0a307ee6684142a605fd66e04205d29409c48f37 与云端 60f55205e7234bbd9f6cc4405d7b030458030447 一致，后续品牌清单、文档及 CI SDK 安装修正另行记录。

| 检查 | 实际结果 |
| --- | --- |
| npm run check | 507 前端、78共享、101后端通过；TypeScript/生产构建通过 |
| 新增前台/键盘回归 | 3项通过，包含重复事件、隐藏、失败恢复和缩放 |
| Android 本地 | Debug/Release各193项通过；Release Kotlin与Java编译通过 |
| 依赖审计 | 0 high/critical，2 moderate，未强制降级ExcelJS |
| 浅色语义文字对比度 | 正文14.36:1，辅助5.29:1，faint4.62:1（最不利背景） |
| DESIGN.md lint | 0 errors、3 warnings |
| UI严格静态检查 | 22项保留，见STATIC-AUDIT；不记为通过 |
| 本地 Chromium | 两种可用二进制均启动失败，系统套接字权限受限 |

Android本地：先npm build和cap sync，wrapper网络失败，改用已有Gradle8.11.1/JDK21/SDK35直接执行testDebugUnitTest、testReleaseUnitTest、compileReleaseKotlin成功；301项Gradle任务。未assemble APK、未签名、未分发。

云端43910628869：优化前/后检查独立运行。原生首轮setup-android默认安装已废弃tools包失败，已修正为platform-tools；保留失败记录，后续结果独立追加。

所有UI使用合成账号/内容或本地PGlite，只验证组件/接口契约，不能替代学校登录、验证码、手机输入法/相册、支付到账、物理设备出水或真实管理员操作。没有生产数据写入或迁移。

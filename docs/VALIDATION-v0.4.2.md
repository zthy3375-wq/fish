# v0.4.2 验证记录

2026-11-06，独立测试分支，基线 main `376c8ede`。

| 项目 | 实际状态 |
| --- | --- |
| Web 单元测试 | 16 个文件、155/155 通过；其中原 main 94 项、从 PR #2 移植31项，本轮新增30项 |
| 课程 DOM/数据链路 | JSDOM 人工 grid/list/kbList 样本，登录/不可信来源不读、身份/密码不读、报告不含真实字段、特殊安排标记、异常不静默丢弃、确认保存到独立学期与备份往返均通过 |
| 类型检查/正式 Web 构建 | `npm run build`（vue-tsc + Vite）通过，默认不启用诊断页 |
| Android 诊断 Web 构建 | `npm run build:diagnostic` 通过，Capacitor Android sync 完成 |
| 原生单元测试 | diagnostic/release 各6项通过（新增5项策略测试 + 原有示例1项），含实际 BuildConfig 开关、精确 HTTPS origin、站外/协议/端口/userinfo 拒绝与登录路径不可读 |
| Android Gradle | JDK21、SDK35，`testDiagnosticUnitTest testReleaseUnitTest assembleDiagnostic assembleRelease` 最终成功。debug 签名的 diagnostic APK 已实际生成，release 仅编译未作发布签名 |
| APK 检查 | apksigner 验证通过；包名 `org.handancampus.app.diagnostic`，versionCode 6，versionName 0.4.2-diagnostic |
| 本地 Chromium | 环境禁止进程单例 socket，无法启动；云浏览器无法访问本地服务。没有把本地移动 UI 检查报告为通过 |
| GitHub Actions | 工作流新增独立 browser 作业，测试360×800、390×844、430×932，原生桥接替身/人工数据；另一个 APK 作业实际原生编译、测试与上传，最终以 PR Checks/Artifacts 为准 |
| 学校账号端到端 | 未执行，没有学生账号；不能宣称已兼容邯郸学院实际登录后 DOM 或实际导入成功 |
| Android 真机/WebView/返回手势/验证码 | 未执行；原生编译与策略单测不能代替手机操作 |
| 持续同步/跨启动授权复用 | 未实现；没有提取/持久化学校凭据，不宣称无限期登录 |
| iOS | 保留工程，本轮没有编译或真机验证，也没有 Android 会话机制的 iOS 移植 |

环境问题与解决：原云端只有 JRE 无 javac，下载官方 Temurin JDK21 补齐；构建网络使用环境已有代理与系统 CA 信任库，没有禁用 TLS 验证。首次新增 JSDOM 测试暴露 eval 的 unknown 类型，增加字符串类型检查后重跑类型检查通过。原有 ExcelJS >500KB 分包警告仍在。

学校实验窗口的实际行为待用户在自己手机验证。若未知认证域名、资源、DOM、iframe 或特殊安排触发限制，应导出最小结构报告用于后续调整，不能把“没有解析”当作“无课”，也不能上传原始日志、Cookie 或完整网页。

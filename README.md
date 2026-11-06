# 邯郸校园 · Handan Campus

面向邯郸学院学生的独立开源校园客户端。Vue 3 + TypeScript + Vite + Capacitor，Android 通过 Kotlin 原生模块连接学校教务系统。非学校官方应用。

**当前可用测试基线：v0.5.0.5（Android versionCode 55）。** 2026-11-06，项目所有者已在本人手机上确认：官方登录后自动同步真实课表，关闭重开仍可查看，当前会话无需重新登录。

> [PR #5](https://github.com/zthy3375-wq/fish/pull/5) 已合并到 main。后续开发从 main 建立短期分支，通过 PR 检查后合并；历史网页版不代表当前 Android 功能。

[功能与验证状态](docs/STATUS.md) · [文档导航](docs/README.md) · [版本记录](CHANGELOG.md) · [参与贡献](CONTRIBUTING.md)

## 当前功能

| 模块 | 当前能力 | 验证范围 |
| --- | --- | --- |
| 学校连接 | 官方网页登录、原生加密保存会话、复用认证、退出清理 | 本人 Android 设备的登录与重开已确认；长期有效期由学校决定 |
| 课表 | 自动查询、日/周展示、多安排与单双周、缓存、刷新、失败保留旧数据 | 真实同步与关闭重开查看已确认；完整性持续核对 |
| 实践课 | 按学校返回的教学周单独显示 | 网页结构与解析已检查；具体显示持续核对 |
| 成绩 | 真实查询、学期筛选、等级成绩、学校绩点、适用时的数值加权 | 手机曾显示92门记录；非演示数据 |
| 考试 | 真实查询、独立更新时间、无安排空状态 | 手机查询已完成；尚无非空考试样本验收 |
| 个人事项 | 独立管理、CSV/XLSX/ICS 导入、备份恢复 | 原有功能保留；不覆盖学校课程 |
| 首页与设置 | 下一节课、今日课程、近期考试、四导航、主题与紧凑布局 | Web/Android 已实现 |
| iOS | 保留 Capacitor 工程 | Swift 学校会话尚未实现，不宣称支持学校直连 |

学校第一教学周日期仍来自本机配置，不能视为已验证的官方校历。当前结论只覆盖本人设备和本人账号，尚不代表全校兼容性验收。

## 安装 Android 测试包

1. 打开 [PR #5 的检查记录](https://github.com/zthy3375-wq/fish/pull/5/checks) 或 [Android 构建工作流](https://github.com/zthy3375-wq/fish/actions/workflows/android-test.yml)。
2. 选择对应分支且**成功完成**的运行，在 Artifacts 下载测试 APK 压缩包，解压后安装 APK。GitHub 下载 Artifacts 通常需要登录；保留期限以该次构建为准。
3. 首次点击“连接邯郸学院”，在官方页面自行登录，之后自动查询。日常直接查看或刷新，学校会话过期时重新认证。

APK 使用测试签名。覆盖安装优先；签名冲突时先保留原应用和备份，不默认卸载。旧诊断包 `org.handancampus.app.diagnostic` 与当前包 `org.handancampus.app` 的数据彼此隔离。

## 本地开发

Node.js 22+；依赖以 `package-lock.json` 为准。

```sh
npm ci
npm run dev
npm run check
```

Android 需要完整 JDK 21（含 javac）、Android SDK 35 与 build-tools 35.0.0：

```sh
npm run android:check
npm run android:apk
```

以上 npm 命令会自动选择 Windows/Linux 的 Gradle Wrapper。正式签名与商店发布尚未配置；`assembleRelease` 不等于生成可直接分发的已签名正式 APK。iOS 编译需要 macOS/Xcode，并有独立的手动 CI；编译成功也不等于已实现学校会话。

## 架构与数据

- `src/components/`、`src/composables/`：Vue 展示、导航、个人课表与学校数据状态。
- `src/services/academic-sync-engine.ts`：学校缓存、分模块更新、重复请求合并、错误保护。
- `src/services/handan-academic-client.ts`：类型化原生客户端接口；Vue 不处理 Cookie 或密码。
- `android/.../academic/`：官方 WebView、CookieManager、Android Keystore AES-GCM 会话存储。
- `android/app/src/main/assets/handan-*.js`：随 APK 编译的固定查询和页面读取脚本。
- `src/domain/`：课程、学期、作息与时间计算；`tests/`：格式、状态、存储和边界回归。

个人课表与学校缓存分开保存；查询失败或异常空响应不会清空上次成功课表。没有业务后端或分析追踪 SDK；学校正常查询仍需设备直接连接官方服务。

## 贡献与许可

原创代码采用 [MIT](LICENSE)。上游研究与历史设计记录见 [文档导航](docs/README.md)。第一版范围为首页、课表、教务和个人设置；社区、二手交易、商家与失物招领尚未开发。

请勿向 Issue、日志、截图或 PR 提交密码、Cookie、令牌及未脱敏学籍信息。查看 [安全说明](SECURITY.md) 与 [贡献指南](CONTRIBUTING.md)。

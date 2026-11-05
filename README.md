# 邯郸校园 · Handan Campus

面向邯郸学院学生的独立校园助手，Web 优先，未来提供 Android 与 iOS。当前 `v0.1.0` 为可交互模拟教务版本，非学校官方应用。

## 已实现

- 首页：今日课程、下一节课、教学周、教务快捷入口。
- 教务：1–18 周课表、按日查看、课程详情、单双周过滤；成绩学期筛选和搜索、学分加权平均；考试、模拟学业进度、模拟校历、官方外链。
- 个人：昵称/专业编辑、浅色/深色/系统主题、紧凑布局、演示应用内提醒、重置本机偏好、隐私说明。
- 响应式桌面侧栏/手机底栏、安全区、焦点圈、弹窗焦点约束与 Escape 关闭、减少动效支持。

**所有课程、教师、教室、成绩、考试、学业进度、开学日期与教学周均为虚构演示。首页固定为 2026-11-05 09:40 的演示时钟，不是实时教务。** 当前专业与年级也不代表真实个人资料。

## 运行

Node.js 22 LTS 或以上，使用仓库中的 package-lock.json。

```sh
npm ci
npm run dev
npm test
npm run build
```

Vue 3 + TypeScript + Vite；无远端教务 API，无账号注册，无追踪 SDK，无第三方字体请求。默认浅色，以本地 localStorage 保存非敏感偏好。浏览器存储不可用时允许继续体验，并提示无法保存。

## 原生平台

Android/iOS 工程已生成，`capacitor.config.ts` 使用 `dist/`；本期未构建签名安装包。

```sh
npm run cap:sync
npx cap open android
npx cap open ios
```

Android 需要 Android Studio/SDK/JDK；iOS 构建与签名需要 macOS/Xcode，发布需相应开发者账号。修改应用标识、签名与版本后再发布。Android/iOS 默认不申请相机、定位或通知权限。

## 结构

- `src/domain/academic.ts`：类型、课表筛选、时间与成绩计算。
- `src/services/academic.ts`：AcademicProvider 契约与独立模拟数据源。
- `src/services/preferences.ts`：带字段校验的本机偏好与故障降级。
- `src/App.vue`：三个业务页面；后续按模块继续拆分组件。
- `src/style.css`：响应式布局、设计变量、动效和主题。
- `android/`、`ios/`：Capacitor 壳。
- `tests/`：计算和存储边界测试。
- `docs/RESEARCH.md`：四个参考仓库的架构、UI、许可证研究。
- `docs/VALIDATION.md`：已执行检查与验证范围。
- `.github/workflows/ci.yml`：push/PR 自动测试及生产构建。

## 后续接入

先取得学校系统访问与数据使用授权，再实现新的 AcademicProvider。不要在前端硬编码凭据或尝试绕过验证码、认证、网络限制。真实会话管理、数据规范化、接口错误与隐私策略需要随接入方案一起设计；当前没有用假后端冒充真实服务。

## 贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。原创代码 MIT；设计研究来源与上游许可记录见 [docs/RESEARCH.md](docs/RESEARCH.md)。本期不包含交易、社区、商家或失物招领。

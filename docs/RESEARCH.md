# 校园应用研究与选型

核对日期：2026-11-05。研究材料为各项目公开仓库的 README、许可证、依赖清单、工程目录及部分关键实现；没有编译运行这些上游 App，也不据此宣称完成了上游真机体验。所有实现均为本项目原创，未搬运上游源码、图标或品牌素材。

| 项目 / 核对提交 | 功能与界面组织 | 工程结构 | 许可证文件 | 本项目采用的思路 |
|---|---|---|---|---|
| [UBAA](https://github.com/BUAASubnet/UBAA) / `155e8b5` | 统一认证、课表、考试、成绩、教室、图书馆等；Material 3；HomeScreen 先展示按时间排序的今日课，再接待办，区分错误、加载、空状态 | Kotlin Multiplatform + Compose；composeApp UI，shared DTO/接口，Ktor server 网关；Android/iOS 壳；支持 Web | MIT | 让今日课程成为首页主任务；通过统一 AcademicProvider 隔离学校差异，UI 不直接解析教务网页 |
| [HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule) / `215a807` | 40+ 校园场景，离网读取、游客数据；Material 3、全局转场与模糊；冷启动优先关键内容 | Kotlin / Android Compose；common-ui、common-logic、network-api、network-core 等模块，baselineProfile 优化 | Apache-2.0 | 游客数据先行、无需登录探索；公共视觉变量与业务模型分离；轻量 opacity/transform 动画和减弱动态效果设置 |
| [DanXi](https://github.com/DanXi-Dev/DanXi) / `3c1f5f0` | 课表、考试、成绩、通知等一站服务；DashboardCard 用 title/link/enabled 模型表达入口；跨端平台导航组件 | Dart/Flutter；repository 按校园上游域隔离；provider 状态；BaseRepositoryWithDio 集中超时、Cookie、错误及网络适配 | GPL-3.0（部分源文件明确 or-later，复用时需逐文件核对） | 导航只保留首页/教务/个人；入口采用结构化配置；将来真实数据源与界面保持分离；本期不启用登录与 Cookie |
| [fzuhelper-app](https://github.com/west2-online/fzuhelper-app) / `3b4ef9f` | 课表作为核心 Tab，成绩、考场、学习中心等集中；课表周切换、课程详情、安全区容器；README 提供各页面截图 | TypeScript / React Native / Expo Router；api/generated、components、hooks、context、原生 modules；TanStack Query 持久查询缓存 | LICENSE 为 AGPL-3.0，README 同时含额外使用限制声明且措辞不一致 | 借鉴课表周边界、内容安全区、多状态页面的通用理念；不引入其代码/资源，未来如需复用先取得明确许可 |

## 实际阅读路径

- UBAA：`README.md`、`LICENSE`、`docs/tech/architecture.md`、`composeApp/.../ui/screens/menu/HomeScreen.kt`。
- HFUT-Schedule：`README.md`、`LICENSE`、`docs/Arch.md`（正文标注待完善，不能当完整架构说明）、common-ui/common-logic/network-api/network-core 工程结构。
- DanXi：`README.md`、`LICENSE`、`pubspec.yaml`、`lib/model/dashboard_card.dart`、`lib/repository/base_repository.dart` 与 repository/platform widget 目录。
- fzuhelper-app：`README.md`、`LICENSE`、`package.json`、`app/(tabs)/index.tsx`、app/settings 与 components/api/context 结构。

## 技术决策 ADR-001

保留 Vue 3 + TypeScript + Vite + Capacitor。当前首要目标是可用的移动网页、手机直接预览和快速迭代；三个模块以表单、列表、课程卡片为主，不需要引入原生渲染引擎。Vue 提供低成本 Web 交付，Capacitor 在同一 dist 基础上承载 Android/iOS。采用原生 CSS 设计变量而不是重型移动 UI 套件，形成轻量、统一的浅蓝灰风格。默认浅色，深色与系统主题均可选。

代价：WebView 复杂手势、后台任务、系统推送与无障碍行为仍需原生插件和真机验证；Capacitor 并不等于已完成双平台发布。本版已经生成 Android/iOS 壳，但不声称通过签名、商店审核或原生构建。

## 许可证与开源边界

本项目原创部分使用 MIT，保留完整许可证。上表是许可证核对记录，不构成对上游全部依赖的审计；若未来移植源码，应再核对具体文件、依赖及声明，保留版权、NOTICE 和对应开源义务。GPL/AGPL 项目没有因为本项目计划开源而被排除，当前跨语言技术栈和范围更适合独立实现。福大助手额外声明的解释未在本任务中得到澄清，因此没有复制其内容。

本项目直接依赖 Vue（MIT）、lucide-vue-next（ISC）和 Capacitor（MIT）；图标通过 npm 依赖提供并保留其包内许可。学校名称仅用于说明服务对象；无官方校徽、官方认证或合作声明。

## 官方链接核对

- https://www.hdc.edu.cn/ ：学校公开首页，包含正方教务入口。
- https://jwgl.hdc.edu.cn/xtgl/login_slogin.html ：公开登录页标题为邯郸学院教学综合信息服务平台。

只核对公开页和设置外链，没有登录、抓取受限内容、尝试接口或保存学校凭据。本版不采用未经核验的教务处子站地址。

# v0.8.2 · 菜鸟驿站出库码入口

历史实现记录。1.2.2-test.2 已替换包名/resolve 前置拦截，并增加用户显式系统兼容重试；当前行为见 docs/STATUS.md，以下“不降级”及“仅 provider”描述不再代表现行实现。

## 本轮范围

今天和我的的校园生活区新增「淘宝出库码」「拼多多出库码」两个固定快捷入口。不改变五个主导航，不新增校园账号连接，不改动学校、趣智、学习通或个人事项的缓存和存储键。

点击后请求 Android 打开相应官方 App。用户使用该 App 自己的登录账号和动态身份码；邯郸校园不读取、保存、生成、截图或缓存身份码，不获取快递列表、手机号、订单或取件结果。没有新权限授权、后台查询或自动拉起。

网页版保留说明和禁用入口，明确需要 Android 客户端，不尝试通过网页或不限定 App 的链接降级。

## 路由证据及使用边界

固定事实来自 JUWPHub 仓库的 `Shortcuts.kt`，已核对本地参考仓库 HEAD 为 `edf81286f26673968d4a804b6fd6bf6fc13f35ef`：

- [拼多多路由及包名，第 67–68 行](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/domain/Shortcuts.kt#L67-L68)：`pinduoduo://com.xunmeng.pinduoduo/mdkd/package?tab=ID_CODE`，包名 `com.xunmeng.pinduoduo`。
- [淘宝路由及包名，第 74–75 行](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/domain/Shortcuts.kt#L74-L75)：`https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code`，包名 `com.taobao.taobao`。
- 上游注释记录拼多多的 `tab=ID_CODE` 用于身份码页；该说明属于上游测试记录，不是本项目在用户手机上的实测结果。

上游为 GPL-3.0。本项目仅记录这些功能性路由和包名事实，独立编写固定枚举桥接、启动控制、界面和测试；未复制上游通用快捷方式实现、配置迁移、UI 或启动回退逻辑。以上来源并非平台的稳定公开 API 承诺，路由可能随官方 App 更新失效。本轮没有逆向或调用取件身份码接口。

## 原生与前端契约

原生插件 `ParcelShortcuts.open({provider})` 只接受 `taobao` 或 `pinduoduo`，拒绝缺少字段、未知值和所有额外参数。调用方不能提供 URL、包名、Activity、脚本或身份信息。路由只在 Kotlin 固定定义。

AndroidManifest 仅增加两个包的可见性声明，没有 `QUERY_ALL_PACKAGES`。启动 Intent 始终带 `setPackage`，并检查解析出的 Activity 属于指定包且可用、可导出；不能打开时不移除包名，不回退到浏览器、其他 App 或未经核对的路径。

返回 `{provider, status}`：

| 状态 | 含义与界面处理 |
| --- | --- |
| `opened` | Android 接受了启动请求。显示「已请求打开」，不代表目标页加载完成、登录成功、身份验证通过或已出库。 |
| `not_installed` | 未检测到目标包，提示先安装官方 App，再重试。 |
| `unavailable` | 路由不可用、Activity 被禁用、启动异常或错误回包，提示手动进入官方 App 查看身份码。 |
| `cancelled` | 本次启动前页面已销毁或启动已取消，不继续拉起；允许用户再次点击。 |

前端额外的 `unsupported` 状态表示当前不是支持该插件的 Android 客户端。前端校验回包 provider 与状态，固定错误文案，不展示原生异常载荷。等待启动回包时禁用两个按钮并合并连续点击；导航后的迟到回包不会污染新页面。

官方 App 的返回键、取消登录、未展示码、取件完成等行为均没有可信回调。因此返回邯郸校园时不执行身份码刷新、不推断取件结果，也不把外部 App 的通用 `RESULT_CANCELED` 冒充已知用户取消。

## 检查与验收

本地已通过：

- 21 项服务/原生注册与安全边界测试、8 项 Vue 组件交互测试。
- 8 项纯 Kotlin/JUnit 契约测试，覆盖固定路由、参数拒绝、未安装、路由不可用、启动异常、销毁取消与不降级重试。
- 出库码实现的 TypeScript 和 Vite 生产构建。

`scripts/parcel-browser-check.mjs` 已纳入 `npm run test:ui`，覆盖 360/390/430px、今天/我的入口、重复点击、错误/取消、迟到回包、缓存保护、导航和无横向溢出。当前执行环境的 Playwright 浏览器缺失；改用系统 Chromium 后进程仍被 `socket() failed: Operation not permitted` 阻止，尚未完成该浏览器回归。可在支持 Chromium 的环境执行；如需系统浏览器，可设置 `PLAYWRIGHT_CHROMIUM_EXECUTABLE` 为其路径。

当前环境没有已配置 Android SDK，纯 Kotlin 契约测试不等于原生 Plugin 编译、APK 安装或路由真机验收。完整 Android 构建与以下真机项目仍须核对：

1. 淘宝、拼多多分别已安装且登录时，点击对应按钮能进入本人出库身份码页面；记录官方 App 版本。
2. 未登录时由官方 App 自行完成登录，邯郸校园不出现平台账号/密码输入框。
3. 目标 App 未安装、停用、版本不支持该路由时，给出可理解的提示，不转交其他 App。
4. 外部 App 取消、按返回键、切回邯郸校园和多次点击，不出现「取件成功」或伪造的码。
5. 两个 App 均分别验证，不能用其中一个成功代表另一个；截图如含身份码或账户资料应遮盖，不提交原图。

本说明仅覆盖出库码入口，不将胖乖/趣智的登录、钱包或充值结果纳入该功能的验证结论。

# v0.8.2 胖乖官方钱包/充值页面

## 交付范围

今天和我的提供“官方钱包”“官方充值页面”两个入口。支持的 Android/WebView 使用独立进程与独立网页数据目录展示胖乖官方 H5，页面自己负责登录、验证码、余额、运营商与订单。本项目没有原生胖乖余额连接器，不显示模拟余额，不保存“已登录”或“充值成功”标志，也没有扫码使用设备的入口。

官方页面仍可能有广告、统计、验证码和平台限制，不是去广告的原生钱包。入口、静态页面语义及来源见 [协议研究](research/V082-PANGGUAI.md)。截至 2026-11-08，没有真实账号登录、短信、账户查询、建单、付款、设备操作或 Android 真机验收。

## 用户操作

1. “官方钱包”先打开 `https://h5.qiekj.com/pages/wallet/myWallet/myWallet`。未登录时由官方自己的账户错误处理转到登录页，并尝试保留原目的地。不能保证网络或页面变化后仍自动跳转。
2. “官方充值页面”打开 `https://h5.qiekj.com/user/recharge/goldList/goldList`。运营商和商户标识由官方账户列表提供。没有写入邯郸学院或其他学校的默认 shopId，也不预选套餐、金额或支付渠道。
3. 顶部显示提供方和域名，保留返回、关闭、登录、钱包、运营商、清除会话。登录后未跳回时可手动选择钱包/运营商。没有账号解绑或伪装成“退出”的快捷按钮。
4. 普通 WebView 完整支付流程尚未证实。未知外链、支付 scheme、Intent URI、银行页面及文件下载不会自动交给系统。无法继续时可点击底部“打开支付宝胖乖小程序”，经本地确认后，只请求官方支付宝打开固定小程序首页。
5. 小程序首页并非学校专属充值页。支付宝小程序登录账号与官方网页独立，不转移网页会话；本地打开确认会提示核对手机号/账户、实际运营商、金额。用户需在小程序自行核对退款条件并确认付款，本应用不提交付款。Android 接受打开请求、跳转与返回均不代表登录或到账成功；返回时提醒核对官方余额/订单，未确认前不要重复付款。

外部入口固定为 `alipays://platformapi/startapp?appId=2018072460764274`，限定目标包 `com.eg.android.AlipayGphone`。没有调用 `Intent.parseUri`，没有传入来自网页的参数、商户号、订单号、支付金额或 fallback URL。目标未安装/不可用时显示手动进入官方 App 或小程序的提示，不放开包名或改用任意网页。

## 会话、账号与隐私

- 保持系统原始 WebView User-Agent，不冒充胖乖 App 或支付宿主。不安装 JavascriptInterface/Capacitor/native bridge，不执行注入脚本，不提取手机号、验证码、密码、token、余额或支付回调。
- 官方网页自行保存的会话可能留在本机。关闭窗口不等于退出账号，也不等于取消订单或解绑。
- 官方设置的已核实按钮是“解除绑定”，不是本项目承诺的退出按钮。它在官方确认后先调用 `user/release`，参数 channel 为 wechat，然后清网页 token。普通 H5 是否能成功尚未核实，网络/服务拒绝可能使清理无法完成。用户应核对官方提示，不把解绑等同于单纯本地退出。
- 胖乖窗口运行在非导出的 `:pangguai_official` 进程。Application.attachBaseContext 在内容提供方启动及任何 WebKit 调用前，核对实际 packageName/process，再用 Android 9+ 的 `WebView.setDataDirectorySuffix("pangguai_official")` 选择独立数据目录。不复制原共享窗口里的会话，不触及主进程教务 Cookie/缓存，也不调用后台解绑接口。现有教务、趣智、课表和任务存储键不变。
- 内嵌网页还必须支持运行时 `WebViewFeature.DELETE_BROWSING_DATA`。项目显式依赖官方 AndroidX WebKit 1.13.0。Android 9 以下、进程/目录初始化失败、清理特性不可用或无法读取清理状态时，禁用内嵌网页，只提供明确确认后的固定小程序入口。不能仅凭 Android 版本推断清理特性可用。
- “清除会话”需本地确认，调用官方 `WebStorageCompat.deleteBrowsingData` 清理此独立 profile 的 Cookie、网络缓存、JavaScript 存储与已安装 Service Worker。只有官方完成回调且清理状态成功落盘后，才显示本机数据已清除；这不是服务器退出、支付宝退出、取消订单或解除账号绑定。
- 清理前先持久记录 reset-pending，代次栅栏使旧回调失效，控制器必须成功销毁唯一所属 WebView 后才开始清理。销毁失败时保留原生视图引用并隔离当前进程；不能丢掉引用后继续删除。清理期间不允许重开页面。进程中断后先完成待处理清理，再允许新页面。
- 平台删除不是原子操作。超时不等于取消：保持未完成标记和在途删除锁，禁止重开和重叠重试。迟到回调只释放在途锁，继续保持暂停，允许用户明确再试；无回调/结果不明则当前进程保持暂停，直到进程重启后重试。没有用 legacy deleteAllData、CookieManager 回调或 getOrigins 充当完整清理完成证据，也不手动删除 Chromium 文件。
- 第三方 Cookie 关闭；文件/内容访问、混合内容、自动弹窗/多窗口、文件选择、下载、定位和页面权限申请均不开放。TLS 证书错误取消连接。敏感窗口设置 FLAG_SECURE；构建配置与创建官方 WebView 前均关闭 WebContents 调试，包括 debug APK。
- 前端和原生只返回固定页面枚举与请求状态。错误提示不包含官方 URL、查询参数、异常原文或网页日志。网页控制台输出不转发到 logcat。

## 导航与资源边界

原生文档导航只接受 HTTPS、无 userinfo、默认/443 端口和精确主机，不使用后缀域名匹配：

- `h5.qiekj.com`：固定入口、根路径回退、已核实的钱包/余额明细、运营商小票/购买、协议/隐私和账号设置路径。
- `market.qiekj.com`：仅 `/marketing?id=34` 与 `/marketing?id=66`，分别为已核实隐私及购买协议。

此策略约束原生可观察的文档跳转。**官方 H5 是 Vue history SPA，pushState/replaceState 和同文档组件切换可能不触发 WebView 导航回调，因此不承诺每个站内路径都被隔离，也不把官方页面称为只读。** 用户在官方页面的操作仍由平台控制。真正稳定的本地边界是不提供原生账户/支付/设备桥、不接受任意外部 Intent、不授予设备权限。

子资源与顶层导航分别判断。允许精确 HTTPS 资源主机：

- `h5.qiekj.com`、`static.qiekj.com`、`userapi.qiekj.com`、`market.qiekj.com`。
- 官方登录使用的网易易盾静态 bootstrap：`cstaticdun.126.net`、`cstaticdun1.126.net`、`cstaticdun-v6.126.net`。
- 从公开 `load.min.js` 核实的初始化 API：`c.dun.163.com`、`c.dun.163yun.com`、`c-v6.dun.163.com`。
- 同一 bootstrap 核实的可选 Watchman API：`ac.dun.163.com`、`ac.dun.163yun.com`、`ac-v6.dun.163yun.com`。

不允许上述 API/资源主机作为任意顶层页面。没有通配域名、全 HTTPS 放行或接受服务器返回任意资源域。后续 CAPTCHA API、图片和 IRisk 配置可能动态下发，尚未全部核实，因此验证码兼容性仍待设备测试。受限资源提示去重，不暴露 URL；失败时提示使用官方 App/小程序，不绕过验证码，不伪造验证成功。

## 验证与限制

2026-11-08 本地证据：

- 新增 26 项服务/桥边界测试、8 项 Vue 交互测试，覆盖固定枚举、平台不可用、错误隐藏、重复点击、取消、重试、卸载后的迟到结果、会话提示、无虚构余额和无支付成功推断。
- 新增 16 项纯 Kotlin/JUnit 策略与生命周期测试，覆盖固定入口、额外参数拒绝、允许路径、market 协议限定、主机伪装/不安全 scheme、资源与顶层隔离、固定小程序目的地，以及进程身份/版本门槛、单视图、清理隔离、超时禁止重叠、迟到回调、待清理恢复、标记读写失败。以 Kotlin 1.9.24 和 JUnit 4.13.2 独立编译运行通过；不等同于 Android Activity 编译或 WebView 运行。
- 仓库 `npm run check`：341 项测试、TypeScript 检查、生产构建通过。既有 ExcelJS 大 chunk 提示仍存在。
- 浏览器替身用例接入 `scripts/pangguai-browser-check.mjs`。Chromium 在本环境因 socket 系统调用权限被拒而无法启动，本轮没有执行通过的浏览器截图/布局结论。
- 本地没有 Android SDK/android.jar。Activity、Plugin、独立进程和数据清理控制器的 Android 编译、APK 安装、系统返回/旋转、数据清理/进程中断恢复、应用间跳转、官方页实际渲染、登录/验证码和支付均未完成运行验证。需在 Android 工作流及本人设备上分阶段验收，不能拿纯 JVM 或合成 UI 测试替代。

本轮没有提交、推送、开 PR、合并或发布。生成的构建输出不加入源码。

## 独立数据清理的官方依据

- [AndroidX WebStorageCompat API](https://developer.android.com/reference/androidx/webkit/WebStorageCompat)：deleteBrowsingData 完成回调与非原子清理约束。
- [AndroidX WebKit 1.13.0 发布说明](https://developer.android.com/jetpack/androidx/releases/webkit#1.13.0)：清理网络缓存、Cookie、本地存储与已安装 Service Worker。
- [Android WebView 数据目录 API](https://developer.android.com/reference/android/webkit/WebView#setDataDirectorySuffix(java.lang.String))：API 28+，必须先于本进程所有 WebView/其他 android.webkit 调用。

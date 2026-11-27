# 智能取件可行性与入口恢复 · 2026-11-27

本轮交付是既有官方入口的可靠性修复和一个独立的公开入口检查。正式自动同步需要两项证据：平台授权明确允许邯院通读取本人包裹，以及 Android、iOS 上的真实到站包裹及取件码验收。本轮尚未取得相关 API 授权或真实包裹样本。

## 邯院通基线和旧问题

| 范围 | 现有实现与问题 | 本轮改动 |
| --- | --- | --- |
| Android | Android 1.3.1 主线及较新的测试修复仅提供固定淘宝、拼多多出库身份码跳转。历史原生抓取实验留在旧分支。Capacitor 等待无回包时，两入口会一直禁用。 | 前端等待上限 6 秒，Kotlin 派发截止为单调时钟 4 秒。超时显示原有官方入口提示，不自动再拉起 App。 |
| iOS | 2.0.5 所用应用源码包含本机取件记录和官方 WebView 的一次性当前页读取。系统 `willResignActive` 会立即销毁该窗口，切出做官方验证会丢失临时会话。子框架响应以及上一轮导航的失败回调也可能影响当前页状态。 | 切后台隐藏官方页与本机码、取消读取并保留原有内存会话。返回恢复同一窗口，不自动重载。相同目标的在途打开合并，结束和失败回调需匹配当前导航。主框架 401、403、超时和入口不可用分别处理。 |
| 数据范围 | iOS 记录以平台、账号、驿站和货架码区分，不能当成运单索引。读取一次当前页不能推断全量完成、出库或历史消失。 | 禁止把验证、超时、403 或无法确认的页面当成空包裹。延续本机加密与账号隔离。首页不新增待取数量。 |

开发基线为 Android 测试修复 `78168bd` 和 iOS 应用源码 `9922275`。后者与 2.0.5 分发分支 `f387938` 的差异在 GitHub 工作流和分发脚本。商业试验分支以及更旧的快递抓取试验未进入本轮。

## 五个项目的源码审查

以下日期是审查时默认分支 HEAD 的提交日期。LICENSE 以固定源码版本为准。本轮补丁独立实现，未复用上游实现或客户端签名代码。

| 项目 | 审查版本 | 源码结论 |
| --- | --- | --- |
| ParcelHelper | 2026-11-24 · `3065526` · GPL-3.0 | [小米接入](https://github.com/O96u/ParcelHelper/blob/3065526033c8ec38e30e473f8c809053945f6398/App/MiExpressAccount.swift) 包含帐号会话、手机验证码绑定、取件字段映射及设备参数构造，接的是小米聚合客户端协议。[菜鸟实现](https://github.com/O96u/ParcelHelper/blob/3065526033c8ec38e30e473f8c809053945f6398/App/CainiaoSyncService.swift) 复用淘宝 Web 会话和客户端网关读取站点字段。[调度](https://github.com/O96u/ParcelHelper/blob/3065526033c8ec38e30e473f8c809053945f6398/App/SyncScheduler.swift) 合并前台并发触发，按来源和账号记录结果。存在原生 iOS 路径的代码证据，缺少邯郸学院账号、长期会话和接口获准使用的证据。 |
| ExpressAssistant | 2026-10-22 · `b892565` · MIT | [Android 小米登录页面](https://github.com/Halo0sama/ExpressAssistant/blob/b892565502d381a58a5a2c57e6d9068e07648c7a/app/src/main/java/com/halo/expressassistant/ui/XiaomiLoginActivity.java) 获取小米客户端会话和关联号码。[同步](https://github.com/Halo0sama/ExpressAssistant/blob/b892565502d381a58a5a2c57e6d9068e07648c7a/app/src/main/java/com/halo/expressassistant/api/XiaomiSync.kt) 依赖账户会话及号码。[数据整理](https://github.com/Halo0sama/ExpressAssistant/blob/b892565502d381a58a5a2c57e6d9068e07648c7a/app/src/main/java/com/halo/expressassistant/ui/SyncEngine.kt) 可从已有物流文本补取件字段。源码含设备标识兼容及可选系统能力路径，未能证明普通非小米设备长期无额外权限运行。iOS 不在此项目代码范围。 |
| Parcly | 2026-11-23 · `7f38825` · GPL-3.0 | [多源调度](https://github.com/Granter-z/parcly/blob/7f38825efbcb4be1c6d1fbedffea7601fdfc1311/lib/platform/connectors/connector_manager.dart)、[详情请求缓存](https://github.com/Granter-z/parcly/blob/7f38825efbcb4be1c6d1fbedffea7601fdfc1311/lib/platform/connectors/sync_optimizer.dart) 与[授权状态](https://github.com/Granter-z/parcly/blob/7f38825efbcb4be1c6d1fbedffea7601fdfc1311/lib/core/engine/platform_auth_status.dart) 区分平台会话和同步失败，支持受限并行、按来源加订单标识去重和跳过近期详情。现行连接器基于各平台会话，不能证明一次手机号验证覆盖三方。 |
| HandyCode | 2026-11-22 · `6643086` · MIT | [菜鸟页面](https://github.com/xianhe51920/handycode/blob/6643086555b31593b843a61d3646c15b907aae5a/app/src/main/java/com/fairycrane/handycode/CainiaoPage.java) 在 WebView 识别登录与展示阶段，可交回淘宝登录。[拼多多页面](https://github.com/xianhe51920/handycode/blob/6643086555b31593b843a61d3646c15b907aae5a/app/src/main/java/com/fairycrane/handycode/PddPage.java) 带有 H5 页面适配和版本变化恢复逻辑。可参考加载、验证、重试区分，不构成独立消费者授权 API。 |
| Parcel Pilot MCP | 2026-05-18 · `b8761d0` · MIT | [会话管理](https://github.com/jieyangxchen/parcel-pilot-mcp/blob/b8761d08148f56e462b79a58da4d06acfb94563c/src/browser/browser-session-manager.ts) 采用 Playwright 本地用户配置，[菜鸟适配器](https://github.com/jieyangxchen/parcel-pilot-mcp/blob/b8761d08148f56e462b79a58da4d06acfb94563c/src/providers/cainiao-provider.ts) 将登录及查询均指向菜鸟集团首页，[解析器](https://github.com/jieyangxchen/parcel-pilot-mcp/blob/b8761d08148f56e462b79a58da4d06acfb94563c/src/providers/html-parsing.ts) 读取通用卡片和物流字段，无明确的取件码映射。同步过程可输出网页截图，本轮未使用该方式接触真实账号。 |

## 数据源选择

| 路线 | 官方权限与输入 | 本轮判定 |
| --- | --- | --- |
| 小米快递聚合 | [账号 OAuth 文档](https://dev.mi.com/docs/passport/open-api/) 有用户资料、手机号及邮箱等权限。参考项目的快递列表依赖聚合客户端的账号/设备协议。本轮未找到可分配给邯院通的快递列表、取件码权限。 | 保留为平台开通权限后的候选。普通小米账号 OAuth 和手机号验证均不足以证明可读快递。 |
| 菜鸟消费者查询 | 消费者 App 内能查看本人快递。查到的[开放平台派件接口](https://developer.alibaba.com/docs/api.htm?apiId=32967)面向驿站派件、以运单号为输入。[菜鸟物流科技取件码产品](https://tech.cainiao.com/productv2/ProductIndex/6)明确使用运单号加收件手机号鉴权。 | 菜鸟物流科技是补齐**已知运单**取件码的优先官方候选，可走平台接入评估。尚缺授权后列出该手机号全部待取运单的接口。它的总体覆盖数据不能代替邯郸学院驿站的验收。 |
| 淘宝授权及校园待取页 | [淘宝 OAuth](https://developer.alibaba.com/docs/doc.htm?articleId=102635&docType=1&treeId=154) 使用应用获准的能力和用户授权。[买家订单 API](https://developer.alibaba.com/docs/api.htm?apiId=45) 文档描述淘宝买家交易，[轨迹 API](https://developer.alibaba.com/docs/api.htm?apiId=10463) 接收淘宝交易号。校园待取 H5 仍是产品网页。 | 淘宝可作已授权淘系订单的运单候选。尚未证明覆盖拼多多等跨平台包裹，也没有已获批的消费者级取件码权限。现有 H5 仅作为官方前台入口。 |
| 快递100等 | [普通轨迹](https://api.kuaidi100.com/document/5f0ffb5ebc8da837cbd8aefc.html)以运单号为输入。[手机号数据文档](https://api.kuaidi100.com/document/6051a69aa52d305ab4d2a1cf)列在快递公司入驻，[入驻资料](https://api.kuaidi100.com/document/ruzhuziliao)要求快递公司签章授权。[取件码 API](https://api.kuaidi100.com/document/qujianmaapi)要求企业凭证、提前提交运单订阅和回调。 | 无法用这些公开文档确认第三方 App 可查询消费者全部现有待取件，也无法用提前订阅覆盖先前已入库的存量。 |

只拿到本人手机号仍缺少获准使用的运单目录。首选验证顺序是先取得消费者运单列表授权，再按需要用平台核准的单票能力补取件码。验收至少要覆盖淘宝与拼多多各一件已进同一校区菜鸟驿站的本人包裹，在非小米 Android 和 iPhone 上核对取件码、跨来源去重、正式出库状态、授权重启和续期及失败时旧记录保留。后台频率需要按接口限速、平台授权与 [iOS 后台调度](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)共同确定。处理范围和授权按[个人信息保护法](https://www.samr.gov.cn/wljys/gzzd/art/2023/art_3ef1e889c1e644d4b65b5f5c7f432386.html)在接入后核对。

## 验证记录

`node scripts/parcel-source-check.mjs` 在 2026-11-27 从此执行环境实际请求了公开入口。每个来源只对固定官方 HTTPS 页面发 GET，限制重定向，不存正文或响应凭据。

| 公开入口 | 第一次完成记录 |
| --- | --- |
| 小米账户入口 | 请求超时 |
| 菜鸟集团官网 | HTTP 200 HTML |
| 淘宝校园取件 H5 | HTTP 403，此环境无法从该响应判断原因或授权后行为 |
| 拼多多官方取件 H5 | HTTP 200 HTML |

HTTP 200 只说明返回了网页。上述四项均为未认证阶段，没有真实运单、取件码、出库状态、覆盖率或同步耗时样本。本地的页面读取和状态回归使用合成夹具。源码基于独立开发分支，正式更新与 TestFlight 都需要所有者另行授权。

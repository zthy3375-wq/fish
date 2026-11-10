# 取件中心重新设计 · 2026-11-10

状态：设计方案；test.3 已实现原生中心、官方待取响应读取、加密缓存与码图展示，正在构建验证。购物订单补全尚未完成，真实账号未验证。以下完整目标不可当成已交付能力，具体以 docs/STATUS.md 为准。

## 目标与旧方案问题

用户要求在邯院通内直接看到真实取件码。旧版让用户操作官方网页、三排默认按钮，账号登录、数据读取和展示混为一体；列表只读取本次可见 DOM，退到后台就清空，不满足日常取件。

新主流程：打开取件中心 → 立即显示上次成功同步的本人包裹 → 前台增量更新 → 点击码放大。首次登录和必要验证使用独立官方登录页，成功验证后自动关闭。日常列表使用 Kotlin 原生视图，平台网页只承担认证及必要的数据运行环境。

## 查阅的主要项目

| 项目 | 源码事实 | 对本项目的用途 |
| --- | --- | --- |
| [ExpressAssistant](https://github.com/Halo0sama/ExpressAssistant) | Kotlin；TbOrders 查询淘宝订单并解析物流 SSR；PddCapture/PddListFetcher 在网页上下文捕获订单响应；PddTraceFetcher 读取物流页 | Android 数据通道优先参考；MIT，保留原许可及来源 |
| [Parcly](https://github.com/Granter-z/parcly) | Flutter；淘宝 MTOP、菜鸟站点包裹及物流补全；拼多多订单响应、rawData、物流文本组合解析 | 参考数据模型、同步与状态判定思路；GPL-3.0，不直接复制到当前工程 |
| [HandyCode](https://github.com/xianhe51920/handycode) | 淘宝 iframe DOM 投影，拼多多官方 React/DOM 投影；身份码使用官方生成内容 | 身份码生成、刷新生命周期和官方登录兼容的参考；不再把页面投影作为包裹主 UI |
| [HuTaoParcelBox](https://github.com/DavidLWB/HuTaoParcelBox) | 基于官方 WebView 的卡片容器；上游参考 HandyCode | 确认与旧方案同类，不能据此声称获得完整原生数据源 |
| [shareven/parcel](https://github.com/shareven/parcel) | 短信解析、本地取件码及桌面卡片 | 可选补充通道，不替代淘宝、拼多多接入 |
| [PickTool](https://github.com/yimeifun/PickTool)、[pinduoduo-quick](https://github.com/ranjiushu/pinduoduo-quick) | 深链打开官方应用或网页 | 只保留为故障帮助入口 |
| [pickup-code-app](https://github.com/zixij644-elaborate/pickup-code-app) | 截图/分享 OCR 与取件码提取 | 后续可选导入，本轮不要求用户截图 |

读取时 Parcly Git tree：c9b0128efb08c4b04b9bd7273d1b1fedcc17a813；ExpressAssistant Git tree：b892565502d381a58a5a2c57e6d9068e07648c7a。上述为树 SHA，不冒充提交 SHA。研究同时读取了 README、核心连接器、登录流程及 ExpressAssistant 的 PDD_REAL 文档和 issue 列表。

## 淘宝数据通道

已在源码看到的接口与页面，均属于上游客户端使用的内部接口线索，尚未在邯院通本人账号验证：

- `mtop.taobao.order.queryboughtlistv2`：订单列表。
- `mtop.cainiao.pickup.plus.queryMultiStaPackages4Xy`：菜鸟多站点包裹列表，源码请求 stationType=XY；不可假定覆盖全部驿站。
- `mtop.cnwireless.cnlogisticdetailservice.wapquerylogisticpackagebymailno`：按已知运单号补取物流与取件信息。
- `pages-g.m.taobao.com/wow/z/app/mtb/logisticsV2/h5-detail?x-ssr=true&bizOrderId=...`：订单物流 SSR 数据。

实现顺序：官方登录 → 验证真实已登录响应 → 优先读取站点待取包裹 → 订单物流补全 → 归一化。先观察官方页面实际返回结构，再锁定字段解析；MTOP 原生调用仅在实际验证后启用。凭据、令牌更新和失效判断归 Kotlin 会话层，页面展示不处理 Cookie。网络错误、令牌轮换失败与登录过期分别处理。

## 拼多多数据通道

两个来源必须分开验证：

1. `m.pinduoduo.net/mdkd/package?tab=ID_CODE` 的多多取件业务：身份码及手机号关联待取列表。HandyCode 的 `express_trackbox` 同源适配是此通道的参考。
2. `mobile.yangkeduo.com/orders.html` 的购物订单：ExpressAssistant 记录 `POST /proxy/api/api/aristotle/order_list_v4`，页面 SDK 生成 anti_content；订单详情进入 goods_express 等物流页补取运单、轨迹和码。

二者登录与覆盖范围不可直接等同。先尝试从取件业务页的真实响应得到站点包裹；缺失时补充本人购物订单。读取不到明确码值时显示“待取，暂未获取取件码”，不从订单编号或手机号猜码。

使用本机 WebView 数据工作器运行官方页面，限定来源和目标响应；结构化响应优先，rawData 次之，明确物流区域文本最后兜底。验证码出现时暂停并在前台打开原会话验证页，完成后继续该平台同步。

ExpressAssistant 的真机记录指出：无签名 GET 可只给首批订单，分页可能被忽略，虚拟列表加载数量受滚动时序影响；文档中的多节点轨迹仍有未验证部分。不能把“成功返回若干订单”当成全量完成，也不能照抄其状态映射把待评价认定为已取。

拼多多网页登录与官方 App 互踢有上游 issue 报告。Parcly 所称解决路径包含改用内置商城，不能据此承诺两端长期同时登录。邯院通不扩展成商城；会话失效时清晰提供重新连接，保留同账号缓存并显示更新时间。

## 两种码分别设计

- 包裹取件码：关联具体包裹、驿站和运单，例如货架码。原生文本显示，可复制、放大，缓存带同步时间。
- 身份条码：平台生成的动态身份凭证，用于扫码出库或亮灯。单独的“出示身份码”页面，仅显示当次官方有效内容；不根据手机号、货架码或运单自行生成。

身份码原生化有独立验收门槛：取得官方码的实际载荷及格式/时效，或安全取得官方生成的码图，再用原生组件展示并验证现场扫描。源码里的 DOM 投影不等于已验证的原生条码接口。未知有效期不编造倒计时；切后台隐藏，返回时重新核验，失败清除旧身份码。包裹取件码缓存与动态身份码采用不同生命周期。

## 原生界面规格

- 入口沿用首页“取快递”；四个主 Tab 保持。
- 顶栏 56dp：返回、取件中心、账号管理。删除三排灰色工具按钮及正常状态下的域名提示。
- 紧凑摘要：待取数量、上次同步时间、小型刷新状态。筛选“待取 / 运输中 / 已取”，淘宝与拼多多作可选筛选标签。
- 默认按真实驿站分组，组标题含站点和件数；未知站点单独列出，不凭近似名称自动合并。
- 卡片依次显示：大号等宽取件码（约 30sp）、驿站、快递公司/运单尾号、来源和到站时间；商品名一行次要信息，不用大图挤占码的位置。
- 点击取件码进入原生放大面板；复制与“我已取件”置于下方。“我已取件”只是本机标记，支持撤销，不点击平台确认收货。
- “出示身份码”是独立次级入口，可选淘宝/拼多多。条码有足够白色静区，不加装饰、不裁边；仅展示时提高当前窗口亮度，离开恢复。
- 首次未连接显示两个简洁连接项。单平台失效只显示对应状态条，不遮挡另一平台包裹。无包裹、未连接、部分同步、断网、需验证、接口变更分别呈现。
- 使用现有浅色/淡紫体系；适配状态栏深色图标与底部手势区；首屏展示至少两张完整卡片作为 360dp 常见屏幕的设计目标，大字体下允许自然滚动。

## 模块与存储

建议 Kotlin 模块：ParcelCenterActivity（原生 UI）、ParcelAuthActivity（认证）、ParcelSyncCoordinator（同步编排）、TaobaoParcelSource/PddParcelSource（数据源）、ParcelRepository（账号隔离缓存）、ParcelIdentitySession（动态身份码）。沿用现有生活入口插件打开中心，保留快递独立 WebView profile，避免影响教务。

包裹模型包含 source/accountScope/orderId/trackingNumber/stationId/stationName/pickupCode/status/statusEvidence/updatedAt/syncedAt，以及明确的 completeness 标志。按账号域+运单号去重；缺单号时用平台订单和子包裹标识，不按相同码跨平台合并。保留多来源证据，订单与包裹一对多。

凭据在应用私有原生层管理；另存凭据使用 Android Keystore 支持的加密。快递缓存排除备份与统计上传；退出当前平台清除该账号缓存和会话，其他平台/学校不受影响。日志仅记录阶段、错误类别和计数，不记录响应、码值、凭据。

## 同步与正确性

- 进页面先读缓存，再同步；首次无缓存逐批展示结果。手动刷新合并重复请求；同平台认证和同步串行。
- 每轮带账号与 generation 标识，取消、切账号后迟到结果不能写入新账号。
- 成功空结果与失败/部分结果不同；不完整响应只增量合并，不删旧包裹。完整快照缺失也须结合状态再决定归档。
- “驿站代收/快递签收”与用户实际取件分别建模。新近轨迹中的“已取件/出库”证据优于历史入库文本；退款、交易完成和待评价不直接等于已取。
- 不无限重试，不用高频保活宣称永久登录。首版优先前台同步；后台调度需另行验证系统限制，不依赖后台网页持续存活。

## 开发与交付门槛

1. 先验证每个平台一个真实待取包裹，得到码、站点、运单对应关系；记录脱敏字段结构，不提交本人响应。
2. 实现原生列表与缓存；核对多个包裹、多站点、分页、码前导零、重复码、代收状态及多件订单。
3. 验证登录后自动返回、重启复用、网络失败、验证码恢复、官方 App 再登录、账号切换隔离。
4. 动态身份码独立验证刷新与实际扫码；失败不能以漂亮截图宣称成功。
5. 单元/原生编译与界面回归通过后交付测试 APK；真实账户结果独立记录。既有 test.2 的测试通过不构成新方案验收。

商业 API 补充调查：[快递100驿站取件码文档](https://api.kuaidi100.com/document/qujianmaapi)公开搜索结果可见注册、回调与手机号/公司匹配错误；全文获取超时。暂不将其作为无需账号、覆盖全部个人包裹的通用 API，也不据此采购或增加后端。

源码入口：[淘宝连接器](https://github.com/Granter-z/parcly/blob/main/lib/platform/connectors/taobao_connector.dart)、[拼多多连接器](https://github.com/Granter-z/parcly/blob/main/lib/platform/connectors/pdd_connector.dart)、[Kotlin 淘宝查询](https://github.com/Halo0sama/ExpressAssistant/blob/main/app/src/main/java/com/halo/expressassistant/api/TbOrders.kt)、[拼多多真机记录](https://github.com/Halo0sama/ExpressAssistant/blob/main/docs/PDD_REAL.md)、[拼多多互踢报告](https://github.com/Halo0sama/ExpressAssistant/issues/3)。上游报告仅作参考，不冒充本项目实测。

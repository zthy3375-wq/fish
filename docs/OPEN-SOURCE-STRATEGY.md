# 开源借鉴与复用策略

核查日期：2026-11-08。范围：保留 Vue 3 / TypeScript / Capacitor / Kotlin，服务邯郸学院 Android 用户；不重写为 Flutter，不恢复已取消的空教室或其他原生平台。

## 结论

- **产品结构参考 DanXi，会话边界参考 MyCHU，趣智协议交叉核对 JUWPHub。** 不把“界面丰富”直接等同于长期成熟，不把公开仓库等同于可以复制。
- 先完成趣智钱包的连接、余额、账单、官方充值跳转；胖乖和蓝牙设备控制独立排期。一个厂商不能代替另一个厂商，学校教务会话不能充当生活服务会话。
- 本轮只形成设计/协议研究结论，**没有引入任何外部源码或素材**。项目维持 MIT；以下 GPL、MPL、无许可证项目均不直接搬运。

## 核查样本与成熟度

日期和归档状态来自 GitHub 仓库元数据；提交固定到实际读取的源码。维护活跃不等于测试通过，也不代表可在邯郸学院直接使用。

| 项目 | 固定源码版本 | 维护证据 | 定位与许可 |
| --- | --- | --- | --- |
| [DanXi / 旦挞](https://github.com/DanXi-Dev/DanXi) | `3c1f5f026fbc7ca50e151865f813cdb381807abe` | 2020-12 建仓；2026-10-21 最近推送；未归档；Android 发布工作流和公开安装渠道 | 有多年历史的校园聚合产品；GPL-3.0，文件声明 GPL-3.0-or-later |
| [MyCHU](https://github.com/RinnMoe/my_chu) | `16c3def3c6a2eba15a5a3691c9d595de66ef82e7` | 2026-09-28 建仓；2026-11-08 推送；未归档；有签名、产物哈希及增量更新工作流 | 新但结构细致的校园聚合项目；MPL-2.0，不能称多年成熟 |
| [JUWPHub](https://github.com/Inonvation/JUWPHub) | `edf81286f26673968d4a804b6fd6bf6fc13f35ef` | 2026-09-18 建仓；2026-11-07 推送；未归档；趣智领域测试及 Android CI | 与当前生活服务接入最贴近，但仍是新项目；GPL-3.0 |
| [wash](https://github.com/Night-stars-1/wash) | `ffc25d25b980f8bef66b41d7d015936989ec825e` | 2025-10 建仓；最近推送 2026-06-10；未归档；所见测试仅模板单测/仪器测试 | 胖乖专用客户端，非校园聚合底座；根目录未发现 LICENSE，GitHub license=null |

未对以上项目执行构建、账号登录或交易，未核实其所有 CI 运行结果。测试目录/构建脚本存在，只证明工程投入，不能据此宣称端到端可靠。

## 1. DanXi：借鉴功能卡片与服务仓库，不复制校园接口

源码入口：
- [Feature 与 FeatureContainer](https://github.com/DanXi-Dev/DanXi/blob/3c1f5f026fbc7ca50e151865f813cdb381807abe/lib/feature/base_feature.dart)：`status`、`loadOnTap`、`onTap`、`notifyUpdate`，功能卡片自身维护连接状态，注册后由首页容器展示。
- [BaseRepositoryWithDio](https://github.com/DanXi-Dev/DanXi/blob/3c1f5f026fbc7ca50e151865f813cdb381807abe/lib/repository/base_repository.dart)：按 `linkHost` 分离 Dio/CookieJar；统一超时、队列拦截器与清理入口。
- [CardRepository](https://github.com/DanXi-Dev/DanXi/blob/3c1f5f026fbc7ca50e151865f813cdb381807abe/lib/repository/fdu/ecard_repository.dart)：校园卡余额/消费记录与 UI 解耦，分页记录属于服务仓库。
- [Android CI](https://github.com/DanXi-Dev/DanXi/blob/3c1f5f026fbc7ca50e151865f813cdb381807abe/.github/workflows/ci_android.yml)：签名配置来自私有 secrets 仓库、nightly 与正式版本分开。该文件未见自动运行单元测试的步骤。

**采纳：** 今天页仅展示下一步行动和轻量摘要；生活服务作为可进入的功能卡片，连接/失效/数据过旧单独展示。现有五导航继续作为外壳，不因新增厂商就新增一级标签。每个 provider 拥有客户端、会话和缓存，不建立一份全局 cookie 大杂烩。

**不采纳：** 复旦校园地址、页面解析规则、密码登录实现、社区/空教室/多平台范围；`linkHost` 隔离也不足以独自保证切换账号安全，仍需账号维度。Flutter/Dart 组件不能直接用于本项目 Vue 页面。

## 2. MyCHU：借鉴跨账号异步隔离与发布校验

源码入口：
- [SessionRuntimeFence](https://github.com/RinnMoe/my_chu/blob/16c3def3c6a2eba15a5a3691c9d595de66ef82e7/lib/services/session_runtime_fence.dart)：`accountKey`、`serviceId`、`scopeKey`、`sessionRevision` 与 `serviceGenerations`；`isCurrent()` 拒绝旧账号/旧代次响应，`fingerprint` 支持同一次会话操作合并。
- [RootNavigationService](https://github.com/RinnMoe/my_chu/blob/16c3def3c6a2eba15a5a3691c9d595de66ef82e7/lib/services/root_navigation_service.dart)：`selectTab()` / `takePendingTab()` 请求既有根导航切换，避免功能页再创建一份根页面。
- [Android 发布工作流](https://github.com/RinnMoe/my_chu/blob/16c3def3c6a2eba15a5a3691c9d595de66ef82e7/.github/workflows/android-release.yml) 与 [build_android_release.ps1](https://github.com/RinnMoe/my_chu/blob/16c3def3c6a2eba15a5a3691c9d595de66ef82e7/scripts/build_android_release.ps1)：构建身份/版本检查、SHA-256 记录、同名发布产物内容冲突时拒绝覆盖、签名私密文件清理。

**采纳：** 给新增 provider 的加载请求捕获账号与会话代次；退出、切换账号后，旧请求即使完成也不能写入当前快照。刷新复用进行中的请求，错误状态不要擦除上次成功数据。深链/通知返回既有页面，不堆叠第二个首页。

**发布优先级：** 先固定包名和受控正式签名，验证版本递增与备份兼容，再做自动更新。记录 commit、APK hash、证书指纹、versionCode；先用完整 APK 验证覆盖升级。MyCHU 的增量更新不是本项目当前必需品。

**限制：** 本次根 `test/` 仅见验证码 fixture，不能把 third_party 中的测试算作业务覆盖；发布工作流不等同于全量回归。本项目必须自行建立会话/钱包回归测试。

## 3. JUWPHub：趣智钱包最有价值的协议对照，也有不能照搬的降级

源码入口：
- [QzxyRepository](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/data/qzxy/QzxyRepository.kt)：账号/余额/账单与蓝牙订单 HTTP 部分；`loggedIn` 用 StateFlow 发布，不依赖页面恢复时才猜登录状态。
- [QzxySessionStore](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/data/qzxy/QzxySessionStore.kt)：与胖乖分文件存储，并说明排除系统备份。但加密存储创建两次失败后，代码返回普通 SharedPreferences；`save()` 仍能写凭据，**不能照搬这种明文降级**。
- [QzxyRecharge](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/ui/qzxy/QzxyRecharge.kt)：`deepLink()` 使用支付宝小程序 `2018090661238647` 的 `pages/recharge/recharge`；不带含登录态的 `myInfo`。`open()` 返回 true 只表示 Intent 已交出，不表示支付成功。源码中的其他学校真机注释不是邯郸学院验收证据。
- [QzxyRecoveryTest](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/test/java/edu/jxslu/schedule/domain/QzxyRecoveryTest.kt) 与 [Android CI](https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/.github/workflows/android-ci.yml)：领域恢复用例，CI 执行 `testDebugUnitTest`、debug/release 构建。

**立即采纳：** 趣智单独的加密会话与退出路径；Vue 只拿必要的业务数据；加密设施不可用时停止保存凭据并明确要求重新连接，不能转明文。充值交给官方支付宝页面，用户自己核对账户并付款；返回后刷新余额/账单，未知结果显示“待核实”。禁止把 token、loginCode 或个人数据拼进跳转 URL/日志。

**延期：** 蓝牙扫描、开阀、两阶段设备下单、胖乖订单。它们是有副作用的独立状态机，不能由“钱包可读”推断已可用；本阶段不后台自动创建订单或重试扣费。

## 4. wash：仅留作胖乖的对照样本

- [ApiService](https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/logic/network/ApiService.kt) 集中网络接口。
- [PayViewModel](https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/ui/goodsdetail/PayViewModel.kt) 分 `createTrade()` 与 `prePay()`，通过 LoadingState 返回请求成功/失败。请求成功仍不等于支付结算完成。
- [README](https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/README.md) 明确是胖乖客户端，功能包括短信登录、扫码设备、历史订单。

**决策：** 当前不引入代码、不引入其登录/交易链路。将来用户确认胖乖场景后，可交叉核对接口事实与订单阶段；先补许可证许可和契约测试，再评估实现。未授权源码不能因为“公开可读”就改成 MIT 发布。

## 落到本项目的实施顺序与验收

1. **趣智钱包闭环（当前）**：一个生活服务入口，连接说明、余额、账单分页、更新时间、官方充值入口。余额未知不能显示 0 元；余额更新不能被当成某笔充值成功证明。
2. **会话与失败语义（同阶段）**：provider + account 独立缓存；断网保留最近成功值并标旧；401/失效与网络错误区分；退出清凭据/账号缓存；旧请求完成不得复活会话。账单失败不覆盖余额，部分分页不得标成全量。
3. **测试门槛**：契约 fixture 覆盖正常/空/缺字段/分页重复/部分失败/失效；并发刷新、切号中响应、退出后返回、存储损坏；充值未安装支付宝、取消、重复点击、返回、超时未知。单测、类型检查、Web 构建、Android 编译与 UI 回归分开记录。
4. **手机验收**：由用户在自己的官方页面连接；核对学校/账号、余额、最近账单与官方应用一致。由用户决定是否充值；未经真机证据不声称支付到账。账号及脱敏证据不提交仓库。
5. **升级可靠性**：先解决固定签名/包名、覆盖安装和备份恢复，才讨论自动更新；不复制参考项目的 CI 凭据、私有仓库或分发渠道。

## 许可证与后续复用门禁

- GPL 项目：借鉴功能分层、状态机与可验证的协议事实，不翻译/改名搬运实现、测试、UI 素材。若确需源码复用，先确认依赖范围、来源文件和项目整体许可方案，不能继续假称全部 MIT。
- MPL 项目：属于文件级 copyleft，不是禁止与 MIT 工程共存；但被覆盖文件及修改仍需遵守 MPL 的源码提供和通知义务。本轮没有必要增加 Dart 移植与许可维护成本，采用独立实现。
- 无许可证：没有明确复制/分发授权，本轮仅研究事实与产品行为；需要代码时先取得授权或选择许可明确的替代品。
- 新引入第三方代码/资产必须记录仓库、固定 commit、文件、许可证/NOTICE、改动与升级方法。现有成熟基础库继续优先，避免为了一个简单钱包再造框架或引入另一套应用栈。
- 每次参考上游更新，先看差异和受影响契约，跑本项目回归再采纳；不自动追随最新分支。参考项目的功能数量、星数和单次成功构建都不能替代本校验收。

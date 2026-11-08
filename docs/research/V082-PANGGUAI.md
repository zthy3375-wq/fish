# v0.8.2 胖乖生活：账户、运营商充值与扫码契约研究

核查日期：2026-11-08。项目基线：`040cfb2b9477d9704a8b393c3d35eeb4f57e5102`。本文件是研究结果与独立实现建议，不是已交付功能或邯郸学院真机验收报告。

本轮只读取公开仓库、官方页面 HTML 和静态资源。没有请求真实账户接口、发送短信、登录、创建订单、付款、开通免密、启动或结束设备；没有复制上游实现、测试、素材或签名密钥。趣智已交付，不以等待趣智手机反馈作为继续研究胖乖的前置条件。

## 1. 可以推进什么

1. **最稳妥的短期入口是官方网页，不是伪装完成的原生钱包。** 官方 H5 确有普通浏览器短信登录、钱包、按商户列出的通用小票页面。可由普通 Android WebView/浏览器展示，让用户自己操作官方登录；不注入官方 App 身份，不读取或转交 token，不分发 Android 接口签名密钥。
2. **原生账户/余额实现有资料，但当前不能称为可用。** Android 接口样本依赖名为 `appSecret` 的签名材料；不同项目的旧版签名还有分隔符差异。没有证据证明它是可自由分发的公开应用标识。不要从公开源码提取、提交或配置该材料，也不要把过时的无签名脚本当成当前可用的替代方案。
3. **余额有三种不同含义。** 普通账户余额、受限余额、各商户小票余额不能相加混称“洗衣/饮水余额”。官方小票页使用“点”，普通钱包使用“元”；积分抵扣金额也不是现金余额。
4. **充值商户必须来自当前账户/官方页面或本校核验。** 官方 H5 的小票列表提供 `shopId`、`shopName`，再用该项进入充值。不能沿用 JUWPHub 的其他学校商户常量，不能把扫码返回的数字 `shopId` 当成充值所需的字符串商户标识。
5. **扫码识别、下单、付款、设备启动、结算是不同阶段。** 本轮可以独立做受限二维码识别/官方入口准备；没有本校设备和交易证据前，不开放原生开水、洗衣或扣款按钮。不要为了凑齐界面展示虚构商户、程序、价格、状态或余额。

## 2. 来源与许可证边界

| 来源 | 固定版本 / 可复核文件 | 许可与使用方式 |
| --- | --- | --- |
| JUWPHub | `edf81286f26673968d4a804b6fd6bf6fc13f35ef`；[QiekjApi][J-API]、[QiekjModels][J-MODEL]、[QiekjRepository][J-REPO]、[充值入口][J-RECHARGE] | 根 LICENSE 为 GPL-3.0。研究接口与产品行为，不移植 Kotlin、测试、UI 或素材。项目仍很新，不因功能丰富就称为多年成熟。 |
| Night-stars-1/wash | `ffc25d25b980f8bef66b41d7d015936989ec825e`；[ApiService][W-API]、[模型目录][W-MODELS]、[扫码页][W-SCAN]、[支付页][W-PAY] | 固定提交的全仓路径未发现 LICENSE/COPYING/NOTICE。公开可读不构成复制授权；只记录协议事实。README 声称短信、扫码设备和订单，不能据此推断所有交易可靠。 |
| Mercury000/HUEL-yktwx | `1bb98ea5bc87e9a217ce6b8af10c47046aa92c73`；[LifeDeviceApi][H-API]、[账户核验说明][H-ACCOUNT]、[洗衣研究][H-LAUNDRY]、[用水研究][H-WATER] | GPL-3.0；2026-10 建仓。提供较新的离线抓包对照说明，仍是第三方作者报告，不是本项目亲测或本校证据。仅用于补全契约，不复制实现。 |
| 3ryng1um/qiekj | `0079ac518442bc03e1d16a93e97b653900598dfd`；[pgsh.py][P-SCRIPT] | 未见根许可证。2026-04 的历史脚本，只交叉核对小票/积分字段，不运行。源码存在原始响应/令牌打印做法，不采纳。 |
| 官方 H5 | `h5.qiekj.com` 2026-11-08 返回的 HTML、路由 bundle 与页面 chunk，见第 12 节 | 不是开源依赖，不复制业务实现。记录公开页面地址、字段、界面单位和导航规则，优先让提供方自行承载认证与支付。 |

本项目的新代码应继续独立实现。接口路径和字段事实不意味着上游源码的许可证可忽略；没有新增第三方源码依赖的必要。已有安全存储、Capacitor 与界面基础继续复用。

## 3. 官方网页入口：已证实的静态行为

### 3.1 精确地址

官方使用 Vue Router **history 模式**，不是 `/#/` 路由。以下地址直接返回官方 SPA HTML，具体页面由脚本渲染：

| 入口 | HTTPS 地址 | 已看到的页面语义 |
| --- | --- | --- |
| 登录 | `https://h5.qiekj.com/login` | 普通浏览器短信登录，亦有特定宿主的授权分支 |
| 钱包 | `https://h5.qiekj.com/pages/wallet/myWallet/myWallet` | 总余额，普通余额与受限余额相关入口 |
| 商户小票 | `https://h5.qiekj.com/user/recharge/goldList/goldList` | 按 `shopName` 展示小票、明细与充值入口 |
| 充值 | `https://h5.qiekj.com/buyGold?shopId=<当前列表返回值>` | 按商户查询当前小票套餐；不可省略/猜测商户后声称精准充值 |
| 运营商信息 | `https://h5.qiekj.com/user/recharge/operatorInfo/operatorInfo` | 路由已存在；完整入参未核实，不直接构造入口 |
| 个人信息 | `https://h5.qiekj.com/user/userInfo/userInfo` | 路由已存在；不作为本项目身份读取接口 |

普通浏览器路径的核心证据：

- H5 的宿主识别区分微信、支付宝、招商银行、云闪付和带官方 App 特定 UA 标记的环境；普通 UA 返回 false。
- `/login` 的页面进入逻辑在普通 UA 下直接进入表单，不要求宿主 OAuth 或原生桥。
- 普通浏览器登录提交的 channel 为 `h5`，不是 `android_app`。点击获取验证码时，官方先调用 `common/isNeedCaptcha`，需要时由其验证码组件验证，再发送短信。**不能跳过这个检查、自动解题或伪造成功。**
- 登录页实际说明未注册手机号将自动创建账户，进一步确认这是注册/登录合并流程。验证码组件为网易易盾，当前 chunk 使用 `initNECaptcha`，可见 bootstrap 域为 `cstaticdun.126.net`、`cstaticdun1.126.net` 及 IPv6 备选 `cstaticdun-v6.126.net`，加载 `/load.min.js`；官方业务校验路径为 `captcha/checkCaptcha`。进一步核验的 API 域与仍未确认的动态资源见 3.4，不能宣称静态白名单已经覆盖完整验证流程。
- 官方自己保存会话、读取 `user/info`。HTTP 过滤逻辑只有在官方 App UA 且原生桥存在时才尝试桥接 `getUserInfo`；普通 H5 分支从自己的网页存储取得会话。
- 因此页面展示不需要本项目注入 `getUserInfo`、`quekeApi`、`qiekj` 或 `WebViewJavascriptBridge`。保持普通 WebView UA；不要添加 `com.qiekj.qeuser` 来冒充官方 App。

**验证限制：** 本轮读取了公开 HTML 和静态脚本，但未能在本环境完成实际浏览器渲染、登录或支付。静态证据不证明短信、钱包实时数据或充值能够在本项目 WebView 完成。

### 3.2 未登录跳转与返回

- 钱包页自身没有“无 token 即跳登录”的路由 guard；激活后请求 `user/info`。
- 公共业务错误处理器对 **`code=2`** 清理官方网页 token 并转到 `/login`。普通浏览器不适用其支付宝特例。
- 路由的 `beforeEach` 将每个非 `/login` 的 `fullPath` 保存为 `redirectRoute`。普通 SMS 登录成功通常返回该路由；没有历史目的地时返回 `/`。
- 因此建议先打开钱包或商户小票页，让官方自己的 code=2 分支保留目的地。**直接从全新存储打开 `/login` 并不能保证登录后直达钱包。** 网络失败、非 code=2、存储不工作时也不能保证自动跳转。
- 可提供固定的“登录 / 钱包 / 商户小票”工具栏作为导航补救，但不读取网页 token，不把页面打开成功解释为账号已连接。不要传外部 `redirect`、`preCode` 或 `redirectProjectUrl`。
- 官方登录还支持跳往某些已有重定向目标；原生容器仍应约束最终顶层导航，不能因为链接由官方 JS 发起就接受任意目的地。

### 3.3 导航与支付边界

- 核心顶层页面：`https://h5.qiekj.com`；官方政策页面另有 `https://market.qiekj.com`。这里的导航策略指**受限顶层导航**：只开放必要路径，阻止 userinfo、非 443 端口、混淆主机、明文 HTTP 与任意外链。官方页面的 HTTPS 静态资源和 API 请求由浏览器管理，不通过本项目原生桥转发；子资源策略与顶层导航分别判断，不能把允许加载资源等同于允许打开该域的页面。
- 公共静态资源主要来自 `h5.qiekj.com`、`static.qiekj.com`；官方请求后端为 `userapi.qiekj.com`。`userapi` 是页面子请求目的地，不是应当允许打开的任意顶层 URL。
- 官方页面也加载客服、统计、验证码和特定宿主 SDK。不能承诺把它变成无广告、无第三方请求的原生钱包；它仍是官方页面。第三方资源域是否为实际必要项需要 WebView 实测，不通过全域放行来掩盖问题。
- 支付模块存在微信 `wx.chooseWXPay`、支付宝宿主桥、招商银行页面/表单、云闪付返回动态 `prepayParam` URL 等不同路径。**未找到足以证明普通独立 WebView 支付完整工作的证据。** 普通浏览器不应伪装这些宿主，也不能把动态字符串一律交给 `Intent.parseUri`。
- 当前可交付“查看官方钱包/商户小票”和明确的官方外部入口；不应宣称“已实现 App 内充值支付”。如提供支付宝入口，应由用户明确点击固定小程序链接，限制目标包为官方支付宝，不转发任意页面提供的 scheme、Intent extras 或 fallback URL。
- 任何未知跳转都应保留当前页面，说明需在官方应用继续。不要自动打开支付、免密、银行、市场下载或任意第三方应用。
- 仅按 h5 主机放行会同时开放订单、设备和账号修改等其他官方业务，不等于“只读钱包”。钱包模式应明确自己的路由范围；设置路由为 `/user/setting/setting`，资料路由为 `/user/userInfo/userInfo`，但没有独立 logout 路由得到核实。设置页实际提供的是“解除绑定”，不是已验证的普通 H5 退出登录按钮，详见 3.5。

### 3.4 网易易盾资源域：确认项与缺口

本轮进一步只读取 [公开 bootstrap](https://cstaticdun.126.net/load.min.js) 以及它列出的两个公开静态 SDK；没有调用配置、挑战或校验 API，也没有触发或解答验证码。

| 用途 | 静态源码明确列出的主机 | 依据与限制 |
| --- | --- | --- |
| bootstrap CDN | `cstaticdun.126.net`、`cstaticdun1.126.net`、`cstaticdun-v6.126.net` | 胖乖登录页 fallback loader 的默认列表。只允许这三个 CDN 不足以初始化验证码。 |
| CAPTCHA 配置/API 默认值 | `c.dun.163.com`、`c.dun.163yun.com`、`c-v6.dun.163.com` | `fetchConfig` 构造 `/api/v2/getconf`；普通默认主/备为前两项，IPv6 主域为第三项、备用仍为 `c.dun.163yun.com`。若所有这些主机被拦截，且官方配置未另设服务器，初始化请求无法完成。 |
| 可选 Watchman 风控默认 API | `ac.dun.163.com`、`ac.dun.163yun.com`、`ac-v6.dun.163yun.com` | `acConfig` 启用时使用；普通主/备为前两项，IPv6 主域为第三项。可被服务端配置替换，不保证每次登录都会用到。 |

以上六个 `c` / `ac` API 主机有直接公开源码依据，可以按 HTTPS **子资源/API** 精确放行；它们不是顶层导航目的地。不开放 `*.163.com`、`*.163yun.com`、`*.126.net` 等通配范围。

仍有重要缺口：

- bootstrap 会从服务端配置取得 `apiServer`、`staticServers` 和 `resources`，再拼出后续脚本地址。因此代码中的默认主机不等于真实配置的全部主机。
- Watchman 静态文件名为 `wm.3.0.0_33d41777.min.js`；另一 IRisk 分支加载 `ir.2.0.13.min.js`，其 API 主机来自 `irConfig.apiServer` / `irServerConfig.apiServer`，未在所读 bootstrap 中给出固定默认域。本轮没有请求这些运行时配置。
- 验证题图片、音频及区域化资源域未从此次官方静态证据完整确认。未找到足以作为全量名单依据的官方域名指引，不因第三方旧样本出现某域就当成胖乖当前必需域。
- `da.dun.163.com/sn.gif` 是统计上报；`only-d-<随机值>-<时间>.nstool.netease.com/ip.js` 用于错误诊断。它们的存在不能证明必须为登录开放统计或任意随机子域。

精确允许上述域能修复已知的初始化拦截，但**不证明完整 CAPTCHA 兼容**。若当前官方流程需要未核验资源，安全失败并提示在官方应用继续；不能自动放开全部域名或跳过验证。本项目不注入原生验证码桥，不提取验证结果，不替用户提交验证码。

### 3.5 官方设置页并非已证实的普通退出入口

[设置页静态脚本](https://h5.qiekj.com/js/user_setting.5ed39add.js) 的按钮显示“解除绑定”，确认框为“您确定要解除绑定?”。其 `loginOut` 调用 `User.logout(true)`，没有按普通浏览器与官方 App 分支，也没有依赖原生桥。

主 bundle 中，`logout(true)` **先等待** `POST user/release`，参数 `channel=wechat`，之后才移除官方网页保存的 token 并重置账户状态。设置页随后返回并清理自己的活动缓存。因此：

- 普通 H5 是否能成功执行这个服务端解除绑定操作未验证；请求失败可能使后续本地清理不执行。不能承诺“点账号即可可靠退出”。
- 本地清理默认方法确实存在，但设置按钮并没有调用它的无服务端操作版本。不能把“解除绑定”改称无影响的“退出登录”，也不能通过注入 JS 改成调用另一个方法。
- 公共取 token 逻辑还存在 `AppToken` Cookie 兜底，而所见 `removeToken` 只移除网页缓存键；不能据此保证所有来源的会话均被清除。
- 原生工具栏最多标“账号/设置”，保留官方确认与原词义；不自动点击、不代调用解除绑定、不全局清空 Cookie 作为替代。页面关闭也不代表已注销。

## 4. 协议和隐私页面

官方 H5 登录页实际链接：

- [企鹅共享用户使用注册协议](https://h5.qiekj.com/user/UserAgreement/UserAgreement)。其静态页面表明注册与使用受平台协议约束，不能把 `/user/reg` 说成仅验证已存在账户。
- [企鹅共享小程序隐私政策](https://h5.qiekj.com/user/privacyPolicy/privacyPolicy)。这是 H5 登录按钮链接的准确目的地，不自行替换为猜测路径。

另外核实的官方分发来源：

- [小米应用商店](https://app.mi.com/details?id=com.qiekj.user) 列出开发者杭州企鹅科技有限公司、Android 包名 `com.qiekj.user`，隐私链接为 [market 页面 id=34](https://market.qiekj.com/marketing?id=34)。
- [Apple 官方商店条目](https://apps.apple.com/cn/app/id1597902801) 的开发者隐私链接为 [用户信息保护政策](https://h5.qiekj.com/user/UserAgreement/userPrivacy/legalPrivacy)。
- 官方路由另有 `/user/UserAgreement/newUserAgreement`，标题为平台用户注册协议；不能仅凭“new”推定它就是当前 H5 表单所链接版本。
- 官方 `buyGold` 页的购买协议链接为 `https://market.qiekj.com/marketing?id=66`。只核实它是购买页引用的目标；没有点击充值或接受协议。

应用内若介绍原生短信方案，应明确“手机号和验证码发送给胖乖平台，可能创建账户”，提供准确协议入口；短信/注册不自动触发。采用官方页面时，让用户在官方表单完成确认，不代勾协议，不代收保存验证码。开通后付、免密或代扣属于另一项承诺，不能由登录确认一并推定。

## 5. 账户 API：事实、单位与可用性

下表是协议研究，**不是已执行的请求清单**。Android 样本基地址均为 `https://userapi.qiekj.com/`，使用表单 POST；官方 H5 某些读取使用 GET。

| 路径 | 输入 | 返回/用途 | 证据与限制 |
| --- | --- | --- | --- |
| `common/sms/sendCode` | `phone`, `template=reg` | 通常业务信封，data 可为空 | J/W/P/H 相互印证。短信是外部动作，不进行探针或自动重试。H5 还先做 CAPTCHA 判断。 |
| `user/reg` | Android：`channel=android_app`, `phone`, `verify`；H5 普通浏览器 channel=h5，可另带 code | `data.token` | 登录/注册共用端点。未找到可靠的“保证只登录已有账户”参数。 |
| `user/info` | Android POST `{token}`；官方钱包 GET，由官方过滤器加入自己的 token | `id`, `phone`, `balance` 等 | W 模型、H 的七次离线抓包核对与官方 H5 页面一致。仅为账号级资料，不是商户余额完整清单。 |
| `user/balance` | POST `{token}` | `tokenCoin`, `integral`, `integralAmount` | J/P；不包含已确认的商户现金总余额结构。 |
| `user/astrict/list` | 官方 H5 POST；会话由页面加入 | 数组中 `remainCoin` | 官方钱包把它作为受限余额，与 `user/info.balance` 相加；本项目未核验真实响应。 |
| `tokenCoin/userTokenCoins` | 官方 H5 POST `{page,pageSize}`，默认 1/20；会话由页面加入 | `total`, `items[]`；每项至少使用 `shopId`, `shopName`, `totalAmount`, `principalAmount`, `presentAmount`, `isAllowRefund` | 官方商户小票页；用于正确的运营商发现，不应只读第一页后宣称所有商户。 |
| `shop/detail` | `{shopId}` | `id`, `shopState`, `allowPayType` 等 | 官方小票页充值前查询。当前代码仅 2/5 状态进入购买；状态是官方观察事实，不代表跨版本永久枚举。 |
| `tokenCoin/goods` | `{shopId}` | `shopId`, `goodsId`, `goodsType`, `shopTokenCoinRewards[]`, `userTokenCoinDTO` | 官方购买页。套餐数据动态变化，不固定金额、赠送或退款政策。 |

### 5.1 金额不能套用一个换算函数

| 字段 | 已有依据 | 正确展示边界 |
| --- | --- | --- |
| `user/info.balance` | 官方钱包页面直接按两位小数处理，并使用“元” | 普通账户余额（元），不是自动可用于当前设备的余额。 |
| `user/astrict/list[].remainCoin` | 官方页面相加为受限余额，再与普通余额合计为“总余额(元)” | 只能在本项目独立核验后按相同口径汇总；不要把缺失视作 0。 |
| `user/balance.tokenCoin` | JUWPHub 与历史 pgsh.py 均除以 100，作为“小票”显示 | 可记录为历史客户端的分/元等值展示口径；不是“现金总余额”。尚无本校原始响应与官方同屏对照。 |
| `user/balance.integral` | 两项目均作积分数量 | 非钱；不自行设兑换比例。 |
| `user/balance.integralAmount` | 两项目解释为积分可抵金额，J 按元展示 | 可抵扣估值，不并入现金或小票。 |
| `tokenCoin/userTokenCoins.items[].totalAmount`、`principalAmount`、`presentAmount` | 官方小票页显示余额单位“点”，分本金/赠送 | 保留“点”；不能因同样包含 tokenCoin 就除以 100 改称元。 |
| `tokenCoin/goods.userTokenCoinDTO.totalAmount` | 官方充值页单位为“点” | 该运营商小票余额；不是账户现金。 |
| 套餐 `cashValue` / `reach` / `reward` | 官方充值页分别标“元” / “点” / “点” | 实际付款金额取套餐 cashValue；不要固定点元比例或把赠送算成退款本金。 |
| 洗衣 SKU `price` | wash 直接加人民币符号；H 抓包说明使用元 | 程序标价，不是最后应付金额；优惠/支付渠道仍需服务器预览。 |
| 用水 sync `amount` | H 离线样本只证明零与非零参与结算分支 | 单位未知，不能显示为金额、毫升或已结算费用。 |

若以后做 native DTO，金额用严格十进制字符串或明确单位的整数，拒绝非有限、负数、异常精度和溢出；空/缺失/无法解析为 unknown，不是 `0.00`。保留最近一次成功值时必须标旧并带更新时间。不要套用浮点格式化或把所有未知字段清零。

### 5.2 错误与会话

- 普遍信封是 `{code,msg/message,data}`。J/H 接受业务 code 0 或 200；官方 H5 当前业务成功条件为 code 0。
- wash 枚举含 code 2 = 未登录、1001 = 验证码错误。它用封闭枚举读取未知 code，可能异常；独立实现应允许未知整数，不把未知状态当成功。
- HTTP 401/403、业务失效、网络失败、字段变化需区分；HTML 网关页不是空数据。
- 登录返回 token 不足以证明余额完整或商户已确认。当前不能使用真实请求验证；未来先核验身份及目标字段再保存“已连接”。
- session 属于 provider + account；切号、退出与并发响应以代次隔离。旧请求不得复活新会话。Keystore 不可用时不能降级明文。
- 官方网页模式下，不同步自己的“已登录”布尔值，不从页面标题或打开动作推断身份，不拷贝官方网页 token 到 Capacitor/日志/备份。

## 6. Android 签名冲突与不含密钥的离线验证

| 实现 | Version | 观察到的签名拼接 |
| --- | --- | --- |
| JUWPHub 普通业务 | 1.60.3 | version 的值后直接接请求 path，无额外 `&` |
| wash | 1.60.3 | version 与 path 之间有 `&` |
| JUWPHub 积分业务 | 1.123.0 | 有 `&`，另建客户端 |
| HUEL | 1.109.1 | 有 `&`；洗衣文档称 85 + 70 + 38 条离线请求签名匹配；账户文档另核对 1.145.0 请求 |
| 2026-04 pgsh.py | 1.59.3 | 无 sign；余额请求甚至使用 channel 字面量 `channel`，只有 Authorization 与 token 表单 |

以上不是可供自动尝试的一组候选签名。旧版冲突未通过独立真实数据消除；历史脚本可能已失效。**不做实时版本轮询、不自动换签名重试，更不从可读源码复制认证密钥。**

较新的签名串结构为：按 `appSecret`、`channel`、毫秒 `timestamp`、账户 `token`、`version` 的键值顺序拼接，再 `&` 加带前导斜杠的 path，对 UTF-8 结果做 SHA-256，输出小写十六进制。J/W 的常量明确名为 secret，H 则使用本地/CI Secret 注入；没有证据把它降格为可公开分发的 appId。

只做算法/传输契约测试时，可使用完全人工的值，不需要真实密钥或账户。独立算得的示例：

```text
appSecret=synthetic-test-only&channel=android_app&timestamp=1700000000000&token=fixture-token&version=1.109.1&/user/balance
SHA256 = f873b83cae5763eee22be54137c0e3e536f5b5d7dc57c412ba4a388a395d142c
```

该向量只验证字节拼接和哈希，**不证明请求被平台接受**。上游测试多为合成参数/测试替身，不能当实时服务验收。H 的登录测试进一步证明其客户端对 SMS/reg 不加 sign，但不证明可绕过官方 H5 的 CAPTCHA 步骤。

官方普通 H5 的当前传输代码没有要求本应用分发 Android appSecret：页面自行发请求并持有自己的 session。这支持使用官方页面，不授权把 H5 会话提取后改造成未经验证的 native API 客户端。

## 7. 运营商发现与充值

### 7.1 最可靠的已知关联

官方小票列表 `tokenCoin/userTokenCoins` 的每一项直接提供 `shopId` 与 `shopName`；点击该项充值时先 `shop/detail`，再进入 `/buyGold?shopId=该项值`。购买页进一步读取 `tokenCoin/goods` 并以服务端当前套餐为准。**这比从学校名称、历史订单第一项或扫码数字 ID 猜商户可靠。**

充值购买动作实际创建虚拟订单：`order/createVirtualOrder` 使用 `shopId`, `goodsId`, `goodsType`, `Num`（所选 reach）, `tokenCoinRewardId`，再进入结果/支付页。这里只记录事实，不实现或调用。JUWPHub 的“充值不是 REST”仅描述其自身没有实现充值 API，不能扩大为平台绝不存在充值接口。

### 7.2 三类标识不可混用

- `goods/scan/v2.data.shopId`：wash DTO 为整数；H 洗衣抓包将它用作首次支付渠道路由标识。
- `goods/normal/details.orgId`：设备所属组织/运营商识别，附 `orgName`；不是天然等于充值商户 ID。
- `goods/normal/details.shopId`、订单 `shopId`：H 说明为字符串商户标识，再次支付使用订单这一值。wash 订单还区分 `shopAutoId`（整数）和 `shopId`（字符串）。
- `shop/outline/v2` 接受 `orgId` + `goodsId`，能给出商户/位置。它可辅助核对，不把展示名称自动当成本校已确认。

所有 ID 在本项目应保留原始字符串，不转 JavaScript Number，尤其长数字商户号。DTO 分别命名 `routingShopId`、`operatorId`、`merchantShopId`，避免一个 `shopId` 字段在全流程代表三件事。

### 7.3 官方外部入口

- Android 应用包名：`com.qiekj.user`，来自官方应用商店。
- 支付宝小程序 ID：`2018072460764274`，JUWPHub 的官方分享链解析记录与另一公开快捷方式样本一致；固定首页入口为 `alipays://platformapi/startapp?appId=2018072460764274`。未在设备上唤起验收，不能保证每个环境可用。
- JUWPHub 的定向充值小程序 page 为 `user/recharge/buyGold/buyGold`，带 `shopId`，page 整体百分号编码。**其商户属于其他学校，不写入本项目、不作为默认值。** 该小程序 page 不等于 H5 的 `/buyGold`。
- 如仅打开小程序首页，应说“打开胖乖生活支付宝小程序”，而非“已直达邯郸学院充值”。用户仍需确认自己的支付宝登录手机号、运营商、金额和退款条件。
- 进入页面、Intent 发出、返回 App、甚至余额变化，都不是某笔充值已到账的证据。

## 8. 二维码解析和设备读取

### 8.1 已知链路

1. wash 从扫码 URL 提取精确大写 `NQT`，POST `goods/scan/v2`，输入 NQT 与 token。
2. 返回数据至少有 `id`, `shopId`, `categoryCode`, `categoryName`, `type`, `shopCanReserve`, `shopWhitelist`, `mpPositionType`, `shopType`, `jumpToAlipayFlag`, `jumpToAlipayFlag2`。
3. 再请求 `goods/normal/details {goodsId,token}` 和 `goods/normal/skus {goodsId,token}`；不能把扫码通过当成可用、在线或支付已确认。
4. H 抓包记录洗衣 `NQT`，类别 `00`；接水使用 `SN`，水类 `04`，另有淋浴 `08`。这是样本范围，不意味着邯郸所有设备都一样。
5. 官方 H5 路由存在 `/skip` 与 `/pages/skip/skip`；其静态页面会调用 `goods/scan/v2` 后按设备资料分流。该页可能有 OAuth/设备业务，不能在研究中拿虚构二维码触发。

JUWPHub 只有 `goods/latestUsed(categoryCode=5)` 的历史饮水机列表，**不能因其没有扫码端点就断言胖乖平台不支持扫码**。同样，历史列表类别 5 不应混同详情的 categoryCode `04`。

### 8.2 独立解析应更严格

wash 仅有 NQT 参数即接受，不校验 URL host。这个做法不能照搬：

- 只解析二维码文本，不访问其中任意 URL。拒绝 `javascript:`, `file:`, `content:`, 任意 `intent:`, userinfo、控制字符和非预期端口。
- 整体限制长度；标准 URI 解析；单次解码；拒绝重复参数、空值、NQT/SN/IMEI 混杂和双重编码造成的歧义。
- 只接受实际核验的官方域和路径。`h5.qiekj.com/skip` 路由有官方静态来源，但本校二维码完整样本仍缺失；不要只因主域以 qiekj 结尾就接受任意子域，也不要把洗衣 UUID 的猜测扩展到所有设备。
- 返回一个类型化的“待核对设备码”对象；传给后台的设备码和 UI 展示不得携带整条不受信 URL。
- 服务端返回的设备 ID、类型、categoryCode 需与后续 details 核对；`type` 非 goods、类别未知、返回 ID 冲突，保持未支持而非走默认洗衣。
- `jumpToAlipayFlag`/相关布尔值不是完整跳转地址，不据此构造未核实的 deep link。
- 相机权限仅在用户选择扫码时申请；不申请定位/蓝牙来完成只读钱包。扫描动作不能自动转成下单、开水或付款。

## 9. 有状态交易：不得简化成一次 POST

### 9.1 饮水后付

J 的链路：选历史设备 → skus → sync 预检 → details → 积分风控 → `payChannelRoute/addUserAfterPayChannel(method=15)` → 位置风控 → `goods/water/unlock` → sync 轮询 → `order/afterPay/creating` → order/detail。

其中开通后付、unlock、endWater、creating 都有副作用，不能由“扫码”或“查询余额”顺带执行。风险检查失败应停止，不伪造位置，不通过改参数绕过。付款渠道15也不是已证实的所有学校默认支付方式。

H 的较新抓包进一步区分：

- unlock 返回 `msgId` 与 `orderNo`；`machine/msg/sync` 确认命令；`goods/water/sync` 通过 `identify` 匹配本次 orderNo。
- 接水中见 `status=1/workStatus=2`；匹配本次订单且 `status=5/workStatus=1` 才有设备结束依据。单独的 workStatus=2 不能证明设备在线或实际出水。
- `goods/endWater` 成功仅表示请求受理；还需核对设备状态。`supportAppUserFinish=false` 的设备可能必须实体按钮结束，不能承诺 App 一定能关水。
- amount 明确为零的已结束样本跳过后付创建；非零样本出现 creating 和 order/sync；amount 缺失/异常不是零。不能套用“零元洗衣无需建单”的逻辑。
- J 的 165 秒等超时属于其项目策略/样本判断，不应宣传成全平台设备必然停止。等待超时只能得到“结果未知”，不是已关闭或已退款。

未来状态机至少区分：已核对设备、开始请求已发、开始结果未知、已确认使用中、结束请求已发、设备已结束、费用待核对、已结算。持久保存请求阶段和已返回订单标识，丢响应后先查同一订单，不能重复 unlock/creating。

### 9.2 洗衣先付

wash 实现 `trade/create` → `pay/unify/prePay` → 支付宝 SDK。其固定优惠 ID/类型、固定 payType13、用 `orderId` 填 prePay.orderNo，以及 SDK 状态就说支付成功的做法都不宜当作成熟闭环直接移植。

H 的离线证据给出更完整链路：

1. 读取设备/程序/商户；`payment=before` 与饮水 `after` 分流。
2. `trade/preview/v4` 计算应付价；items 包含 goodsId、skuId、amount、num、soldType，promotions 不能搬用别校固定优惠。标价不代替预览 realPrice。
3. `payChannelRoute/prePay` 动态读取渠道，首次传扫码路由 shopId。渠道可能不可用、需开通或完全不返回；不硬编码支付宝/余额一定可用。
4. `trade/check_device_status` → `machine/sync(msgId)` 读取健康/命令结果。该 sync 的布尔响应与饮水的对象响应不同。
5. `trade/create` 返回 tradeNo、orderId；该抓包明确 **tradeNo 对应支付 orderNo**，orderId 用于详情等，不能混用。
6. 余额2使用 `pay/unify/pay`，第三方渠道使用 `pay/unify/prePay` 获取服务端签名参数；均属付款阶段。
7. `order/pay_status` 确认支付，再由 `machine/device_is_start` / 同一订单详情确认启动。SDK 回调、预支付参数、支付成功、设备启动分别记录。
8. 已有订单再次支付用 `payChannelRoute/againPay` 和原 orderNo、订单字符串 shopId，不再次创建。

零元桶自洁样本仍需建单、支付处理、支付确认和启动确认。运行中 orderStatus=2，匹配同一订单的 orderStatus=3 + finishTime 有完成依据；completeTime 可能只是预计结束时间，倒计时结束不能宣布衣服洗好。没有验证洗衣停止接口时不提供“结束洗衣”。取消、退款、超时、付款已扣但启动失败仍需独立验证和恢复设计。

## 10. 原生/UI DTO 建议

这是本项目独立设计，不是照搬上游类。

### 10.1 现在可实现的官方页面模式

- 原生方法：`openOfficialPage(target)`，target 仅允许 `login`、`wallet`、`operatorTickets`；`openOfficialMiniApp()` 仅打开固定小程序首页。
- 返回：`opened`、`destination`、固定错误类别，例如 `unsupportedPlatform`、`missingOfficialApp`、`navigationBlocked`。
- 不返回 token、手机号、余额、merchantId、订单号；不提供 `connected=true` 或 `recharged=true`。UI 展示“官方页面查看”，不展示 0 元占位。
- 网页自己拥有认证、服务端状态和操作；App 只负责受限导航、安全返回与明确能力说明。关闭页面不注销官方账号、不取消订单、不解除代扣。
- 若在本机持久保存官方网页 session，应禁用备份，说明保存范围；不要为了退出胖乖清空教务或趣智的 Cookie/缓存。Android 全局 WebView CookieManager 的清理范围必须专门审查。

### 10.2 后续获准并核验原生接入时

- `AccountSnapshot`：provider、脱敏手机号、验证状态、更新时间、stale、固定错误类型。平台账号 ID 只在原生作为隔离键。
- `WalletSnapshot`：普通余额元、受限余额元、小票原始值与明确单位、积分数、积分可抵元分别可空，分别保留更新时间与完整性；不默认求总和。
- `OperatorTicket`：merchantShopId、shopName、balancePoints、principalPoints、giftPoints、source、verifiedAt。对应账户；分页截断明确。
- `DevicePreview`：goodsId、categoryCode、名称、operatorId、routingShopId、merchantShopId、paymentMode、通信方式、结束能力、SKU 列表，各未知能力保持 unknown。
- 交易 DTO 另设，不混在钱包刷新里；持久化 attemptId、阶段、orderNo/orderId、device/SKU/account 归属与最后一次服务端确认。实际发送按钮每次明确显示商户、设备、程序、金额及支付方式。

## 11. 本校还缺的证据与验收顺序

1. 用户自己的官方账号在普通 WebView 中完成一次登录；核对验证码/协议/返回目的地，不能通过合成测试代替。
2. 对比官方钱包、商户小票与用户实际说的“剩余金额”：洗衣/饮水是否同一运营商、同一种资产？未核实前只保留官方命名。
3. 经用户在手机上核对的运营商名称、商户充值链接或官方小票列表。没有这些就不默认商户。
4. 本校洗衣机和饮水机二维码原始文本/类型、设备 details/sku/payment/通信能力。只收任务必需信息，不让用户公开 token、短信码、完整账户抓包。
5. 普通官方 WebView 是否能完成选商户、支付渠道与支付跳转；支付宝小程序是否匹配同一个手机号/商户。没有实测就只说入口可打开。
6. 未来交易验证先读设备与报价，再由用户明确启动最小操作；确认支付、设备启动、使用结束、费用归属各阶段。失败/超时不重复扣款，不宣称服务失败即钱没扣。

离线测试应覆盖：单位混用、缺值不归零、长 ID、分页/部分失败、401/业务2/HTML错误、退出与换号迟到结果、二维码恶意地址/重复参数/不同类别、固定链接编码、支付外跳限制、取消与返回、无支付宝。只有真实账户/设备证据可以解除对应未验证标记。

## 12. 公开官方静态资源快照索引

文件只是研究来源，未复制进本仓库。哈希用于以后检查引用版本是否变化；文件 URL 中的前端构建 hash 不等同于 API 版本。

| 公开资源 | SHA-256 |
| --- | --- |
| [主 bundle](https://h5.qiekj.com/js/app.c17a893c.js) | `6cab591d72761706a01d9d23091ea1578cf58852a168cc638bb43c039ad0eb74` |
| [登录页](https://h5.qiekj.com/js/pages_oneLogin.39280240.js) | `a0d05fb66f53dcd356c15246fe9613fe5e1f961e662de9f292dce19c238788be` |
| [钱包页](https://h5.qiekj.com/js/pages_myWallet.2381003c.js) | `b549f084e4238f47df26603356a6d9d5c347287f266ef9e7b2a8c447d1bb475e` |
| [商户小票列表](https://h5.qiekj.com/js/user_goldList.d8c8e0e9.js) | `079339e386caecca51e57995c96d3797ac4dc8100a23c5b2dea7c094a409e960` |
| [小票购买页](https://h5.qiekj.com/js/user_buyGold.92206bfe.js) | `e8aeeef080f4c8b05dc9126826417dacadc2d10ff016abf67d2e653a9a5d6385` |
| [设备读取路由](https://h5.qiekj.com/js/pages_skip.a1ce81b2.js) | `bb7135157666f5185f156da6abbb750e542c9bd74bace26c12be61efa94c85c0` |
| [当前登录页所链注册协议](https://h5.qiekj.com/js/user_UserAgreement.9c21cdf0.js) | `4793c1633727ad5fb309de436bd005969a90755c87d21fa1c7b32c45d50aeb58` |
| [当前登录页所链隐私政策](https://h5.qiekj.com/js/user_privacyPolicy.79ca76f5.js) | `c3234fca5037b0037d8bbc78e627b744739bad88ecf8dcc3b98e7ccdecd96402` |
| [官方设置页](https://h5.qiekj.com/js/user_setting.5ed39add.js) | `5dab468804737f5b6b9d19807d02f194a916308365a980a99d906f3b5da644b7` |
| [网易易盾 bootstrap](https://cstaticdun.126.net/load.min.js) | `86d282af5aa54c1343b1ba568d3dc7d0903ee3138e20133c124bf59b886c433a` |
| [bootstrap 所列 Watchman 静态 SDK](https://cstaticdun.126.net/wm.3.0.0_33d41777.min.js) | `a3143ab7420ee016cc3e8409da104e70a19774af56f62de9a88f829d8742c0a2` |
| [bootstrap 所列 IRisk 静态 SDK](https://cstaticdun.126.net/ir.2.0.13.min.js) | `c96a0feb5eb853d0fb85142fc727ab449025863c52ad59afce22f67dde9fa9ef` |

### 固定版本源码链接

[J-API]: https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/data/qiekj/QiekjApi.kt
[J-MODEL]: https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/data/qiekj/QiekjModels.kt
[J-REPO]: https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/data/qiekj/QiekjRepository.kt
[J-RECHARGE]: https://github.com/Inonvation/JUWPHub/blob/edf81286f26673968d4a804b6fd6bf6fc13f35ef/app/src/main/java/edu/jxslu/schedule/ui/water/QiekjRecharge.kt
[W-API]: https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/logic/network/ApiService.kt
[W-MODELS]: https://github.com/Night-stars-1/wash/tree/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/logic/model
[W-SCAN]: https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/ui/scancode/ScanCodeScreen.kt
[W-PAY]: https://github.com/Night-stars-1/wash/blob/ffc25d25b980f8bef66b41d7d015936989ec825e/app/src/main/java/com/srap/wash/ui/goodsdetail/GoodsDetailScreen.kt
[H-API]: https://github.com/Mercury000/HUEL-yktwx/blob/1bb98ea5bc87e9a217ce6b8af10c47046aa92c73/app/src/main/java/com/mercury/yktwx/data/life/LifeDeviceApi.kt
[H-ACCOUNT]: https://github.com/Mercury000/HUEL-yktwx/blob/1bb98ea5bc87e9a217ce6b8af10c47046aa92c73/docs/life-service-accounts.md
[H-LAUNDRY]: https://github.com/Mercury000/HUEL-yktwx/blob/1bb98ea5bc87e9a217ce6b8af10c47046aa92c73/docs/life-devices-laundry.md
[H-WATER]: https://github.com/Mercury000/HUEL-yktwx/blob/1bb98ea5bc87e9a217ce6b8af10c47046aa92c73/docs/life-devices-water.md
[P-SCRIPT]: https://github.com/3ryng1um/qiekj/blob/0079ac518442bc03e1d16a93e97b653900598dfd/pgsh.py

未验：本校真实账号、官方 WebView 渲染/登录/充值、所有设备与支付；风险：错误单位或商户映射可能误导余额/充错账户，重复交易可能重复扣费，缺少结束证据不能保证设备已停止。

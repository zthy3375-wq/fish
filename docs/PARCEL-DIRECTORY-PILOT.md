# 待取包裹授权联调 · 2026-11-27

核心验收未完成。Android 与 iOS 的联调客户端可以接入批准的只读包裹目录。截至本轮，没有获准供邯院通读取菜鸟消费者全量待取目录的数据源，也没有用真实账号获取过任何取件码。测试入口在「首页 → 取快递 → 待取包裹联调」。淘宝、拼多多出库身份码沿用原入口。

## 从参考源码确认的取码方式

| 项目 | 认证、请求、解析和续用 | 接入结论 |
| --- | --- | --- |
| ParcelHelper · GPL-3.0 | iOS 保存小米账号会话，关联已验证手机号，使用聚合客户端协议查询包裹及结构化取件码。菜鸟实现复用淘宝 Web 会话和客户端网关，返回列表后映射驿站及取件码。前台调度合并并发请求。 | 有直接取码实现和 iOS 代码。对应客户端包裹读取权限尚未开放给邯院通。 |
| ExpressAssistant · MIT | Android 登录页获取小米会话并关联手机号，聚合请求返回物流数据，同步层对轨迹及详情做取件码提取。源码提供部分设备兼容逻辑。 | 代码有安卓取码路径。非小米设备长期可用性、iOS 和第三方权限均待核实。 |
| Parcly · GPL-3.0 | 淘宝连接器维护淘宝会话，查询菜鸟待取列表、解析运单和取件码，再补淘宝物流与单票详情。引擎限制并发并按来源记录登录状态。 | 可参考多源调度与缓存设计。它依赖各平台会话和内部地址，不能证明一次授权覆盖淘宝和拼多多。 |
| HandyCode · MIT | 官方 App 内的 WebView 处理菜鸟和拼多多页面登录、会话及当前内容。 | 页面适配流程可参考。源码未提供第三方应用的结构化授权目录。 |
| Parcel Pilot MCP · MIT | Playwright 载入持久浏览器会话，菜鸟适配器的入口和查询都指向集团官网，解析器读取通用物流卡片。 | 通用解析器无明确取件码映射，也无证据表明它能经菜鸟集团首页读取消费者待取包裹。 |

精确文件、提交及维护日期见 [五项目源码审查](PARCEL-SOURCES-20261127.md#五个项目的源码审查)。联调代码根据 OAuth 和公开业务文档独立实现。

| 渠道 | 已核实的当前边界 | 真实数据验证 |
| --- | --- | --- |
| [小米 OAuth](https://dev.mi.com/docs/passport/scopes/) | 资料及手机号等授权不含公开的快递读取权限。小米聚合是否愿意为第三方开通、跨设备覆盖哪些包裹仍需平台确认。 | 未取得权限。 |
| [菜鸟物流科技](https://tech.cainiao.com/productv2/ProductIndex/6) | 可按已知运单号及收件手机号鉴权查取件码。消费者端的本人全量包裹目录未找到可开放申请的同等接口。 | 未取得测试凭据。 |
| [淘宝开放平台](https://developer.alibaba.com/docs/doc.htm?articleId=102635&docType=1&treeId=154) | 淘宝授权有应用级权限，买家订单候选仅覆盖获准的交易范围。淘宝校园网页未登录探测返回 HTTP 403。公开[淘宝协议](https://terms.alicdn.com/legal-agreement/terms/suit_bu1_taobao/suit_bu1_taobao201811121436_80276.html)要求自动提取前取得平台许可。 | 未取得消费者跨平台包裹及取件码权限。 |
| 拼多多消费者入口 | 公开 H5 探测可返回网页。未找到第三方消费者待取目录及取件码授权契约。 | 未取得权限，未登录实测。 |
| [快递100取件码](https://api.kuaidi100.com/document/qujianmaapi) | 已实现公开企业接口客户端。查询须有获批企业凭据、已经订阅的运单和匹配的收件手机号。只返回单票结果。快递100另有面向[快递公司入驻](https://api.kuaidi100.com/document/ruzhuziliao)的手机号查询，需快递公司签章授权，未找到直接面向校园 App 的授权说明。 | 通过公开响应契约的合成测试。实际单票仍需获准企业测试环境和已订阅运单。 |

## 联调配置

供应商或经供应商批准的适配服务须提供以下 HTTPS 只读契约。该契约是客户端联调接口，源码没有内置可代用的供应商。接入后需按实际的 OAuth 授权方式及接口约定配置或适配。

- `POST /oauth/device/code` 按 [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628) 发送表单 `client_id` 及范围 `parcels.read offline_access`。返回 `device_code`、`user_code`、`verification_uri`、`expires_in` 及可选 `interval`、`verification_uri_complete`。授权页必须在配置的相同 HTTPS 来源下，由系统浏览器打开。
- `POST /oauth/token` 实现设备授权和刷新令牌授权。Bearer 业务令牌只留在原生层。用户可以在应用提供的授权页自行验证手机号或登录，凭据由授权方接收。
- `GET /v1/parcels` 接收 Bearer，按授权账户返回完整目录，分页使用不透明的 `cursor`。JSON 返回 `items` 和可选 `nextCursor`。单项包含 `carrier`（规范快递公司缩写），`trackingNumber`，`source`（如 `cainiao`），`state`（`ready`、`picked_up`、`in_transit`、`unknown`），UTC 毫秒 `updatedAt`，以及可选字符串 `pickupCode`、`station`。返回端须统一同一承运人的别名，并明确标注出库。只可在完整成功后用空数组表示无记录。
- 两端按承运商和运单号去重。冲突选择最近状态，同时间的出库优先。待取码用字符串原样保存前导零。全部分页成功才写入快照，网络或分页异常保留上次结果。401/403 或授权过期会移除已失效的本机会话和快照。
- 客户端不允许查询重定向，成功缓存五分钟，手动请求至少间隔十秒，设备 OAuth 遇到连接异常后增加等待时间，遵守服务端秒数 `Retry-After`。停留在联调页或回到前台时才触发查询，未启用后台周期拉取。断开会删除本机授权及快照。授权方的账户撤权由授权方控制。

### 构建

Android 使用独立安装包 `org.handancampus.app.parcelpilot`。Gradle 配置须通过 Debug 构建。开发者在供应商注册移动端公共 client ID，无需向客户端写入 client secret。

```sh
npm ci
npm run build
npx cap sync android
cd android
./gradlew :app:assembleDebug -PparcelPilot=true \
  -PparcelDirectoryOrigin=https://approved-provider.example \
  -PparcelDirectoryClient=public-android-client
```

iOS 在 Xcode 选择 Hanyuantong 的 Debug 配置，真机直连安装。测试用自有签名及隔离 Bundle ID，可按本地开发团队配置。编译时启用以下 Build Settings，示例域名和 ID 需替换。默认构建无入口。

```
PARCEL_PILOT_ENABLED=YES
PARCEL_DIRECTORY_ORIGIN=https:/$()/approved-provider.example
PARCEL_DIRECTORY_CLIENT=public-ios-client
```

这里的 `$()` 是给 Xcode Build Settings 文件使用的空变量，避免 `//` 被视为注释。通过 `xcodebuild` 命令参数配置时直接传入 `https://` 开头的地址。配置后打开 App 的同一路径，用户名和验证码在数据方网页输入。

### 快递100单票联调

仅在获准企业测试账号、一个已订阅的本人运单以及确认该次调用的可能费用后执行。令牌、运单与电话都无需放入 Git 或聊天记录。CLI 读取已安全注入的 `KUAIDI100_KEY` / `KUAIDI100_SECRET` 和标准输入 JSON（`carrier`、`trackingNumber`、`receiverPhone`），仅输出脱敏结果。没有真实条件时用合成测试。

```sh
npx vitest run scripts/parcel-kuaidi100.test.mjs
node scripts/parcel-kuaidi100.mjs --live
```

## 真实验收条件

先取得数据方书面确认或测试项目权限，范围要明确允许邯郸学院菜鸟消费者包裹的目录、取件码、出库状态和两端使用。测试应由本人在设备上完成同一授权，准备一件淘宝及一件拼多多已入同一校区菜鸟驿站的包裹。分别记录非小米 Android 和 iPhone 上的包裹数量、取件码一致率、出库后状态、重复率、重启授权及实际同步耗时。报告只记录脱敏结果。全部通过后才能确认核心完成。

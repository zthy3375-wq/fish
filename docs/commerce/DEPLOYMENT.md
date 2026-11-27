# 邯院通校园周边 V1.0 部署与验收

Android Vue/Capacitor、原生 SwiftUI 和独立商家工作台共用腾讯云 CloudBase HTTP 函数 `hyt-community`。商业接口位于 `/hyt-community/v1/commerce.*`，服务端通过同一个 PostgreSQL 实现业务规则。管理入口通过现有账号页面发现，工作台独立部署并重新登录。

## 隔离环境

1. 使用独立 CloudBase PostgreSQL 测试环境及测试账号。先准备现有社区版本的账号和会话表。对已有目标环境核对社区版本及唯一项目所有者记录，避免重复安装旧社区 SQL。所有操作使用该环境的 API 密钥和环境 ID。
2. 备份 PostgreSQL，使用数据库管理身份执行 [commerce-schema.sql](../../cloudbase/commerce-schema.sql)。该迁移建立 `hyt_commerce`，只读取现有社区账号、会话和项目所有者身份。默认广告总开关及 iOS 开关均关闭。核对执行 SQL 的 CloudBase 服务身份能够调用 `hyt_commerce.run(text,jsonb,text)`，并确认 `anon`、`authenticated` 及可供客户端使用的数据库角色无法读取商业表、执行商业函数或读取私有图片对象。若实际环境的 DB API 使用不同服务身份，由迁移所有者按该环境的服务角色授予 schema `USAGE` 和单个 `run` 函数的 `EXECUTE`，保留表访问限制。
3. 准备名称为 `hyt-commerce` 的私有 CloudBase 存储桶，允许 JPEG，单文件大小上限 1,200,000 字节。SQL 在存在 CloudBase 存储表时建立限制策略。用匿名和学生登录分别核对原始对象拒绝访问。健康检查必须核对签发后的图片可用，私有资质材料仅出现在商家自查和运营审核响应中。
4. 在独立环境以现有社区的 HTTP 函数部署流程打包 `cloudbase/functions/community`，保留当前社区设置和已有环境变量，补充下表配置。先保留 `COMMERCE_ENABLED=false` 验证原接口，检查数据库及存储权限后再开启隔离联调。生产签名、强制更新和 TestFlight 流程与此无关。

| 变量 | 用途 |
| --- | --- |
| `COMMERCE_ENABLED` | 精确值 `true` 启用商业接口 |
| `COMMERCE_METRIC_SALT` | 独立环境至少 32 字符的随机密钥，用于去重和匿名举报限流 |
| `COMMERCE_ADMIN_URL` | HTTPS 商家工作台地址，仅向有权管理商业模块的会话返回 |
| `COMMUNITY_WEB_ORIGINS` | 逗号分隔的精确 HTTPS 工作台 Origin，追加到现有名单 |
| `COMMUNITY_TRUST_PROXY` | 由 CloudBase 网关确实覆盖 `X-Real-IP` 时设为 `cloudbase` |

5. 执行 `VITE_COMMERCE_API=https://<测试域名>/hyt-community/v1/ npm run merchant:build`，在独立 HTTPS 站点托管 `dist-merchant`。相机需要 HTTPS 并由店员主动授权。托管应设置 `X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`、`Content-Security-Policy`（脚本和样式来自自身域，图片允许目标 CloudBase 存储域，连接仅允许 HTTPS API，设置 `frame-ancestors 'none'`）。HTTP 只用于 localhost 浏览器联调。商家工作台的登录令牌仅保存在页面内存。
6. Android 隔离构建传入 `ORG_GRADLE_PROJECT_commercePreview=true` 和 `ORG_GRADLE_PROJECT_commerceService=https://<测试域名>/hyt-community/v1/` 后运行 `npm run android:apk`。包名 `org.handancampus.app.commercepreview`。iOS 使用 Debug 构建并传入 `COMMERCE_TEST_SERVICE=https://<测试域名>/hyt-community/v1/`，在独立模拟器使用测试账号；Debug 里的会话与其会话数据库绑定。两端覆盖测试地址时，邯院通账号登录和商业接口走同一测试环境。正式构建沿用既有生产地址。未传测试地址的并装 APK 可以验收启动和入口，线上未启用时入口显示暂未开放。
7. 使用测试账户依次验证商家入驻、主体审核、优惠领取、扫码或输入核销、合同预留、线下凭证登记、排期、商家报告。测试数据仅向隔离环境写入。建立每日任务用服务身份运行 `SELECT hyt_commerce.prune_private();`。检查数据库查询和图片存储计量，再决定开启范围。

## 运营与权限

- 最高商业角色来自社区数据库中唯一的既有项目所有者身份。只有该身份可调整套餐及自定义价格、广告开关和商务权限。商务管理员由所有者授权。社区管理员身份本身没有商业权限，商业授权也不授予社区权限。
- 商家注册邯院通账号，提交主体信息和 JPEG 资质，审核通过后可用免费版。修改门店公开资料生成待审版本，学生端继续看到最后一次通过的版本。商家无法访问其他商户数据。下架门店会暂停现有广告。恢复前应检查商家资质及被暂停档期。
- 普通账号可浏览、收藏、举报。优惠券需要管理员线下查验学生身份并按账号 ID 授权。仅保留资格标记和操作留痕。运营端记录核验结论，避免记录证件号或复制学生证。学生通过领取提示获取自己的账号 ID。商家核销响应只含优惠标题和核销时间。
- 合同按北京时间录入，开始包含、结束不包含。套餐名称、权益和标价在签约时保存快照，改价影响后续签约。基础版免费，选定位置由合同统一预留。可按月登记、登记 14 天试用或由所有者为付费短期推广定价。线下实际收款在合同下登记，退款以负数登记，余额不得超出合同价。素材须审核，排期在合同及预留区间内，收到全额款项后可展示。试用每商家一次。
- 全站广告上限为首页 3、周边 Banner 3、每分类 2。暂停排期保留预留，取消合同释放库存。排期和合同历史、审核理由、主体及广告材料应归档。审批记录和素材生命周期需遵循运营主体适用的留存要求。关闭开关后，当前云实例清空缓存，其他实例读缓存最多 15 秒，已打开页面的广告许可最多再显示 2 分钟且不会跨过排期截止时间。
- 线上回退优先关闭广告，再关闭模块开关或回滚上一版函数。数据库和素材留作对账与归档。独立验证期不需要迁移或写入任何线上业务数据。

## 数据与性能

广告和公开目录首屏使用按平台、分类及参数区分的 15 秒进程内缓存，同键并发共享读取。门店、收藏、优惠券、素材、合同与管理列表使用游标分页。移动端不轮询广告；到期与展示许可由本地状态收起。图片从客户端压缩为 JPEG 再在服务端按像素重编码，批量签发临时链接。浏览曝光和访问仅由登录账号发送，每批最多 12 个、目标粒度按天去重，服务器仅向经营者返回汇总。无教务、社区或跨应用广告追踪。

## App Store 与广告规则核对

- Apple 审核指南 [2.5.18](https://developer.apple.com/app-store/review/guidelines/#software-requirements) 要求广告适合年龄分级、提供不当广告举报入口并约束定向数据。两端所有付费推荐标示「广告」，提供举报，广告依据排期和目录分类展示。
- 同 [3.1.3(g)](https://developer.apple.com/app-store/review/guidelines/#other-purchase-methods) 核对，Apple 区分专用广告管理 App 和购买在同一 App 显示的推广。学生端无购买、支付或套餐下单。iOS 广告默认关闭，应在 App Review Notes 准确说明线下签约流程、展示条件、资格和测试访问，并在苹果确认当前模式后才考虑启用正式广告。审核结果以苹果为准。
- [《互联网广告管理办法》](https://www.samr.gov.cn/zw/zfxxgk/fdzdgknr/fgs/art/2023/art_d93a579afd45413e8576e4623fab348f.html) 第九条涉及广告可识别性，第十四条规定主体核验、材料审核和广告档案一般自发布终了至少保留三年，第十六条涉及平台投诉举报机制。经营者应核实经营主体及需额外审查的广告类别。V1 由人工审核，商家提交素材不会直接展示。
- [《中华人民共和国个人信息保护法》](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) 要求目的明确、最小必要和透明处理。正式启用前核对隐私文本、处理目的、保存期限、学生账户注销关联清理和 App Store 隐私标签。

## 本地验证命令

```bash
npm ci
npm run check
npm run check:commerce
npm run merchant:build
python3 ios-native/Scripts/generate_project.py
```

CloudBase 远程测试与真机核销须使用隔离环境。Apple 平台测例通过原有 macOS GitHub Actions 启动。缓存有效期、权限和真实 HTTP 规则可用隔离 PostgreSQL 测试先行验证。

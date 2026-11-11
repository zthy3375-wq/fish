# 快捷用车 · 1.2.3-test.2 /144（仅测试）

基于 PR #53 的00c8bde新建feature/bike-quick，完整承接 PR #52 扫码、学习通、接水和鸿蒙修复，原生快递试验仍独立。

## 本轮交互

- 首页“骑车”展开两家快捷入口，记住上次选择（只作高亮，不自动启动）。打开面板不请求相机；哈啰按钮启动本机扫码，美团按钮直接请求官方扫一扫，避免在邯院通先扫一次。两家真实目标页仍待实测，美团扫码Scheme沿用历史公开来源，不包装成当前安卓已验证入口。
- 哈啰识别成功后显示品牌、车号和“前往用车”，沿用官方c3x.me观察到的完整qrCode参数。相册/手电筒/对焦沿用原生扫码；未取得车辆直达真机确认，故暂不提供“识别后自动跳转”。
- 本机也能识别美团车码，保留完整b值和_1后缀，但网页可能进入下载页，建议官方扫码。
- 官方扫码/支付宝入口成功分发后记录最近入口，只含品牌、可选10位车号、目标App枚举和打开时间。车码、ticket、凭据、URL不持久化，无云请求。记录12小时后移除；未来时间/畸形记录拒绝。没有官方订单/账号数据，记录不标为骑行中；清除、过期、换账号或关闭应用不代表还车。
- “返回官方用车”只通过固定包名的标准Launcher打开上次支付宝/美团/哈啰App，不带车码、URL、ticket，不调用扫码或use路径。不承诺恢复当前订单，提示可能到首页，请用户在官方端查看当前骑行。入口恢复/前台唤醒只重读本机记录，不自动打开任何App。
- 失败不覆盖此前最近入口；重复点击由Vue与原生同时拦截。记录清理不调用官方订单接口。其他方式收起展示App首页、复制车号、车码网页和适用扫码回退。扫码中关闭面板忽略迟到结果并使临时ticket失效。

## 2026-11-11 路径复核与新增来源

无账号公开GET再次核对：哈啰200，响应SHA-256仍为f9e9584a0bccb1ea4cc4373c2980da18c5df363a7f7e2eb7ecf9127fe1e0e3d9；美团200，仍重定向保留b参数的下载页，响应e64f1a04c446695c0fd223c6891c88e74795fe0620398da2a6ac83c8aef82298。官方goRide引用的通用唤起页亦200，不提供单车订单回执。没有登录或发起车辆控制。

新增返回方式的包名来自应用市场公开的开发者分发信息：[支付宝](https://app.mi.com/details?id=com.eg.android.AlipayGphone)、[美团](https://app.mi.com/details?id=com.sankuai.meituan)、[哈啰](https://app.mi.com/details?id=com.jingyao.easybike)。分别固定com.eg.android.AlipayGphone、com.sankuai.meituan和com.jingyao.easybike，不允许JS传包名。

返回使用Android标准[getLaunchIntentForPackage/getLaunchIntentSenderForPackage](https://developer.android.com/reference/android/content/pm/PackageManager#getLaunchIntentSenderForPackage(java.lang.String))，API33以上在常规Launcher不可见时尝试后者；不把查询失败当作未安装。旧安卓无法取得Launcher或系统拒绝时提示手动切回官方App，不自动退到扫码或携码路径；没有新增广泛包查询权限。Android APK与鸿蒙原生应用跨环境仍需实测。

能力区分：本轮只有已识别车码、本机入口记录和系统分发结果；没有可靠的车辆/订单回执，不能显示“已打开对应车辆”“骑行中”“已还车”。UI表述为已请求入口、可能首页/网页、跳转失败，实际目标页及车辆、登录、费用和还车由官方端确认。

## 本轮验收

前端测试覆盖被动打开、两家分流、单次点击、识别后确认、重复点击、失败保留记录、关闭迟到回调、清除、过期/前台恢复、非法记录与存储失败。新增原生回归用例覆盖固定扫码、返回Launcher无车码、缺失处理程序不重发用车和安全拒绝；原有二维码校验和携码原样保留用例继续保留。本轮原生测试/构建尚未执行，无新APK，当前结果和环境阻塞见STATUS。

待真机：美团/哈啰扫码Scheme实际目标页、支付宝哈啰车辆带入、未登录后继续、三类App返回是恢复已有页面还是首页、缺失App与鸿蒙兼容、真实开锁收费和还车。上述未知项不得以自动化分发通过替代。

---

以下保留1.2.3-test.1的研究与历史验收，交互以本轮说明为准。

# 扫码骑车 · 1.2.3-test.1 /143

基于 fix/learning-course-read 的56d9a33新建 feature/bike-scan，包含学习通、接水和鸿蒙跳转修复；与原生快递试验分支无合并。仅测试，不发布或修改更新元数据。

## 本轮用户反馈与应用内用车调查

用户于2026-11-11反馈扫码成功。该反馈确认扫码环节，尚未确认车辆直达、官方登录后继续、开锁和还车。进一步核实哈式骑 H5、通用开放平台、官方规则和 GitHub 实现后，仍未取得适用于样本普通共享单车的第三方骑行接入合同，本轮采用路线C，保持现有官方入口与回退。没有增加占位登录/开关锁按钮或生成重复APK。详细适用范围、证据、申请材料及批准后的实施方案见[应用内骑车调查](BIKE-IN-APP.md)。

## 2026-11-11 公开入口核对

使用无账号的Android浏览器UA公开GET，不调用开锁、支付或车辆控制接口。两张用户照片本机解码为：

| 平台 | 车码 | 核对结果 |
| --- | --- | --- |
| 美团 | `http://www.mobike.com/download/app.html?b=8646834293_1` | HTTP与HTTPS均返回200，重定向至 `https://bike.meituan.com/mtbike/download/zh/index.html?b=8646834293_1`，保留b完整值 |
| 哈啰 | `http://c3x.me/?n=9150978196` | HTTP与HTTPS均返回200，页面脚本升级HTTPS，并按n分流；支付宝环境携带完整qrCode进入官方小程序 |

第一手来源：

- [哈啰车码落地页](https://c3x.me/?n=9150978196)，响应SHA-256 `f9e9584a0bccb1ea4cc4373c2980da18c5df363a7f7e2eb7ecf9127fe1e0e3d9`。脚本helloBike中，当n/e/u存在且处于支付宝浏览器，使用 `alipays://platformapi/startapp?appId=2017050407110255&query=`，query为对`qrCode=`加当前完整URL的编码。本实现采用同一参数合同，由系统处理支付宝入口；没有调用开锁API。普通浏览器分流bike.html，本次GET也返回200并展示下载引导。
- [美团车码落地页](https://bike.meituan.com/mtbike/download/zh/index.html?b=8646834293_1)，响应SHA-256 `e64f1a04c446695c0fd223c6891c88e74795fe0620398da2a6ac83c8aef82298`。实际引用[download.12a3d5d9.js](https://s3.meituan.net/static-prod01/ws-assets/com.sankuai.bikeuser.web.mtbike/oRSeKFIEkCNDQ5Nn1fcnk/mtbike/js/download.12a3d5d9.js)，SHA-256 `eedb6daec382a7289dc88c769e0f3718f18950b08853d193066d147b301f65c5`；goRide打开通用美团唤起页，没有在该函数中传车号，不能认定免二扫。按脚本实际提供的lock_qrcode路径进一步公开读取，页面/脚本均200，仍未获得可在任意安卓客户端使用的车辆直达合同。
- [GitHub作者维护的URL Scheme清单](https://github.com/JamesHopbourn/Apple-Automation/blob/master/URL%20Scheme%20Collect.md)列有 `imeituan://www.meituan.com/scanQRCode`；[历史Scheme集合](https://gist.github.com/vayocc/4beb753313f57f17d2bc244cd1eeeb36)列有 `hellobike://hellobike.com/scan_qr`。这些是历史社区观测，主要面向iOS，不构成当前Android兼容证明。仅作为用户主动点击“尝试打开官方扫码”的固定回退，不附加推测车号参数。未采用需Launch Center Pro回调的单车扫码变体。
- [哈啰开放平台](https://m.hellobike.com/AppHelloOpenApiPortalWeb/latest/index.html)单车模块列“敬请期待”；[哈式骑](https://saas.hellobike.com/)列需申请权限的H5用车接入。不能据此假定校园普通哈啰车已可合作接入。[美团官方共享单车协议](https://rules-center.meituan.com/m/detail/guize/190?activeRule=1)列App/小程序入口，本轮未取得个人开发者的公开原生开锁接口。

## 实现与状态边界

首页增加紧凑单行入口，打开后复用CampusScanActivity，保留手电筒、相册识别、重新对焦与相机权限处理。扫描只本机解析，不自动跳转。只支持实际观察到的c3x.me根路径n参数和www.mobike.com固定路径b参数，参数必须唯一、10位数字；美团保留`_1`后缀。未知域名、路径、协议、端口、附加参数、片段、编码混淆及空白一律拒绝，未知样式不推定可用。

原始车码仅保存在原生内存，由一次扫描生成不透明ticket。Vue只取得品牌、车号和ticket，不能传URL、包名或自造车号去打开。关闭/新扫描/宿主销毁使旧ticket失效；关闭后迟到扫码不恢复车码。无账号缓存、车辆历史、云请求或扫码统计。

哈啰“前往用车”先请求已观察到的支付宝小程序入口，无处理程序时回退该车码的HTTPS页面；美团交给系统打开保留完整b参数的HTTPS车码链接。系统不依赖包名可见性来判断安装；安全拒绝不自动遍历其他路径。主动回退支持官方扫码、系统车码网页和复制编号。没有扫码页处理程序时明确提示可能未安装或不支持，不宣称未安装。外部页面的网络、登录及订单状态由官方处理，本应用不把Intent已分发当作车辆直达或开锁成功。

## 验收边界

已验证：照片本机解码、公开GET及上述页面结构。自动化覆盖原样车码解析、恶意输入拒绝、携码构造、缺少处理程序/安全拒绝/宿主关闭的生产Android适配器、UI重复点击/取消/旧结果清理、两家回退文案和窄屏布局。具体检查与签名构建证据见STATUS。

待真机：Android相机/相册对真实车辆识别、当前支付宝是否接受并展示对应哈啰车辆、未登录后是否保留车辆、官方App扫码Scheme在当前Android/鸿蒙兼容环境的实际目标页、美团是否由系统正确交给App。两家“免二次扫码”均未完成设备验收；美团目前按回退交付。真实开锁、收费、还车及骑行卡抵扣由用户现场确认。

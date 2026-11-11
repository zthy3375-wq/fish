# 扫码骑车 · 1.2.3-test.1 /143

基于 fix/learning-course-read 的56d9a33新建 feature/bike-scan，包含学习通、接水和鸿蒙跳转修复；与原生快递试验分支无合并。仅测试，不发布或修改更新元数据。

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

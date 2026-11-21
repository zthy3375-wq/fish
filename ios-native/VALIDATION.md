## 社区帖子快捷回复对齐（2026-11-21）

参照 Android 1.3.1 的帖子底栏和回复编辑器。iPhone 采用贴底编辑层与可保持可见的发送区，支持点开后自动聚焦、收起保留文字与配图、继续回复指定评论、匿名状态和 1000 UTF-16 单元计数。发送失败在当前编辑层提示并允许重试，发送确认后再刷新讨论列表。

新增仅在调试模拟器中启用的隔离交互用例，覆盖输入条、键盘、匿名、草稿恢复、失败重试与发布后评论显示。执行结果以该提交的 CI 和附件为准。

## Android 1.3.1 逐页复审（2026-11-21）

以 Android main `dca5582` 的 APK、页面代码和实际截图为基准，和 iPhone 13 的上一轮截图逐页复查。修正课表入口、教学周调整和已同步学期的离线切换、首页两钱包和生活卡片、社区登录注册、学习通作业与统一日程、设置主题和通知入口、荣誉殿堂的布局及五栏导航。

iPhone 13 新截图与安卓再次并排审看后，补齐社区欢迎插图和未填写表单的提示、设置主题的行内排列、首页和课表的按钮配色，并先采集空待办清单，再运行测试数据写入流程。

新增测试覆盖多学期缓存与换号隔离、校准后的跨学期隔离、重启后保留、不改变课程周次及学习通作业的清单状态。更新模拟器流程以检查课表视图切换及设置、荣誉殿堂中的底栏。新截图、编译和执行结果以本提交对应的 CI 为准。

系统组件、官方登录页和第三方跳转使用各端原生实现。双端视觉验收需要相同网络状态、账号状态和数据。此次未使用实际学校、学习通或社区账号，也未操作接水机、洗衣机或真实支付。

## Android 1.3.1 对齐整合（2026-11-21）

本轮将 iPhone 五栏视图、课表时间轴、待办日程、钱包和私信与 1.3.1 荣誉、注册和管理流程整合。新增旧设备收藏迁移测试，扩展社区隔离联调用例以覆盖公开昵称、求助采纳及撤销、社区收藏查询和普通用户的成员目录权限。当前提交的 Xcode 和实体 iPhone 验收结果以对应 CI 及实际记录为准。

## Android 1.3.0 对齐 · 首页与胖乖接水

首页与胖乖钱包共用直饮水商户余额，缺失或重名时显示暂未获取。首页可分别连接学校、查看今天所属周的课表、折叠课程和进入学习通及成绩。头图铃铛提供本机公告、已读状态及原生系统提醒设置。

对照 Android 1.3.0（184）的实际状态转换。机身已停水时可按当前记录 ID 离线恢复扫码，设备结束和付款结果仍由平台确认。仅在本机加密存储写入成功后释放占用。最近消费展示当前移出记录，也识别旧版的手动停水记录。下一次接水须重新识别设备、核价和确认。

原生回归覆盖启动状态未知、使用中、结束请求已发送、核账阶段、重复点击、旧确认、登录过期、换号、落盘失败、重启以及下一次扫码时设备仍忙。验证使用隔离的胖乖请求和存储。真实扫码、机身停水和正式账单需在校园设备复核。

## iOS 五 Tab 与 Android test.30 / test.31

本次本地运行的共享协议、学习通解析和快递解析分别通过 5、34、39 个场景。前端 534 项及隔离的社区服务 126 项通过。目录由 Android 代码生成，包含 32 项，其中 8 项隐藏。未接触生产账号和设备。新增 iPhone 构建、两个尺寸的模拟器验收、实际 Android APK 截图任务；最终状态以此开发分支对应运行记录为准。以往运行的通过数量只适用于各自所列的提交。

## 搭子招募（test.12，本轮原生 CI 通过）

客户端源码 `dd39d9cc76688699f497555826f3754d1ca0b76a`，tree `c47444f4d551374d792d9d82f01c55768f408ffb`；CI 合并提交 `ca9f96a953658cdf1c5b8e890367976ec3651e47` tree 一致。[CI 43839100059](https://github.com/zthy3375-wq/fish/actions/runs/43839100059) 整体成功：374 项单元用例中 373 项通过、1 项真机数据保护检查按设计跳过；42 项 TreeholeTests 全通过。5 项现有 UI 流程（重点任务 2 项、其他 3 项）、模拟器 App/测试目标、未签名 iPhone Release 编译、模拟器打包与截图导出通过。

新增原生招募编辑、报名卡片、私人报名名单与「我报名的」；新增 4 项测试覆盖日期/旧草稿、失败与版本合并、迟到请求、服务端状态刷新和名单协议。首轮工程验证发现新 Swift 文件未登记，重新生成 Xcode 工程后上述完整 CI 通过。后续 `4c238209` 仅改后端匿名隔离与测试脚本/文档，客户端与原生工程源码不变。

schema 8 真实接口联调、匿名保护与临时数据清理通过，见 [本轮记录](../docs/COMMUNITY-BUDDIES.md)。没有可分发 IPA/TestFlight；真实相册、输入法、弱网与 iPhone 真机仍待验收。下面保留历史版本证据。

## 投票帖与评论配图（test.11，本轮 CI 全部通过）

独立原生 SwiftUI 新增单选投票编辑/展示/改选/撤回、按账号保存的投票草稿、评论和楼中楼最多三张图片及纯图片回复。图片沿用原生相册与压缩，提交失败保留，账号变化丢弃迟到结果。投票修订号保护列表、详情与多层返回快照。

产品源码 `09cd2a535ad76982722be73f83fec15b84ff3600`，tree `af88548957304fe7876d4a31258ce1d7dfeb12d4`，CI 合并提交 `98c4931c1e14c76fe68938c5008bd2d52cac0e8d` 与该 tree 相同。[CI 43822655325](https://github.com/zthy3375-wq/fish/actions/runs/43822655325) 整体成功：370 项单元用例中 369 项通过、1 项真机数据保护检查按设计跳过；38 项 TreeholeTests 全部通过。5 项现有 UI 流程（重点任务 2 项、其他 3 项）、模拟器 App/测试目标、未签名 iPhone Release 编译、模拟器打包和截图导出通过。

新增 5 项 XCTest 覆盖草稿校验/旧草稿、截止/旧评论数据、投票失败保留与状态合并、账号退出后的迟到选票，以及截止错误和原生取消传输。首轮根视图编译出现 Swift 类型推断超时；拆分滚动页面与生命周期修饰后重新跑完整 CI，通过。后续提交仅补文档与真实联调脚本的 postId 参数，不改变该产品源码。

邀请码内测服务已升级 schema 7；真实投票与评论图片联调和清理通过，见 [本轮记录](../docs/COMMUNITY-POLLS-COMMENTS.md)。没有可分发 IPA/TestFlight；真实相册/输入法、弱网和 iPhone 真机流程仍待设备验收。

---

## 关注用户与关注动态（test.10，本轮 CI 全部通过）

原生公开主页关注、关注动态、本人关注名单与失败重试已实现；新增 4 项 XCTest 覆盖失败保留、返回快照、旧账号迟到响应、名单分页去重/重试及筛选回退。关注动态仅展示公开帖，和分区/兴趣/搜索/排序共同生效；关注用户与关注讨论保持独立。

产品源码 `7d604d0c8398ccc98d487c07e54975fc1f8c5885` 的 [CI 43814771045](https://github.com/zthy3375-wq/fish/actions/runs/43814771045) 整体成功：365 项单元用例中 364 项通过、1 项真机数据保护检查按设计跳过，33 项 TreeholeTests 全部通过；5 项 UI 流程（重点任务 2 项、其他 3 项）、模拟器 App/测试目标编译、未签名 iPhone Release 编译、模拟器打包和截图导出成功。CI 合并提交 `f6f253e6fefbde67d6c93cf00a00ed98940d7181` 与产品源码 tree 相同。后续文档与触控脚本不改变 Swift/Kotlin/Vue 产品代码。

邀请码内测服务已升级 schema 6；真实关注/取消、本人名单和匿名排除联调通过，详见 [本轮记录](../docs/COMMUNITY-FOLLOWING.md)。没有签名 IPA/TestFlight；iPhone 真机相册、网络/键盘、升级缓存与真实账号体验仍待设备验收。

---


## 兴趣分区与社区首页（test.9，本轮 CI 全部通过）

原生四分区与六种兴趣标签、发帖选择/草稿标签、旧分类聚合和筛选失败回退已实现。新增 3 项 XCTest 覆盖旧草稿、过滤参数、失败恢复及迟到分页隔离。匿名树洞新帖与回复统一匿名；搭子仍为普通图文帖。

产品源码 `ed5fb73757f46020b0dc1882db0fd16ec49f48f4` 的 [CI 43809848404](https://github.com/zthy3375-wq/fish/actions/runs/43809848404) 整体成功：361 项单元用例中 360 项通过、1 项真机数据保护检查按设计跳过，29 项 TreeholeTests 全部通过；5 项 UI 流程（重点任务 2 项、其他 3 项）、模拟器 App/测试目标编译、未签名 iPhone Release 编译、模拟器打包与验证产物导出均成功。CI 合并提交 `51fd34ff693120dd38188e063abfbcedec21af70` 与产品源码 tree 相同。最终提交仅补验证文档与 Web 触控检查，产品源码未改变。

邀请码内测后台 schema 5 的真实接口联调通过，详见 [本轮记录](../docs/COMMUNITY-DISCOVERY.md)。没有签名 IPA、TestFlight 或实体 iPhone 验收；真实相册、输入法、大字布局、系统返回和弱网流程仍待真机实测。

---

## 头像与轻量回应（test.8，本轮 CI 全部通过）

原生 SwiftUI 同步头像预览、相册读取与 512px 方形压缩、公开头像与匿名图标、三种回应及失败回退。新增 4 项 XCTest 覆盖裁切、网络失败、账号切换旧响应及返回状态；后续刷新会同步更新保存的回应状态，避免返回时覆盖新计数。

产品源码 `c4874693259ac5d42831cc96d32dca2e2b651a9e` 的 [CI 43805152701](https://github.com/zthy3375-wq/fish/actions/runs/43805152701) 整体成功：358 项单元用例中 357 项通过、1 项真机数据保护检查按设计跳过，全部 26 项 TreeholeTests 通过；5 项 UI 流程、模拟器 App/测试目标编译、未签名 iPhone Release 编译、模拟器打包与验证产物导出均成功。CI 合并提交 `39986089308cda40b9a4f63e4aa5a424c3c9f61d` 与源代码 tree 相同。最终记录提交只改文档，产品源码与上述验证基线一致。

没有签名 IPA、TestFlight 或实体 iPhone 验收；模拟器不能代替真实相册、输入法、手势和网络流程。test.7 的证据仅描述历史版本。

---

## 社区互动消息与讨论回访（test.7，本轮 CI 已通过）

源码 `fa31e79c7646b9e67e1eb7636aec63db904750c3` 的 [CI 43736636366](https://github.com/zthy3375-wq/fish/actions/runs/43736636366) 整体成功。354 项单元用例中 353 项通过、1 项真机数据保护检查按设计跳过，包含全部 22 项 TreeholeTests；5 项 UI 流程、模拟器 App/测试目标、未签名 iPhone Release 编译及模拟器打包均成功。

本轮原生实现五个主 Tab、互动消息及已读、消息直达评论、参与/关注讨论、公开主页和简介。新增三项 URLSession 回归覆盖消息读取失败/旧账号响应、回复上下文与已读、关注失败与公开主页清理。最终记录提交只改文档和 Web 触控检查的输出路径，不改产品源码，因此本次 CI 覆盖交付实现。无签名 IPA、TestFlight 或实体 iPhone 验收；模拟器不能替代真机网络、键盘、相册与手势。

---

## 即时阅读、整卡操作与图片排序（2026-11-15，完整 CI 已通过）

SwiftUI 同步缓存正文即时进入、独立详情加载/重试、返回及账号代次隔离；作者区/留白/配图进入帖子，分区/点赞/菜单各自响应；九图与四图、图片排序、动态字体与边缘返回手势。新增三项 URLSession 延迟与错误用例。

源码 `ec97a99` 的 [CI 43727858904](https://github.com/zthy3375-wq/fish/actions/runs/43727858904) 整体成功：351 项单元用例中 350 项通过、1 项真机数据保护按设计跳过，包含全部 19 项 TreeholeTests；5 项 UI 流程、模拟器 App/测试目标、未签名 iPhone Release 编译和模拟器打包成功。CI 合并提交 `8720a08` 与主体源码 tree 相同。最终补充提交只修改 Web 回复框焦点描边和验证文档，未修改任何 iOS 源码或资源，故本轮结果覆盖最终原生实现。无签名 IPA、TestFlight 或社区真机网络、相册、输入法和手势验收。下方保留历史证据。

---

## 社区连续阅读与返回定位（2026-11-15，完整 CI 已通过）

SwiftUI 同步自动翻页、页尾错误重试、原帖子返回位置、评论入口直达、缓存帖子互动数量更新与收藏移除；分页独立于全页 busy，旧账号/筛选/刷新响应按代次隔离。新增 5 项 TreeholeTests 覆盖URLSession 测试适配器的错误、延迟响应、去重、游标停滞和缓存更新。源码 `93e35b2` 的 [CI 43718162187](https://github.com/zthy3375-wq/fish/actions/runs/43718162187) **整体成功**：348 项原生用例中 347 通过、1 项真机数据保护按设计跳过，16 项 TreeholeTests 全部通过；5 项 UI 流程、模拟器 App/测试目标编译、未签名 iPhone Release 编译和模拟器打包成功。CI 合并提交 `e647b2e` 与源码 tree 相同；后续仅更新文档。没有签名 IPA、TestFlight 或真机网络、手势、相册与覆盖安装验收。下面保留上一版本证据。

---

## 社区阅读与互动优化（2026-11-15，完整 CI 已通过）

源码 `a7aaf12` 同步中性信息流、固定正文/评论导航、紧凑互动栏与回复 sheet、按比例图片和多图分页、评论预览两条与展开收起。请求按互动独立处理；失败回退、并发点赞/收藏字段合并、清除账号后的旧响应隔离新增三项 XCTest。

[CI 43684658792](https://github.com/zthy3375-wq/fish/actions/runs/43684658792) **整体成功**：343 项原生用例中 342 通过、1 项真机数据保护按设计跳过，全部 11 项 TreeholeTests 通过；5 项 UI 流程、模拟器 App 与测试目标编译、未签名 iPhone Release 编译和模拟器打包通过。后续 Web 大图链接重试修复未改变本目录的应用、测试、项目或资源源码；本轮证据覆盖最终原生实现。没有签名 IPA、真机相册/键盘/网络或 TestFlight 验收。下方为上一版本证据。

---

## 分区图文树洞（2026-11-15，完整 CI 已通过）

新增 PhotosPicker 九图、去元数据 JPEG、按账号加密草稿、分区排序、标题、大图缩放、楼中楼和评论点赞。新增三项测试覆盖上传边界、跨账号草稿和图片缩放。

源码 `dd6a821` 的 [CI 43679768647](https://github.com/zthy3375-wq/fish/actions/runs/43679768647) 整体成功：340 项单元用例中 339 通过、1 项真机数据保护按设计跳过，全部 8 项树洞测试通过；5 项 UI 流程、模拟器 App/测试目标、未签名 iPhone Release 编译及模拟器产物打包通过。后续 `ffff3bf` 仅修复 Web 草稿返回，没有改变 iOS 源码。没有签名 IPA、真机相册/网络、TestFlight 或 App Store 发布证据。

前一版 1c1a5fc / CI 43617649419 模拟器编译与未签名设备编译通过，337 项单测日志 1 跳过/0 失败，但步骤在结束阶段超时，UI 未执行。此次将单测步骤预算从 8 分钟调整为 12 分钟。
首版 30e227b 的 CI 43614199439 最终整体成功，336 项单测中 1 项按设计跳过、5 项 UI 和未签名设备编译通过。下方“仍在执行”为当时记录。

---

## 树洞开发分支（2026-11-14）

新增独立邯院通账号、Keychain 会话、SwiftUI 树洞、昵称/匿名帖子和评论、举报管理。新增 4 项原生会话边界/匿名模型测试；当前代码的 Xcode 模拟器 App/测试目标编译已在 CI 43611619469 通过；该次混用 Xcode 16.4 SDK 与 iOS 26.2 模拟器，回归阶段被后续提交取消，不计为测试通过。CI 现在选择不高于当前 SDK 的模拟器并统一测试构建目标，[43612196671](https://github.com/zthy3375-wq/fish/actions/runs/43612196671) 已通过全部 5 项 UI 测试、模拟器编译和未签名 iPhone Release 编译。单元测试宿主启动被模拟器拒绝（应用正在安装/卸载），未执行单元用例，整体运行失败；不记为 XCTest 全通过。CI 将单元与 UI bundle 拆为顺序调用，使用同一份 build-for-testing 产物运行 test-without-building，修复安装竞争并减少重复构建；新回归 [43614199439](https://github.com/zthy3375-wq/fish/actions/runs/43614199439) 的 `Native unit regression` 已通过，包含新增树洞和调课用例；其余完整流水线仍在执行。该次源码 `30e227b` 与上一轮 `5c17abf` 之间仅改动工作流和文档，应用及测试源码完全相同。上述记录是两次运行的分项证据，不代表其中某次工作流已整体成功。已人工查看 43612196671 的首页与个人页截图，树洞入口、文字和安全区域显示正常。腾讯云邀请码内测服务已部署，已通过公网 HTTP 双账号检查；这不替代 iPhone 真机网络或 TestFlight 验收。

# 2026-11-14 按周调课（云端验证受阻）

新增学校课程按周调整、恢复原安排、时间冲突确认、账号/学期隔离与离线保存；10 项新增 XCTest 包含编辑页合成渲染截图测试，尚未执行。[macOS CI 43561594650](https://github.com/zthy3375-wq/fish/actions/runs/43561594650) 在 runner 启动前被 GitHub 账号付款/消费上限限制阻止。本轮 iOS 编译、XCTest、截图和模拟器包均未完成；下面已通过的两端优化记录不覆盖本次调课功能。Android 已改用 Linux 本地构建并通过验证，但不替代 Swift 原生验证；iOS 需可用的 Mac 或 macOS 云端构建服务，详见 [调课验收](../docs/COURSE-ADJUSTMENTS.md)及[免费构建途径](../docs/LOCAL-BUILD.md)。

---

# 2026-11-14 联合优化验证

共享脚本、接水预检、轮询与首页课程进度已修改，新增 XCTest 回归。[macOS CI 43557758974](https://github.com/zthy3375-wq/fish/actions/runs/43557758974) 已整体成功：

- 322 项原生单测：321 项通过、1 项真机数据保护测试按设计跳过，0 失败。
- 5 项 UI 流程通过：2 项重点待办流程和 3 项其余流程。
- 未签名 iPhone Release 编译、模拟器打包、测试结果和截图导出成功。
- 人工查看首页、课表与胖乖未登录页截图，安全区域和按钮显示正常。首页截图没有课程，课程进度边界由单元测试覆盖，动态显示仍需带课程验收。

验证源提交为 `9bbecf47b39f95dbd5b3a0df431eb112caa5bfb0`，CI 合并提交 `2ef373e24924e71e6ad5775e55881ce6786d3e05` 与该源码树完全一致；后续仅追加文档。学校真实账号、付款、扫码设备和真机签名安装尚未验收。完整结果见 [两端整理与验收](../docs/ANDROID-IOS-REVIEW-20261114.md)。下方保留历史阶段记录，其中“待验证”仅描述当时状态。

---

# Native iOS validation

Baseline: Android main 780bbc85c0b70e8d9273129eca666d7141e21e42, production 1.2.1.

- Native protocol metadata adaptation: 5 JSDOM synthetic scenarios passed, including repeated all-history queries, partial failure and explicit-term metadata.
- Source and asset review: official icon and campus artwork reused; both school JavaScript resources are byte-identical to Android.
- No change to Android, application web code, cloud services, release version or update metadata.
- `npm ci` from the unchanged lockfile, 439 frontend tests, TypeScript and production build passed. Initial reused dependency directory lacked Leaflet; clean installation resolved it.
- Independent static security review found and fixed automatic refresh narrowing all-history grades and failure of current-term partial merges. Query selection now remains independent of resolved term; native adapter retains resolved-term metadata even on timetable failures. Additional fixes preserve inaccessible Keychain/cache records and refresh stale presenters.
- 23 native XCTest cases cover 10 academic adapter/session cases, 3 schedule cases, 8 backup cases and 2 Keychain-backed encrypted-storage cases. The storage tests write/read using separate storage instances and reject corrupted files without replacing them.
- Two UI smoke scenarios cover four tabs, repeatedly opening/cancelling editors, empty-save validation, adding a personal task, terminating/relaunching the app with the task retained, and completing/filtering it. All school inputs in tests are synthetic; no real school account was used.
- Initial macOS CI run 42998193147 passed 10 initial unit tests, one UI scenario and unsigned iPhone compilation. Expanded run 42999720611 then correctly caught a personal-data persistence failure caused by disabling simulator code signing and losing Keychain access. CI now uses Xcode's local ad-hoc simulator signing (`Sign to Run Locally`), with no production certificate and no plaintext-storage fallback.
- Run 43001094199 on source 8dff3a4 passed all 23 unit tests, both UI scenarios, unsigned Release iPhone compilation, simulator packaging and artifact upload. The workflow's overall conclusion is cancelled because a later source commit superseded it after those steps; this is not recorded as an overall successful run. The separate run [43002345881](https://github.com/zthy3375-wq/fish/actions/runs/43002345881) on source 5fa0a6a is fully successful: 23 unit tests, 2 UI scenarios, simulator compilation and unsigned Release iPhone compilation. It includes the stale-course-detail guard. Xcode 16.4 / iOS 18.5 simulator was used. Screenshot pixel review confirmed correct safe areas, the repaired home image width and persisted completed task. This validates the first core milestone only; later feature additions need new runs.
- Web synthetic UI check could not launch because Playwright Chromium is absent in this executor; this is not iOS UI verification.
- Android verification reached the Gradle wrapper but could not download Gradle 8.11.1 (`Network is unreachable`). Android compilation was not completed in this environment. The generated order-only Capacitor changes from that check were reverted; existing Android source and build configuration remain unchanged.
- Physical iPhone and real school login are untested. No production signing, IPA distribution, TestFlight or App Store submission.
- Full Android feature parity is not complete; see README's explicit remaining functionality list.

## Second-stage implementation (validation pending)

Learning, Quzhi, Pangguai, CSV/XLSX/ICS import, notifications, fixed parcel/help destinations and WidgetKit source are integrated after the successful core milestone. These additions are not covered by run 43002345881. Each new source revision requires fresh simulator tests and unsigned iPhone compilation. No live SMS, credentials, payments or device operations were used during development.

The app and widget use separate default Keychain groups; only the widget snapshot key is explicitly shared. Shared snapshots are AES-GCM encrypted and excluded from backup. App Group and shared Keychain provisioning require the owner's Apple development setup for physical-device acceptance. Reminder delivery, widget gallery/rendering and third-party app handoff remain physical-device checks.

Apple implementation references: [local notification scheduling](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app), [WidgetKit timeline data sharing](https://developer.apple.com/documentation/widgetkit/timelineprovider), and [required-reason API manifest](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). The system-uptime use is only a local SMS cooldown interval; no uptime data is transmitted.

## Expanded parity implementation and current CI evidence

- Run [43006908844](https://github.com/zthy3375-wq/fish/actions/runs/43006908844), source84b090a: project/assets passed; compile failed on Quzhi error-property shadowing and an actor-isolated nested callback. These were repaired. Tests did not execute.
- Run [43008659027](https://github.com/zthy3375-wq/fish/actions/runs/43008659027), source098492b: expanded app and tests compiled, then the host crashed before unit tests because the iOS18.5 simulator could not load libswiftWebKit.dylib. All three UI tests failed to launch; device Release was skipped. No second-stage XCTest pass is claimed. Simulator-only compatibility handling follows Apple's [WebKit bug293831](https://bugs.webkit.org/show_bug.cgi?id=293831); the physical-device deployment target remains16.
- Added Android-compatible backups, multi-semester/course-arrangement/time-table management, rich tasks, school profile and grade analysis, homepage summaries, display preferences, bounded opt-in analytics implementation (production disabled), and current-page parcel pickup reading. Native tests are synthetic; each source revision must complete fresh macOS CI.
- Independent static security reviews confirmed and repaired: Widget cleanup independent of preference state; retryable Quzhi orphan-cache cleanup; no throwing storage metadata step after destination commit; imported recurrence element-identity comparison; recurrence relationship remapping after original-ID merge. The initial suspicion of native UUID round-trip duplication was disproved by the UUID-preserving helper and is not a confirmed defect.
- Re-review found no additional confirmed issue in parcel account checks/cancellation/partial snapshots, default-disabled analytics consent/delete races, school-profile account isolation, backup strict field allowlists, replacement confirmation baselines, or independent school/personal calendars. Static review is not runtime acceptance.
- Re-ran unchanged web aggregate:439 tests, TypeScript and production build passed. School-script adaptation5 and Learning DOM34 synthetic scenarios passed; parcel DOM39 synthetic checks passed with no network/account use. Android reference checks also cover tasks50, semesters18, and grade analysis32 cases. No actual school, delivery, SMS, payment, water or laundry account was used.

## Expanded runtime regression (2026-11-11)

- Runs [43012103176](https://github.com/zthy3375-wq/fish/actions/runs/43012103176) and [43013419431](https://github.com/zthy3375-wq/fish/actions/runs/43013419431) caught Swift name-shadowing compile errors in the task priority clamp and analytics error properties. Both were repaired; neither run executed tests.
- Run [43015596815](https://github.com/zthy3375-wq/fish/actions/runs/43015596815), source7ff164b, successfully compiled all expanded app/test targets and the unsigned iPhone Release target. It executed311 unit cases with12 failed assertions, and5 UI flows with2 failed flows. This is not a passing run.
- Runtime fixes now use exact fixed analytics URLs rather than parent-directory URL equality; retain strict request/response URL and POST checks. The production analytics gate remains disabled. Backup round trips retain subsecond task timestamps without collapsing creation/update identity.
- The two task UI failures were obsolete StaticText selectors: the real title is an edit Button. Exported accessibility hierarchy and completed-task screenshot confirm persistence and filtering; regression selectors now track the actual UUID-backed edit control and state across relaunch instead of weakening the assertions.
- Simulator file-protection attributes can be absent, as reproduced by [Apple DTS](https://developer.apple.com/forums/thread/780632). Encryption/atomic replacement/backup-exclusion assertions remain enabled. A separate physical-device protection test is explicitly skipped on simulator; protection on a real iPhone remains unverified.
- Photo QR parsing adds Apple's local [Core Image QR detector](https://developer.apple.com/documentation/coreimage/cidetectortypeqrcode) when Vision inference cannot produce results. Both decoders process bounded local pixels and reject conflicting validated device codes. No image is uploaded and no device action occurs during parsing. Fresh CI is required for these repairs.

- Run [43018879724](https://github.com/zthy3375-wq/fish/actions/runs/43018879724), source1ee053b: all316 unit cases finished with315 passed, one explicit physical-device-protection skip and zero failures. Unsigned iPhone Release compiled successfully. Three UI scenarios passed; the two task flows still failed because their metadata belongs to a SwiftUI Other wrapper containing the real Button. The saved records are visible in exported screenshots and hierarchy; this remains a test-selector failure, not evidence of lost records. The exact wrapper/child structure is now used for the next targeted regression.
- CI now runs the two task UI cases first, then all unit tests and the remaining three UI cases on the same source/build, avoiding duplicate execution while retaining full-suite coverage when both stages succeed. Each result bundle is preserved. Source after1ee053b also explicitly applies the existing high-contrast primary-label color to13 primary buttons and adds a four-appearance contrast assertion; this still requires its own runtime result.

## Android 1.3.0 visual comparison, November 19

The previous Pro Max and SE screenshots differ from Android on all five tabs. The owner independently observed the same on iPhone 13 with iOS 15.4. The visual branch uses the Android 1.3.0 header, home artwork, Lucide tab icons, period labels, task quick entry and four-column academic shortcuts as references. The screenshot regression now targets iPhone 13 hardware geometry and records the actual simulator runtime. An unsigned device build at minimum deployment 15.4 checks API availability. Neither that build nor a newer simulator establishes physical iOS 15.4 acceptance.

On commit 0000176, Android 1.3.0 and iPhone 13 simulator screenshots confirmed all five tab highlights moved to the correct fifth of the screen. A geometry assertion on both simulator sizes confirmed the four profile shortcuts occupy a single row. The seven-page comparison exposed a proportional-minute gap over lunch and a longer settings front page. The follow-up maps teaching periods, occupied breaks and empty breaks with Android’s timetable axis rules, puts quick entry in the task list flow and groups the secondary settings. The visual test waits for a terminal community connection state before capture and exercises an empty period opening its course editor.

## 2026-11-21 TestFlight 2.0.0 真机反馈

同帖双机照片暴露了旧验收没有覆盖的登录后广场。以 Android 1.3.1 实际组件为参照，本次调整广场入口、排序、分区、卡片互动与发帖按钮。扩展 iPhone UI 回归，使用合成账号经过广场、学习分区、继续聊、帖子和回复重试，并保留广场截图。

待办完成证据覆盖先完成主任务、先完成子任务和从安卓备份恢复的个人任务。课表从周视图打开空课日、保有已完成记录的空清单、立即离开彩蛋页、启动时已有教务和学习通缓存分别处理。学校缓存限当前已验证的本机账号，社区荣誉仍以服务端授予为准。此记录不代表两个实体设备的全流程验收。

发帖页与广场共用分区编号。荣誉殿堂采用服务端返回的成就分类和解锁条件，保留未获得的常规里程碑，隐藏未获得的停发记录及隐藏成就的名称。

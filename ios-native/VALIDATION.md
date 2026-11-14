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

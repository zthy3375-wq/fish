# 邯院通仓库审查与清理记录 · 2026-11-11

审查对象：`zthy3375-wq/fish`。基线为 `main@b46ac3ebd6b69677d5c5fcfc0ab10872f2f04751`，正式版本 1.2 /133。审查开始时远端有15个分支、6个未关闭PR，main跟踪366个文件。下表是该时点的快照，不包含本轮新建的文档整理分支/PR。

所有者要求删除前询问。初轮审查只整理说明、入口和维护规则；随后所有者明确确认“abc都删了吧”，授权执行下方A/B/C。执行前重新核对7个远端头SHA及快递承接关系，均与本清单一致。

## 已确认的执行结果

| 组别 | 结果 |
| --- | --- |
| A | 5个已取消功能分支已从GitHub删除；原有PR继续关闭 |
| B | PR #46、#47已关闭，parcel-center/cards两个旧分支已删除；PR #48及parcel-native保留 |
| C | [独立清理PR #56](https://github.com/zthy3375-wq/fish/pull/56)已移除闲置组件与未使用符号，严格检查11处诊断清零；源码变更尚未合入main |

删除后通过GitHub分支列表再次确认7个候选均不存在，main、归档、研究分支和PR #48–51的分支SHA保持原值。本轮没有合并main、重新部署服务、改动发布清单或交付新APK。下方“远端分支快照”保留删除前状态与完整SHA，用于追溯。

## 审查结论

### 1. 优先处理主线与部署代码的差异

`cloudbase/functions/analytics/core.mjs:12` 只接受三段版本号。使用同一份合法人工请求分别传入版本 `1.2`、`1.2.0`、`1.2.3-test.2`，main的本地校验结果分别为400、200、400；当前已发布版本恰为1.2。该调用仅在本机运行，没有上报到生产。

[PR #49](https://github.com/zthy3375-wq/fish/pull/49)已修正版本校验，并记录小时暂存/汇总服务已部署为hourly-v3，但对应源码还在`fix/analytics-hourly`。直接从main重新部署统计服务，会用旧实现覆盖这项修复。**保留该分支，优先审查并归并已部署代码。**本轮没有重新验证线上定时器或账单，部署结论沿用PR与分支中的证据。

### 2. 手机新修复尚未进入main

[PR #51](https://github.com/zthy3375-wq/fish/pull/51)为1.2.2-test.4 /142，包含学习通课程读取与单课重试，并完整承接[PR #50](https://github.com/zthy3375-wq/fish/pull/50)的接水旧记录和鸿蒙跳转修复。Git祖先检查确认`2207435`包含在`56d9a33`中。两者目前均未合入main；不能因骑车方案取消而丢弃这些修复，也不应反向合并已取消的骑车分支来取得它们。

### 3. 清理机会主要在旧分支与少量未使用符号

正常`npm run check`通过。初次额外启用`vue-tsc --noUnusedLocals --noUnusedParameters`时发现11处诊断，详见C组；这是加严分析的结果，不是现有默认CI失败。用户确认后，PR #56已清理这些诊断，严格检查退出0。

从`src/main.ts`做静态导入追踪，没有发现可直接批量删除的整组业务模块。导入关系会保守保留未使用的导入，因此同时用Vue类型检查核对；`QuickAction.vue`只被App未使用地导入，可作为单独候选。`CourseCard.vue`、`academic-adapters/zhengfang-timetable.ts`及胖乖官方WebView仍有其他生产调用，须保留。

### 4. 文档已存在跨版本冲突

README曾写“没有业务后端”，但当前仓库已有腾讯云统计/更新；统计说明仍以D1与旧站点登录为开头；路线图还将桌面小组件、正式签名和自动更新写成未来计划。这些会影响后续开发判断。本轮已修正入口并加上历史标记，旧资料和原路径均保留。

### 5. 云函数测试与默认检查分离

`.github/workflows/ci.yml`只运行`npm run check`，该命令不包含`cloudbase/tests/*.verify.mjs`。`cloudbase-updates.yml`的部署job限定手动触发，不能替代普通PR的云函数测试。建议后续增加独立的只测不部署检查，再统一旧部署入口；本轮没有改工作流或触发部署。

## 目录与维护入口

| 目录 | 职责 | 维护注意 |
| --- | --- | --- |
| `src/components`、`src/composables` | Vue页面、交互与状态 | `App.vue`为1029行，后续可按弹层和账号生命周期拆分；不在本轮改变行为 |
| `src/domain`、`src/services` | 课表、个人事项、缓存、导入与原生接口 | 保留存储键、迁移、断点与错误保留逻辑 |
| `android/app/src/main/java/.../academic`、`learning` | 教务与学习通 | 学校/学习通登录与会话由原生管理 |
| `android/.../life`、`widget`、`update` | 校园生活、桌面课表与更新 | 官方入口、真实订单与本机状态各自独立 |
| `android/app/src/main/assets` | 固定教务/学习通读取脚本 | 与原生适配及合成样本同时维护 |
| `cloudbase`、`scripts/cloudbase` | 匿名统计、更新与部署工具 | 主线统计代码与部署分支存在差异，先核对PR #49 |
| `tests`、`android/app/src/test`、`scripts/*browser-check.mjs` | 领域、原生和合成UI回归 | 合成测试不表示真实学校账号或设备已验收 |
| `docs` | 当前说明与历史研究 | 先读README/STATUS/本审查；旧版本资料不覆盖新决定 |
| `releases/android-candidate.json` | 已授权发布清单 | 审查、合并或测试均不授权更新用户端 |

## 远端分支快照

“独立提交”指相对main的提交数量，包含承接的修复，不等于独有功能数量。SHA为当时分支头，供删除前复核。

| 分支 | 头SHA | 独立提交 | 状态与建议 |
| --- | --- | ---: | --- |
| `main` | `b46ac3e` | 0 | 已发布1.2，保留 |
| `fix/analytics-hourly` | `3442bb0` | 9 | PR #49，部署代码尚未归并，保留 |
| `fix/learning-course-read` | `56d9a33` | 9 | PR #51，最新非骑车修复，保留 |
| `fix/water-recovery` | `2207435` | 5 | PR #50，已被#51完整承接；先保留，待#51验收整合后再收口 |
| `feature/parcel-native` | `dd3ba77` | 18 | PR #48，暂停的最新快递试验，保留 |
| `feature/parcel-cards` | `4968237` | 7 | PR #47，完整包含于parcel-native，候选B |
| `feature/parcel-center` | `5d00940` | 3 | PR #46，完整包含于parcel-cards/native，候选B |
| `feature/bike-quick` | `2cf64bb` | 14 | PR #54已关闭，用户取消，候选A |
| `research/bike-in-app` | `00c8bde` | 12 | PR #53已关闭，用户取消，候选A |
| `feature/bike-scan` | `ef663e5` | 11 | PR #52已关闭，用户取消，候选A |
| `feature/free-classrooms-v060` | `40a1d64` | 3 | PR #10已关闭，空闲教室取消，候选A |
| `feature/navigation-v051` | `f6f9559` | 3 | PR #7已关闭，旧导航/iOS草稿，候选A |
| `archive/v0.2.1` | `8fc5e72` | 0 | 已包含于main；保留版本锚点，暂不建议删除 |
| `archive/v0.3` | `830476e` | 0 | 已包含于main；保留版本锚点，暂不建议删除 |
| `research/handan-academic-v041` | `d97732b` | 1 | PR #2早期研究，尚有独立研究提交，先保留 |

## 所有者已确认的删除清单

### A：已取消功能的5个远端分支（已删除）

1. `feature/bike-quick`，当前头`2cf64bb99cfe214614bff99129ad3848f8591a1c`。
2. `research/bike-in-app`，当前头`00c8bde701344c49ea2ee3e9b2a629dd241057a8`。
3. `feature/bike-scan`，当前头`ef663e5af9ebac3c752fbffdfebd0bd08d3316a5`。
4. `feature/free-classrooms-v060`，当前头`40a1d64d6f6f968298881b20c732ca025bfa390e`。
5. `feature/navigation-v051`，当前头`f6f95599974e1cfb0a7e4012cd296d811f7c5710`。

这些分支均未合入main；删除分支不会从当前正式版删除任何功能。它们有未合并提交，含义是放弃继续维护这些分支，不能描述成“全部已合并”。原PR讨论和本清单保留追溯；接水/鸿蒙/学习通修复另由保留的PR #51承接。**本组已按确认执行，远端复核不存在。**

### B：重复的2个旧快递分支及PR（旧PR已关闭，旧分支已删除）

- 关闭PR #46，删除`feature/parcel-center@5d00940cea488a0eee2f3acfb8d95922701880dc`。
- 关闭PR #47，删除`feature/parcel-cards@496823780937c3b9eb2a28e459276f5c49fa92d1`。

Git祖先验证：center → cards → native。保留PR #48及`feature/parcel-native`，不会丢失前两代的提交；最新试验仍暂停，不合入main。**本组已按确认执行，PR关闭且远端分支复核不存在。**

### C：未使用代码（已清理，独立PR #56）

| 文件 | 候选 |
| --- | --- |
| `src/App.vue` | 5个未使用导入：`ArrowRight`、`Clock3`、`timeOf`、`QuickAction`、`CourseCard`；未使用计算值`greeting` |
| `tests/handan-native-adapter.test.ts` | 4个未使用`url`形参，改为明确忽略的参数或省略，不删除测试用例 |
| `tests/pangguai-water-ui.test.ts` | 未使用`pollWater`导入 |
| `src/components/QuickAction.vue` | App导入清理后，无生产引用；删除组件文件前需明确确认 |

前三行对应11处加严类型检查诊断；最后一行为组件文件删除。实际清理移除5个App导入、greeting计算值与pollWater导入，4个测试回调参数改为`_url`，删除QuickAction.vue，保留全部测试用例。仅移除App的`CourseCard`导入，不删除仍在`AcademicDetail.vue`使用的`CourseCard.vue`。CSS保留，未按选择器静态搜索批量删除。**本组已在PR #56执行，尚未合入main。**

C组本地验证：40个文件/421项测试、TypeScript、生产构建通过；加严未使用检查退出0，git diff --check通过。云端结果见该PR；原生源码、工作流与版本号未改动。

## 建议保留的内容

- 当前正常功能、所有测试样本和断点/缓存迁移代码；保留默认检查通过的主线基线。
- 归档/研究文档、`docs/mobile-preview.jpg`及现有截图。它们有历史引用，优先标记历史，删除或移动另行确认。
- Android普通/圆形图标与PWA图标，即使字节相同也有独立资源引用；两个云函数的同内容`scf_bootstrap`各自用于打包，均不按重复文件删除。
- `scripts/prepare-update.mjs`为旧站点通道工具，只接受三段版本号，不能作为当前1.2发布命令；已在APP-UPDATES中位于旧通道记录。是否彻底退役需要先决定旧客户端兼容策略。
- `academic-adapters/zhengfang-timetable.ts`的`parseZhengfangWeeks`仍被教务同步和回归测试使用；不能因其研究来源旧而整体删除。
- 现有部署/发布工作流。仓库main在快照时未保护且无ruleset，是否启用保护另行决定；本轮不改变权限或发布方式。

## 本轮实际验证与整理

- `npm run check`：40个测试文件、421项测试通过，TypeScript和生产构建通过。
- `node --test cloudbase/tests/*.verify.mjs`：12项测试通过。
- 加严未使用检查：初次11处诊断，C组清理后全部消除；未改变默认CI设置。
- 检查main中全部366个跟踪路径：没有跟踪APK、AAB、依赖目录、dist、签名文件或iOS工程；这不是完整的git历史密钥审计。
- 静态本地Markdown目标检查：原有导航未发现缺失文件；本轮完成后再次检查修改的文档入口。
- 初轮文档PR #55不包含产品代码变化；获批后的C组产品代码清理单列于PR #56，原生代码未改，不声称新增真机验收。历史PR的构建结果仍归属于原PR。
- 已补充README、STATUS、ROADMAP、统计说明和文档导航；明确已发布、未合入、暂停、取消四类状态，并在开发说明中记录删除前须确认。

执行任何已获同意的删除前，重新获取远端分支头、核对上面的SHA与承接关系；头发生变化时重新审查，不直接沿用本清单。

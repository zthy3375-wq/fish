# Android 测试包交付证据

Android CI 保留原有 debug/release 原生测试、两次 debug 构建和浏览器回归。两种可安装测试包分别上传，名称不再绑定某个历史功能：

- `handan-campus-regular-debug-<commit>`：普通包，使用 Gradle 默认 applicationId。
- `handan-campus-parallel-preview-debug-<commit>`：独立预览包，使用现有 `-PlearningPreview=true` 配置。该参数只是保留的构建开关名称。

选择目标分支、对应 commit 且整体成功的工作流运行。下载 Artifact ZIP 后解压，每份包含有明确名称的 APK 和 `build-evidence.json`。需要与旧应用并存时选 parallel-preview；实际包名和版本以 JSON 为准，不凭文件名猜测。

## JSON 验证了什么

- `source_commit` 与检出代码 HEAD 一致；PR 检查中通常是 GitHub 的测试合并提交，不一定是分支 HEAD。
- `build_variant` 区分普通 debug 与并行预览 debug。
- `apk` 中的 applicationId、versionName、versionCode、minSdk 和 debuggable 来自官方 Android SDK `aapt dump badging`，包名、版本和最低 SDK 必须匹配本次 Gradle 求值后的配置。
- 并行预览包还必须与同一次构建中已验证的普通包使用**不同 applicationId**，同时 versionName、versionCode、minSdk 和 source_commit 一致。缺少普通包证据或任一条件不符会停止预览包上传；`parallel_installation` 记录用于对比的普通包包名与 APK 哈希。
- `apk.sha256` 和 `apk.bytes` 对应**解压后的 APK 文件**。它们不是 GitHub Artifact ZIP 的哈希/大小，也不是签名证书指纹。
- `signing.certificate_sha256` 来自官方 `apksigner verify --verbose --print-certs`；签名验证非零退出、缺工具、缺字段、元数据不符都会停止该包上传。

JSON 不含时间戳、机器路径或密钥。相同 APK、提交和构建类型产生相同 JSON；这不是宣称 APK 构建本身可逐字节复现。CI 在复制出的独立目录校验每份 APK，后续预览构建不会覆盖先前上传的普通包。

## 安全安装边界

这些仍是 CI debug 测试签名。不同运行通常使用不同的临时 debug 签名，证书指纹仅用于比较，**不保证覆盖升级**；本改动不生成、导出或保存签名密钥，也不配置正式发布。

安装前比较包名、版本与证书。遇到签名冲突时保留旧应用和数据，不要默认卸载；先在旧应用内完成个人数据备份。独立预览包的数据、缓存与账号会话不会自动迁移，需要重新连接账号或使用已有备份恢复功能。此证据不能代替真实账号、真机行为或充值到账验收。

## 开发检查

无需安装 SDK 即可运行替身输出测试：

```sh
node --test scripts/check-apk-evidence.mjs
```

实际检查由工作流完成：Gradle 通过 `--init-script ../scripts/apk-evidence.init.gradle` 执行 `:app:writeDebugApkEvidenceExpectation`，从已求值配置写出预期值，避免另行硬编码版本号。每次构建均重写预期值；目前不支持新增 product flavor 或 debug 后缀，遇到这些配置会明确失败，需同步扩展证据任务。

`scripts/apk-evidence.mjs` 的必选参数是 `--apk`、`--expected`、`--variant`、`--source-commit`、`--build-tools-dir`、`--output`。预览包还必须通过 `--regular-evidence` 传入本次普通包已验证的 JSON。CI 明确使用 SDK `build-tools/35.0.0` 下的 `aapt` 和 `apksigner`，不会用 ZIP 内容或文件名冒充包元数据。输出路径必须不存在，防止误覆盖已有文件。

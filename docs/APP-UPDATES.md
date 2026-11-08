# 腾讯云更新迁移 · 1.0.5

当前新通道：`https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-updates/android/stable.json`。独立云函数 hyt-updates，不改动统计数据库。

GitHub Actions Repository Secret：`PGYER_API_KEY`。工作流 `.github/workflows/cloudbase-updates.yml` 使用已验证的 `CLOUDBASE_API_KEY` 部署服务，将蒲公英密钥作为服务端环境变量注入，客户端和发布清单不含密钥。

发布清单 `cloudbase/functions/updates/releases.json` 的 latest 指向 releases 中的一个版本；每项包括 versionCode、versionName、minSupportedVersionCode、minSdk、sha256、sizeBytes、notes、buildKey。只可加入已签名且在蒲公英真实下载验证一致的包，禁止用最新版本短链替代固定 buildKey。旧版记录保留以支持已缓存的下载。版本策略修改须独立发布。

未配置密钥或 release 时通道返回 503，客户端保留已知策略，不宣布虚假版本。不要在所有用户上开启强制策略做测试；使用受控测试构建或独立测试清单验证。当前 1.0.4 仍检查旧通道，迁移版需要先覆盖安装一次，或通过旧通道分发一次。

接通后验收：普通更新提示 → 应用内下载 → SHA-256/签名/包名校验 → 系统安装权限 → 覆盖安装 → 数据保留。强制更新验证无“稍后”、返回不绕过、断网保留已知策略、撤回策略恢复；接水和编辑中的安全延后保持原逻辑。

## 发布验证与迁移

`releases/android-candidate.json` 固定待发布签名 APK 的哈希、大小、版本和来源。`publish-android-candidate.yml` 使用 GitHub Secret 上传到蒲公英，核对包名及版本后，实际下载并比较 SHA-256 和字节数；验证通过后才部署腾讯云版本清单。发布凭证产物随后应回写到 `cloudbase/functions/updates/releases.json`，避免后续部署回退。

已实际观察蒲公英 install 接口跳转至 `pgyer-apps-cfw.appmeme.com`；服务端及 Android 只额外允许这个确切主机，不允许整个 appmeme.com 域。版本信息只允许腾讯云固定接口。安装包仍检查签名、包名、版本、大小和哈希。

当前候选发布支持上传、下载验证及更新清单；构建与签名仍使用现有 CI 和离线签名，还没有完成“一次确认即自动打包签名发布”。手机上的系统安装、数据保留及国内关闭 VPN 的网络表现需用户实测。强制更新自动化已覆盖，尚未宣布手机实测通过。

以下为旧通道记录，保留兼容说明。

# 邯院通应用内更新

从 1.0.1（101）开始，正式 Android 包启动时检查更新，回到前台最多每五分钟检查一次；“我的 → 检查更新”可随时手动检查。此实现是前台版本检查，不包含后台远程通知服务。1.0 没有更新检查代码，需手动覆盖安装一次 1.0.1。

更新页：https://hanyuantong-updates.dewydahlia.chatgpt.site

更新渠道：`/android/stable.json`。仅公开安装包与更新说明，不发布应用源码、账号数据或密钥。独立更新站点 project_id：`appgprj_6af06c3ae7ac819195fe9a096e93a7e3`，后续复用此站点与源仓库，不另建域名。

## 发布下一版

1. 增加 Android versionCode 与版本名，保留 org.handancampus.app，使用 1.0 正式签名密钥。正式证书 SHA-256：`4be86ec93e000025f12839aa31da16c55ea3c9a7097917226572d3450dca86d9`。
2. 完成测试、构建 release、zipalign、离线签名与 apksigner 验签，核对 APK 内部包名和版本。密钥不进入源码或 CI。
3. 打开更新站点源仓库。执行 `node scripts/prepare-update.mjs /path/signed.apk 102 1.0.2 101 /path/site/dist "更新说明"`，再同步站点源码并发布。
4. 上例的 minimumSupportedCode=101：101 用户可稍后更新；改为 102：低于 102 的用户必须更新。只能指向已完整上传且签名正确的安装包。版本链接不可覆盖为不同文件。
5. 上线后读取 JSON 并实际下载验证 SHA-256。调整最低支持版本或回撤强制要求，只需修改渠道 JSON 再发布站点，不需要重新打包客户端。

## 客户端行为

原生下载到应用缓存，不跳转浏览器或迅雷，不请求公共存储权限。下载前需点击确认；显示进度，失败可重试。下载完成和每次安装前检查大小、SHA-256、APK 包名、版本号和与当前安装应用一致的签名。只访问固定 HTTPS 更新域名，重定向逐跳验证，文件最大 80 MiB。

首次安装更新可能需要允许“来自此来源的应用”。授权后返回再次点击安装，系统安装界面仍需用户确认。强制更新没有“稍后”，返回键不会放行；提供重试与退出。读取到强制策略后暂时离线仍保留该要求；首次检查失败且没有已知策略时不锁住应用。服务器可降低最低支持版本解除限制。不兼容 Android 系统版本时不强制升级。

正在编辑、原生业务操作或未结束的接水会话会延后更新弹窗和安装，保留结束接水、付款与保存入口。下载进程被杀时下次重新下载；不承诺后台断点续传。正式包与预览包不能互相覆盖。

自动化覆盖版本比较、最低支持版本、撤回策略、网络失败保留策略、可选/强制交互、进度与安装权限提示。系统安装权限往返与真实覆盖升级仍需手机验证。

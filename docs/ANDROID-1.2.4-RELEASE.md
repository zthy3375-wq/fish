# Android 1.2.4 发布记录

2026-11-14，所有者明确要求发布正式版 1.2.4，并启用强制更新。此次仅分发 Android；iOS 调课验证在发布时仍运行中，未签名或分发 iOS 安装包。

## 范围与来源

包含两端整理 PR #63 和按周调课 PR #64 的 Android 成果：学校课程调整时间/地点、按实际上课周生效、冲突确认和恢复原安排；保留接水确认修复、跨学期考试缓存、退出账号后的迟到写入隔离、学习通与鸿蒙跳转修复。暂停的 Android 原生快递和统计试验未合入。

应用源码远端 `2308863cef4b2ac837ccc1b5342d9c1fe31e6fde`，本地 `8f3f4a1776c16fd6f0c55ac49a24838400eaa94a`，完整源码树均为 `c0a35add16ff96d0d843fbc1407cf436d97b4023`。后续提交仅处理发布脚本、目录、临时发布入口和文档，不改变已验签 APK 的应用代码。

## 安装包

| 项目 | 核验结果 |
| --- | --- |
| 文件 | Hanyuantong-v1.2.4.apk |
| 包名 | org.handancampus.app |
| 版本 | versionCode 150 / versionName 1.2.4 |
| 系统 | minSdk 23 / targetSdk 35 |
| 构建 | Release，非 debug |
| 大小 | 12,430,367 bytes |
| SHA-256 | a5272bd52a283abf0d138720ad9ef6c024692d0aa214997da6bab7181a4e0b76 |
| 原签名证书 SHA-256 | 4be86ec93e000025f12839aa31da16c55ea3c9a7097917226572d3450dca86d9 |
| 签名与资源 | 单一签名者，v1/v2/v3、4 字节/16 KB ZIP 对齐、28 个网页资源逐字节核验通过 |

使用原私钥备份完成签名，密钥与密码未进入仓库、安装包、日志或发布站点。覆盖原正式版，无需卸载；独立预览版仍保留独立的数据目录。尚未在真实手机执行此次覆盖安装及升级后数据验收。

## 验证

- 本地前端 481 项、共享解析 78 项、TypeScript、生产构建通过。
- 本地 Android Release 182 项原生测试：0 失败、0 错误、0 跳过；Release 编译成功。更新服务 5 项检查通过。
- [云端 Quality 43605634823](https://github.com/zthy3375-wq/fish/actions/runs/43605634823) 与 [Android 43605634989](https://github.com/zthy3375-wq/fish/actions/runs/43605634989) 通过；Android 包含 Debug/Release 单元测试、构建、APK 证据校验与移动浏览器回归。
- 发布站点仅新增带文件摘要的 APK，保留原应用、历史 APK 和旧站点 stable.json。站点 17 项既有测试、生产构建通过，14 个 Android 静态文件与源码逐字节一致。
- 下载站实际下载、蒲公英发布任务重新下载，以及最终腾讯更新接口下载，大小和 SHA-256 均匹配交付包。
- 自动检查使用合成输入，不代表真实学校账号、问题手机或现场饮水机已验收。

## 发布结果

[发布任务 43606113963](https://github.com/zthy3375-wq/fish/actions/runs/43606113963) 成功上传蒲公英并部署腾讯云更新服务。蒲公英固定 buildKey：`2366ffdd425f60f5dc82a40aefb82515`，下载入口 <https://www.pgyer.com/hanyuantong>。

线上 latest/versionCode 为 150，minSupportedVersionCode 为 150，versionName 为 1.2.4。旧版本联网检查更新时进入强制更新流程，现有接水/支付/编辑期间的延后安装规则保留。更新说明：**修复了一些问题**。

发布证据目录回写到 `cloudbase/functions/updates/releases.json`，候选固定 buildKey 后同步留存；发布完成即撤销本次临时工作流分支入口，防止后续非发布工作重复上传或回退线上版本。

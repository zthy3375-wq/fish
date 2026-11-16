# 安全复核 · 2026-11-17

范围：Vue 3/TypeScript、Capacitor 原生会话边界、Node 社区接口/数据库。此为代码及自动化复核，未执行生产渗透测试。未修改生产表、账号、权限或服务部署。

## 已保留的边界

- `android/app/src/main/java/org/handancampus/app/community/TreeholeClient.kt:20`：原生保存会话、白名单 action、正文体积上限，返回前剥离会话及密码/恢复码摘要；HTTP 不跟随重定向并限制响应体。既有会话测试复核。
- `cloudbase/functions/community/core.mjs:10`：scrypt 有并发预算，密码随机盐，客户端身份/角色不作为授权依据。
- `cloudbase/schema-community.sql`：管理员处理、匿名隔离、私信成员关系由服务端 RPC 检查；既有 PostgreSQL/PGlite 用例覆盖越权、屏蔽、删除、幂等、速率和数据保全。本轮后端 101 项通过，不能代替生产 RLS 配置审计。
- `android/app/src/main/AndroidManifest.xml:11`：禁止备份；社区内容使用 Vue 文本插值，未新增 v-html、动态脚本或敏感 Web 存储。
- `capacitor.config.ts`：WebView 调试关闭；未修改 Android 包身份、签名或线上更新元数据。

## 待处理

SBP-001 / 中等：`npm audit` 报告 ExcelJS → uuid 依赖的 2 项 moderate、0 high/critical。自动修复会将 ExcelJS 降至破坏性版本；本轮不执行。课表导入已有 5 MB、ZIP 预算、表格行列和公式拒绝保护，见 `src/services/import-courses.ts:11`。后续独立验证依赖替换或兼容 override，避免破坏导入。

## 实测边界

未读取真实账号凭据，未访问他人账号，未测试线上管理删除/禁言、支付、学校认证或物理接水。管理员仍限已有举报处理能力，完整站长授权界面不在本轮新增；不伪造其已实现。

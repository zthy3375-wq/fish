# v0.4.1 验证记录

日期：2026-11-06。基线 main：`376c8ede7e0fdc4b11a9beabfdaab783b3acdf87`。
分支：`research/handan-academic-v041`。本轮为研究与离线适配交付，不是正式登录发布。

| 执行项目 | 本轮实际结果 |
| --- | --- |
| 依赖安装 | `npm ci --ignore-scripts` 完成，385 packages |
| 全量自动化 | `npm test`：15 个测试文件、127 项全部通过；原 94 项保留，新增 33 项 |
| 类型检查与生产构建 | `npm run build` 最终通过，包含 `vue-tsc --noEmit` 与 Vite 6.4.5 构建 |
| 构建提示 | 原有 ExcelJS 解析分包约 940 KB / gzip 271 KB，仍触发 >500 KB 提示 |
| 公开登录检查 | `node scripts/inspect-public-academic.mjs` 单次 GET 成功，HTTP 200、V-9.0、SSO 配置字段为空、X-Frame-Options SAMEORIGIN；无登录/认证 POST |
| 源码研究 | 本地检出拾光应用与 warehouse 的固定提交，实际阅读通用 HTML 适配、GDUST JSON 适配、桥接、Cookie 兼容处理及数据库模型，详见研究报告 |
| 移动浏览器 | **未执行**；本轮无 UI/正式导入入口变动 |
| Android/iOS 构建及真机 | **未执行**；保留工程，未新增原生桥接或签名包 |
| 学校认证及本人接口联调 | **未执行/阻塞**；学校第三方授权和接口契约未确认，无真实账号登录 |
| 线上预览部署 | **未执行**；未把研究适配器注册为正式连接器/导入入口 |

首次构建发现检查脚本 `.mjs` 缺少类型声明（TS7016），补充 `.d.mts` 后重新执行生产构建通过。该问题已修复，不以首次构建失败当作最终结果。

新增测试由 `tests/zhengfang-adapter.test.ts`（31项）及 `tests/public-academic-inspection.test.ts`（2项）组成。全部使用人工 HTML/JSON 样本；网络查询不在自动化测试里运行。测试并不证明身份归属、学校允许使用、真实账号同步或原生登录回调。

离线格式链路已经覆盖：正方常见字段→多个课程安排与明确作息→预览→既有 CRUD→首页/日/周共用课程选择器→IndexedDB 保存读取→版本化 JSON 备份恢复。只有测试显式执行保存，适配函数自身不写数据库、不清空课表、不修改个人设置。

原有自动化也覆盖 CSV/XLSX/ICS、本机 CRUD、数据迁移、周网格布局、会话取消/过期等功能。它们本轮全部通过，但不能替代浏览器渲染或原生设备验证。

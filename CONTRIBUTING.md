# 参与贡献

请先阅读 [README](README.md) 与 [当前状态](docs/STATUS.md)。当前维护 Android 与 `ios-native/` 原生 Swift/SwiftUI iPhone 工程，覆盖教务、个人安排与现有校园生活功能。Flutter 验证和空闲教室开发已停止。

## 开始开发

main 是整合目标；存在尚未合并的正式修复或两端整合 PR 时，先按 STATUS 核对最新测试基线，避免从较旧 main 覆盖新实现。通常从更新后的 main 创建 `feature/*`、`fix/*` 或 `chore/*` 短期分支，PR 目标均为 main。一个 PR 解决一个明确问题；合并后删除已确认无独立工作的短期分支。不要重复合并已被替代的研究/诊断分支。

```sh
npm ci
npm run dev
npm run check
```

每个PR解决一个明确问题，说明触发条件、最终行为、验证结果和仍未验证的部分。文档或CI改动按影响范围验证；涉及学校会话或原生代码时，完成对应平台的单测与构建；Android 需要 Capacitor 同步，iOS 需要工程再生成、XCTest 和设备编译，共享脚本变更需检查两端资源一致。UI有变化时检查移动端宽度及返回、键盘和安全区。

## 常用检查

| 命令 | 用途 |
| --- | --- |
| `npm run check` | 单元测试、共享协议检查、类型检查、生产构建 |
| `npm run check:shared` | 两端教务脚本与 iOS 页面读取协议检查 |
| `npm run test:watch` | 本地增量测试 |
| `npm run android:check` | 构建网页、同步Android、原生debug/release测试 |
| `npm run android:apk` | 构建网页、同步Android、原生测试并生成debug APK |
| `npm run test:ui` | 构建后运行人工原生替身界面检查；先安装Playwright Chromium |

Node.js 需 22.12+；`JAVA_HOME` 需指向完整JDK 21。苹果构建步骤见 [iOS README](ios-native/README.md)。不要把本机SDK路径提交仓库。旧诊断窗口与空授权框架已删除；人工数据只在tests/fixtures中使用。

## 学校适配

- 用户只在学校官方页面输入凭据；Vue不得直接处理Cookie或密码。
- 保持学校查询只读，不绕过验证码、证书校验或服务器认证。
- 数据接口与展示页面分别验证；别把渲染后的DOM误当原始HTTP响应。
- 格式测试、浏览器结构检查、用户真机反馈分别记录，不用单测数量替代真实接入验证。
- 空/异常响应保留旧数据；学校缓存与个人事项分开，退出和切换账号不能混用缓存。
- 访问或日志需要排查时，优先只保留状态码、阶段和有界计数，不记录完整HTML、Cookie、令牌、学号或密码。

## 问题反馈

提供应用版本、设备/系统、操作步骤、预期与实际结果。截图先遮挡姓名、学号和其他个人信息。不要把真实学校账号用于公开测试样本。安全问题见 [SECURITY.md](SECURITY.md)。

原创代码采用MIT；新增第三方代码、字体或图片必须保留来源和适用许可。不要提交依赖目录、构建产物、环境凭据、原生签名文件或未脱敏个人数据。未经明确确认，不合并main、不部署正式站点、不删除远程历史分支。

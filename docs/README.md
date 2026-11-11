# 文档导航

阅读项目现状请以 [当前进度](STATUS.md) 和根目录 [README](../README.md) 为准。版本文档描述对应时点，不覆盖较新的真机反馈。历史记录中的其他平台计划均已停止；当前只维护Android。

## 当前维护入口

先按模块找到实现与维护记录；下方版本研究文档继续保留原路径。

| 工作 | 入口 |
| --- | --- |
| 分支、PR、删除确认和执行证据 | [2026-11-11 仓库审查与清理](REPOSITORY-REVIEW-2026-11-11.md) |
| 已发布版本和历史验收 | [STATUS](STATUS.md) · [版本记录](../CHANGELOG.md) |
| 应用更新和测试 APK 证据 | [更新与发布](APP-UPDATES.md) · [包名/签名校验](APK-EVIDENCE.md) |
| 匿名统计及与部署分支的差异 | [统计维护说明](ANALYTICS.md) |
| 学习通协议与问题回归 | [协议研究](research/V070-CHAOXING.md) · [验证码续传](V072-LEARNING-FEEDBACK.md) · [当前修复 PR #51](https://github.com/zthy3375-wq/fish/pull/51) |
| 原生饮水和洗衣 | [接水](V088-WATER.md) · [洗衣](V086-LAUNDRY.md) |

- [胖乖官方页面模式与边界](V082-PANGGUAI-OFFICIAL.md)
- [淘宝/拼多多出库码直达](V082-PARCEL-SHORTCUTS.md)
- [胖乖协议、金额口径与官方来源](research/V082-PANGGUAI.md)
- [APK 包名、签名与文件校验](APK-EVIDENCE.md)
- [趣智钱包与真机验收](V081-QUZHI-WALLET.md)
- [开源项目比较与复用策略](OPEN-SOURCE-STRATEGY.md)

- [成绩分析算法口径、培养方案调查与验证范围](V060-GRADE-ANALYSIS.md)

- [当前功能、验证证据与未完成事项](STATUS.md)
- [变更记录](../CHANGELOG.md)
- [开发与提交规范](../CONTRIBUTING.md)
- [隐私与安全反馈](../SECURITY.md)
- [教务架构与上游研究](V0.5.0-INTEGRATED-ACADEMIC.md)：早期研究记录，部分“待验证”已被STATUS更新。
- [学校真实页面、展示页/数据接口纠错](V0.5.0.4-VERIFIED-HANDAN-HTML.md)

## 历史记录

文件保留原路径，避免已有 PR 链接失效。标题下的历史标记提醒读者不要把早期限制视为当前状态。

| 阶段 | 说明与验证 |
| --- | --- |
| v0.5.0初版 | [实现](V0.5.0-INTEGRATED-ACADEMIC.md) · [早期验证](VALIDATION-v0.5.0.md) |
| v0.4.3自动识别 | [记录](V0.4.3-AUTOMATIC-CONNECTION.md) |
| v0.4.2诊断 | [实现](V0.4.2-ANDROID-TEST.md) · [验证](VALIDATION-v0.4.2.md) |
| v0.4连接框架 | [接口边界](V0.4-ACADEMIC-CONNECTION.md) · [PR #1审查](PR-1-REVIEW.md) |
| v0.3.1课程管理 | [研究](RESEARCH-v0.3.1.md) · [验证](VALIDATION-v0.3.1.md) |
| v0.3 | [使用](V0.3-GUIDE.md) · [验证](VALIDATION-v0.3.md) |
| v0.2系列 | [设计系统](DESIGN-SYSTEM.md) · [研究](RESEARCH.md) · [v0.2](VALIDATION-v0.2.md) · [v0.2.1](VALIDATION-v0.2.1.md) |
| 其他历史验收 | [初期](VALIDATION.md) · [v0.3](VALIDATION-v0.3.md) |

历史截图保留用于设计追溯，不代表当前APK界面。个人文件导入/备份仍可用，早期学校“检测→预览→导入”流程已被v0.5直连替代。

# Android test.15 浏览器与触控收尾

2026-11-16，核对最新远端与文档后，继续维护 `feat/community-reading-design-20261116` / 草稿 [PR #74](https://github.com/zthy3375-wq/fish/pull/74)。本轮补齐真实浏览器、触控验证和后续 CI；客户端、后台协议与线上数据未改，已交付 test.15 /165 继续有效。

## 基线与环境

远端 `a797b15c11aaf18c479308a6d02932fa65b7c65b` 与本地 `61df97f` 的 tree 同为 `6938d119af9f382367d9dfe5b6eb16d198bd2c4f`，保留 test.13–15。本地环境禁止 Chromium 所需套接字，因此使用仅运行测试的临时 GitHub 分支 `test/community-test15-review-20261116`，无部署、发布步骤或云端凭据。

实际 Chromium 运行生产构建；社区/私信使用合成账号、PGlite PostgreSQL 与本机 HTTP 路由，仅替换原生桥接。触控使用真实 Vue 组件的离线演示。未向普通用户发送测试内容。安装中文字体供 Linux 截图显示，没有将字体打包进应用。

## 通过结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整社区浏览器 | 209 项，360 /390 /430px | [43892361276](https://github.com/zthy3375-wq/fish/actions/runs/43892361276)，community job `133386679400` 成功 |
| 私信与粉丝浏览器 | 27 项，同上三种宽度 | [43893088820](https://github.com/zthy3375-wq/fish/actions/runs/43893088820)，messages job `133389228833` 成功 |
| 真实组件触控 | 72 项，同上三种宽度 | 同次工作流，touch job `133389229576` 成功 |
| 离线交互录像/截图 | 发帖、详情、大图、评论、回复、点赞、返回与匿名发布完成，无外部请求或页面异常 | 同次 touch artifact 的 PNG、WebM 与 `recording.json` |

重点核对有用 / 欢乐 / 抱抱顺序，欢乐切换/取消与失败回滚，不误进详情；列表关闭平台点击高亮与文本选择，触摸正文无默认聚焦方框，长文自动扩展，键盘导航仍有提示，发布操作区至少 44px。草稿、图片排序、投票、搭子与多层返回均通过。

私信检查包含本人粉丝数字/名单/回关、关注计数、公开主页发私信、服务端已收但响应丢失后的幂等重试、字面文本显示、返回后草稿、第二账号未读/收发、67 条消息的增量/历史分页、500px 高度输入栏/发送按钮、双方屏蔽及旧能力退化。相关截图已检查。

首轮私信检查在屏蔽后的空列表定位失败：脚本使用精确文本匹配，空状态实际还包含说明子元素。改为等待空状态容器，再核对提示与会话数量为 0，全宽度通过。未修改产品权限，收发/分页/屏蔽断言保留。首轮工作流整体仍为失败，其中 community job 的 209 项成功有效。

## 来源与持续检查

- 首轮提交 `2e8bf339f8d5d6dd252a104c54d5016d808c7b18`：完整社区 209 与原有触控 66 项通过。
- 增加焦点/长文/欢乐切换断言、修正空状态定位后，`3c05ae638defb41e078620bffd5d868d3d45cc0f` 的私信/触控工作流完整成功。本地等价测试改动为 `e76333d`。
- community artifact `14237392269`，SHA-256 `f63c748731d93406bcf2dd9131c9bbede1569b4575bd45eb7ff1391de0f42e14`。
- messages artifact `14237797009`，SHA-256 `0026cde8b070e269a9213f238b341c636ba659c1e6f8860a184354d7fe587b7a`。
- touch artifact `14237831900`，SHA-256 `bbedc01471f58d1c038b5c60e0867680caf243f55078714750a49e0787ca0234`。
- 结束后以 `8f01a7c1f59f7dfde72b7d57875c7daccd537b2a` 移除临时测试工作流；分支 tree `c81f7e6c6ea91c3eafff9400cbde6fbe5cf979e2` 与本地 `e76333d` 完全一致。临时入口未进入开发分支。
- 原有 Android browser job 接入私信、离线预览/触控命令与产物，YAML 解析通过。各命令在上述专用工作流实际执行；没有重复触发完整 Android 构建，串行接线待后续常规 CI 执行。

本地重跑先执行 `npm run build`，安装后端依赖与 Playwright Chromium，依次运行 `scripts/treehole-browser-check.mjs`、`scripts/community-messages-browser-check.mjs`，生成预览后运行 `scripts/treehole-preview-check.mjs` 与 `scripts/treehole-touch-check.mjs`。

## 安装包与待验收项

`src/`、Android 原生与 Capacitor 配置相对产品源码 `a71100f` 无变化。原签名 `Hanyuantong-v1.3.0-test.15-Community.apk` 仍为 12,491,982 bytes，SHA-256 `bc6d809eaae4909d130b61978a1741c168c43a945cc82139ee4203bc7a539194`，本轮再次核对一致，未重打或替换。

此前前端 504、共享 78、后端 96、Android Debug/Release 各 193 项与签名/资源证据保留，本轮没有重复执行。schema 10 真实接口与数据清理见 [启用记录](COMMUNITY-ACTIVATION-20261116.md)。

浏览器移动尺寸覆盖布局与交互；实体覆盖安装、系统输入法/相册与实际 WebView 观感仍待实测。iOS 未改；main、正式 1.2.4 /150、蒲公英和正式更新元数据保持。

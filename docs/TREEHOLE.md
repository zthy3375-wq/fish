# 邯院通树洞 · 首轮开发

分支：`feature/treehole-accounts-20261114`。基于正式版 1.2.4。Android 测试版本 1.3.0-test.1 / 151。未合并 main，未改动蒲公英或线上更新配置。

## 本轮范围

独立邯院通账号（登录账号、公开昵称、密码、一次性展示的恢复码），文字帖子、昵称/可选匿名、评论/回复、点赞、收藏、搜索、我的帖子、删除、举报、屏蔽与管理员处理。Android 使用原生加密会话 + Vue 界面，iOS 使用 Keychain + SwiftUI。首页与“我的”增加入口，原四个底部栏目保留。图片、私信、通知、评课不在本轮范围。

## 匿名规则

服务端只投影公开字段，不向其他用户返回账号 ID、登录名或匿名作者昵称。每个账号在不同帖子中获得不同随机代号，同帖匿名发言代号稳定；匿名楼主的回复始终匿名。昵称帖的作者匿名回复时不显示楼主标识。昵称与匿名方式发布后固定。同一用户的不同匿名帖不可通过屏蔽接口关联：匿名内容只能隐藏整个讨论；昵称屏蔽只影响该人的昵称内容。账号设置可恢复全部屏蔽内容。管理员处理举报、锁帖、删帖与禁言，由服务端角色权限控制并记录审计。

## 账号与服务

账号密码使用随机盐 scrypt；数据库保存会话 token 和恢复码的 SHA-256 摘要。Android Keystore / iOS Keychain 保存 token，前端 JS 不接触 token。学校教务账号、姓名与学号不自动成为社区身份，也不传给社区服务。注册默认关闭，可用服务器邀请码开放内测。恢复码重设密码会使原登录失效，修改密码会使其他设备退出。注销会删除作者内容并移除会话；举报处理审计保留去身份账号记录。

后端目录 `cloudbase/functions/community`，独立 HTTP 函数计划路径 `/hyt-community/v1/`，SQL 在 `cloudbase/community-schema.sql`。社区表与现有教务/统计表隔离，客户端数据库角色禁读写。现阶段尚未向腾讯云部署，也没有开放线上注册。当前移动端遇到服务未就绪会显示连接失败，不提供假成功。

## 本地验证

- `npm run check:community`：PGlite 运行实际 PostgreSQL schema 与 RPC，验证多账号权限与匿名投影。
- `npm run check`：既有 Web 单测、共享协议、社区后台、TypeScript 与产物构建。
- `npm run test:treehole`：浏览器界面与实际本地 PostgreSQL 后端联调（仅原生桥接被测试适配器替代）。
- Android `testDebugUnitTest testReleaseUnitTest assembleRelease`：原生会话边界和编译。
- iOS 新增 TreeholeTests；由 PR 上的 macOS CI 编译和执行。

验证结果将随实际完成更新。上线前仍需部署服务、绑定运营管理员账号及真机联网验收。正式推送保持单独授权。

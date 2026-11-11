# 邯院通 Flutter 核心验证版

独立目录、独立测试包，不替换已发布 Android 客户端，不包含发布/更新入口。共享 Dart UI、课表模型和离线状态用于 Android/iOS；官方 WebView 登录和学校会话由各平台原生桥实现。

## 开发

安装 Flutter stable 后：`flutter pub get`、`flutter analyze`、`flutter test`。平台构建：`flutter build apk --debug`；macOS/Xcode 配置后 `flutter build ios --no-codesign`。真实账号验收必须在本人设备完成，合成测试不证明学校登录成功。

## 桥接合同

MethodChannel `org.handancampus.flutter/academic`：login / getTimetable / logout。登录成功返回 session=valid 和不含身份信息的 sessionScope；取消返回 cancelled=true。课表返回 session、sessionScope、modules.timetable.status 和 data；data 必须包含 term{xnm,xqm}、kbList[]、practice[]，可选 periods[]。不向 Dart 传递 Cookie、密码、令牌、认证 HTML。原生必须为新登录生成新 scope，并拒绝旧请求写回新会话。

## 缓存和时间

flutter_secure_storage 保存 active scope 及该 scope 的白名单课表（课程、教师、教室、周次、节次、实践课程、时间表和本机时间校准）。显式切换/退出立即清空显示，序列化删除旧缓存；取消不会恢复旧账号。过期、网络失败、空或不完整返回保留最后成功数据。异步结果受 generation 校验，不跨账号恢复。新学期不沿用旧学期日期。

2026 秋季（xnm=2026,xqm=3）默认首周周一 2026-09-14，其他学期需本机设置。未有官方 periods 时不猜测上课时刻；用户可明确选择此前提供的 13 节/40 分钟时间表。实践课单独展示，不编造星期或节次。

## 核心验收

1. 官方网页本人登录，确认实际课程、教师、教室、单双周/多节与学校一致。
2. 关闭进程后重开，断网仍能查看保存时间和课表。
3. 断网刷新保留缓存；会话过期提示重新认证，不伪装成无课。
4. 切换账号并取消，旧课表不可见；新账号只显示新 scope 数据。
5. 退出后冷启动不显示旧课表；验证系统备份/设备迁移不会恢复已退出账号。
6. Android 和 iOS 分别完成上述检查；未真机通过前不得称为跨平台登录验证完成。

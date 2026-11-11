# Flutter 核心验证版（第一阶段，开发测试专用）

## 隔离范围

基于 `main` 的 `780bbc85c0b70e8d9273129eca666d7141e21e42`（正式版1.2.1 /145）。新分支 `migration/flutter-core-phase1`，工程 `flutter_app/`，未合并 main。

- Android独立包名 `org.handancampus.fluttercore`，名称“邯院通·Flutter验证”，独立测试签名和数据沙箱。可与正式包 `org.handancampus.app` 并装，不能覆盖正式版。
- iOS独立 bundle identifier `org.handancampus.fluttercore`，Swift验证工程，不包含发行证书/描述文件。
- 不连接项目业务服务器、不读写正式版数据，不包含自动更新、蒲公英、腾讯更新接口或TestFlight发布步骤。
- 原项目、签名、版本清单与线上服务保持原状；本分支唯一新增工作流只检查新工程并保存测试产物。

## 已实现的核心路径

Flutter共用首页、今日/周课表、学校设置、解析与缓存状态机。登录使用两端原生官方页面，固定 `https://jwgl.hdc.edu.cn`，密码与验证码仅由使用者在官方页面输入。登录后读取实际学校课表，严格校验学期、周次、单双周、星期、连续多节、教师与教室；实践课独立保留。

查询采用旧项目已验证的Index页面与JSON查询路由；仅带入课表能力，保留编译内置页面读取回退。不查询成绩/考试/学习通/生活服务。

- 只有完整有效响应可替换缓存。网络、登录失效、格式变化、部分行不完整均保留上次课表。
- 明确JSON课表结构中的空数组与未知HTML区分；空返回显示本次未返回课程，仍保留已有非空课表。未识别的页面不会宣称“无课”。
- 本机缓存加密保存，重开直接读取，无需网络；登录有效性不以缓存存在推断。
- 新登录生成不含身份信息的会话scope，缓存隔离。切换/重新登录会先确认清除当前学校离线课表；取消不恢复另一账号。退出/清缓存使用代次保护，取消旧请求写回。
- 日期锚点仅对明确已知的2026秋季使用2026-09-14，其他学期需设置，不猜测。学校未提供节次时间时仍显示节次课表，可选择已知邯院作息；未确认时间不会伪造“下一节课”时刻。

## 安全边界与待验收限制

- Android Keystore AES-GCM保存原生Cookie与scope；iOS Keychain `WhenUnlockedThisDeviceOnly`保存Cookie属性与scope。Flutter仅接收白名单课表和scope，不接收Cookie、密码、令牌或原始HTML。
- Flutter课表使用系统安全存储，不导出账号资料。Android关闭应用备份、HTTP明文与WebView调试/文件访问，登录窗口禁截图。iOS使用非持久WKWebsiteDataStore，无脚本消息桥，默认TLS校验。
- Android公开CookieManager只能读取URL对应的Cookie请求头，恢复沿用原项目的根路径/安全属性策略，并等待每次写入回调后再导航。**不能把这等同于完整Cookie属性备份，真实学校会话重开需要设备验证。**
- AndroidWebView使用期间可能写入平台沙箱Cookie数据；操作结束、退出和下一次启动前清理，持久恢复来源为加密vault。异常进程终止时短暂残留不能保证立即清除；应用备份已禁用。iOS使用真正的非持久WebKit存储。
- Android请求起始地址与页面导航限制学校HTTPS域，但 `shouldInterceptRequest` 不覆盖所有子资源重定向目的地。**不能声称完整拦截全部跨域资源跳转。**学校页面资源跳转仍需实测/后续加固；未禁用TLS或修改系统网络安全。iOS另有WKContentRuleList子资源白名单。
- 验证码不会自动破解、代填或跳过。遇到学校验证展示官方页面，由本人完成后继续。
- 本阶段没有真实学校账号、安卓手机、iPhone或本地macOS，不能宣称真实登录/验证码/长期会话/网络切换或iOS真机已通过。

## 验证命令

在 `flutter_app`：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
# macOS + Xcode
flutter build ios --simulator --debug
# 真机需用户开发者签名和设备，不提供未签名IPA冒充可安装产物。
```

在仓库根目录：`npm ci && node --test flutter_app/test_js/adapter.test.mjs`。

工具版本与最终执行结果见本次交付报告；GitHub `Flutter core verification` 工作流的Android与iOS状态必须分别核实。模拟器产物不是已签名设备IPA，不上传任何分发平台。

## 本人设备验收清单

1. 保留正式App，并装Flutter验证APK；首次打开无任何演示课程。
2. 在官方页面完成登录/密码错误重试/取消/验证码，核对真实当前学期、单双周、多节、教师、教室和实践课。
3. 读取成功后彻底关闭重开，飞行模式离线查看；恢复网络手动刷新。
4. 学校会话过期应提示重新连接但旧课表继续可见；服务异常/未知HTML/部分数据不覆盖成功缓存。
5. 换账号必须先确认清理；新账号不能看到上一账号课表，慢请求不能回填旧数据；退出后重开无旧课表。
6. 撤销网络、Wi-Fi/移动网络切换、读取中返回/关闭/重复点击，以及安全存储失败后的“重试清理”。
7. iOS在macOS完成编译，再用合法开发签名安装设备，重复上述测试，特别检查WKWebView验证码、Cookie恢复及Keychain行为。

## 后续范围

真实账号/两端设备验收完成后再决定下一阶段。当前不迁移其他模块，不合并main，不发布或改动任何现有更新通道。

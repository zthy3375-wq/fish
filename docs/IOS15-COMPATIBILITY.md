# 邯院通原生 iOS 15.4 兼容

以现有原生 Swift/SwiftUI iPhone 功能为基线，最低部署目标从16.0调整为15.4。五个Tab、原生身份会话、个人与学校数据格式均保留；未移植Android test.13–16新增功能或改动安卓界面。

## 兼容实现

统一入口：`ios-native/Hanyuantong/Compatibility/CampusCompatibility.swift`。

| 能力 | iOS 16及以上 | iOS 15.4 |
| --- | --- | --- |
| 导航 | NavigationStack | NavigationView单列模式 |
| 标题和值 | LabeledContent | 原生文本行，支持换行及辅助功能组合 |
| 多行输入 | 垂直TextField | TextEditor，保留原绑定与编辑标识 |
| 头像、帖子、评论及扫码选图 | PHPicker | PHPicker；不要求全相册权限 |
| 系统文字分享 | ShareLink | UIActivityViewController |
| 回复弹层 | 中/大两档 | 标准可关闭sheet，保留忙碌时防误关闭 |
| 底栏显示 | SwiftUI toolbar | UIKit公开容器接口，离开社区时恢复原状态 |
| 适应宽度的分区/回应 | ViewThatFits | 可滚动分区或垂直回应组 |

扫码相册读取仍在临时文件回调有效期内检查大小、读取数据，保留20MB上限与原二维码/设备码校验。资料编辑、备份、教务及学习通详情使用同一组兼容控件；不重写服务接口和存储。

生成器统一App、Widget、单元测试与UI测试的15.4部署目标，并重新生成工程。CI在物理iPhone目标的Release编译后核对App及内嵌Widget的MinimumOSVersion，避免模拟器临时提高部署目标掩盖高版本API。

## 验证

工作流43999923230全部成功：App/Widget的15.4 Release编译和最低版本核验通过，模拟器App/测试编译通过；原生377项通过、1项真机检查跳过、0失败，5项UI流程通过，共享协议78项通过。原生代码及交互验证见[Native VALIDATION](../ios-native/VALIDATION.md)，对应工作流[43999923230](https://github.com/zthy3375-wq/fish/actions/runs/43999923230)。编译与模拟器结果均不替代15.4设备实际安装、选图、输入法、返回导航与学校/支付/出水验收。

此前编译发现并修正了扫码CoreTransferable、导航/底栏显示及社区工具栏条件构建的版本要求。失败记录保留在分支工作流，不将失败运行计为成功。

本轮没有生成可分发IPA、配置签名团队、上架、修改生产服务、合并main或推送用户更新。历史固定源码IPA工作流仍属于旧基线，不用于本分支分发。

## 官方API参考

- [SwiftUI导航迁移](https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types)
- [PHPicker与iOS15有序选择](https://developer.apple.com/videos/play/wwdc2021/10046/)
- [UIKit系统分享](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller)
- [ToolbarContentBuilder](https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder)

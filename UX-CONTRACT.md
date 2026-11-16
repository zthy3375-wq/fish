# 邯院通交互约定

五 Tab 保留，二级页面继续使用 `useNavigation` / `NavigationStack`。社区列表/详情/编辑使用既有 Treehole 流程，草稿、返回位置、匿名与公开身份隔离保留。

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
| --- | --- | --- | --- | --- |
| Select/Listbox | 原生 select，共享令牌 | 现有课程与任务表单 | native | 浏览器课表/表单回归 |
| Date | 原生 date/datetime-local | 北京时间领域函数 | native | 任务及搭子回归 |
| Form | 各领域编辑器与共享 CSS | 领域校验、现有接口 | create/edit | 组件与浏览器测试 |
| Scrollbar | src/product.css | DESIGN.md | 原生窄滚动条 | 浏览器计算样式 |
| Toast | App.vue notify / 社区状态区域 | 原有操作结果 | status/error | 页面操作回归 |
| CRUD | 领域服务与原生桥接 | 服务端授权与幂等请求 | 保留/返回原入口 | 现有端到端测试 |

加载保留上次成功内容；失败显示恢复操作；禁用表示正在执行或权限/条件不足。删除/注销/禁言沿用明确确认和服务端校验。角色字段只控制展示，服务端决定授权。账号切换不复用旧账号结果。恢复码流程本轮保留，身份体系更改需独立设计。

键盘：底栏隐藏仅在文本编辑聚焦且视口明显缩短时触发；缩放不当作键盘。弹层约束视口高度，焦点保持在打开的对话框内并在关闭时返回触发点。安全区域继续由原生 WindowInsets 提供。

前台刷新：隐藏状态不请求，浏览器 focus、visibilitychange 与 Android appStateChange 合并；不同时执行同一轮缓存刷新，不在刷新中发起接水/支付操作。

验证：合成桥接、PGlite 与浏览器不能证明学校账号、物理出水、支付到账或真机输入法通过，须分别记录。

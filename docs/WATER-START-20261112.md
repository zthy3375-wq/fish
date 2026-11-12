# 1.2.2 接水确认后无反馈：修复候选

基于已发布 1.2.2 /146 的 release/android-1.2.2 c06e0cc，独立测试版1.2.3-test.1 /147。未更改正式更新接口、发布清单或蒲公英。

## 已定位

1. PR60 在新启动预检加入 status=5 且 workStatus=1 的要求。status=5 是已存在用水会话的结束判据，现有协议证据不支持把它当作所有新启动必须满足的就绪条件。设备/SKU/付款渠道已重新查询且可用、同步明确 workStatus=1 时，缺少或不同的旧会话 status 会被新增条件拦截，尚未发出 unlock。
2. Vue 确认后立即销毁报价卡片。原生拒绝在没有新会话时只写全局 pgError，显示在钱包顶端；接水区域没有失败或明确的启动状态反馈。旧组件测试模拟了 startWater 函数，没有走真实 composable 的错误处理，因此漏过该问题。

用户尚未提供点击后的实际错误或设备响应，以上是源码中可复现的缺陷；不能据此确认问题手机命中了哪一种返回。

## 修复

- 新启动在最新 details/SKU/渠道核验后，对非空同步返回要求明确 workStatus=1；workStatus=2 仍阻止重复开水，缺失/未知仍保持 WATER_WAIT。不再要求旧会话 status=5。空会话沿用既有合同，网络/认证错误仍中止。
- 使用中/结束确认仍匹配 orderNo/identify 与既有 status/workStatus 条件；不放宽结束、账单或扣费核验。
- 接水区域显示启动等待状态、原生失败原因，并滚动到可见反馈。消费过的报价不会复用；重试先重新查询、再由用户确认。
- 已持久化但结果未知的启动继续阻止第二次 unlock；不自动重发启动、结束、结算或付款。

## 验证

新增测试直接挂载生产 Vue 组件，使用真实 pangguai composable 和模拟原生桥，覆盖预检拒绝、等待反馈、重复点击保护、丢失响应但已持久化启动、准备失败。新测试在原代码3项失败；修复后4项通过。已有16项接水界面测试继续通过。

新增原生回归覆盖就绪workStatus不要求旧订单结束status、归档后仍必须重新确认最新可用设备；既有忙碌/不完整返回/重复命令回归保留。完整前端检查、Android编译与原生测试结果须按本次新CI记录，不引用旧构建冒充新结果。

协议依据为已有来源的固定提交：Mercury000/HUEL-yktwx 1bb98ea5bc87e9a217ce6b8af10c47046aa92c73 的 docs/life-devices-water.md、LifeDeviceModels.kt，以及 Inonvation/JUWPHub edf81286f26673968d4a804b6fd6bf6fc13f35ef 的 QiekjModels.kt / QiekjRepository.kt（会话结束与开水预检分别处理）。独立实现，无上游源码复制；未使用真实账号、设备码或网络控制命令作测试。

仍需问题手机安装测试包，核对首次启动、旧记录后启动、机身实际出水和同订单账单；当前未声称现场已修复。

## 本次构建与测试包交付

本地与Quality检查43222581544通过453项前端测试、TypeScript和生产构建。Android test APK任务43222581539完整成功：Debug/Release原生测试、Debug/Release构建、平行预览包与360/390/430浏览器回归通过。构建合并提交7fe0152e21d68588c2b95cddca906c9c30e818df的树bd9d9dfafdab171dcd7a87aede9737f5c2f51fb3与应用源码8538502050a6f47ff16cd1e7f8e55fb8b9337f20完全一致。

交付Hanyuantong-v1.2.3-test.1-WaterStartFix.apk，12,426,271字节，SHA-256 b68fcc2b0c54bf349bfa9c67fb6f2ab03ef167c8b369fe7e0d33286c8cd27d1b。包名org.handancampus.app、147/1.2.3-test.1、非debug、28个前端资源逐字节、4字节及原生库16KB对齐核验通过。原正式证书4be86ec93e000025f12839aa31da16c55ea3c9a7097917226572d3450dca86d9；v1/v2/v3签名验证通过。测试包按原包名/签名制作供覆盖安装，实际安装、现场接水和同订单扣费仍待本人验收。未合并、未推送或修改线上更新清单。

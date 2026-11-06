# v0.5.0 实际验证记录

2026-11-06。本记录区分实际运行与待验证项。

- npm ci：成功。
- TypeScript / vue-tsc：成功。
- npm run build：成功；原 ExcelJS 大分包提示保留。
- npm test：20 个测试文件，171 项通过，其中包含原有160项。
- npx cap sync android：成功。
- 原生 testDebugUnitTest / testReleaseUnitTest、assembleDebug / assembleRelease：成功；宿主默认 JRE 缺 javac，改为现有 `/workspace/tools/jdk21` 成功。
- 新增格式链路测试：固定原生查询脚本的候选 POST、分页、字段白名单、空考试和会话过期；学校数据通过现有 flatten → ScheduleGrid/CourseCard 模型；同步失败保留数据、切换账号隔离、在途退出保护。
- 测试数据是人工构造，不是学生真实教务响应。
- 本地 Chromium 无法启动，失败原因为宿主禁止 socket()；没有把本地浏览器检查声称通过。GitHub CI 将运行独立浏览器替身测试，实际状态以 Actions 为准。
- 没有连接 Android 真机/模拟器；没有执行 instrumentation、学校账号登录、验证码或受保护接口联调。P0/P1/P2/P3 一律待真机验证。
- 未构建 iOS，未开发 Swift 学校适配；未合并 main、未部署正式站点。

# v0.3.1 源码对比与改造取舍

> 历史记录：本文描述对应版本开发时点；当前功能和最新真机反馈以 [STATUS.md](STATUS.md) 为准。

研究时间：2026-11-06（北京时间）。fish 基线为 `830476ef770aa22acfbf1b04004c6aab7bb01f4e`，已建立 `archive/v0.3` 恢复分支。拾光读取的是当时 main 的实际 Kotlin 源码，未以宣传截图代替源码分析。

| 关注点 | fish v0.3 实际实现 | 拾光实际实现与本次取舍 |
|---|---|---|
| 周视图 | AcademicDetail 按唯一 start 分组，每组一行；CSS 近似固定行高，8px 教室文字 | ScheduleGrid 计算 `startSection/endSection × sectionHeight`，按日期列定位和测量。fish 重写为独立轴映射和区间布局引擎，保留7列及真实起止时间，跨节占高；不用课程开始时间分组。 |
| 点击添加 | 管理弹窗 → 添加 → 全量字段 | WeeklyScheduleScreen 的 onGridCellClicked 根据列、节次创建 PresetCourseData。fish 空白格直接传 day/period/week 给独立编辑页，预填当前作息时间；默认整学期每周，界面明确显示，用户可改为单双周或自定义周。 |
| 课程详情/冲突 | 单个 Course 详情，原表格无法表达重叠 | CourseDetailBottomSheet 从 clusterCourses 构建多课程详情。fish 手机采用重叠区间合并入口和完整列表逐门查看，避免同列并排后每个课程只剩一两个字；引擎同时计算稳定的冲突 lanes，端点相接不算冲突。 |
| 编辑流程 | CourseEditor 一次展开名称、时间、周范围、备注等全部字段 | AddEditCourseScreen 有独立 Scaffold、保存与返回、未保存退出确认，支持多个 schemes。fish 保留一门课程多个 Arrangement 的模型，改为全屏编辑，名称/教师/教室优先，时间与教学周按安排展开，颜色/备注折叠。未实现拖动与拉伸。 |
| 作息数据 | 节次与明确时间都放在安排内，无独立作息 | CourseTable 代表课表元信息；TimeSlot 通过 timeTableId 关联独立 TimeTable，Course 区分标准节次与自定义时间。fish 保留学期作为现有课表容器，新增 TimeTable/TimeSlot 与 semester.timeTableId，并区分 period/custom 模式，不强行迁移为另一个数据库架构。 |
| 导入 | 一个函数按后缀分支，CSV/XLSX/ICS 可用 | 官方适配文档把来源数据规范化为 courses/timeSlots/config。fish 增加可信内置文件适配器接口，统一预览契约；不复制动态注入脚本桥接、不增加学校登录或受保护数据抓取。 |

## 布局规则

每节课为一个坐标单位，坐标在该节起止时间内线性插值；空课间最多压缩为0.35单位。课间若存在真实的独立课程，则使用其实际分钟长度展开，避免午间课程被压成细条。首末节外的自定义课程扩展时间轴，不裁切课程。CSS 使用 rem 作为单位高度，字体缩放时网格一起增大。标题12px、地点11px，不使用8px字体。

一天内按时间排序，求重叠区间的连通组；组内仍保留所有原安排及其精确位置。手机显示该重叠组的范围和数量，点击后列出完整名称、时间、教室、教师，再进入单个详情。该设计刻意优先可读性，不把重叠课程挤进多个极窄列。

## 数据兼容

payload 从1升级到2，IndexedDB数据库名、对象仓库与原Preferences地址不变。迁移只新增作息关联，全部旧安排标为 custom，保留ID、星期、起止时间、周规则、备注和用户偏好；写入v2前另存原v1快照。Web快照与迁移在同一事务写入，已有更新v2时不以旧v1覆盖。备份恢复同时接受v1和v2，未知版本拒绝。原快照可从数据管理导出。

新的 period 安排在规范化数据层解析为作息的真实起止时间，首页、日/周课表、冲突与提醒共用这一份结果。作息另存或切换先预览影响及冲突；旧custom课程不移动。另存为新方案仅关联当前学期，避免误改其他学期。

## 许可证与来源

拾光仓库根 LICENSE 为 Apache-2.0。fish 保持原 MIT 许可证；本次借鉴通用产品流程与布局思想，独立实现 Vue/TypeScript 代码，没有复制或翻译 Kotlin 源码，也没有复制品牌、资源和独有图形。

阅读的源码（路径相对 shared/src/commonMain/kotlin/com/xingheyuzhuan/shiguangschedule/）：
- ui/schedule/WeeklyScheduleScreen.kt
- ui/schedule/components/ScheduleGrid.kt
- ui/schedule/components/CourseBlock.kt
- ui/schedule/components/CourseDetailBottomSheet.kt
- ui/settings/course/AddEditCourseScreen.kt
- data/db/main/CourseTable.kt、TimeSlot.kt、Course.kt

仓库：https://github.com/ShiGuangSchedule/shiguangschedule

官方文档：
- https://sgschedule.jursin.top/guide/user/add-table
- https://sgschedule.jursin.top/guide/developer/school-adaptation

# v0.2 · Calm 设计系统

参考用户提供的两张校园应用截图，提取浅灰底、低饱和蓝灰、细描边、紧凑信息、四宫格与分组列表、悬浮导航和抽屉的通用原则。没有复制其品牌、字体、插画和专有功能。本项目使用系统字体与 Lucide 线性图标；不假装实现未开发的导入与校内服务。

## 统一规则

所有语义变量集中在 `src/tokens.css`。各组件不自行定义独立品牌色。

| 类别 | 规则 |
|---|---|
| Color | 背景 #F7F8FB，表面 #FDFDFF，主文字 #283445，正文辅助 #6D7889，主色 #4F6F94，描边 #DCE1E9；辅助文字 #6B788A，保证浅色表面的可读性 |
| Typography | 系统中文 / 平台字体；页面 23px、节标题 15–16px、正文 13–14px、辅助 10–12px、数值 19–23px；数据使用 tabular-nums |
| Spacing | 4/8/12/16/20/24/32px；手机边距 20px，360px 以下边距 16px |
| Radius | 小控件 10px、课程卡 16px、分组与概览 22px、导航为胶囊 |
| Shadows | 内容卡片 0 2px 7px / 1.5% 透明度；仅悬浮导航与浮层使用清楚但轻量的层级阴影 |
| Icon | Lucide，常规 21–23px，细节 13–17px；1.65 线宽，选中态 1.9 |
| Motion | 120/200/300ms；平移与 opacity；导航滑块使用缓出弹性曲线；无大面积实时模糊 |
| States | hover 为轻背景；触摸缩放 0.98；禁用 35% 不透明；focus-visible 3px 清晰焦点圈；课程状态同时使用文字与色彩 |
| Dark Mode | 语义 token 全量替换；系统主题实时监听；保留 v1 偏好存储键与既有个人数据 |
| Safe Area | env(safe-area-inset-*)；主内容预留 112px + bottom inset；浮层使用 dvh；输入框 16px，软键盘弹出隐藏导航 |
| Responsive | 移动优先；<374px 缩减辅助信息，>=768px 限制内容宽 680px；不改回桌面宣传页 |

## 页面与组件

- AppHeader：日期/学期、教学周、数据来源、通知与返回。
- FloatingNavigation：三个模块，transform 滑块；没有 blur。每项触摸区至少 53px 高。
- AcademicSummary / QuickAction：概览四项和四宫格，数据来自现有 mock provider。
- CourseCard：统一时间、教室、教师、状态；已结束 / 正在上课 / 下一节均有文字标记。
- ServiceGroup / SettingsRow / SectionHeader：统一分组和分割线，无重复嵌套容器。
- EmptyState / LoadingState：空、加载和错误独立呈现。
- AcademicDetail：保留成绩筛选、搜索、课表单双周和详情等能力，加入紧凑周视图和教学周选择。

## 交互与边界

主页使用北京时间，实际日期与时间驱动当前课程与下一次课程。演示学期仍为 2026-09-07 起 18 周，所有教务均明确为模拟。超出学期不无限重复旧课程。近期安排不编造官方通知，显示“未同步 · 前往官方入口”。

Hash + History 维护模块、子页面和浮层；浏览器后退优先退出详情/抽屉。Android 通过 Capacitor App backButton 绑定相同返回逻辑；根页面才退出。iOS 是否触发原生边缘返回仍须真机验证，不以网页 history 代替实测结论。

浮层可 Escape 关闭、约束焦点、恢复来源焦点、背景 inert；只使用内层滚动，不占用页面横向手势。周视图无左右滑动捕获，避免与系统手势冲突。支持 prefers-reduced-motion，60 FPS 是设计目标，没有声称实测达标。

---
version: alpha
name: 邯院通
description: 面向邯院学生的日常工具；白色阅读面、淡紫分组背景、小金鱼校园横幅。
colors:
  primary: '#6843b5'
  primary-strong: '#50318e'
  background: '#f7f6fa'
  surface: '#ffffff'
  text: '#262233'
  muted: '#696477'
  faint: '#736d80'
  tint: '#eee8f8'
  highlight: '#f4f0fa'
  border: '#e3dfeb'
  divider: '#eeebf3'
  danger: '#a73e4a'
  success: '#547a70'
  course-blue: '#55769b'
  course-blue-bg: '#edf2f9'
  course-purple: '#7e739a'
  course-purple-bg: '#f1eef6'
  course-orange: '#9a7b58'
  course-orange-bg: '#f7f1e9'
  course-green: '#628b7e'
  course-green-bg: '#edf4f1'
typography:
  sans:
    fontFamily: -apple-system, BlinkMacSystemFont, Roboto, 'Noto Sans CJK SC', 'Microsoft YaHei', sans-serif
  brand:
    fontFamily: '''Noto Serif SC'', ''Songti SC'', SimSun, serif'
    fontSize: 37px
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: 1px
  headline:
    fontSize: 24px
    fontWeight: 700
    letterSpacing: -.02em
  title:
    fontSize: 16px
    fontWeight: 650
    lineHeight: 1.5
  body:
    fontSize: 14px
    lineHeight: 1.8
  editor:
    fontSize: 17px
    lineHeight: 1.8
  label:
    fontSize: 12px
  navigation:
    fontSize: 11px
    fontWeight: 500
rounded:
  xs: 4px
  control: 8px
  sm: 10px
  navigation: 12px
  md: 16px
  avatar: 18px
  lg: 20px
  community-sheet: 22px
  pill: 999px
spacing:
  unit: 4px
  sm: 8px
  md: 12px
  content: 16px
  page: 20px
  lg: 24px
  xl: 32px
components:
  button-primary:
    backgroundColor: '{colors.primary}'
    textColor: '{colors.surface}'
    rounded: '{rounded.sm}'
    padding: 12px 20px
  button-secondary:
    backgroundColor: '{colors.tint}'
    textColor: '{colors.primary}'
    rounded: '{rounded.sm}'
    padding: 12px 20px
  card:
    rounded: '{rounded.md}'
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
  sheet:
    rounded: '{rounded.lg}'
    backgroundColor: '{colors.surface}'
  topic-chip:
    backgroundColor: '{colors.background}'
    textColor: '{colors.muted}'
    rounded: '{rounded.avatar}'
    padding: 0 12px
  topic-chip-selected:
    backgroundColor: '{colors.tint}'
    textColor: '{colors.primary}'
  navigation:
    backgroundColor: '{colors.surface}'
    textColor: '{colors.muted}'
    padding: 4px 8px
---

# Design System: 邯院通

## Overview

**Creative North Star: "安静的校园工具"**

中文校园工具，面向 Android 上频繁、短时、单手的查课、学习任务、生活服务与社区阅读。延续现有浅紫与白色品牌：白色承担阅读，淡紫承担分组和选中状态，小金鱼与校园横幅承担主要品牌表达。业务页面保持安静，层级来自正文、辅助文字、间距和细分隔。

参考 Apple HIG 的层级、可读性、安全区域与直接操作，保留 Android 返回和系统控件。运行时令牌以 `src/tokens.css` 为准；`src/product.css` 在既有布局样式之后加载，共享语义值而保留领域布局。首页局部布局由其后加载的 `src/home-dashboard.css` 持有，校园横幅与生活服务分别由 `src/campus-home.css` 和 `src/components/LifeServices.vue` 持有。社区沿用相同语义令牌，编辑与阅读仍有局部排版。此记录来自当前代码及 Chromium 合成截图；2026-11-17 首页改版已获独立浏览器与源码审查 ship，详细范围见 `docs/home-redesign/DESIGN-RECORD.md`。未有获批视觉稿或原生截图，尚无本轮真机验收。

**Key Characteristics:**
- 白色阅读面与淡紫选中面。
- 系统中文无衬线处理业务，宋体保留给横幅品牌。
- 五 Tab 与既有二级页面结构稳定。
- 静态分组平面化，浮层使用柔和深度。

## Colors

低饱和紫色组织操作与状态，白色和浅紫灰组织阅读；前置令牌记录浅色默认值，深色覆盖仍由运行时代码持有。

### Primary

- **校园紫** `primary`：主要按钮、可操作入口、焦点和选中状态。
- **深校园紫** `primary-strong`：选中导航文字、倒计时等需要更明确色重的位置。
- **淡紫选中面** `tint`：次级按钮、选中指示器和状态底色。
- **浅紫阅读强调面** `highlight`：行悬停和局部内容强调。

### Secondary

- **课程蓝／紫／暖棕／绿** `course-*` 与对应 `*-bg`：课程区分与紧凑课表底色，沿用现有领域映射。
- **危险红** `danger`、**完成绿** `success`：危险和成功反馈；与文字语义配合使用。

### Neutral

- **浅紫灰底** `background` 与 **白色阅读面** `surface`：页面背景及内容面。
- **深紫灰正文** `text`、**辅助紫灰** `muted`、**次级紫灰** `faint`：正文、说明与低优先级信息。
- **轮廓灰紫** `border` 与 **细分隔灰紫** `divider`：容器边界和内容分隔。

**The Shared Palette Rule.** 首页和社区使用同一组语义颜色；局部排版不建立第二套主题。

辅助文字在浅色面上以 4.5:1 为可读性目标；禁用状态单独表达。原有深色主题保留，其颜色随 `data-theme` 覆盖，不能把浅色值写死到新业务组件。

## Typography

**Display Font:** 现有宋体回退栈，仅用于校园横幅品牌。
**Body Font:** 系统无衬线回退栈；Android 优先使用系统可用字形。

**Character:** 业务内容清楚、紧凑，字重用于区分操作和阅读层级。横幅宋体保留校园气质，不承担表单或社区正文。

### Hierarchy

- **品牌**：使用 `brand`；窄屏横幅缩至（33px），口号使用宋体（15px），窄屏为（13px）。
- **页面标题**：应用页头使用 `headline`；课表页头为（21px），社区页头为（19px / 650）。基础 `font-page` 仍为（23px），并非所有页头的最终字号。
- **分组标题**：使用 `title`；资料页分组提示为辅助色（13px），避免与页面标题竞争。
- **正文**：默认使用 `body`；社区编辑正文使用 `editor`，标题输入为（21px / 650 / 1.5）。社区阅读区域继续由原有组件拥有字号与行高。
- **辅助信息**：以（12–13px）为主，底栏与部分元信息仍使用（11px）；课表紧凑网格保留原有较小字号，不扩大为通用正文规则。
- **输入**：通用弹层输入使用（16px）；边框式社区表单为（15px）；搜索和原生筛选可保留局部紧凑规格。

**The Brand Type Rule.** 宋体只承担横幅品牌；业务标题、正文、输入和操作沿用系统无衬线。

长标题允许换行，正文不以固定高度裁切；计数、时间和统计数字按需使用 tabular-nums。

## Layout

五 Tab 顺序为：首页／课表／社区／待办／我的；保留既有二级页、返回位置和领域内容顺序。应用与社区内容上限为（680px）。常规页头边距为（20px），在宽度不超过（374px）时缩为（16px）；首页主内容始终使用（16px），社区正文为（18px），课表有独立紧凑边距。

采用现有 4px 基础节奏，复用前置间距级。常规卡片内边距以（16px）为主，按列表或表单内容允许局部调整；首页主内容顶部留白为（14px），业务组间距为（20px）。首页依次为校园横幅、课程速览、校园生活、今日计划；原有按需统计提示仍保留。横幅基础高度为（224px），另加顶部安全区域。课程与学习入口共用一个内容面，时刻与课程名称／地点并排，完整时间线默认折叠；课程节次高度仍由原有领域布局计算。这些为首页局部构成，不新增全局间距或尺寸令牌。

底栏五等分，入口最小高度（52px），上方细分隔线；底部留出系统安全区域。安全区域从原生 WindowInsets，经 `--native-safe-top`／`--native-safe-bottom` 与环境回退提供。输入键盘开启时沿用现有底栏隐藏逻辑。浮层约束视口高度并允许滚动；（768px）及以上通用弹层四角圆润，较窄视口保留底部弹层形态。

## Elevation & Depth

静态卡片不带阴影，利用色面和细边界分组。浮层、菜单、社区发布浮钮和反馈消息使用柔和阴影；局部回复栏与消息可使用透明白色及模糊。底部导航由顶部分隔线与页面区分，当前产品覆盖层取消其浮动投影。

### Shadow Vocabulary

- **静态卡片**（`none`）：`shadow-card`。
- **浮层／提示**（`0 7px 22px rgba(33,48,70,.14), 0 1px 3px rgba(33,48,70,.08)`）：`shadow-float`；深色运行时另有覆盖。
- **通用底部弹层**（`0 -8px 32px #26223312`）：轻柔上向分离。
- **社区对话框**（`0 -4px 32px #12121a0d`）与 **回复弹层**（`0 -8px 50px #20202a0d`）：现有局部浮层规格。

**The Quiet Surface Rule.** 静态分组依靠色面和细边界；浮层深度不扩散为每张卡片的装饰。

## Shapes

主按钮与共享搜索使用 `sm`，共享卡片为 `md`，通用弹层为 `lg`。首页课程、生活服务与今日计划组使用（16px）外圆角；生活服务内部操作行圆角为（0），由外组统一裁切。其他既有服务分组保留 `lg`；头像和局部小控件使用前置圆角级。社区弹层保留 `community-sheet` 顶角，横向小标签、发布浮钮与开关可使用胶囊或圆形。底栏选中指示器与按钮使用 `navigation` 圆角。边框通常为一条细线；不将所有容器改成胶囊。

## Components

### Buttons

主要操作用紫底与浅色文字，次级操作用淡紫底与紫字；共享按钮内边距见前置令牌，字重（600），最小高度（44px）。社区发布浮钮最小高度（48px），编辑页发布操作保留较小可见胶囊与完整触控高度。图标保持紧凑图形，实际命中区域至少（44 × 44px）。按下沿用轻微缩放或背景反馈；禁用保留业务状态与真实原因。

共享反馈时长为 fast（120ms）、normal（200ms）、slow（300ms）；共享缓动为现有 standard／spring 曲线。社区前进（200ms）、返回（180ms）、弹层（220ms）保留局部时长。reduced-motion 停用相关过渡与动画，不能把局部返回时长写成全局令牌。

### Chips

社区话题筛选以背景色承载未选中，选中用淡紫与紫字，并提供 `aria-pressed`。现有话题胶囊为（36px）高，属于现状中的触控待核项；新增交互仍遵守（44px）触控目标，不以这一局部值作为通用规范。

### Cards / Containers

共享卡片使用白色阅读面、细边界和 `md` 圆角，无静态投影。首页生活服务采用同一白色内容面与行分隔，具体规格见下文；其他服务和设置分组沿用既有较大圆角与行分隔。社区帖子保留作者、正文、图片、互动的阅读顺序，不强加统一装饰容器。

### Home Course Overview / Life Services

课程速览以淡紫底承载当前课程或下一节课，左侧为开始／结束时刻，右侧为可换行的课程、地点与教师；时间使用等宽数字。课程整块可进入详情，跨日课程保留日期。今日课程使用原生按钮控制展开，默认收起，通过 `aria-expanded` 与 `aria-controls` 关联内容；点击、Enter 或 Space 均可操作，展开后保留原时间线的动态进度和课程详情入口。展开与查看课表入口至少（44px）高；学习通与成绩在同组底部双列排列，入口至少（48px）高。无课程时按真实连接与缓存状态展示连接学校或课表路径。

生活服务的趣智校园、胖乖生活各占完整操作行，最小高度为（72px），图标、用途、账户／余额状态与行尾箭头同时呈现；金额为次级信息，保留“上次查询”和登录失效提示。取快递与校园平面图在同组底部双列排列，最小高度为（64px）。组内行圆角为（0），外组为（16px），以细分隔连接，不叠加静态投影。窄屏说明可换行。旧 `src/interface.css` 的首页服务（92px）高度与隐藏箭头覆盖已去除；组件自身持有行高、圆角和箭头。这些规则限定本轮首页及其复用生活服务视图，其他页面保持各自布局。

### Inputs / Fields

通用表单使用浅色底、细边框与 `sm` 圆角；输入随内容与错误提示增高。占位文字与说明使用 `muted`。共享键盘焦点为（2px）紫色轮廓，偏移（3px）；社区按钮按键盘导航状态展示焦点。编辑页标题和正文沿用无边框写作面、清晰光标与占位文字，局部移除轮廓属于现存实现，后续需单独验证键盘可用性，不能推广为通用输入默认。

### Navigation

底栏保留五入口与中文标签；未选中为辅助色，选中为深紫并提高字重，淡紫指示器跟随当前位置。社区粘性顶栏和二级导航保持原有层级；正文滚动与浮动操作避让底栏、回复栏和安全区域。

### Campus Banner / Little Goldfish

保留现有校园横幅、小金鱼和宋体品牌；业务区不复制整块横幅装饰。鱼的移动、摆动与旗帜动画沿用现有开关与暂停状态，低动态偏好下停止动画。通知和动画开关保留（44 × 44px）命中区域。

## Do's and Don'ts

### Do:

- Do 保留首页、课表、社区、待办、我的五 Tab、小金鱼、现有校园横幅和主题选择。
- Do 从运行时语义令牌取色，依内容层级选择正文、辅助文字和边界。
- Do 将主操作与图标实际触控区域做到至少 44px；允许文字、错误信息和表单随内容增高。
- Do 让长标题换行、数字按需等宽，并尊重安全区域与 reduced-motion。
- Do 保留真实加载、错误、空状态和恢复入口；截图使用合成数据时明确标注为测试。

### Don't:

- Don't 将所有卡片、按钮、分组统一改成胶囊，或用装饰卡片替代功能层级。
- Don't 将横幅品牌宋体扩散到业务正文，或为系统字体另行下载字体包。
- Don't 隐藏失败、用演示数据填充线上空状态，或改变接口、权限、存储键和数据格式。
- Don't 因记录设计而更改课表节次几何、草稿、返回位置或匿名与公开身份隔离。
- Don't 将现有小触控区域、特殊焦点覆盖或局部硬编码颜色推广为新页面默认值。

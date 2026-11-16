---
version: alpha
name: 邯院通
description: 面向邯院学生的日常工具；白色阅读面、淡紫分组背景、小金鱼校园横幅。
colors:
  primary: '#6843B5'
  background: '#F7F6FA'
  surface: '#FFFFFF'
  text: '#262233'
  muted: '#696477'
  tint: '#EEE8F8'
  danger: '#A73E4A'
typography:
  sans:
    fontFamily: "-apple-system, BlinkMacSystemFont, Roboto, 'Noto Sans CJK SC', 'Microsoft YaHei', sans-serif"
  brand:
    fontFamily: "'Noto Serif SC', 'Songti SC', SimSun, serif"
rounded:
  sm: '10px'
  md: '16px'
  lg: '20px'
spacing:
  unit: '4px'
  page: '20px'
  content-max: '680px'
components:
  button: {height: '44px'}
  card: {rounded: '16px'}
  sheet: {rounded: '20px'}
---
# 邯院通设计规范

## Overview
中文校园工具，Android 单手操作，早八路上查课与宿舍接水。使用 Operate 模式：内容和状态优先。小金鱼与现有校园横幅是唯一大面积品牌表达，业务页面保持安静。参考 Apple HIG 的层级、可读性、安全区域与直接操作，保留 Android 返回和系统控件。

运行时唯一令牌来源为 `src/tokens.css`；本文件记录其意图和关键值。`campus-home.css` 不再重定义主题。社区使用同一语义令牌，只保留局部排版。

## Colors
白色内容、淡紫中性分组背景，紫色用于可操作入口与选中状态；危险操作使用 danger。原有深色选项保留兼容，不移除用户设置。辅助文字在浅色面上保持 4.5:1 目标；禁用状态另行表达。

## Typography
中文无衬线用于业务内容，原有宋体仅用于横幅品牌。正文 14–17px、辅助信息 12–13px；课表紧凑网格允许更小字号。输入框 16px，数字使用 tabular-nums。长标题换行，正文不可用固定高度裁切详情。

## Layout
保留五 Tab：首页／课表／社区／待办／我的；任何功能不并入其他 Tab。原有二级页和返回位置保持。页面边距 20px，窄屏 16px，内容上限 680px；卡片内部 16px、组内 8px、组间 20px。课程网格保留原有节次高度计算。

## Elevation & Depth
静态分组使用一条细边界，无重复投影。浮层和菜单才使用有偏移的柔和阴影。底部导航以顶部分隔线与页面分开，避让系统手势区域。

## Shapes
卡片 16px，主要按钮 10px，底部弹层 20px。小标签可用胶囊；避免将所有容器变成胶囊。

## Components
表单、加载、错误、空状态保留真实数据语义。主操作至少 44px 高；图标触控区域 44px。按下反馈 120ms，页面切换 180ms，尊重 reduced-motion。不为动画移动输入框、课表或正在阅读的内容。

## Do's and Don'ts
保留小金鱼、全部接口、权限、存储键和数据格式。系统字体不额外下载。不要用统一装饰卡片替代功能层级，不隐藏失败、不用演示数据填充线上空状态。所有截图中的合成数据须明确标注为测试。

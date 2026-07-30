# 任务模块视觉重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 按 `D:/birdphoto/任务` 设计稿重做任务模块全部页面，同时保留需求约束、演示数据和后端接口边界。

**Architecture:** 保留 `TaskExperienceController` 和领域模型，重构共享视觉组件并让各页面通过组合实现。水墨素材集中由背景和场景组件管理；页面只负责信息结构和状态映射。

**Tech Stack:** Flutter、Material 3、现有 PNG 资产、Widget tests、Android bird flavor。

---

### Task 1: 锁定视觉和导航契约

**Files:**
- Modify: `test/bird_companion/tasks/task_visual_structure_test.dart`
- Modify: `test/bird_companion/tasks/task_navigation_test.dart`

- [x] 添加水墨背景、关键页面结构、直接进入任务详情以及无临时过渡页的失败测试。
- [x] 运行测试确认因当前结构不符合而失败。

### Task 2: 重建共享任务视觉组件

**Files:**
- Modify: `lib/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart`
- Modify: `lib/bird_companion/features/tasks/presentation/widgets/task_design_components.dart`
- Modify: `lib/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart`
- Create: `lib/bird_companion/features/tasks/presentation/widgets/task_scene_art.dart`

- [x] 建立背景预设、页头、卡片、按钮、状态、指标行、场景主视觉和统一间距。
- [x] 运行共享组件测试并修正窄屏和大字号布局。

### Task 3: 重做任务首页

**Files:**
- Modify: `lib/bird_companion/features/tasks/presentation/pages/task_home_page.dart`
- Test: `test/bird_companion/tasks/task_visual_structure_test.dart`

- [x] 按设计稿重建标题、当前任务、四宫格、筛选和列表。
- [x] 保留导入/索引、AI 分析、复制、同步和断线语义。

### Task 4: 重做 SD 卡四状态

**Files:**
- Modify: `lib/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart`
- Test: `test/bird_companion/tasks/task_navigation_test.dart`

- [x] 按四张设计稿重建场景、信息卡、检查清单和恢复操作。
- [x] 已检测状态直接开始导入并进入任务详情。

### Task 5: 重做复制流程

**Files:**
- Modify: `lib/bird_companion/features/tasks/presentation/pages/copy_content_page.dart`
- Modify: `lib/bird_companion/features/tasks/presentation/pages/copy_confirmation_page.dart`
- Test: `test/bird_companion/tasks/task_navigation_test.dart`

- [x] 精确实现范围、目标、容量、XMP、摘要、安全提示和开始复制状态。
- [x] 保留容量不足、目标离线和返回修改的交互边界。

### Task 6: 重做详情和结果

**Files:**
- Modify: `lib/bird_companion/features/tasks/presentation/pages/task_detail_page.dart`
- Modify: `lib/bird_companion/features/tasks/presentation/pages/task_result_page.dart`
- Test: `test/bird_companion/tasks/task_visual_structure_test.dart`

- [x] 实现设计稿中的主卡、阶段时间线、详情行、操作区和结果指标。
- [x] 派生暂停、失败、断线、取消和部分成功视觉。

### Task 7: 收紧任务流程

**Files:**
- Modify: `lib/bird_companion/app/bird_demo_shell.dart`
- Delete: `lib/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart`
- Modify: `test/bird_companion/tasks/task_navigation_test.dart`

- [x] 删除独立批次命名页和演示审阅页入口。
- [x] 分析完成后进入相册，复制和结果返回路径保持可预测。

### Task 8: 验证和截图

**Files:**
- Modify: `docs/YUYUYU_WORK_PROGRESS.md`

- [x] 运行 `dart format`、任务测试和相关静态分析。
- [x] 构建 bird debug APK，在模拟器逐页截图并与 9 张设计稿对比。
- [x] 修正溢出、遮挡、文字层级、背景位置和触控尺寸。


---

## Completion Notes

- 任务模块视觉重做已按 `D:/birdphoto/任务` 参考稿完成一轮实现。
- 独立批次命名页和演示审阅页已从主任务流移除。
- 任务首页、SD 卡状态、复制流程、详情页和完成页均已保存最终截图到 `docs/task-ui-screenshots/`。
- 最新任务模块结构测试、导航测试和静态分析均通过。

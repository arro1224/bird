# B11：任务设计收口与生产可达性

日期：2026-08-10  
前置批次：B10 分页、缓存、性能与筛选体验  
范围：任务设计稿 01–16、任务首页入口、SD 卡流程、复制确认、任务详情、任务结果与同步结果

## 1. 交付结论

- 任务首页和右上角“+”操作单现在共用同一份能力解析结果，始终展示导入/索引、AI 分析、复制、同步四个入口。
- 不可执行入口不再直接消失，而是禁用并说明原因，包括断开连接、权威状态读取中、未取得存储卡扫描、扫描中、无可用批次、空批次、同批次任务冲突和无待同步修改。
- 无当前任务卡片按连接中、重连中、断开、读取失败和确无运行任务分别展示真实状态。
- 任务详情的演示完成能力改为显式选择：生产默认关闭，只有 `BirdDemoShell` 明确开启；生产缺少日志回调时不再输出演示占位提示。
- 批次建立页只有在注入真实 `onStartImport` 回调时才能提交，不再以 SnackBar 假装任务已创建。
- 外部接口新增 0 个，修改 0 个；B11 只新增 App 内部展示模型和能力解释，不改变 birdbox-v1 请求或响应。

## 2. 任务首页能力模型

`TaskHomeCapabilityResolver.resolveCapabilities` 以既有冻结读取结果为唯一依据：

- 盒子连接状态与权威状态是否就绪；
- `DeviceStatus`；
- 当前项目 `BatchSummary`；
- 当前存储卡扫描 `CardScanResult`；
- 盒子任务列表及 `available_actions`；
- 当前设备命名空间下是否存在本地待同步操作。

每个入口返回 `type`、`enabled`、`description` 和 `disabledReason`。原有 `resolve` 保留并从同一列表筛选可执行类型，因此现有调用方和测试替身无需改变接口。

## 3. 设计稿 01–16 生产映射结论

| 设计稿 | 生产实现 | B11 结论 |
| --- | --- | --- |
| 01 可执行操作面板 | `task_home_page.dart`、`task_home_capability_resolver.dart` | 已收口；首页与操作单同源，四入口可见，不可用时说明原因 |
| 02 SD 卡已识别 | `sd_card_flow_page.dart` | 已实现；显示扫描信息并进入真实批次建立流程 |
| 03 SD 卡未识别 | `sd_card_flow_page.dart` | 已实现；提供重新扫描和设备详情入口 |
| 04 SD 卡读取失败 | `sd_card_flow_page.dart` | 已实现；显示权威错误信息并允许重试 |
| 05 SD 卡为空 | `sd_card_flow_page.dart` | 已实现；空卡状态不会进入批次创建 |
| 06 导入任务运行中 | `task_detail_page.dart`、`job_status_view_adapter.dart` | 已实现；进度、阶段、当前文件及动作来自盒子任务快照 |
| 07 AI 任务暂停 | `task_detail_page.dart`、`repository_task_experience_controller.dart` | 已实现；只按 `available_actions` 显示恢复、取消等操作 |
| 08 复制内容 | `copy_content_page.dart`、生产复制流程 | 已实现；范围、目标盘和空间来自真实 Repository |
| 09 复制确认 | `copy_confirmation_cubit.dart`、`copy_confirmation_page.dart` | 已实现；提交前重新估算，校验目标在线/容量，并携带版本和幂等键 |
| 10 复制任务失败 | `task_detail_page.dart`、`production_task_result_page.dart` | 已实现；失败详情和恢复动作基于盒子任务/报告 |
| 11 同步完成 | `task_sync_result_sheet.dart`、`BirdSyncService` | 有意偏离；冻结 API 没有同步任务实体，继续采用 App 本地同步结果单，不伪造持久盒子任务 |
| 12 任务断线 | `task_detail_page.dart` | 已实现；保留最后快照，写操作可见但禁用，并提示重连刷新 |
| 13 正在重连 | `task_detail_page.dart`、生产控制器 | 已实现；重连后重新读取权威快照，旧会话结果不会覆盖新连接 |
| 14 取消任务对话框 | `task_detail_page.dart` | 已实现；二次确认后调用真实控制接口，并以返回/刷新快照为准 |
| 15 复制成功结果 | `production_task_result_page.dart` | 已实现；生产路由使用真实任务 ID 和真实报告数据 |
| 16 复制报告 | `production_task_result_page.dart`、`JobReport` | 已实现；只显示冻结报告字段；XMP 数量缺失时显示“盒子未提供权威数量” |

## 4. 有意偏离与数据真实性

- 设计稿 11 的“同步任务完成”不落为盒子任务，因为 birdbox-v1 没有对应创建、查询或报告接口。UI 使用 `BirdSyncService` 的即时本地结果展示同步成功、失败、冲突和剩余数量。
- 设计稿 16 展示了 XMP 数量，但冻结 `JobReport` 不保证提供该字段。生产页面不以复制照片数推导 XMP 数量，缺失时明确标记盒子未提供。
- 设计稿中的固定设备名、批次名、照片数量、进度、速度和任务 ID 均只作为视觉参考，不进入生产数据源。
- 导出日志是独立诊断能力；它不会被伪装为 `available_actions` 中不存在的任务控制动作。

## 5. B11 修改文件

- `lib/bird_companion/features/tasks/domain/task_experience.dart`
- `lib/bird_companion/features/tasks/domain/task_home_capability_resolver.dart`
- `lib/bird_companion/features/tasks/presentation/task_experience_controller.dart`
- `lib/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart`
- `lib/bird_companion/features/tasks/presentation/pages/task_home_page.dart`
- `lib/bird_companion/features/tasks/presentation/pages/task_detail_page.dart`
- `lib/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart`
- `lib/bird_companion/app/bird_demo_shell.dart`
- `test/bird_companion/features/tasks/production_task_b11_design_closure_test.dart`

## 6. 自动化门禁

B11 专项覆盖：

- 断连、无批次、扫描中、同批次任务冲突和待同步状态的入口解释；
- 360dp 宽度、1.5 倍字体下首页与“+”操作单均保留四入口且无布局异常；
- 生产路由保留真实导入、任务控制、日志与结果回调；
- 生产页面不存在“已进入流程”或“任务已准备”等成功占位；
- 任务详情默认不允许演示完成；
- 复制结果缺失 XMP 权威数量时不伪造数值。

最终验证结果：

- B11 专项测试：3/3 通过；
- 任务模块目录回归：138/138 通过；
- 相册目录回归：40/40 通过；
- birdbox-v1 契约测试：4/4 通过；
- OpenAPI、引用、Schema 与 fixture 校验通过；
- B11 相关 Dart 静态分析：`No issues found`；
- `docs/contracts/birdbox-v1.openapi.yaml` SHA-256 仍为 `44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f`。

## 7. B12 建议

B12 应作为发布与真机验收批次，不再扩展功能面：

- 在真实盒子和真实 SD 卡上验证设计稿 02–05 的插拔、损坏卡、空卡与重扫；
- 在断网、重连、409/422、目标盘离线和容量不足情况下验证权威状态收敛；
- 在 360/426dp、1.3/1.5 倍字体及中英文长文件名下完成视觉走查；
- 使用 3,672–10,000 张真实照片验收 B9/B10 搜索筛选首反馈、总耗时、内存峰值和取消手感；
- 发布前再次执行任务、相册、同步与冻结契约全量门禁。

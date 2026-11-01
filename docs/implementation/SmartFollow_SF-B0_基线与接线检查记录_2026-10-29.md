# SmartFollow SF-B0：基线与接线检查记录

日期：2026-10-29（Asia/Shanghai）。对应[实施计划 SF-B0](D:/Androidstudio2/project/4/docs/implementation/SmartFollow_剩余App任务与实施批次_2026-10-29.md:57)。

本批目标是建立接手基线、明确可复用接口与后续接线缺口；不实施 E1～E4/C1/M1～M3，不修改业务源码，不开发后端。

## 1. 源码与工具基线

| 项目 | 本轮实际结果 |
| --- | --- |
| 分支 | `thirdtime` |
| HEAD | `c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8` |
| 开始时工作区 | 无已跟踪文件改动；仅上一轮新增的剩余任务计划文档未跟踪 |
| App 版本 | `1.14.11+176`（未改） |
| Flutter | `3.44.5 stable`；framework `f94f4fc76b` |
| Dart | `3.12.2 stable` |
| SDK | `D:/flutter344/flutter`，与项目已有 package_config/local.properties 一致 |
| 业务范围 | 复用甲部分和 E0；本人剩余 E1～E4、C1、M1～M3 |

普通 `flutter.bat` 首次在受限环境下停留于 SDK 缓存锁，直接调用已缓存工具后明确报出 SDK `bin/cache/lockfile` 写权限不足。已终止这两次启动诊断，经工具授权后使用同一 SDK 的 Dart 和 Flutter tool snapshot 正常运行检查。没有修改 SDK 启动脚本、项目 JDK 路径或依赖版本，没有执行升级或 pub get；启动诊断不计为业务测试失败。

## 2. 实际检查与证据

| 检查 | 本轮结果 | 日志 |
| --- | --- | --- |
| 相关测试 | **465 通过 / 1 跳过 / 0 失败**，退出码 0 | `build/smart-follow/sf-b0/related-tests.log`、`related-tests-result.json` |
| 全仓静态分析 | **No issues found**，退出码 0，分析耗时 167.7 秒 | `build/smart-follow/sf-b0/analyze.log`、`analyze-result.json` |
| 工具版本 | 已读取实际运行版本 | `flutter-version.log`、`dart-version.log` |

相关测试覆盖这五个目录，递归运行其中现有测试：

```text
test/bird_companion/features/smart_follow
test/bird_companion/features/recognition
test/bird_companion/features/copy
test/bird_companion/features/tasks
test/bird_companion/tasks
```

实际执行方式（PowerShell；日志重定向到上述目录）：

```powershell
$taskDart = 'D:/flutter344/flutter/bin/cache/dart-sdk/bin/dart.exe'
$taskFlutter = 'D:/flutter344/flutter/bin/cache/flutter_tools.snapshot'
& $taskDart $taskFlutter test --no-pub --reporter expanded `
  test/bird_companion/features/smart_follow `
  test/bird_companion/features/recognition `
  test/bird_companion/features/copy `
  test/bird_companion/features/tasks `
  test/bird_companion/tasks
& $taskDart $taskFlutter analyze --no-pub
```

唯一跳过项：`python_backend_contract_test.dart` 的实际 Python HTTP 契约测试，测试自身说明需要单独启动 Python contract fixture；本轮未提供 `BIRDBOX_CONTRACT_BASE`。该项保持待验收，未用 Dart mock 替代，不属于本人后端开发任务。

本轮未运行全仓 Flutter 测试、Android 原生单测、APK 构建、手机手工流程、真实盒子或正式发布门禁。当前测试集合不能代表这些检查已通过。

## 3. 可以直接复用的接口及接线位置

| 需求 | 现有 App 接口/实现 | 接手方式 |
| --- | --- | --- |
| 能力与旧盒子兼容 | `SmartFollowRepository.capabilities`、`SmartFollowCapabilities.canShowEntry/canUpdateMetadata`、`SmartFollowEntryGate` | 新入口统一消费，不继续只检查旧 Map 中的 copy.available |
| 批次与识别任务 | `RepositoryTaskExperienceController.activeBatchId/jobs`；`JobRepository.page/detail`；BirdJobStatus 的 `sourceProjectId/type/state` | 按批次关联权威 analysis job；不能把最近任意任务当本批次识别 |
| 源/目标与角色 | `CopyRepository.devices/source`、`CopyDevicePolicy`、`StorageDeviceSummary` | 配置复用设备规则；不直接访问板端路径 |
| 未开始时识别＋跟随 | `startAnalysisForActiveProject` → `JobRepository.createAnalysis` → `JobApi.createAnalysis`；`AnalysisJobRequest.smartFollow` | 保留单次 analysis-jobs 原子请求；补稳定请求键和结果未知处理 |
| 识别进行中开启 | `SmartFollowRepository.startOnRecognitionJob` | 复用先查后建、ALREADY_ACTIVE 接管及稳定键，页面不直调 HTTP |
| 会话发现与重读 | `refreshForJob`、`snapshotForJob`、`refresh` | 当前通过 recognition-events 的 `smart_follow_session_id` 关联；未取得正式新查询接口前不发明路径 |
| 运行页 | `BirdRoutes.smartFollowRun`、`SmartFollowRunArgs`、`SmartFollowRunPage` | 路由和子任务弹层已可复用，补必要参数刷新与收尾回调 |
| 子任务分页与详情 | `repository.childJobs`、`showSmartFollowChildJobsSheet`、`BirdRoutes.copyJobDetail` | 保留分页与去重；汇总时另确保全量、终态和字段完整 |
| 控制动作 | `repository.act`＋五动作白名单＋后端 allowedActions | 保留版本冲突后刷新，不能本地自造动作 |
| 信息变化 | `metadataAvailability`、session 的 metadataUpdateAvailable/activeMetadataUpdateId | 页面层接能力与变化提示，识别状态单独获取 |
| 信息预览/创建 | `previewMetadata`、`createMetadataUpdate` | 复用 token/过期/显式部分确认和幂等规则，不绕仓库 |
| 信息父任务 | `metadataUpdate(updateId)`、SmartFollowMetadataUpdate/ChildUpdate | 新页面展示与恢复，沿已有 copyJobId 追溯原复制任务 |
| 事件 | dependencies 已 bindEvents；仓库六事件唤醒重读 | 不拿事件 payload 数字直接累计，不把 WS 当唯一恢复来源 |

主要阅读落点：

- [SmartFollowRepository](D:/Androidstudio2/project/4/lib/bird_companion/features/smart_follow/data/smart_follow_repository.dart:22)
- [SmartFollowApi](D:/Androidstudio2/project/4/lib/bird_companion/features/smart_follow/data/smart_follow_api.dart:17)
- [任务控制器](D:/Androidstudio2/project/4/lib/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart:364)
- [运行页路由壳](D:/Androidstudio2/project/4/lib/bird_companion/app/app_router.dart:349)
- [旧识别入口](D:/Androidstudio2/project/4/lib/bird_companion/features/recognition/recognition_widgets.dart:8)

## 4. 完成页数据来源与缺口

| 展示项 | 现有可读取事实 | 后续实现边界 |
| --- | --- | --- |
| 识别已处理/总数 | BirdJobStatus.finishedCount/totalCount | 当前运行页只接收路由数值，不是持续订阅；SF-B3 补动态读取 |
| 识别成功/失败/跳过 | JobReport.successCount/failedCount/skippedCount，识别事件快照还提供部分统计 | 不把识别任务“处理成功”直接等同 high；待确认等完整分类尚需权威字段对账 |
| eligible/待复制/已分配 | SmartFollowSession 对应计数 | 直接展示，保留照片单位，不与文件数混算 |
| 已复制照片/文件 | session.copiedAssetCount/copiedFileCount | 使用权威计数；不从 RAW/JPEG 配对策略推算 |
| 子任务冻结规模及复制/跳过/失败文件 | SmartFollowChildJob 对应字段 | 完整分页、ID 去重和全部终态之后才能作终态聚合；默认零值不证明字段确实提供 |
| 不适用、实际复制字节、信息输出结果 | CopyJobStats/CopyReport 有对应部分字段 | 区分计划 totalBytes 与 copiedBytes；逐任务读取所需报告，缺项不补零 |
| 覆盖数 | 当前 child 摘要和 CopyReport 无专用覆盖总数字段 | 不把冲突数或成功数当覆盖数；权威字段/既有明细口径未确认前显示未提供 |
| 会话结束、部分完成及原因 | session.state/errorCode/errorMessage，子任务结果 | 支持 completed/completed_partial/failed；报告不齐时明确待补齐，不能宣称全部成功 |
| 信息保存/更新 | CopyReport、metadata availability/preview/update | 复制结束不证明信息写入成功；父任务状态独立 |

信息更新 DTO/API 已有，但部分字段使用兼容别名且缺失时回退 0。SF-B5/SF-B6 接线前应确认“未提供”和真实零值的呈现方式；如确需增强字段存在性，仅做有样本依据的最小 App 契约修补，不在 UI 中猜 raw 字段。

## 5. 接缝核查及后续批次归属

下列是本批静态检查发现或需要补证的点，**不代表现有 465 条测试失败**。按已批准计划在对应后续批次修复/验证，不在 SF-B0 中提前改动整个功能。

| 编号 | 发现与依据 | 最小处理位置 | 后续批次/验收 |
| --- | --- | --- | --- |
| S01 | 旧 RecognitionOptions 只看 copy.available；请求只有目标/配对/冲突三字段 | entry 配置与 recognition_widgets | SF-B1/B2：总能力为 false 无可执行入口；发完整 DTO |
| S02 | 原子创建链路未暴露稳定 idempotencyKey；ApiClient 在未传入时为每次 POST 生成新键 | App 侧 JobRepository/JobApi/创建控制器的最小参数接线 | SF-B3：两种创建路径分别测连点、超时、同意图重试；不更换 key 盲建 |
| S03 | startAnalysisForActiveProject 遇到活动 analysis 会直接返回已有 jobId，不会应用新的 smartFollow 参数 | entry 路径决策；复用 startOnRecognitionJob | SF-B3：运行中开启必走会话创建/接管，而非返回分析任务即当作成功 |
| S04 | 分析结束事件仍会触发任务根的相册导航；SmartFollow 此时可能 draining | task_experience_root 的完成回调及导航 | SF-B3：识别结束而复制未结束时仍可留在/进入会话；普通分析旧行为不退化 |
| S05 | SmartFollowRunPage 只在初始化/手动刷新/仓库通知时更新；无生命周期观察、重连刷新或失败退避 | 运行页路由协调或最小页面控制器 | SF-B3/SF-B7：无新 WS 时前台恢复仍重读；失败退避、后台停刷新、销毁不留任务 |
| S06 | 任务根有 WS 断线时的固定 4 秒轮询，但它受通用 queued/running analysis 限制；不能覆盖识别终态后 SmartFollow 继续 draining 的恢复 | 同 S05，复用现有事件而补会话级恢复 | SF-B3：识别先结束、事件缺失的复制排空场景仍更新 |
| S07 | 运行路由传入的识别 processed/total 是打开时的普通值；正式路由未接 onOpenCompletion，未传信息父任务 | app_router、动态任务读取、finish 路由 | SF-B3 动态计数；SF-B4 完成入口；SF-B6 父任务接线 |
| S08 | TaskTile 更换 repository 时未迁移监听；EntryGate 在同一 repo 下设备变更后不直接订阅缓存重置 | entry/widget 生命周期的最小接线 | SF-B1/B3：换盒子不保留旧能力入口/会话；dispose 移除正确监听 |
| S09 | 仓库换设备会清快照/能力，但正在进行的读取未用设备 generation 隔离 | 在有针对性异步测试证明后最小增强仓库；页面同时校验会话/设备身份 | SF-B3：旧盒子迟到响应不写入新盒子；本轮仅登记，未断言已完成动态复现 |
| S10 | M1 时机不能以 session.isFinished 代替 RecognitionJob 是否终态；提前收尾跟随不停止识别 | 信息操作状态决策 | SF-B5：提前 finish/stop 后识别仍运行时只显示次级保存提示 |
| S11 | 完成页分类/覆盖/信息结果字段不完整；子任务摘要存在缺失默认零 | finish 统计投影及必要字段存在性适配 | SF-B4/SF-B5：全部分页、缺字段、零值、部分报告失败分别测试 |

R3 结论：全局事件绑定已完成，旧 1 秒 Panel 轮询也随 E0 删除；**不再做“替换已删除计时器”**。剩余是新会话运行链路的前台/重连/退避及设备隔离接线。按 S05/S06/S08/S09 列入 SF-B3，SF-B7 做集成回归，不推翻甲已交付的主体工作。

## 6. 本批交付与后续入口

- **SF-B0 已完成**：基线、相关测试与静态分析、接口复用清单、数据来源及 R3 接缝核对均已完成。
- 交付物：本记录、更新后的批次计划、`build/smart-follow/sf-b0/` 内日志和 `evidence.json`（退出码、结果、源码清单及日志 SHA-256）。证据目录由 build 规则忽略；移交机器时需连同日志一并复制，不能只转发文档中的结论。
- 本批不新增测试或修改业务行为；现有相关测试为后续开发提供比较基线。
- 下一批：**SF-B1（E1＋E2）四态入口与双模式**，先完成统一识别状态/能力/已有会话决策，再接复制范围页和任务入口。
- 后端材料缺失不影响 SF-B1/B2 本地实现；真实跨端发现、原子创建保证和统计语义仍由对方交付，不能用本地测试代签。

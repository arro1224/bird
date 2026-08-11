# B8：冻结刷新、现状快照与失败复现

日期：2026-08-10  
范围：项目 1 任务模块、相册搜索/筛选、birdbox-v1 冻结契约  
基线提交：`c63131a42fa1964ae797457e85a09684705ecbd4`

## 1. 工作树处理授权

- 已跟踪但未提交的文件，以及 Git 未追踪文件，只要与任务模块或相册搜索/筛选问题直接相关，均可修改、测试和纳入后续提交。
- 无关文件保持不动；B8 不执行 `git reset`、`git checkout` 或 `git clean`。
- B8 开始前工作树已包含任务、相册、复制、任务中心、契约测试和 mock server 等未提交变更，本批次不把这些变更误判为 B8 新建内容。

### B8 开始前的相关变更清单

已修改：

- `lib/bird_companion/features/gallery/data/photo_api.dart`
- `lib/bird_companion/features/gallery/data/photo_repository_impl.dart`
- `lib/bird_companion/features/gallery/domain/photo_query.dart`
- `lib/bird_companion/features/gallery/domain/photo_repository.dart`
- `lib/bird_companion/features/gallery/presentation/gallery_page.dart`
- `lib/bird_companion/features/tasks/**`
- `lib/bird_companion/features/copy/**`
- `lib/bird_companion/features/jobs/**`
- `test/bird_companion/features/gallery/album_view_cache_key_test.dart`
- `test/bird_companion/features/gallery/gallery_resilience_test.dart`
- `test/bird_companion/features/gallery/photo_module_baseline_contract_test.dart`
- `test/bird_companion/tasks/**`
- `test/contracts/contract_validation_test.dart`
- `tool/contracts/contract_validator.dart`
- `tool/mock_box_server/mock_box_server.dart`

未追踪：

- `docs/contracts/B0-FREEZE-2026-08-06.md`
- `docs/contracts/birdbox-v1-freeze.json`
- `docs/contracts/proposals/`
- `lib/bird_companion/features/gallery/domain/photo_version_batch_coordinator.dart`
- `lib/bird_companion/features/tasks/domain/task_home_capability_resolver.dart`
- `lib/bird_companion/features/tasks/presentation/pages/task_sync_result_sheet.dart`
- `test/bird_companion/features/gallery/photo_api_version_contract_test.dart`
- `test/bird_companion/features/tasks/**`

## 2. 冻结契约快照

当前批次必须新增外部接口：0 个。当前批次允许修改外部接口：0 个。

| 权威文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `docs/contracts/birdbox-v1.openapi.yaml` | 45511 | `44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f` |
| `docs/contracts/birdbox-v1-freeze.json` | 1462 | `04283cedb1dbd3eeb4a71d478e971ef154c311bd1d224c512366707d9efdcdfe` |
| `docs/contracts/birdbox-v1-baseline.json` | 1580 | `a5ecf1879e2a61991358619cfa2ab6d99db081a49fb72b58c1282ffae5396597` |
| `docs/decisions/ADR-001-birdbox-v1.md` | 4114 | `c64aece279a6b4a7fd0f740fc8af3f9cb0dd5c5a8ae2ebd3b0eda90f319f7d79` |
| `test/contracts/fixture-manifest.json` | 1986 | `49d0a5aba58f893b30a8196948c700df719368b877ba4c9b05fcabab1984e336` |

照片列表 `GET /projects/{projectId}/files` 的冻结查询参数只有：

`cursor`、`page_size`、`sort`、`keep_state`、`analysis_state`、`group_id`、`scene_id`。

`search`、`species`、`tags`、评分、识别度、清晰度、识别结果和推荐条件不得加入该网络请求。

## 3. “白鹭”跨页缺陷复现

新增现状特征测试：

- `test/bird_companion/features/gallery/b8_photo_query_freeze_test.dart`
- 第 1 页为空但 `has_more=true`，第 2 页 fixture 含“白鹭”。
- 当前 `PhotoApi.page` 只读取一次服务器页面，且 `search=白鹭` 不属于冻结网络参数，因此不会自动扫描第 2 页。
- B8 以可通过测试记录现状，不在本批次改变生产逻辑；B9 应把该特征测试替换为跨页搜索成功用例。
- 同一测试从冻结 OpenAPI 动态读取允许的查询参数，断言照片列表请求未发送任何未声明参数。

## 4. 任务设计 01–16 与生产文件映射

| 设计稿 | 生产入口/文件 | B8 判断 | 后续处理 |
| --- | --- | --- | --- |
| 01 可执行操作面板 | `task_experience_root.dart`、`task_home_page.dart`、`task_home_capability_resolver.dart` | 需收口 | 复核禁用原因、防重复点击与返回栈 |
| 02 SD 卡已识别 | `sd_card_flow_page.dart`、`repository_task_experience_controller.dart` | 需收口 | 真机卡插入和设备信息验收 |
| 03 SD 卡未识别 | 同上 | 需收口 | 重扫入口和错误文案验收 |
| 04 SD 卡读取失败 | 同上 | 需收口 | 权限、损坏卡和重试状态验收 |
| 05 SD 卡为空 | 同上 | 需收口 | 空批次和返回路径验收 |
| 06 导入任务运行中 | `task_detail_page.dart`、`job_status_view_adapter.dart` | 已实现，需验收 | 核对进度、事件轮询和可用动作 |
| 07 AI 任务暂停 | `task_detail_page.dart`、`repository_task_experience_controller.dart` | 已实现，需验收 | 只依据权威状态和 `available_actions` |
| 08 复制内容 | `copy_content_page.dart`、生产复制确认流程 | 已实现，需收口 | 目标盘、空间和真实数据 |
| 09 复制确认 | `features/copy/presentation/copy_confirmation_page.dart` | 已实现，需收口 | 提交前重估、版本和幂等 |
| 10 复制任务失败 | `task_detail_page.dart`、`production_task_result_page.dart` | 已实现，需验收 | 409、磁盘满、断线和恢复 |
| 11 同步完成 | `task_sync_result_sheet.dart`、`BirdSyncService` | 有意偏离 | 保持 App 本地结果层，不伪造盒子任务 |
| 12 任务断线 | `task_detail_page.dart`、`repository_task_experience_controller.dart` | 已实现，需验收 | 断线时保留页面并禁用写操作 |
| 13 正在重连 | 同上 | 已实现，需验收 | 重连后权威刷新并隔离旧会话 |
| 14 取消任务对话框 | `task_detail_page.dart`、任务 action API | 已实现，需验收 | 二次确认、冲突和取消后状态 |
| 15 复制成功结果 | `production_task_result_page.dart` | 已实现，需收口 | 真实任务 ID、相册入口和返回栈 |
| 16 复制报告 | `production_task_result_page.dart`、`JobReport`、failure 分页 | 已实现，需收口 | 缺失权威字段时隐藏或标“未提供” |

## 5. B8 完成门槛

- [x] 记录基线提交、相关工作树授权和开始前变更范围。
- [x] 记录冻结契约权威文件及 SHA-256。
- [x] 建立“白鹭位于第 2 页以后”的现状特征测试。
- [x] 建立照片列表网络参数与冻结 OpenAPI 一致的断言。
- [x] 完成任务设计 01–16 到生产文件的映射。
- [x] 定向测试通过。
- [x] birdbox-v1 契约校验通过且冻结 SHA 不变。

## 6. 验证结果

以下命令于 2026-08-10 执行通过：

```powershell
flutter test --no-pub test/bird_companion/features/gallery/b8_photo_query_freeze_test.dart
dart run tool/contracts/verify_contracts.dart
flutter test --no-pub test/contracts/contract_validation_test.dart
flutter test --no-pub test/bird_companion/features/gallery/b8_photo_query_freeze_test.dart test/bird_companion/features/gallery/photo_api_version_contract_test.dart test/bird_companion/features/tasks/production_task_r0_baseline_test.dart
```

结果：

- B8 新增现状特征与冻结参数测试：2/2 通过。
- birdbox-v1 OpenAPI、`$ref`、Schema 与 fixture 校验通过。
- birdbox-v1 契约测试：4/4 通过。
- B8 相册契约与任务生产基线组合回归：8/8 通过。
- `docs/contracts/birdbox-v1.openapi.yaml` SHA-256 仍为 `44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f`。
- 本批次未修改生产接口、请求参数、响应字段、状态码或冻结文件。

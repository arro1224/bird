# B9：搜索/筛选正确性闭环

日期：2026-08-10  
前置批次：B8 冻结刷新、现状快照与失败复现  
范围：项目 1 相册搜索、鸟种筛选、组合筛选、跨页结果与本地游标

## 1. 交付结论

- 已修复“白鹭位于第 2 个服务端分页及以后时，搜索结果为空”的问题。
- 当查询包含 App 本地条件时，Repository 使用冻结参数逐页扫描候选照片，直到 `has_more=false`，再统一去重、筛选和排序。
- 中文名、英文名、拉丁名及 `species_id` 通过现有 `GET /api/v1/species` 做别名解析；别名请求失败时回退到照片候选字段的原始文本匹配。
- 本地分页使用 `local-v1-<session>-<offset>` 游标；该游标只由 App 内部执行器消费，不会传入 `PhotoApi`。
- 外部接口新增 0 个，修改 0 个；冻结 OpenAPI、请求路径、请求体、响应和状态码均未改变。

## 2. 实现结构

### QueryPlan

`photo_query_plan.dart` 将查询分为两部分：

- 冻结服务端条件：`cursor`、`page_size`、`sort`、`keep_state`、`analysis_state`、`group_id`、`scene_id`。
- App 本地条件：`search`、`species`、`min_score`、`min_confidence`、`tags`、`clarity_state`、`recognition_state`、`recommended_only`。

本地条件存在时，服务端扫描页大小使用冻结上限 `200`。`PhotoQuery.parameters` 仍是唯一网络参数来源，没有加入任何未声明字段。

### 本地筛选引擎

`photo_local_filter_engine.dart` 从 Repository 中抽出为纯逻辑组件，覆盖：

- 文件名、用户标签、鸟种中文名/英文名/拉丁名/ID 的标准化匹配；
- 鸟种候选 OR、不同筛选维度 AND、标签 AND；
- 评分、首候选识别度、清晰度、识别状态、推荐、保留状态、处理状态、分组和场景；
- 可由 `PhotoSummary` 复算的排序；无法由摘要复算的冻结排序保留服务端顺序。

搜索别名和鸟种别名分别保存，避免“搜索麻雀 + 鸟种白鹭”因别名集合混用而错误命中。

### 跨页执行与本地会话

`photo_local_query_executor.dart`：

1. 解析别名；
2. 使用冻结参数逐页读取照片；
3. 对照片 ID 去重并防止重复服务端游标造成死循环；
4. 完成本地筛选和排序；
5. 将完整结果放入最多 16 个内存会话并按原查询 `page_size` 切页；
6. 加载更多时直接消费本地会话，不再次请求服务端。

会话丢失或本地游标无效时，从无服务端游标状态重新扫描，确保内部游标不会出网。

## 3. 修改文件

- `lib/bird_companion/features/gallery/domain/photo_query_plan.dart`
- `lib/bird_companion/features/gallery/domain/photo_local_filter_engine.dart`
- `lib/bird_companion/features/gallery/data/photo_local_query_executor.dart`
- `lib/bird_companion/features/gallery/data/photo_repository_impl.dart`
- `test/bird_companion/features/gallery/b9_photo_query_execution_test.dart`

以上包含本批次新文件和与问题直接相关的既有未提交文件；无关工作树改动未清理、未覆盖。

## 4. 自动化门禁

B9 定向测试覆盖：

- 第 1 页为空且 `has_more=true`，第 2 页英文候选通过“白鹭”别名命中；
- App 本地条件与本地游标均不进入网络参数；
- 本地结果分页不产生额外网络请求；
- 鸟种、评分、识别度、标签、清晰度、识别状态和推荐组合筛选；
- 搜索别名与鸟种别名隔离；
- 无法本地复算的冻结排序保留服务端顺序；
- 服务端重复游标时有限停止。

验证结果：

- B9 定向测试：6/6 通过；
- 相册目录回归：32/32 通过（包含 B9 最终新增的 2 个用例）；
- 任务模块目录回归：135/135 通过；
- birdbox-v1 契约测试：4/4 通过；
- OpenAPI、引用、Schema 与 fixture 校验通过；
- 相关 Dart 静态分析：No issues found；
- `docs/contracts/birdbox-v1.openapi.yaml` SHA-256 仍为 `44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f`。

## 5. B10 边界

B9 先闭环结果正确性。扫描进度、取消、完整候选集持久缓存、数据事件精准失效、离线“不完整结果”提示和 3,000–10,000 张性能验收属于 B10，不在本批次伪装完成。

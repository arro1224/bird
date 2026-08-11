# B10：分页、缓存、性能与筛选体验

日期：2026-08-10  
前置批次：B9 搜索/筛选正确性闭环  
范围：相册本地筛选进度、取消、候选缓存、失效、离线完整性提示和大数据保护

## 1. 交付结论

- 长时间本地筛选不再只显示通用加载状态：Gallery 保留已有照片，并持续显示“已扫描 N 张、命中 N 张”。
- 用户可取消正在执行的筛选；取消令牌在别名解析、每个服务端分页前后及缓存写入后检查，取消后不会继续请求下一页，也不会显示错误。
- 完整候选集按设备命名空间、项目、冻结服务端条件和排序缓存 10 分钟；只改变 App 本地条件时无需重新扫描盒子分页。
- 照片/缓存数据事件及批量照片修改会先清除对应项目的内存会话和完整候选缓存，再刷新页面。
- 扫描在已有分页后因网络失败时返回明确的“不完整缓存结果”，不会把“缓存中无结果”描述为“项目中无结果”。
- 筛选重置会同时清除搜索、鸟种、阈值、标签、状态、推荐、分组、场景和自定义排序。
- 外部接口新增 0 个，修改 0 个；所有新增能力均位于 App 内部。

## 2. 状态与执行模型

`GalleryState` 新增以下内部状态：

- `filtering`：本地完整筛选是否正在执行；
- `scannedCount` / `matchedCount`：已扫描候选数与当前命中数；
- `resultComplete`：结果是否来自完整候选集；
- `cacheScope`：`none`、`complete` 或 `partial`。

`PhotoQueryExecutionRepository` 是可选 App 内部能力，不改变原 `PhotoRepository.page` 签名。生产 Repository 支持：

- 带进度回调和取消令牌的分页执行；
- 按项目失效本地查询会话和候选缓存。

不支持该能力的既有测试替身和调用方仍按原接口工作。

## 3. 完整候选缓存

缓存键组成：

`device namespace + project_id + 冻结服务端参数 + sort`

约束：

- 只在服务端分页完整结束后写入 `complete=true` 的候选集；
- App 本地搜索词、鸟种、标签和阈值不进入候选缓存键；
- 缓存有效期 10 分钟，过期条目在读取时异步清理；
- 内存结果会话最多 16 个且最多保留约 50,000 个结果项，优先淘汰旧会话；
- 照片数据变化、批量审阅修改和缓存事件精准失效当前设备/项目的候选集；
- 本地短期游标仍不持久化，也不进入网络请求。

## 4. 页面体验

- 筛选开始后立即显示固定可见的进度浮层，不因滚动位置而消失。
- 已有结果继续保留，避免搜索输入时整页空白或旧结果被通用 loading 遮盖。
- 取消后保留已有结果，并清除 loading/filtering 状态。
- 完整缓存命中显示缓存加速提示；离线或中断后的部分结果显示“仅在已缓存照片中查找，结果可能不完整”。
- 部分缓存内没有命中时显示“已缓存照片中没有符合条件的结果”。

## 5. 修改文件

- `lib/bird_companion/features/gallery/domain/photo_repository.dart`
- `lib/bird_companion/features/gallery/domain/photo_local_filter_engine.dart`
- `lib/bird_companion/features/gallery/data/photo_local_query_executor.dart`
- `lib/bird_companion/features/gallery/data/photo_repository_impl.dart`
- `lib/bird_companion/features/gallery/presentation/gallery_cubit.dart`
- `lib/bird_companion/features/gallery/presentation/gallery_page.dart`
- `lib/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart`
- `test/bird_companion/features/gallery/b10_photo_filter_experience_test.dart`

## 6. 自动化门禁

B10 定向测试覆盖：

- 每个服务端分页的扫描/命中进度及完成状态；
- 取消后不再请求下一分页；
- 不同本地筛选复用同一完整候选快照；
- 网络中断后的部分结果完整性标记；
- Gallery 过滤时保留旧照片并可无错误取消；
- 照片数据事件先失效项目候选缓存；
- 10,000 张照片本地筛选性能保护；
- 重置清除搜索和所有高级筛选条件。

最终验证结果：

- B10 定向测试：8/8 通过；
- 相册目录回归：40/40 通过；
- 任务模块目录回归：135/135 通过；
- birdbox-v1 契约测试：4/4 通过；
- OpenAPI、引用、Schema 与 fixture 校验通过；
- 相关 Dart 静态分析：No issues found；
- `docs/contracts/birdbox-v1.openapi.yaml` SHA-256 仍为 `44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f`。

## 7. B12 发布门禁保留项

B10 的自动化性能用例保护本地 10,000 张筛选不出现算法退化。真机局域网下 3,672–10,000 张候选的首个进度反馈、完整结果耗时、内存峰值和弱网取消手感仍应在 B12 进行设备级验收，不能用单元测试代替。

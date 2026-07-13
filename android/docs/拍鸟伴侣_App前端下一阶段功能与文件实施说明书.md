# 拍鸟伴侣 App 前端下一阶段功能与文件实施说明书

> 项目路径：`D:\Androidstudio2\project1\aves`  
> 对照资料：《拍鸟伴侣_盒子端与App端需求汇总说明书》《拍鸟伴侣App端需求》《拍鸟伴侣App P0版 前端需求进度跟踪表》  
> 审查日期：2026-07-11  
> 范围：只覆盖 App Flutter 前端、前端与盒子端的协同接口及测试；不包含盒子端 AI、读卡、复制和 XMP 的真实实现。

## 1. 当前进度结论

当前项目已经具备拍鸟伴侣独立 `bird` flavor、分层目录、基础页面、API/Repository/Cubit 骨架和可运行的模拟盒子服务。它已经超过“纯 UI 原型”，但还没有达到进度表的 P0 验收状态。

按不同口径估算：

- 页面和工程骨架：约 60%。
- 通过模拟盒子演示主流程：约 40%。
- 满足真实盒子联调与 P0 验收：约 20%–30%。

主要原因不是页面数量不足，而是多个页面尚未形成可验证的完整闭环：自动发现、真实事件刷新、完整组合筛选、审阅撤销/冲突、复制保护、任务失败处理、性能和测试仍未完成。

## 2. 进度表建议状态

| 编号 | 建议状态 | 当前依据 | 未满足的关键验收点 |
|---|---|---|---|
| F001 | 进行中 | 已有独立入口及 `bird_companion` 分层 | Aves 原本地相册逻辑仍保留，未完成“全部剥离”验收 |
| F002 | 基本完成 | Dio、WebSocket、Bloc、Hive、缓存和通用组件已加入 | 仍需组件测试及统一错误/加载规范 |
| F003 | 进行中 | 手动 IP、热点、扫码、最近设备已实现 | 局域网自动发现仍为已知设备占位；真实盒子未联调 |
| F004 | 进行中 | 设备卡片、告警、任务概览已实现 | WebSocket 实时状态和异常矩阵未验收 |
| F005 | 部分完成 | 有网络监听、待同步存储和冲突对象 | 未自动重连，离线队列未接入实际写操作 |
| F006 | 进行中 | 当前/历史批次、筛选、恢复入口已实现 | 分页、事件刷新、恢复结果未验收 |
| F007 | 进行中 | 网格、分页结构、占位已实现 | 未使用正式缓存图片组件，未做万张性能测试 |
| F008 | 部分完成 | 仅有低置信度筛选和基础排序 | 鸟种、评分、标签、保留/分析状态组合筛选未完成 |
| F009 | 部分完成 | 详情、主体框、识别、评分、EXIF 已有 | 主体框坐标算法、版本历史、真实预览图未验收 |
| F010 | 部分完成 | 分组列表和代表图入口已有 | 组内照片浏览、推荐标识、快速标记不完整 |
| F011 | 部分完成 | 分析中/失败等基础占位已有 | 废片、低置信、多主体、主体小等完整状态未覆盖 |
| F012 | 部分完成 | 保留状态可提交 | 鸟种、评分、标签、撤销、离线同步和冲突闭环缺失 |
| F013 | 部分完成 | 多选和批量保留/弃用入口已有 | 标签增删、整组操作、撤销、部分失败反馈缺失 |
| F014 | 进行中 | 三种模式、容量预估、目标盘、确认框已有 | 空间不足拦截、重复提交保护和结果页未验收 |
| F015 | 进行中 | 列表、演示任务、详情、进度和日志入口已有 | 实时事件、失败项、任务控制和日志文件结果缺失 |
| F016 | 部分完成 | 版本、缓存清理、诊断入口已有 | 忘记设备、真实版本、缓存大小、日志下载缺失 |
| F017 | 未开始 | 无万张数据和内存基准结果 | 滚动、图片缓存、大图内存均未验收 |
| F018 | 未开始 | 有部分提示组件 | 尚未系统测试断线、拔卡、拔盘、冲突、任务恢复 |
| F019 | 未开始 | 仅一个模型映射测试 | Cubit、Widget、Golden、集成测试及正式安装包缺失 |

## 3. 下一阶段总体顺序

```text
接口契约与连接会话
→ 设备/批次实时状态
→ 图库分页、图片缓存和完整筛选
→ 分组与单张审阅闭环
→ 离线回写、撤销与冲突
→ 复制与任务闭环
→ 设置诊断
→ 性能、异常、测试和交付
```

不要先做 F017/F019，再回头修改数据模型。应先锁定盒子端契约和状态机，否则测试用例、分页和缓存都会反复修改。

## 4. P0-1：锁定接口契约与连接会话

### 4.1 要完成的功能

1. 与盒子端确认 HTTP 基础地址、API 版本、配对方式和错误结构。
2. 确认局域网发现使用 mDNS 还是 UDP，并替换当前已知设备占位实现。
3. 建立全局连接会话：当前设备、连接中、在线、断线、重连中、版本不兼容。
4. WebSocket 断线后指数退避重连；重连成功后重新拉取设备、任务、批次和待同步操作。
5. 手动地址、热点、扫码和自动发现统一进入同一个握手流程。

### 4.2 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `lib/bird_companion/core/network/api_endpoints.dart` | 用盒子端最终路径替换临时 `/api/v1` 路径，并增加 API 版本常量。 |
| `lib/bird_companion/core/network/api_client.dart` | 增加配对令牌、请求 ID、操作来源、版本头、统一 envelope 解包和幂等键。 |
| `lib/bird_companion/core/network/event_client.dart` | 增加心跳、断线检测、自动重连、订阅恢复和最后事件序号。 |
| `lib/bird_companion/core/network/api_exception.dart` | 映射超时、未授权、版本不兼容和盒子错误码。 |
| `lib/bird_companion/features/connection/data/device_discovery_source.dart` | 删除当前只返回已知设备的实现，接入最终 mDNS/UDP 发现协议。 |
| `lib/bird_companion/features/connection/data/connection_api.dart` | 完成握手、API 兼容检查、配对和事件通道建立。 |
| `lib/bird_companion/features/connection/data/connection_repository_impl.dart` | 保存当前设备、配对信息、最近设备和重连上下文。 |
| `lib/bird_companion/features/connection/presentation/connection_cubit.dart` | 增加自动重连、版本不兼容、配对失败和取消连接状态。 |
| `lib/bird_companion/app/app_dependencies.dart` | 注入全局连接会话，不让页面各自判断是否在线。 |

### 4.3 需要新增的文件

| 文件 | 用途 |
|---|---|
| `lib/bird_companion/core/session/device_session.dart` | 保存当前设备、连接状态、最后更新时间和配对信息。 |
| `lib/bird_companion/core/session/device_session_cubit.dart` | 向所有页面广播在线、断线、重连和切换设备状态。 |
| `lib/bird_companion/core/network/reconnect_policy.dart` | 定义退避时间、最大重试次数和前后台恢复策略。 |
| `lib/bird_companion/features/connection/data/mdns_device_discovery_source.dart` 或 `udp_device_discovery_source.dart` | 实现最终局域网发现协议，二选一。 |

### 4.4 验收标准

- 自动发现和手动地址都能连接真实或模拟盒子。
- 版本不兼容有明确提示，不能直接进入首页。
- 断开网络后出现全局断线条；恢复网络后自动重连并刷新权威状态。
- “重新连接”进入连接页后可以返回原页面。

## 5. P0-2：设备状态、批次和事件刷新闭环

### 5.1 要完成的功能

- 设备状态通过 WebSocket 更新，前台恢复时主动刷新。
- 当前任务变化、插拔卡、高温、低电量和错误码实时更新。
- 批次列表支持服务端分页、筛选、排序和事件增量刷新。
- 恢复未完成批次后显示提交中、成功或失败，而不是无反馈。

### 5.2 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `features/device/data/device_repository_impl.dart` | 合并 HTTP 初始状态和 WebSocket 增量事件，保留最后更新时间。 |
| `features/device/presentation/device_status_cubit.dart` | 增加断线缓存态、前台刷新、合法任务控制状态和控制失败反馈。 |
| `features/device/presentation/device_status_page.dart` | 展示最后更新时间、断线状态、刷新结果和错误详情入口。 |
| `features/device/presentation/widgets/device_alert_banner.dart` | 对未插卡、读卡失败、高温、低电量、服务异常分别给出动作。 |
| `features/batches/data/batch_api.dart` | 加入 cursor/page、筛选、排序及恢复结果解析。 |
| `features/batches/domain/batch_repository.dart` | 返回分页对象，而不是一次性 `List`。 |
| `features/batches/presentation/batch_list_cubit.dart` | 增加加载更多、事件刷新、恢复状态和部分错误处理。 |
| `features/batches/presentation/batch_list_page.dart` | 增加到底提示、恢复确认和操作结果提示。 |

### 5.3 需要新增的文件

| 文件 | 用途 |
|---|---|
| `features/batches/domain/batch_page.dart` | 定义 items、nextCursor、hasMore。 |
| `features/batches/presentation/widgets/batch_resume_dialog.dart` | 展示将恢复的阶段和影响范围。 |
| `features/device/presentation/device_error_detail_page.dart` | 展示错误码、建议动作、关联任务和日志入口。 |

## 6. P0-3：图库分页、缓存、完整筛选和高张数性能

### 6.1 当前缺口

- `photo_tile.dart` 使用 `Image.network`，没有使用已引入的 `cached_network_image`。
- `filter_sheet.dart` 只实现低置信度开关，不满足 F008。
- 网格底部 item 在 build 时直接触发加载更多，可能重复请求。
- 缩略图 URL 的 baseUri、鉴权、缓存键和失效机制未统一。
- 未进行 10,000 条数据性能测试。

### 6.2 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `features/gallery/domain/photo_query.dart` | 增加鸟种、评分区间、置信度、清晰度、标签、保留状态、分析状态、分组等强类型字段。 |
| `features/gallery/data/photo_api.dart` | 支持 cursor/page、组合筛选、服务端排序和部分失败格式。 |
| `features/gallery/data/photo_repository_impl.dart` | 合并分页结果、去重、事件增量更新和缩略图 URL 解析。 |
| `features/gallery/presentation/gallery_cubit.dart` | 防重复分页，保留滚动查询状态，处理照片分析完成事件。 |
| `features/gallery/presentation/gallery_page.dart` | 增加明确空状态、分页失败重试、筛选数量和进入复制确认入口。 |
| `features/gallery/presentation/widgets/photo_grid.dart` | 改为滚动阈值触发加载，避免 itemBuilder 中重复调用。 |
| `features/gallery/presentation/widgets/photo_tile.dart` | 使用缓存图片，补评分、置信度、保留状态和低置信度叠层。 |
| `features/gallery/presentation/widgets/filter_sheet.dart` | 实现全部组合筛选和清除筛选。 |
| `features/gallery/presentation/widgets/sort_sheet.dart` | 使用当前 Flutter 推荐的 RadioGroup/选择组件，去除弃用 API。 |
| `features/gallery/presentation/widgets/selection_action_bar.dart` | 增加待确认、精选、标签、全选当前结果和操作确认。 |
| `core/storage/local_cache.dart` | 保存批次查询、筛选条件和滚动位置；清缓存不删除待同步操作。 |

### 6.3 需要新增的文件

| 文件 | 用途 |
|---|---|
| `core/network/authenticated_image_provider.dart` | 为缩略图和预览图附加盒子鉴权信息。 |
| `features/gallery/domain/gallery_filter.dart` | 强类型组合筛选对象及序列化。 |
| `features/gallery/domain/gallery_sort.dart` | 定义合法排序字段和方向。 |
| `features/gallery/presentation/widgets/active_filter_chips.dart` | 展示和单独移除已启用筛选条件。 |
| `features/gallery/presentation/widgets/gallery_empty_state.dart` | 区分无照片、分析未完成、筛选无结果。 |

### 6.4 验收标准

- 10,000 条摘要数据连续滚动无明显卡顿和重复分页。
- 返回详情后保持筛选条件、已加载页和滚动位置。
- 所有进度表筛选条件可组合，并由服务端返回正确结果。
- 缩略图失败、分析中、跳过和失败有不同展示与动作。

## 7. P0-4：分组审阅与单张详情正确性

### 7.1 当前缺口

- 分组页主要是组卡列表，没有完成组内大图切换、推荐排名和快速标记闭环。
- `subject_overlay_view.dart` 目前以固定 `*100` 计算坐标，不能保证不同屏幕、图片比例和缩放后的检测框准确。
- `photoHistory` 端点存在，但 `review_api.dart` 未真正读取版本历史。
- 预览加载失败、多个主体、低置信度和 AI 原始结果缺少完整交互。

### 7.2 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `features/review/data/review_api.dart` | 同时获取详情、版本历史、人工决策和可编辑标签。 |
| `features/review/domain/review_repository.dart` | 增加撤销、批量/整组操作和冲突返回类型。 |
| `features/review/presentation/group_review_cubit.dart` | 管理当前组、当前照片、上一/下一组、整组修改和撤销。 |
| `features/review/presentation/group_review_page.dart` | 完成组内大图、横向照片带、推荐理由和快速状态操作。 |
| `features/review/presentation/widgets/group_photo_strip.dart` | 显示真实缩略图、Top 排名和当前选择。 |
| `features/review/presentation/photo_detail_cubit.dart` | 增加编辑草稿、未保存、提交中、已同步、待同步、冲突和撤销状态。 |
| `features/review/presentation/photo_detail_page.dart` | 增加鸟种、评分、标签编辑，保存前后状态和离开页面保护。 |
| `features/review/presentation/widgets/subject_overlay_view.dart` | 基于图片原始尺寸、BoxFit 留白和缩放矩阵计算主体框。 |
| `features/review/presentation/widgets/recognition_panel.dart` | 完整展示 Top-N、中文/英文/拉丁名、置信度和人工选择。 |
| `features/review/presentation/widgets/version_history_panel.dart` | 展示 AI 原值、人工值、操作来源、时间和版本。 |
| `features/review/presentation/widgets/conflict_dialog.dart` | 展示本地/远端差异并返回用户选择。 |

### 7.3 需要新增的文件

| 文件 | 用途 |
|---|---|
| `features/review/domain/review_draft.dart` | 保存未提交的鸟种、评分、标签和保留状态草稿。 |
| `features/review/domain/review_conflict.dart` | 定义本地与远端版本差异。 |
| `features/review/presentation/widgets/species_picker.dart` | 搜索和选择鸟种候选。 |
| `features/review/presentation/widgets/tag_editor.dart` | 用户标签增删与系统标签只读展示。 |
| `features/review/presentation/widgets/unsaved_changes_dialog.dart` | 返回页面前提醒保存、放弃或继续编辑。 |

## 8. P0-5：离线回写、撤销、冲突和批量操作

### 8.1 要完成的功能

- 所有单张/批量写操作携带 `source`、`updated_at`、`version` 和幂等键。
- 断线时写入待同步队列，而不是直接报错丢失。
- 重连后按顺序同步；版本冲突必须显示差异，不能静默覆盖。
- 单张和批量修改支持撤销；批量部分失败可查看失败项并重试。

### 8.2 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `core/sync/pending_operation.dart` | 增加幂等键、实体版本、操作来源和失败原因。 |
| `core/storage/pending_operation_store.dart` | 支持按照片/批次查询、更新状态和清理成功项。 |
| `core/sync/sync_coordinator.dart` | 接入连接会话，支持暂停、重试、冲突和同步报告。 |
| `core/sync/conflict_resolver.dart` | 从简单版本比较升级为字段级冲突结果。 |
| `features/review/data/review_repository_impl.dart` | 在线直接提交；离线入队；409/版本冲突转为领域对象。 |
| `features/gallery/data/photo_repository_impl.dart` | 批量操作使用离线队列和幂等键，解析部分成功/失败。 |
| `features/gallery/presentation/selection_cubit.dart` | 管理提交、撤销、失败项和重试状态，而不只是 `Set<String>`。 |
| `features/gallery/presentation/widgets/batch_operation_result.dart` | 展示成功/失败数量和失败项入口。 |

### 8.3 需要新增的文件

| 文件 | 用途 |
|---|---|
| `core/sync/sync_report.dart` | 同步成功、失败、冲突数量和失败操作列表。 |
| `features/gallery/domain/batch_operation_result.dart` | 定义批量操作部分成功结果。 |
| `features/gallery/presentation/batch_operation_failure_page.dart` | 查看失败照片、原因和重试。 |
| `features/review/data/undo_repository.dart` | 调用盒子撤销接口或提交历史版本。 |

## 9. P0-6：复制确认与任务中心完整闭环

### 9.1 复制确认缺口

- 空间不足尚未形成明确的提交拦截规则。
- 创建任务未使用幂等键，快速重复点击可能重复创建。
- 待确认照片在三种复制模式中的规则需要盒子端确认。
- 创建后只进入任务详情，缺少完整结果报告。

### 9.2 任务中心缺口

- Job WebSocket 事件未接入 `JobCenterCubit`。
- 暂停、继续、重试、跳过、取消的合法状态矩阵未实现。
- `jobFailures` 端点已定义，但没有失败项页面。
- 日志导出按钮未处理生成中、下载地址、保存/分享和失败状态。

### 9.3 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `features/copy/presentation/copy_confirmation_cubit.dart` | 增加容量校验、目标盘掉线、提交幂等和重复点击保护。 |
| `features/copy/presentation/copy_confirmation_page.dart` | 空间不足禁用提交并显示解决建议。 |
| `features/copy/presentation/widgets/copy_scope_summary.dart` | 明确保留、弃用、待确认、精选数量和 XMP 策略。 |
| `features/jobs/data/job_api.dart` | 增加失败项、任务报告、日志导出结果解析。 |
| `features/jobs/data/job_repository_impl.dart` | 合并 HTTP 与 WebSocket 任务更新。 |
| `features/jobs/presentation/job_center_cubit.dart` | 管理筛选、实时更新、任务控制、日志导出和错误状态。 |
| `features/jobs/presentation/job_center_page.dart` | 增加任务筛选、控制入口、日志导出进度和完成结果。 |
| `features/jobs/presentation/job_detail_page.dart` | 展示失败原因、当前文件、速度、结果报告和合法控制按钮。 |

### 9.4 需要新增的文件

| 文件 | 用途 |
|---|---|
| `features/jobs/domain/job_action_policy.dart` | 定义各状态允许的暂停、继续、取消、重试和跳过动作。 |
| `features/jobs/presentation/widgets/job_failure_list.dart` | 展示失败项及重试入口。 |
| `features/jobs/presentation/widgets/job_result_summary.dart` | 展示成功、失败、容量、XMP 和耗时。 |
| `features/jobs/presentation/widgets/log_export_dialog.dart` | 日志类型、时间范围、生成、下载和分享状态。 |

## 10. P0-7：设置与诊断

### 10.1 需要修改的文件

| 文件 | 修改目的 |
|---|---|
| `features/settings/presentation/settings_cubit.dart` | 读取当前设备、自动重连、缓存大小、版本和最近错误。 |
| `features/settings/presentation/settings_page.dart` | 增加连接设置、自动重连、忘记设备和隐私说明。 |
| `features/settings/presentation/diagnostics_page.dart` | 运行状态检查，展示 API/事件通道/版本/错误码并导出日志。 |
| `features/settings/presentation/widgets/version_info_card.dart` | 展示真实 App、软件、API、模型、类别表和 schema 版本。 |
| `features/settings/presentation/widgets/cache_management_card.dart` | 计算真实缓存大小，清理结果可见，保护待同步数据。 |

### 10.2 需要新增的文件

| 文件 | 用途 |
|---|---|
| `features/settings/presentation/widgets/connection_settings_card.dart` | 当前连接方式、地址、自动重连和忘记设备。 |
| `features/settings/presentation/widgets/privacy_card.dart` | 说明本地运行和默认不上传原图。 |
| `features/settings/domain/diagnostic_result.dart` | 表达 HTTP、WebSocket、版本、存储和日志检查结果。 |

## 11. P0-8：性能、异常和测试交付

### 11.1 性能任务

- 用 10,000 条照片摘要和多页数据压测图库。
- 统计首次加载、翻页、筛选和返回恢复耗时。
- 验证缩略图缓存命中、大图释放和连续详情浏览内存。
- 检查页面重建导致的重复 HTTP 和 WebSocket 订阅。

### 11.2 异常任务

- 断网、热点切换、App 后台恢复。
- 盒子重启、WebSocket 中断、任务继续执行。
- 拔卡、读卡失败、目标盘拔出、空间不足。
- 批量操作部分失败、人工修改版本冲突。
- 模拟盒子返回超时、401、409、500 和未知字段。

### 11.3 需要新增的测试文件

| 文件 | 用途 |
|---|---|
| `test/bird_companion/core/api_client_test.dart` | envelope、错误码、超时、版本头和幂等键。 |
| `test/bird_companion/core/sync_coordinator_test.dart` | 离线队列、顺序、重试和冲突。 |
| `test/bird_companion/features/connection_cubit_test.dart` | 搜索、连接、超时、配对、断线和重连。 |
| `test/bird_companion/features/device_status_cubit_test.dart` | 初始查询、事件刷新、控制任务和异常。 |
| `test/bird_companion/features/batch_list_cubit_test.dart` | 分页、筛选、恢复和事件更新。 |
| `test/bird_companion/features/gallery_cubit_test.dart` | 分页去重、组合筛选、事件更新和失败重试。 |
| `test/bird_companion/features/photo_detail_cubit_test.dart` | 编辑、离线、提交、撤销和冲突。 |
| `test/bird_companion/features/copy_confirmation_cubit_test.dart` | 三模式、空间不足和防重复提交。 |
| `test/bird_companion/features/job_center_cubit_test.dart` | 实时事件、动作矩阵、失败项和日志。 |
| `test/bird_companion/golden/*.dart` | 连接、设备、批次、图库、详情、复制、任务的正常/空/错/断线截图。 |
| `integration_test/bird_companion_p0_flow_test.dart` | 连接→批次→图库→修改→复制→任务结果完整流程。 |

### 11.4 需要修改的模拟盒子文件

| 文件 | 修改目的 |
|---|---|
| `mock_box_server/server.py` | 增加分页、筛选、状态变化、人工回写、失败项、日志下载和可配置异常。 |
| `mock_box_server/README.md` | 增加测试场景、真机连接、防火墙和停止服务说明。 |

建议进一步新增：

```text
mock_box_server/
├─ server.py
├─ state.py                 # 可变设备、批次、任务状态
├─ fixtures/                # 正常、空、异常、冲突测试数据
├─ scenarios.py             # 高温、断线、空间不足等场景切换
└─ README.md
```

## 12. 建议的近期两周任务切片

### 第一批：先获得可靠的真实/模拟联调闭环

1. 完成 P0-1 连接会话、自动重连和最终接口契约。
2. 扩展模拟盒子，支持分页、人工回写、任务控制和异常切换。
3. 完成设备、批次、任务 WebSocket 刷新。
4. 修复所有页面空白、重复导航和无返回入口问题。

### 第二批：完成审片核心价值

1. 完整组合筛选和缓存图片。
2. 分组内浏览与快速标记。
3. 单张鸟种、评分、标签、保留状态编辑。
4. 离线队列、撤销、冲突和批量失败处理。

### 第三批：交付前收口

1. 复制空间保护和任务结果。
2. 设置诊断和日志下载。
3. 万张性能、异常矩阵和自动化测试。
4. 更新进度表、修复缺陷并生成 P0 安装包。

## 13. 下一步最优先的具体任务

如果只能先选一项，应优先完成：**接口契约 + 全局连接会话 + 模拟盒子扩展**。

理由：当前设备、批次、图库、审阅、复制和任务都依赖同一连接与协议。如果先继续堆 UI，后续接口锁定时会同时修改所有页面；先稳定连接、分页、事件和写操作格式，后续功能才能真正按进度表验收。

完成这一项后，进度表可先将 F002 标为“完成”，F003–F005 标为“进行中/待联调”，其余任务继续按本说明书推进。F017–F019 在核心闭环完成前不要标为已开始或完成。

# 拍鸟伴侣 App 前端需求与文件级实施清单（P0）

> 适用范围：只覆盖移动 App 的 Flutter 前端，不包含盒子端 Linux 服务、AI 推理、读卡、原图复制、XMP 生成等盒子端实现。  
> 整理依据：《拍鸟伴侣｜盒子端与移动 App 端需求汇总说明书》V1.0、《拍鸟伴侣 App 端需求》、前端需求进度跟踪表，以及当前 Aves Flutter 工程结构。  
> 文档目标：把产品描述拆成可以直接建文件、编码、自测和验收的小任务。

## 1. 当前项目核对结论

当前仓库主体是 Aves Flutter 相册项目，Android 目录只是宿主工程，UI 主代码位于仓库根目录的 `lib/`。

进度表中的 F001、F002 标记为“完成”，但以当前工作区为准仍需要重新验收：

- `pubspec.yaml` 中目前未看到 Dio、Bloc、Hive、WebSocket 等进度表声明的核心依赖。
- `lib/` 中未找到 `DeviceStatus`、`Batch`、`JobStatus`、`UserDecision`、`CopyJob` 等拍鸟伴侣业务模型。
- 未找到设备连接、设备状态、批次、审片、复制确认、任务中心等拍鸟伴侣专属页面。
- 当前代码仍保留完整 Aves 本地相册、媒体库、地图、编辑器等功能，不能认定“已移除全部本地相册读写逻辑”。
- Git 工作区当前是干净状态，因此这些能力不是未提交修改造成的“搜索不到”。

结论：Aves 可以作为图片网格、图片查看、主题和通用交互的参考或复用来源，但拍鸟伴侣 P0 应建立独立业务模块，避免设备端数据与 Aves 本地媒体库模型强耦合。

## 2. App 前端职责边界

### 2.1 本次必须负责

- 连接盒子热点、同局域网盒子、手动 IP；二维码连接可保留入口并根据扫码方案接入。
- 展示设备、电量、温度、容量、插卡、错误和当前任务状态。
- 展示当前批次、历史批次和批次统计。
- 分页浏览缩略图，支持分析中占位、组合筛选、排序、多选和批量操作。
- 展示鸟体框、Top-N 鸟种、置信度、评分、原因标签、EXIF、AI 原值和人工结果。
- 支持修改鸟种、评分、标签、保留状态并回写；支持待同步、失败重试和版本冲突提示。
- 支持基础 burst/scene 分组审阅。
- 支持复制策略确认、容量校验、目标盘选择和二次确认。
- 展示导入、分析、复制、同步任务并提供暂停、继续、重试、跳过失败项和日志导出入口。
- 处理空状态、加载、弱网、断线、错误、低电量、高温、拔卡、目标盘空间不足等状态。

### 2.2 不属于 App 前端

- 鸟体检测、鸟种分类、清晰度评分、分组算法等模型推理。
- 盒子端 Linux 文件系统访问、存储卡挂载、文件扫描、缩略图生成。
- 原图复制、哈希校验、XMP 写入和 Manifest 生成。
- 盒子端任务调度、断点恢复、数据库与日志服务。
- 删除相机卡原片；App 中“弃用”只是一种审阅状态。
- P0 不做账号、会员、百科、个人图鉴、云识别、NAS、高级皮肤、完整多设备管理、BLE 传图。

## 3. P0 页面和导航

主流程：

```text
启动/连接设备
  → 设备状态总览
  → 当前批次或历史批次
  → 图库浏览
  → 分组审阅或单张详情
  → 人工修改与同步
  → 复制确认
  → 任务中心/结果
```

建议状态页连接成功后使用底部导航：`设备`、`批次`、`任务`、`设置`。图库、分组、详情和复制确认作为二级页面，避免主导航项目过多。

P0 不单独做 2–4 图同步缩放的“对比审阅页”。需求总说明将其定位为手机简化、P1 增强，进度表也未列为 P0 独立任务。P0 可先在分组页提供横向大图切换和快速标记，为后续对比页预留路由。

## 4. UI 通用要求

### 4.1 视觉层级

- 设备在线、任务正常、保留使用主色或绿色；警告使用橙色；不可恢复错误和空间不足使用红色。
- “待确认”与“低置信度”必须有文字标签，不能只依赖颜色。
- “弃用”不能使用垃圾桶和“删除原片”文案，避免造成物理删除误解。
- 所有任务进度同时显示进度条和数字，例如 `1,280 / 3,200 · 40%`。
- 鸟种置信度显示百分比，低置信度附“需人工确认”。
- AI 值与人工值在详情页明确区分；人工值优先展示，但应提供“查看 AI 原始结果”。
- 手机布局优先，最小可点击区域 48dp；平板只要求基本自适应，不在 P0 做专属复杂布局。

### 4.2 每个页面都要覆盖的状态

- 首次加载：骨架屏或明确的加载提示。
- 内容正常：数据、操作入口和刷新状态完整。
- 空数据：说明为什么为空，并提供下一步操作。
- 可恢复错误：错误原因、重试按钮和返回入口。
- 断线缓存：保留已加载内容，顶部显示断线条和重连入口。
- 权限或能力不可用：说明缺失能力，不让页面卡死。

### 4.3 建议屏幕基线

- 设计基线：手机宽度 360–430dp，兼容横屏。
- 图库默认 3 列，可按屏宽变为 2–5 列。
- 缩略图使用固定比例容器和缓存图，禁止列表直接加载 RAW 或全尺寸预览。
- 大图页主体框坐标必须按原图尺寸到显示区域等比换算，并考虑 BoxFit 留白。

## 5. 页面级可执行 UI 小点

### 5.1 启动与设备连接页

页面组成：

1. 顶部品牌区：App 名称、简短说明。
2. 连接方式切换：附近设备/局域网、盒子热点、手动 IP、扫码。
3. 已发现设备卡片：设备名、IP、版本、信号、在线状态、连接按钮。
4. 手动地址表单：IP/主机名、端口、格式校验、连接中禁用状态。
5. 最近设备：上次连接信息和一键重连。
6. 连接状态：搜索中、连接中、握手校验、成功、失败、API 版本不兼容。
7. 失败提示：超时、地址无效、不在同一网络、配对失败、版本不兼容，分别给出处理建议。

验收：手动 IP 和两种 Wi-Fi 场景可进入连接流程；失败不白屏；成功后保存最近设备并进入设备页。

### 5.2 设备状态总览页

页面组成：

1. 顶部设备栏：名称、在线状态、网络方式、刷新/断开入口。
2. 全局异常横幅：高温、低电量、未插卡、读卡失败、服务错误。
3. 状态卡片：电量/供电、温度、总容量/剩余容量、卡状态。
4. 当前任务卡：任务类型、状态、数量进度、速度、当前文件、预计剩余信息（有数据时）。
5. 快捷入口：当前批次、历史批次、任务中心、诊断。
6. 无卡状态：允许进入历史批次和设置，不把整个页面锁死。
7. 实时刷新：WebSocket 事件优先，页面恢复前台时主动拉取一次。

验收：状态变化能刷新；警告有文字解释；当前任务可跳转；暂停/继续按钮只在对应状态显示。

### 5.3 批次/项目页

页面组成：

1. 当前批次置顶卡：时间、卡标识、总数、导入/分析/复核/复制进度。
2. 历史批次列表：时间、总张数、保留/弃用/待确认、任务完成状态。
3. 筛选：全部、进行中、待审阅、待复制、已完成、异常。
4. 排序：最新优先/最早优先。
5. 未完成任务恢复入口：显示恢复原因和将继续的阶段。
6. 空状态：未插卡且无历史批次时，引导连接设备和插卡。

验收：可进入正确批次图库；统计值和状态一致；分页或增量加载历史批次。

### 5.4 图库浏览页

页面组成：

1. 批次标题和统计摘要。
2. 网格：缩略图、文件序号/名、鸟种 Top1、评分、置信度、审阅状态、分组标记。
3. 分析状态占位：待分析、分析中、跳过、失败，不能混成同一种灰色块。
4. 筛选面板：鸟种、评分、置信度、清晰度、标签、保留状态、分析状态、分组。
5. 排序面板：拍摄时间、评分、置信度、保留状态；升降序。
6. 多选模式：已选数量、全选当前结果、保留、弃用、待确认、精选、标签、取消选择。
7. 批量操作结果：成功数量、失败数量、失败项入口和重试。
8. 分页加载：下拉刷新、底部加载、到底提示、加载失败重试。
9. 筛选条件保留：进详情再返回时恢复滚动位置和条件。

验收：万张数据使用分页/虚拟列表；滚动不触发全量图片解码；组合筛选结果正确；多选操作有确认和反馈。

### 5.5 分组审阅页（P0 基础版）

页面组成：

1. 分组列表/卡片：代表图、burst/scene、张数、时间跨度、Top1/Top3 推荐。
2. 组内条带：横向缩略图，推荐照片显示排名和原因。
3. 当前大图：支持缩放、左右切换、进入单张详情。
4. 快速标记：保留、弃用、待确认、精选。
5. 整组操作：整组设定状态，操作前显示影响张数。
6. 上一组/下一组，保持当前筛选条件。

验收：推荐标识清楚；整组操作可撤销；组内切换不重复请求已缓存图片。

### 5.6 单张详情页

页面组成：

1. 大图预览：缩放、拖动、加载失败重试。
2. 主体框图层：开关显示，支持多主体，框的位置随缩放正确变化。
3. 核心结果卡：当前鸟种、置信度、评分、保留状态、低置信度标记。
4. Top-N 候选：中文名为主，可展示英文/拉丁名；点击候选可作为人工鸟种。
5. 评分解释：总评分、质量/构图分（接口提供时）、清晰/模糊/主体小等原因标签。
6. 人工编辑：鸟种搜索选择、评分、标签增删、保留/弃用/待确认/精选。
7. EXIF 折叠区：拍摄时间、机身、镜头、焦距、快门、光圈、ISO、尺寸等接口提供字段。
8. AI 原始结果和版本历史折叠区：人工结果不能覆盖掉原始值的查看入口。
9. 保存状态：未保存、提交中、已同步、待同步、同步失败、版本冲突。
10. 撤销：撤销最近一次人工修改；无历史时禁用。

验收：修改重进页面后仍存在；冲突不静默覆盖；断线编辑进入待同步队列；主体框坐标准确。

### 5.7 复制确认页

页面组成：

1. 模式单选：仅保留、全量复制、双轨复制；每种模式有非技术描述。
2. 复制范围摘要：总张数、预计复制数、保留、弃用、待确认、精选数量。
3. 目标存储卡片：名称、类型、总容量、剩余容量、在线状态。
4. 空间可视化：所需空间与剩余空间；不足时红色提示并禁止提交。
5. XMP 说明：是否生成、将包含哪些人工结果；具体生成工作由盒子完成。
6. 风险提示：待确认照片是否包含、目标盘拔出风险、不会删除原卡。
7. 二次确认弹窗：再次显示模式、目标盘、张数、容量。

验收：三种模式文案无歧义；空间不足不可创建；成功后跳任务中心；重复点击不会创建多个任务。

### 5.8 任务中心/结果页

页面组成：

1. 任务筛选：全部、运行中、暂停、失败、完成。
2. 任务卡片：类型、状态、进度、完成/失败数量、速度、当前文件、开始时间。
3. 任务控制：暂停、继续、重试；取消和跳过必须二次确认。
4. 失败详情：失败项、用户可理解原因、建议动作、重试入口。
5. 完成报告：成功/失败数、复制容量、XMP 状态、耗时。
6. 日志导出：选择日志类型/时间范围，展示生成中、成功分享/保存、失败重试。
7. 断线状态：保留最后进度并标记“数据可能不是最新”，不能伪装成任务停止。

验收：事件推送后局部刷新；状态与按钮组合合法；失败项可重试；任务完成可回批次/图库。

### 5.9 设置与诊断页

页面组成：

1. 连接设置：当前方式、设备地址、自动重连、忘记设备。
2. 版本信息：App、盒子软件、API、模型、类别表、数据库 schema（接口提供时）。
3. 缓存：缩略图缓存大小、清理按钮、清理确认和结果。
4. 日志与诊断：导出日志、连接诊断、最近错误码。
5. 隐私说明：核心流程本地运行、默认不上传原图。

验收：版本值准确；清缓存不删除人工待同步操作；日志导出失败有重试。

## 6. 建议目录结构

为降低对 Aves 原代码的侵入，建议新增 `lib/bird_companion/` 独立模块，再逐步决定哪些 Aves 组件迁入或复用。

```text
lib/bird_companion/
├─ app/                 # App 入口、路由、主题和全局依赖
├─ core/                # 网络、缓存、错误、同步、通用模型与组件
└─ features/
   ├─ connection/       # 设备发现和连接
   ├─ device/           # 设备状态总览
   ├─ batches/          # 当前/历史批次
   ├─ gallery/          # 图库、筛选、多选
   ├─ review/           # 分组和单张审阅
   ├─ copy/             # 复制确认
   ├─ jobs/             # 任务中心
   └─ settings/         # 设置与诊断
```

每个 feature 统一分为：

```text
data/           DTO、数据源、Repository 实现
domain/         页面使用的业务模型、Repository 接口
presentation/   Bloc/Cubit、页面、局部组件
```

若最终团队决定继续使用 Aves 现有 Provider 状态体系，可以把下文的 `*_cubit.dart` 换成对应 `ChangeNotifier`，但不能同时混用两套全局状态方案。进度表已明确 Bloc，因此本清单按 Bloc/Cubit 拆分。

## 7. 文件级实施清单

以下路径均相对于 Flutter 仓库根目录。`新增`表示需要创建；`修改`表示在现有文件上接入。

### 7.1 工程入口与依赖

| 动作 | 文件 | 目的 |
|---|---|---|
| 修改 | `pubspec.yaml` | 增加 Dio、flutter_bloc、equatable、Hive、WebSocket、图片缓存、扫码等最终选定依赖；声明拍鸟伴侣资源。 |
| 新增 | `lib/main_bird.dart` | 拍鸟伴侣独立 Flutter 入口，避免直接启动完整 Aves 相册。 |
| 新增 | `lib/bird_companion/app/bird_companion_app.dart` | 创建 `MaterialApp.router`、主题、本地化和全局依赖。 |
| 新增 | `lib/bird_companion/app/app_router.dart` | 定义连接、设备、批次、图库、分组、详情、复制、任务、设置路由及参数。 |
| 新增 | `lib/bird_companion/app/app_shell.dart` | 连接成功后的设备/批次/任务/设置底部导航壳。 |
| 新增 | `lib/bird_companion/app/app_dependencies.dart` | 集中装配 API、缓存、Repository、Bloc，避免页面内直接 new 服务。 |
| 修改 | `android/app/build.gradle.kts` | 若采用独立 flavor，注册 bird 构建入口和应用标识；仅属于 App 打包配置。 |

### 7.2 设计系统与通用 UI

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/app/theme/app_colors.dart` | 定义品牌色、在线、警告、错误、保留、弃用、待确认、精选语义色。 |
| 新增 | `lib/bird_companion/app/theme/app_spacing.dart` | 统一 4/8/12/16/24 等间距和圆角，减少页面硬编码。 |
| 新增 | `lib/bird_companion/app/theme/app_typography.dart` | 统一标题、正文、数据数字、标签文字样式。 |
| 新增 | `lib/bird_companion/app/theme/app_theme.dart` | 组合 Material 主题、卡片、按钮、弹窗、输入框和浅深色策略。 |
| 新增 | `lib/bird_companion/core/widgets/status_badge.dart` | 统一展示在线、任务、分析、审阅、复制状态。 |
| 新增 | `lib/bird_companion/core/widgets/async_content.dart` | 统一加载、内容、空状态和错误重试布局。 |
| 新增 | `lib/bird_companion/core/widgets/disconnected_banner.dart` | 全局断线提示、最后更新时间和重连按钮。 |
| 新增 | `lib/bird_companion/core/widgets/metric_card.dart` | 设备电量、温度、容量等指标卡。 |
| 新增 | `lib/bird_companion/core/widgets/progress_summary.dart` | 统一任务进度条、数量和百分比。 |
| 新增 | `lib/bird_companion/core/widgets/confirm_action_dialog.dart` | 统一批量修改、取消任务、复制等危险或大范围操作确认。 |
| 新增 | `lib/bird_companion/core/widgets/error_notice.dart` | 统一错误码、可理解说明、建议动作和日志入口。 |
| 新增 | `lib/bird_companion/core/widgets/empty_state.dart` | 未插卡、无批次、无照片、筛选无结果等空状态。 |
| 新增 | `lib/bird_companion/core/widgets/keep_state_selector.dart` | 统一保留/弃用/待确认/精选选择器。 |

### 7.3 核心模型、网络、缓存与同步

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/core/models/device_models.dart` | 定义 Device、DeviceStatus、CardStatus 及枚举。 |
| 新增 | `lib/bird_companion/core/models/batch_models.dart` | 定义 Batch、批次统计和批次状态。 |
| 新增 | `lib/bird_companion/core/models/photo_models.dart` | 定义照片摘要、详情、预览、主体框、识别、评分、标签、EXIF。 |
| 新增 | `lib/bird_companion/core/models/review_models.dart` | 定义 Group、KeepState、UserDecision、VersionHistory。 |
| 新增 | `lib/bird_companion/core/models/job_models.dart` | 定义 JobStatus、CopyJob、目标存储、日志导出状态。 |
| 新增 | `lib/bird_companion/core/network/api_client.dart` | Dio 基础配置、baseUrl、超时、配对信息、统一响应处理。 |
| 新增 | `lib/bird_companion/core/network/api_endpoints.dart` | 集中维护临时接口路径，正式接口变化时避免全项目替换。 |
| 新增 | `lib/bird_companion/core/network/event_client.dart` | WebSocket/SSE 连接和设备、照片、任务事件流。 |
| 新增 | `lib/bird_companion/core/network/api_exception.dart` | 将网络、协议和盒子错误码映射为前端错误类型。 |
| 新增 | `lib/bird_companion/core/network/connectivity_monitor.dart` | 监听手机网络和盒子连接可达性。 |
| 新增 | `lib/bird_companion/core/storage/local_cache.dart` | Hive 初始化及最近设备、批次摘要、筛选条件和缩略图元数据缓存。 |
| 新增 | `lib/bird_companion/core/storage/pending_operation_store.dart` | 保存断线期间人工操作，独立于可清理图片缓存。 |
| 新增 | `lib/bird_companion/core/sync/pending_operation.dart` | 定义待同步操作、版本、来源、时间和重试次数。 |
| 新增 | `lib/bird_companion/core/sync/sync_coordinator.dart` | 重连后按顺序提交待同步操作并刷新权威数据。 |
| 新增 | `lib/bird_companion/core/sync/conflict_resolver.dart` | 检测版本冲突，输出需要用户选择的差异，不静默覆盖。 |
| 新增 | `lib/bird_companion/core/errors/user_message_mapper.dart` | 把错误码转换为中文提示和可执行建议。 |

模型字段在 UI 层必须通过 DTO/映射适配，禁止页面直接依赖需求文档中的临时 JSON 字段名。

### 7.4 设备连接功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/connection/data/device_discovery_source.dart` | 局域网自动发现盒子；若协议未定，先提供 mock 实现。 |
| 新增 | `lib/bird_companion/features/connection/data/connection_api.dart` | 连接、握手、版本兼容、配对和断开请求。 |
| 新增 | `lib/bird_companion/features/connection/data/connection_repository_impl.dart` | 聚合发现、手动地址、最近设备和连接结果。 |
| 新增 | `lib/bird_companion/features/connection/domain/connection_repository.dart` | 定义 UI 可使用的连接能力接口。 |
| 新增 | `lib/bird_companion/features/connection/presentation/connection_cubit.dart` | 管理搜索、输入、连接、失败、重连状态。 |
| 新增 | `lib/bird_companion/features/connection/presentation/connection_page.dart` | 设备连接主页面。 |
| 新增 | `lib/bird_companion/features/connection/presentation/widgets/connection_method_tabs.dart` | 切换局域网、热点、IP、扫码方式。 |
| 新增 | `lib/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart` | 展示发现的设备和连接操作。 |
| 新增 | `lib/bird_companion/features/connection/presentation/widgets/manual_address_form.dart` | IP/端口输入、校验和提交。 |

### 7.5 设备状态功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/device/data/device_status_api.dart` | 获取设备、卡、版本和当前任务状态。 |
| 新增 | `lib/bird_companion/features/device/data/device_repository_impl.dart` | 合并主动查询与实时事件。 |
| 新增 | `lib/bird_companion/features/device/domain/device_repository.dart` | 对 presentation 暴露状态流和刷新能力。 |
| 新增 | `lib/bird_companion/features/device/presentation/device_status_cubit.dart` | 管理首屏加载、实时刷新、异常和任务控制。 |
| 新增 | `lib/bird_companion/features/device/presentation/device_status_page.dart` | 设备状态总览页面。 |
| 新增 | `lib/bird_companion/features/device/presentation/widgets/device_header.dart` | 设备名、在线状态、网络方式和刷新入口。 |
| 新增 | `lib/bird_companion/features/device/presentation/widgets/device_metrics_grid.dart` | 电量、温度、容量和卡状态网格。 |
| 新增 | `lib/bird_companion/features/device/presentation/widgets/current_job_card.dart` | 当前任务摘要和合法控制按钮。 |
| 新增 | `lib/bird_companion/features/device/presentation/widgets/device_alert_banner.dart` | 高温、低电量、拔卡等全局告警。 |

### 7.6 批次功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/batches/data/batch_api.dart` | 分页查询当前与历史批次、恢复未完成任务。 |
| 新增 | `lib/bird_companion/features/batches/data/batch_repository_impl.dart` | 批次缓存、分页和事件刷新实现。 |
| 新增 | `lib/bird_companion/features/batches/domain/batch_repository.dart` | 定义批次列表、详情和恢复接口。 |
| 新增 | `lib/bird_companion/features/batches/presentation/batch_list_cubit.dart` | 管理筛选、排序、分页和恢复状态。 |
| 新增 | `lib/bird_companion/features/batches/presentation/batch_list_page.dart` | 当前/历史批次页面。 |
| 新增 | `lib/bird_companion/features/batches/presentation/widgets/current_batch_card.dart` | 当前批次突出展示和快捷入口。 |
| 新增 | `lib/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart` | 历史批次统计和状态展示。 |
| 新增 | `lib/bird_companion/features/batches/presentation/widgets/batch_filter_bar.dart` | 批次状态筛选和排序。 |

### 7.7 图库、筛选与批量操作

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/gallery/data/photo_api.dart` | 分页查询照片摘要、筛选选项和缩略图引用。 |
| 新增 | `lib/bird_companion/features/gallery/data/photo_repository_impl.dart` | 分页、缓存、事件增量更新和批量操作实现。 |
| 新增 | `lib/bird_companion/features/gallery/domain/photo_repository.dart` | 定义照片列表查询和批量修改接口。 |
| 新增 | `lib/bird_companion/features/gallery/domain/photo_query.dart` | 定义分页、组合筛选、排序，避免散落 Map 参数。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/gallery_cubit.dart` | 管理列表、分页、刷新、筛选和错误状态。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/selection_cubit.dart` | 独立管理多选、全选当前结果和批量提交。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/gallery_page.dart` | 图库浏览主页面。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/photo_grid.dart` | 响应式网格和懒加载触发。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/photo_tile.dart` | 缩略图、识别、评分和状态叠层。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/analysis_placeholder.dart` | 待分析、分析中、跳过、失败的差异化占位。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart` | 鸟种、评分、置信度、清晰度、标签和状态组合筛选。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/sort_sheet.dart` | 时间、评分、置信度和保留状态排序。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart` | 多选数量和批量审阅操作栏。 |
| 新增 | `lib/bird_companion/features/gallery/presentation/widgets/batch_operation_result.dart` | 展示批量成功/失败项和重试入口。 |

可评估复用 Aves 的网格滚动、缩略图和图片查看实现，但应迁移成只依赖 `PhotoSummary`/URL 的组件，不能继续依赖 Android MediaStore、本地路径或 Aves 数据库 Entry。

### 7.8 分组审阅与单张详情

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/review/data/review_api.dart` | 查询组、照片详情、版本历史，提交单张/整组人工结果。 |
| 新增 | `lib/bird_companion/features/review/data/review_repository_impl.dart` | 详情缓存、人工回写、撤销和冲突转换。 |
| 新增 | `lib/bird_companion/features/review/domain/review_repository.dart` | 定义分组、详情和人工审阅接口。 |
| 新增 | `lib/bird_companion/features/review/presentation/group_review_cubit.dart` | 管理组分页、组内切换、整组操作和撤销。 |
| 新增 | `lib/bird_companion/features/review/presentation/group_review_page.dart` | P0 分组审阅页面。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/group_card.dart` | 代表图、组类型、张数、Top 推荐和原因。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/group_photo_strip.dart` | 组内横向缩略图与排名。 |
| 新增 | `lib/bird_companion/features/review/presentation/photo_detail_cubit.dart` | 管理详情加载、编辑草稿、保存、待同步、撤销和冲突。 |
| 新增 | `lib/bird_companion/features/review/presentation/photo_detail_page.dart` | 单张审阅详情页。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart` | 大图和一个/多个主体框叠加，处理缩放坐标。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/recognition_panel.dart` | Top-N、置信度和低置信提示。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/rating_reason_panel.dart` | 评分、清晰度和原因标签。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/review_editor.dart` | 鸟种、评分、标签和保留状态编辑。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/exif_panel.dart` | EXIF 折叠展示。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/version_history_panel.dart` | AI 原值、人工修改和版本历史。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/sync_state_indicator.dart` | 已同步、待同步、失败、冲突状态。 |
| 新增 | `lib/bird_companion/features/review/presentation/widgets/conflict_dialog.dart` | 展示本地与盒子端差异，让用户明确选择。 |

### 7.9 复制确认功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/copy/data/copy_api.dart` | 获取目标存储/容量估算并创建复制任务。 |
| 新增 | `lib/bird_companion/features/copy/data/copy_repository_impl.dart` | 复制预估、幂等提交和错误映射。 |
| 新增 | `lib/bird_companion/features/copy/domain/copy_repository.dart` | 定义复制预估和任务创建接口。 |
| 新增 | `lib/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart` | 管理模式、目标盘、估算、校验和提交。 |
| 新增 | `lib/bird_companion/features/copy/presentation/copy_confirmation_page.dart` | 复制确认主页面。 |
| 新增 | `lib/bird_companion/features/copy/presentation/widgets/copy_mode_card.dart` | 三种复制模式解释和选择。 |
| 新增 | `lib/bird_companion/features/copy/presentation/widgets/storage_target_card.dart` | 目标盘状态、容量和选择。 |
| 新增 | `lib/bird_companion/features/copy/presentation/widgets/copy_scope_summary.dart` | 复制范围、审阅状态和预计容量摘要。 |
| 新增 | `lib/bird_companion/features/copy/presentation/widgets/copy_confirm_dialog.dart` | 创建任务前二次确认，阻止重复提交。 |

### 7.10 任务中心功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/jobs/data/job_api.dart` | 查询任务、控制任务、查询失败项和请求日志包。 |
| 新增 | `lib/bird_companion/features/jobs/data/job_repository_impl.dart` | 合并任务列表查询和实时事件。 |
| 新增 | `lib/bird_companion/features/jobs/domain/job_repository.dart` | 定义任务查询、控制、重试和日志接口。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/job_center_cubit.dart` | 管理任务筛选、实时进度和控制结果。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/job_center_page.dart` | 任务中心列表页。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/job_detail_page.dart` | 任务详情、失败项和完成报告。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/widgets/job_card.dart` | 任务摘要、进度和合法操作。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/widgets/job_failure_list.dart` | 失败项、原因、重试和跳过。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/widgets/job_result_summary.dart` | 完成数量、失败数量、容量、XMP 和耗时。 |
| 新增 | `lib/bird_companion/features/jobs/presentation/widgets/log_export_dialog.dart` | 日志类型/时间范围选择及导出状态。 |

### 7.11 设置与诊断功能

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `lib/bird_companion/features/settings/presentation/settings_page.dart` | 连接、缓存、版本、隐私入口。 |
| 新增 | `lib/bird_companion/features/settings/presentation/diagnostics_page.dart` | 连接诊断、错误码、版本和日志导出。 |
| 新增 | `lib/bird_companion/features/settings/presentation/settings_cubit.dart` | 加载版本/缓存信息，执行忘记设备和安全清缓存。 |
| 新增 | `lib/bird_companion/features/settings/presentation/widgets/version_info_card.dart` | 展示 App、盒子、API、模型和 schema 版本。 |
| 新增 | `lib/bird_companion/features/settings/presentation/widgets/cache_management_card.dart` | 展示/清理图片缓存，明确不清除待同步操作。 |

### 7.12 假数据、资源和测试

| 动作 | 文件 | 目的 |
|---|---|---|
| 新增 | `assets/bird_companion/mock/device_status.json` | 设备页未联调前的正常/告警状态假数据。 |
| 新增 | `assets/bird_companion/mock/batches.json` | 批次列表和各种进度状态假数据。 |
| 新增 | `assets/bird_companion/mock/photos.json` | 图库、分析中、低置信、失败和不同审阅状态假数据。 |
| 新增 | `assets/bird_companion/mock/groups.json` | burst/scene 分组和推荐排序假数据。 |
| 新增 | `assets/bird_companion/mock/jobs.json` | 运行、暂停、失败、完成任务假数据。 |
| 新增 | `test/bird_companion/core/model_mapping_test.dart` | 验证临时接口字段到 UI 模型的映射和缺字段兼容。 |
| 新增 | `test/bird_companion/core/sync_coordinator_test.dart` | 验证离线队列、重试、顺序和冲突分支。 |
| 新增 | `test/bird_companion/features/connection_cubit_test.dart` | 验证搜索、连接、超时、失败和重连状态。 |
| 新增 | `test/bird_companion/features/gallery_cubit_test.dart` | 验证分页、组合筛选、去重和事件更新。 |
| 新增 | `test/bird_companion/features/photo_detail_cubit_test.dart` | 验证编辑、保存、离线、撤销和冲突。 |
| 新增 | `test/bird_companion/features/copy_confirmation_cubit_test.dart` | 验证三种模式、空间不足和防重复提交。 |
| 新增 | `test/bird_companion/features/job_center_cubit_test.dart` | 验证任务状态与可用按钮组合。 |
| 新增 | `test/bird_companion/golden/` 下各核心页面截图测试 | 固定正常、空、错误、断线、警告等关键 UI 状态。 |
| 新增 | `integration_test/bird_companion_p0_flow_test.dart` | 验证连接→批次→图库→修改→复制→任务的 P0 闭环。 |

## 8. 重新拆分后的可执行任务顺序

### P0-A：工程与可演示 UI 骨架

1. 创建独立入口、路由、主题和底部导航。
2. 建立核心模型和 mock 数据。
3. 建立所有页面空壳，跑通完整路由。
4. 完成通用状态、空状态、错误、断线和确认弹窗组件。

交付结果：不依赖盒子接口也能演示完整 P0 页面流。

### P0-B：连接、设备和批次

1. 接入连接握手和版本检查。
2. 完成设备状态查询与事件刷新。
3. 完成当前/历史批次分页。
4. 完成未插卡、高温、低电量、读卡失败、断线重连 UI。

交付结果：能连接盒子并进入正确批次。

### P0-C：图库和审阅

1. 接入照片分页、缩略图和分析状态事件。
2. 完成筛选、排序、多选和滚动状态恢复。
3. 完成基础分组审阅。
4. 完成详情大图、主体框、Top-N、评分原因、EXIF、历史。
5. 完成人工编辑、批量编辑、撤销、离线队列和冲突弹窗。

交付结果：能在高张数批次中完成审片并可靠回写。

### P0-D：复制、任务和诊断

1. 接入目标存储和容量估算。
2. 完成三种复制模式和二次确认。
3. 完成任务列表、实时进度、控制、失败项、完成报告。
4. 完成日志导出、版本和安全清缓存。

交付结果：能创建复制任务并追踪到完成或可恢复失败。

### P0-E：性能与验收

1. 使用至少 10,000 条照片摘要数据做分页和滚动测试。
2. 验证缩略图缓存、列表回收和大图内存释放。
3. 覆盖断网、后台恢复、拔卡、拔目标盘、空间不足、版本冲突。
4. 完成核心 Cubit、Widget/Golden 和端到端测试。
5. 打包前复核所有“弃用”文案均不暗示删除原片。

## 9. 前后端联调前必须锁定的契约

这些问题不阻塞前端先用 mock 制作 UI，但正式联调前必须由双方确认：

1. 盒子发现方式：mDNS、UDP 广播还是固定热点地址。
2. HTTP 基础地址、API 版本协商、设备身份和配对/授权方式。
3. 实时通道使用 WebSocket 还是 SSE，断线重连和事件补偿机制。
4. 分页方式：page/pageSize、offset/limit 或 cursor；筛选排序由盒子完成还是 App 本地完成。
5. 缩略图/预览图鉴权、尺寸档位、缓存键和失效策略。
6. `bbox` 坐标格式：像素还是归一化、原图方向是否已应用、多主体结构。
7. 鸟种数据：中文名、英文名、拉丁名、类别 ID、模型版本和 Top-N 数量。
8. 人工回写的版本字段、幂等键、批量部分失败格式和撤销能力。
9. 复制三种模式的精确定义，特别是“双轨”的目录/范围规则和待确认项处理。
10. 任务可执行动作矩阵：什么状态允许暂停、继续、取消、重试、跳过。
11. 日志包是返回下载地址、文件流还是系统分享所需文件。
12. 错误码表及用户可见/仅诊断字段的边界。

## 10. P0 前端最终验收清单

- 能通过热点、局域网或手动地址建立连接，并正确处理超时和版本不兼容。
- 设备状态、电量、温度、容量、卡状态、当前任务和异常会刷新。
- 当前及历史批次可分页查看，未完成批次有恢复入口。
- 图库能分页展示大量缩略图，分析中和失败状态清楚。
- 组合筛选、排序、多选和批量操作可用，返回列表保持位置。
- 分组页能展示推荐并进行单张/整组快速标记。
- 详情页能正确展示主体框、Top-N、评分原因、EXIF 和版本历史。
- 鸟种、评分、标签和保留状态可修改；断线可排队；冲突不静默覆盖。
- 复制前能看懂复制范围、目标盘和容量；空间不足禁止提交；创建操作幂等。
- 任务中心能显示实时进度，合法地暂停、继续和重试，失败原因可追踪。
- 所有核心页面都有加载、空、错误、断线和重试状态。
- App 不加载 RAW 原图、不直接访问盒子文件目录、不删除相机卡原片、不覆盖 AI 原值。

## 11. 后续版本预留但不进入 P0

- P1：BLE 发现/配网、2–4 图同步对比、断点续传增强、平板专属布局、模型/软件升级、复制校验详情。
- P2：云端增强识别、鸟类百科、个人图鉴、用户偏好、账号/会员、NAS、OTA 和多设备管理。


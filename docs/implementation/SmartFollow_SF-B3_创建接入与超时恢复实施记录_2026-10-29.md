# SmartFollow SF-B3：两条创建路径、运行页接入与超时恢复

日期：2026-10-29（Asia/Shanghai）。基线：`thirdtime / c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`，延续 SF-B0～SF-B2 工作区。对应乙 E4 与 R3 的 App 集成接缝。

**SF-B3 App 侧已完成：两条创建路径、导入接续、会话接管、持久化请求与运行页恢复已接通。最终关联回归 561 通过 / 1 跳过 / 0 失败，静态分析无问题。** 未提交 Git、构建 APK 或连接真实盒子；正式后端幂等和设备验收仍须联调确认。

## 1. 两条创建路径

| 进入时机 | 实际行为 |
| --- | --- |
| 本批次尚未识别 | 单次 analysis-jobs 请求携带完整 smart_follow DTO，由后端原子创建分析任务和会话；App 不再顺序创建第二个跟随会话 |
| 已有正在运行的识别 | 复用 SmartFollowRepository.startOnRecognitionJob；已有会话或 ALREADY_ACTIVE 时接管原会话 |
| 导入前选了识别并复制 | 保存本地已确认配置并绑定新批次；导入完成后重新校验设备、能力、源卡绑定有效期、策略版本和识别阶段，再走相同原子创建服务 |
| 创建结果未知 | 持久保留原请求，提供“查询原请求”和“用原请求重试”；重进页面后也可查询；识别先结束时仍保留查询入口 |
| 成功或接管 | 进入返回的同一个 sessionId；运行页通过会话读取 recognitionJobId，重进任务详情时先发现已有会话 |

配置确认和真正开始仍是两个操作。开始前重新核验 SF-B2 的不可变意图；过期、换盘、源卡变化、偏好版本或空间变化时拒绝提交并清除旧确认，要求重新核对。离开页面、退后台、读取器替换或盒子上下文变化后，尚未发出的请求不能继续写入。

复制范围页、开始识别对话框和 AI 分析详情均接入正式开始按钮。普通 recognized_assets、选中/筛选复制、整批复制和全量备份保留原有范围与固定快照语义。

## 2. 幂等与超时处理

新增 SmartFollowCreationService 只保存 App 的创建意图，不维护复制队列：

- 原子创建在发送前持久化随机稳定键、原 DTO、源卡身份、批次和已有任务基线；同一次未决意图不得更换键或参数。
- 运行中开启仍使用已有仓库的 follow-start-jobId 规则；同 job 的并发请求合并，未决参数冻结。
- 本地持久化失败时不 POST。创建响应丢失后先读现有 jobs 分页、job detail、recognition-events 关联与会话详情；校验批次、识别任务，以及原子路径的目标盘归属。
- 查询不能确认、候选不唯一、分页异常、返回错误归属、已有分析但尚无会话关联时，保持结果未知，不显示创建成功，也不额外创建普通分析/复制任务。
- 用户明确重试且原请求仍可安全校验时，只重放同键同参数；有未决跟随时，切回“仅识别”也不能绕过它另建分析任务。
- 导入后的自动接续只尝试一次创建；后续自动恢复只查询，不周期性 POST。配置不再有效时等待用户从入口重新确认；不降级为普通识别。
- 明确拒绝的 4xx（不含结果可能未定的 408/409）允许结束该未决请求；409/超时/断连等不通过换键重建来处理。

本批没有发明按请求键查询的新接口。原子响应沿用现有平铺 job 数据与 smart_follow_session_id；缺失关联时使用现有查询兜底。**jobs 的唯一候选与事件关联不是后端按幂等键查询的正式保证**，查询不足时只能保留待确认。正式后端仍需确认原子事务、唯一约束、幂等重放及跨端查询保证。

源卡 token/策略版本仍作为 App 本地校验上下文；未收到正式契约前，不自行给 smart_follow 请求增加目标绑定/偏好版本等 wire 字段。

## 3. 运行页与恢复

- 生产路由注入实际 jobs detail 读取，识别 processed/total 随权威任务刷新，不再固定为打开页面时的路由数字；不以 eligible 代替已处理数。
- 前台且路由可见时补拉：正常间隔 4 秒，失败按 8/16/32/60 秒退避，上限 60 秒；进入后台或打开子任务详情时暂停，返回/恢复前台立即补拉。
- 重连刷新信号会补读；同一页面的并发刷新合并。WS 仍由既有仓库唤醒会话重读，不直接拿事件数字改计数。
- 读取失败时保留并标明上次状态、禁用旧动作；空态提供重读。页面销毁后取消定时器和订阅，不继续更新 UI。
- 换盒子时仓库推进设备代次，旧能力、读取、创建和动作响应不能回填新盒子；旧请求完成也不能删除新盒子同 ID 的进行中读取。创建配置和运行路由同样核验代次。
- 识别结束且队列仍排空时保留 draining；不因分析完成事件自动跳相册并把复制流程误作完成。已有会话可从任务入口重新进入。

定时器只负责 REST 补拉和退避，不制造进度、累计计数或复制队列。完成结果页及信息更新页面仍属于 SF-B4～SF-B6。

## 4. 主要改动

新增：

- entry/smart_follow_creation_service.dart：两路径协调、确认复核、本地持久化、查询与重试、导入配置暂存。
- entry/smart_follow_start_panel.dart：显式开始、结果未知、原请求查询/重试，以及识别结束后仍可用的查询组件。

接线与最小扩展：

- app_dependencies、app_router：共享创建服务、设备代次、运行页真实任务读取及恢复信号。
- AnalysisJobRequest / JobApi：只向 transport 传幂等键，不改变请求 JSON；BirdJobStatus 保留可选 smart_follow_session_id，避免创建响应丢失关联。
- entry 配置意图、模式入口及 recognition_widgets：本地意图序列化、正式创建面板与导入前完整配置回传。
- RepositoryTaskExperienceController / TaskExperienceRoot：导入后复核、禁止裸 Map 绕过、未决请求防重复、已有会话导航与分析完成时的跟随保护。
- SmartFollowRepository：在原仓库上补并发创建合并、原参数冻结和设备代次隔离；保留原版本合并、动作白名单及已有会话恢复规则。
- SmartFollowRunPage：前台/路由恢复、退避、真实识别进度、旧状态提示与失败重读。

没有修改后端、数据库、OLED、复制子任务清单或真实文件写入逻辑；没有新增接口路径、会话状态或动作。

## 5. 验证

| 检查 | 最终结果 | 证据（build/smart-follow/sf-b3/） |
| --- | --- | --- |
| 本批新增用例 | 40 项，均纳入最终回归 | 创建服务 19、设备隔离 6、运行恢复 7、创建交互 5、HTTP 请求 1、任务控制器 2 |
| 关联回归 | **561 通过 / 1 跳过 / 0 失败**，退出码 0 | related-tests-final.log、related-tests-final-result.json |
| 全仓静态分析 | **No issues found**，退出码 0 | analyze-final.log、analyze-final-result.json |
| 改动文件格式 | **累计 34 个 Dart 文件，0 changed**，退出码 0 | format-check.log、format-check-result.json |
| Git 空白检查 | 通过，退出码 0 | diff-check.log、diff-check-result.json |
| 中文大字号布局 | 360dp、1.5 倍文本，已查看渲染图，无布局异常 | creation-pending-360dp-150pct.png；本地 widget 渲染，不是真机截图 |

关联回归覆盖 SmartFollow、recognition、copy、两组 tasks、jobs 路由、统一导航及复制设置。相比 SF-B2，增加 40 个本批用例，并扩大到已有 jobs 路由测试；唯一跳过项仍为未配置 BIRDBOX_CONTRACT_BASE 的外部 Python HTTP 契约服务。

本地 HTTP 验证分两层：

1. loopback HTTP 验证完整 analysis 请求、稳定 Idempotency-Key 头、两个 ID 保留和普通分析请求兼容；不把 HTTP stub 的重放响应当成服务端幂等证明。
2. 项目现有 MockBoxServer 验证导入完成后实际发出原子分析创建、关联同一会话、再次刷新不产生第二条分析。该 mock 没有 RC3 /storage/source，本用例的设备配置明确使用强类型 fixture；导入、jobs、SmartFollow 会话查询走真实 HTTP。没有为测试擅自新增后端接口。

初轮测试暴露的 Future 清理回调循环等待、测试 fixture、旧源码单行断言和格式问题已处理。最终回归通过后仅补齐一处分支大括号，行为不变，并重新完成静态和格式检查。最终结论以上表日志为准，早期日志仅供诊断。

机器可读证据：build/smart-follow/sf-b3/evidence.json，含最终日志、截图及累计 Dart 改动哈希。build 被 Git 忽略，移交需另行携带。本批未执行全量 Flutter 测试、Android 原生测试、APK 构建或真实设备/正式后端验收。

## 6. 下一批

**SF-B4：完成结果页（C1）**。补 completed / completed_partial / failed 结果、完整分页与子任务报告、识别和复制的分项统计、缺失字段提示，并接上运行页 onOpenCompletion。不得把 draining、单个子任务完成或缺字段的默认零值当作整体完成。

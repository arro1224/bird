# SmartFollow SF-B7：验收矩阵与遗留清单

日期：2026-10-29。对应 App 修改任务书 §11 十五条及两人分工书 §11、§12。本文登记本次实际结果，不代替后端回执。

**本地 App 回归通过，真实联合验收尚未通过。第 13 条还有明确的 App 接线缺口，需先取得普通 CopyJob 与信息更新会话的关联协议再补适配。** 其余涉及真实队列、写盘、进程退出续跑及 OLED 的行为也不能由 fixture 签字。

## 1. 证据层级

- L：真实 App 类的单元、组件、仓库和路由测试；F：内存 fake 后端；H：实际 HTTP 客户端连接受控 mock server。这三类均属本地自动化。
- E：Android 14 / API 34、x86_64 隔离模拟器，安装本次 Normal Debug APK、两次冷启动及版本检查；只验证安装启动，不验证 SmartFollow 全流程。
- R：正式接口、真实手机、盒子、目标盘、OLED 联合验收。本次未执行，不能用 E 或 F/H 替代。
- 下表“通过”仅指本地栏；“未通过”表示联合验收未达到，可能因待实测，也可能有明确缺口，原因分列。

完整日志位于 `build/smart-follow/sf-b7/`。本次默认 `test/` 全量结果 **1606 通过 / 3 跳过 / 0 失败**；不包含 `integration_test/` 设备驱动。

## 2. 十五条逐项对照

测试路径以下均相对仓库根；`SF/` 表示 `test/bird_companion/features/smart_follow/`。

| # | 验收要求 | 本地结果与证据 | 联合结果及仍需验证的内容 |
| --- | --- | --- | --- |
| 1 | 未开始时识别并复制，不产生两个独立流程 | **通过 L/H**：`SF/entry/smart_follow_creation_service_test.dart`、`SF/smart_follow_atomic_http_test.dart`；一个 analysis POST 携带 smart_follow，稳定幂等键，非顺序创建两任务 | **未通过 R**：需正式后端证明原子提交、唯一会话及崩溃恢复 |
| 2 | 识别中 SmartFollow / 当前结果选择不同 | **通过 L**：`SF/entry/smart_follow_modes_test.dart`、`smart_follow_entry_decision_test.dart`；演示帧 01/02 | **未通过 R**：真机接正式能力响应检查入口与请求 |
| 3 | 首张 high＋有效鸟种 committed 后即可进入复制 | **通过 F/L**：`SF/fake_smart_follow_backend_test.dart`、`smart_follow_repository_test.dart`、`smart_follow_run_page_test.dart` 验证逐张入队及权威快照展示 | **未通过 R**：真实 committed 事件、持久队列与首张延迟未测；App 不自行判断资格 |
| 4 | medium / unknown / reject / exception / 未处理不入复制数 | **通过 F/L**：fake eligibility 负向用例、会话数字展示；不在页面按置信度计算数量 | **未通过 R**：需真实分类样本及后端筛选结果，fake 不能证明真实 Pipeline |
| 5 | 新结果进新 child，不修改旧清单 | **通过 F/L**：`SF/fake_smart_follow_backend_test.dart` 子任务清单冻结与后续封批用例；仓库按 ID 读取 | **未通过 R**：真实 CopyJob manifest 不变、重启后不重复执行尚待核验 |
| 6 | App 退出重开，任务身份/数量/进度恢复 | **通过 L/H**：`SF/smart_follow_run_recovery_test.dart`、`smart_follow_device_isolation_test.dart`、`finish/smart_follow_metadata_update_controller_test.dart`；生命周期补拉、设备隔离、持久化抽象找回原 ID | **未通过 R**：手机杀进程/断电、Hive 真实落盘、App 离线时盒子持续执行待测；E 的启动不包含任务恢复 |
| 7 | 创建超时重试不产生双任务 | **通过 L/H**：两条创建路径、稳定键和原始请求体、连点合并、响应丢失后查询、未知结果不盲建；`SF/entry/smart_follow_creation_service_test.dart`、`SF/smart_follow_atomic_http_test.dart`、仓库测试 | **未通过 R**：正式幂等记录、跨端唯一性、查询覆盖范围和保留期待回执 |
| 8 | 拔盘等待、原盘恢复、错盘阻止 | **通过 F/L**：配置控制器身份确认、fake 等待恢复、`SF/smart_follow_stage_test.dart` 与换设备隔离 | **未通过 R**：物理热拔插、真实介质身份、剩余空间及 allowed_actions 需实测 |
| 9 | Copy 快于 Recognition 时等待新结果 | **通过 L/F**：运行页、stage、fake 测试；不会用当前队列为空推断会话完成 | **未通过 R**：真实队列空闲与后续结果进入的连续场景待测 |
| 10 | Recognition 快于 Copy 时排空后才完成 | **通过 L/F**：运行恢复、完成控制器/正式导航测试；演示帧 05/06/07 | **未通过 R**：真实剩余队列及最终统计收敛待测 |
| 11 | 信息开关与 committed 快照；变化先提示，确认再更新 | **通过 L/H/F**：配置请求 review_export；`SF/finish/smart_follow_metadata_*_test.dart`、`smart_follow_metadata_update_*_test.dart` 验证预览、部分授权、过期重取、父任务、报告及再次变化；未确认零创建 | **未通过 R**：committed 信息版本冻结、关闭时零物理写入、真实副本安全更新和部分失败待测 |
| 12 | recognized_assets 保持确认时冻结快照 | **通过 L/H**：`SF/entry/smart_follow_modes_test.dart` 及 `test/bird_companion/features/copy/` 全目录回归；普通复制不创建跟随会话 | **未通过 R**：正式复制清单需用确认后新识别结果验证不扩大 |
| 13 | batch_all_assets 先全复制，识别后只更新信息 | **部分通过 L**：普通 scope 和不等待识别行为保留，模式测试覆盖；**后续信息提示/预览/父任务对普通 CopyJob 的接线未完成** | **未通过，存在 App 缺口**：现有 M1～M3 只接受 SmartFollowSession；缺普通 CopyJob 到该会话/更新上下文的正式映射。不得编造 sessionId、端点或用重复制模拟更新。取得协议后补普通结果页入口/上下文适配与测试，再验物理零重复制 |
| 14 | App/OLED 同一任务数字一致、不重复创建 | **通过 L/H（App 部分）**：权威 GET、事件只唤醒重读、旧版本与重复响应保护、已存在会话接管；仓库与创建服务测试 | **未通过 R**：OLED 端 ID、状态、数量和跨端并发创建未测 |
| 15 | capability=false 的旧盒子无可执行入口 | **通过 L/H**：`SF/entry/smart_follow_entry_decision_test.dart`、模式/配置/metadata 测试覆盖 false、缺失、404、失败；无可执行创建或更新 | **未通过 R**：正式旧固件/能力 true、false 响应与发布开关待测 |

## 3. 必须保留的 App 后续项

1. **第 13 条接线**：对方确认普通 `batch_all_assets` 的信息更新上下文、关联查询和授权接口；App 补普通复制完成后的信息可更新提示，复用 M2/M3，验证不新增照片 CopyJob。它属于待补 App 工作，不仅是设备测试。
2. 正式字段回执后收敛适配：当前覆盖/待确认等未确认统计显示“未提供”，关键预览字段不足时禁止授权；不能为了画完整页面补零。
3. 取得真实环境后执行上表 R 项，特别是两条创建路径的响应丢失、杀进程恢复、目标热拔插、部分信息更新与 OLED 对账。失败时按实际结果补 App 适配，不预签通过。
4. 补真实连续流程录屏。本次交付 13 帧组件演示 GIF，逐页挂载 fixture，明确标识本地演示；它不是一次连续的 App 操作录像。

## 4. 字段问询单十项对账

本次提供的问询单仍是未勾选草稿，**没有收到对方正式答复**。下表“待回执”是证据状态，不是替对方选择选项。

| # | 问询项 / 对方答复 | App 现状与联调影响 |
| --- | --- | --- |
| 1 | capability 名称：待回执 | 既有强类型兼容解析；incremental 与 copy 总门控，metadata 单独门控；缺失/false/404 不开放执行 |
| 2 | 错误码前缀：待回执 | 沿现有错误映射与安全兜底；未知错误不当成功，正式表到齐后收敛别名 |
| 3 | 动作集合：待回执 | 仅现有 pause、resume、finish_current_results、stop_following、retry；按 allowed_actions；不新增 cancelled 状态或 resume_recognition |
| 4 | 识别已处理/总数：待回执 | 从关联 RecognitionJob 权威快照读取；不拿 eligible 代替 processed；与会话分开刷新 |
| 5 | 活动会话发现：待回执 | 复用现有 job 关联与 recognition-events 的 smart_follow_session_id；不新增列表查询；正式全量可发现性/超时查回保证仍待确认 |
| 6 | 信息更新与部分确认：待回执 | M1～M3 已在现有 DTO/API 上完成本地路径；能力/真实 availability 不满足禁操作。普通全量复制的上下文另有第 13 条缺口 |
| 7 | 完成页统计：待回执 | 读完全部 child 分页，去重；子任务终态且报告完整才给最终汇总；缺失、冲突、未知状态不报全部成功 |
| 8 | 事件与版本：待回执 | 事件仅触发权威补拉，保留 event_seq/state_version 保护；正式六类事件 schema、重放规则及样本待提供 |
| 9 | 等待态和动作：待回执 | 消费后端状态/原因/allowed_actions；拔盘、错盘、空间不足的正式响应待核验 |
| 10 | 专属协议头：待回执 | 沿 Authorization、X-Api-Version 和写入幂等键；没有自行新增 smart-follow-v1 头 |

## 5. 契约与发布门禁

仓库冻结契约为 `birdbox-v1@1.0.0` / API v1，OpenAPI 3.1.0；`docs/contracts/birdbox-v1-freeze.json` 和现有 schema 校验通过。**此检查只证明仓库既有冻结材料一致，不能证明 SmartFollow 扩展正式 OpenAPI/事件已冻结。** SmartFollow 当前消费既有 App 实现与联合任务书语义，扩展版本待正式回执。

`--strict-baseline` 实测失败 **13 项**：baseline.status 仍为 blocked_external_inputs；缺 box.repository、branch、firmware_sha、deployment_command、database_schema_version、database_migration、database_rollback、integration_base_url；缺 owners.protocol、flutter_core、box_api、qa_release 四个 contact。保留原值，没有填假信息绕门禁。

三项全量跳过为 2 项 Direct AP Python 环境测试和 1 项 Python Copy 契约测试，分别需要 BIRDBOX_DIRECT_AP_BASE、BIRDBOX_CONTRACT_BASE；现有 Python fixture 还依赖外部 BIRDBOX_BACKEND_ROOT。本次没有该环境，未以 Dart mock 冒充通过。

本次可交付 **Normal Debug 联调包**，不满足正式 Release 门禁。后端仍应在实现并验收前保持真实 capability=false；App 没有强开能力、注入假进度或擅自部署后端。

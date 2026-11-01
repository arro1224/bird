# SmartFollow SF-B6：信息更新父任务与报告（M3）

日期：2026-10-29（Asia/Shanghai）。分支 `thirdtime`，HEAD `c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`；延续 SF-B0～SF-B5 工作区。

**SF-B6 App 侧已完成。SF-B5 原只读回执已替换为正式父任务页面，支持父子结果、历史重进、原 RC3 详情及再次信息变化后的预览确认。最终关联回归 710 通过 / 1 跳过 / 0 失败，全仓静态分析无问题。** 本地验证不代表真实盒子安全写盘或正式后端验收已完成。

## 1. 正式页面与状态

- 新增 `presentation/finish/smart_follow_metadata_update_controller.dart` 和 `smart_follow_metadata_update_page.dart`。
- 本地路由 `/smart-follow-metadata-update` 接受原 sessionId、可选 updateId 和设备身份。SF-B5 新建任务成功、已有任务入口、历史任务入口均进入此页。
- 路由只带 sessionId 时，从已有 session/availability 或已知历史发现原 update ID；不创建任务找回进度。指定 ID 固定查看该报告，不会因为后来出现另一个 active ID 而替换旧报告。
- 展示等待、运行、完成、部分完成、失败、已取消；未知父/子状态显示“状态待确认”，继续读取，不推断终态。
- 页面展示父任务统计、原复制会话状态、子 MetadataUpdateJob 对应的原 CopyJob、错误/受阻原因及已知更新历史。更新任务不会改写已结束的复制会话。
- 父任务显示 completed 但子任务失败、失败/受阻项大于零时，按部分更新呈现。父任务终态但子任务尚在运行时提示报告待补齐，不能作为完整结果。

## 2. 报告数据与完整性

沿用已有 `GET /api/v1/smart-follow-metadata-updates/{update_id}` 响应作为任务及报告来源。没有另造 report 端点或专用 MetadataUpdateJob 详情接口；原 CopyJob 按已提供的对应 ID 打开现有 RC3 页面，并绑定原设备。

| 内容 | 来源及规则 |
| --- | --- |
| 子任务数、更新照片/文件、失败、不变、受阻 | 父任务 DTO 既有字段及原有别名；新增存在性标记，只认非负整数，缺失显示“未提供” |
| 子更新文件、失败文件 | 子 DTO 既有文件统计；不使用默认 0 证明成功 |
| 原复制批次 | 子项的 copy_job_id / 原有 source_copy_job_id 对应关系；缺失时禁用详情入口 |
| 原因 | 父 error_message / error_code；子可选 error_message / error_code；未提供具体原因时明确显示缺失 |
| 完整最终报告 | 父任务终态、子列表明确提供、按 metadata_update_id 去重后数量吻合、子任务均终态、关键统计与映射齐全且无已知矛盾 |

异常列表或非对象子项不再被静默过滤为成功结果。相同子任务重复返回时去重；内容冲突、父子已更新文件数不一致、无子任务却非零更新结果均提示核对。失败项/受阻项尚未冻结为照片或文件的统一口径，因此使用“项”，不将其与子失败文件数强行相加比较。

照片用“张”，文件用“个”。运行中数字仅表示当前返回的事实，不生成百分比或按时间增加进度。未知状态、缺字段和报告读取失败都不会显示成“全部信息保存成功”。

## 3. 恢复与历史

- 前台且路由可见时每 4 秒读取原任务；失败按 8/16/32/60 秒退避。打开其他页面或进入后台暂停周期读取，返回、恢复前台和连接刷新信号立即补拉。
- 同页并发刷新合并，页面销毁清理计时器、事件订阅和监听。换盒子时核对设备代次、ID、地址和连接状态，隐藏旧事实并拒绝旧响应回填。
- 仓库对明确给出 state_version 的父任务快照防止旧版本回退；没有明确版本时不虚构版本顺序。
- 创建成功或识别到已有 active ID 时，把已知父任务 ID 保存到原 LocalCache，按设备和会话分开；串行合并历史引用，去重且保留先前任务。不保存本地写入队列，不做自动提交或自动重试写入。
- 后端 active ID 消失后，仍可按已知 ID 查看历史报告；缺少 updateId 时可恢复最近已知任务。没有本地记录且无法从已有 session/availability 证明关联时，只提示重新读取，不任意认领另一个父任务。
- 读取失败保留并标明上次结果，禁用依赖最新状态的入口。刷新只读取原任务，不重建父任务，不重复制或回滚已经成功的副本。

## 4. 完成后再次出现信息变化

父任务结束后重新读取能力和真实 metadata availability，后续前台读取也继续检查。旧报告成功不永久清除“有新信息可更新”的事实。

- capability=false：历史报告仍可查看，隐藏再次更新操作。
- availability 暂不可读：报告保留，单独提示变化状态未确认，不启用新写入入口。
- availability=false：提示当前无新的可更新信息，后续变化仍会检查。
- availability=true 且没有其他活动父任务：提供“预览新的信息更新”，进入 SF-B5 的完整预览与最终确认流程，不直接 POST 创建。
- availability 返回另一个 active ID：提供查看当前任务，当前旧报告和历史链接保持原 ID。

M1 同步调整：已返回终态且没有未结束子任务的旧 active ID 不再永久挡住新预览；原报告入口继续保留。若子任务仍未结束或状态未知，仍按原活动任务处理。

没有新增 revision 字段或在 App 自行比较未确认的 revision 编号；“更晚信息可更新”由真实 availability 决定。

## 5. 文件与兼容性

新增生产文件 2 个：M3 控制器与页面。接线调整 app_router、bird_route_args、M1 控制器/入口、SF-B5 预览页面。删除旧只读弹窗，既有 SF-B5 导航及回执测试迁移到正式页面。

模型只补报告字段存在性、子列表有效性及可选错误文本；仓库补设备隔离的历史 ID 和父任务版本保护。没有新增服务端路径、状态、动作、请求参数，也没有修改真实后端、数据库、固件或文件复制逻辑。

新增测试文件 5 个：metadata_update fixture、控制器、页面、正式导航、HTTP。SF-B0～SF-B5 工作区变更均保留。

## 6. 验证与证据

证据目录：`build/smart-follow/sf-b6/`（构建目录，不提交）。

| 检查 | 最终结果 | 证据 |
| --- | --- | --- |
| 本批新增测试 | **50 项**：控制器 36、页面 11、正式导航 2、HTTP 1 | `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_update_*_test.dart` |
| 关联回归 | **710 通过 / 1 跳过 / 0 失败**，退出码 0 | `related-tests-final.log`、`related-tests-final-result.json` |
| 全仓静态分析 | **No issues found**，退出码 0 | `analyze-final.log`、`analyze-final-result.json` |
| 累计 Dart 格式检查 | 无改动 | `format-check.log`、`format-check-result.json` |
| Git 空白检查 | 通过 | `diff-check.log`、`diff-check-result.json` |
| 360dp / 1.5 倍中文文字 | 三张渲染图已查看，无布局异常 | `screenshots/metadata-update-*-360dp-150pct.png` |
| 源码与证据索引 | SHA-256、环境和验证范围 | `evidence.json` |

关联回归覆盖 smart_follow、recognition、copy、features/tasks、tasks、jobs、统一导航和复制设置；不是全仓测试验收。唯一跳过项仍为未配置 `BIRDBOX_CONTRACT_BASE` 的外部 Python HTTP 契约检查。

新增用例覆盖正常/部分/失败/未知状态、字段/列表/映射缺失、重复冲突、数量不符、终态父任务与运行子任务矛盾、失败重读、身份及旧版本保护、历史跨仓库恢复、设备隔离、并发历史保存、前后台及路由恢复、再次出现信息变化和其他活动父任务。

正式导航测试验证原 CopyJob ID/设备参数交给 RC3 目标页，以及 M3 返回 SF-B5 预览时零创建；RC3 目标页面用测试探针接收参数。HTTP mock 通过实际 SmartFollowApi 验证全部请求为既有 GET、报告失败后仍读取原 update ID、终态后重新读取 availability，没有创建、复制或新 MetadataUpdateJob 详情请求。

截图、报告数据和持久化恢复测试来自本地 fixture/存储抽象；生产路径接现有 Hive LocalCache，尚未代替手机断电、实际目标盘安全写入或正式后端字段验收。本批未构建 APK、提交 Git 或部署后端。

回退时仅移除本批正式 M3 页面/路由、报告模型与历史扩展，并恢复 SF-B5 接线；不能整体清空含前序批次的工作区。

下一批：**SF-B7：App 集成回归与交付收口**。

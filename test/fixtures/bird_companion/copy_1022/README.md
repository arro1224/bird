# 复制 1022 真实响应待补清单

记录日期：2026-10-22。源码核对基线为 `thirdtime @ db0261245`。

本目录目前只有缺口清单，没有本轮从真实盒子抓取的响应。现有 fake repository、Dart mock 以及单测构造数据均为测试数据，不得标为“现场真实样本”。它们足以开展 B1 状态与时序修复，不能证明板端 timing/plan_state 的真实字段语义。

| 建议样本名 | 接口/场景 | 当前状态 | 后续使用 |
|---|---|---|---|
| source-offline-error.json | 源卡在预检后断开；二次预检或创建返回的错误包络 | 未采集 | B3 错误映射 |
| target-offline-error.json | 目标盘在预检后断开；二次预检或创建返回的错误包络 | 未采集 | B3 错误映射 |
| preview-copy2-skip3.json | POST /api/v1/copy-jobs/preview 与 GET /api/v1/copy-previews/{id} | 未采集 | B4 汇总及 token/id 关系 |
| preview-items-all-pages.json | GET /api/v1/copy-previews/{id}/items 的所有分页 | 未采集 | B4 plan_state、明细总数与游标 |
| preview-raw-jpeg.json | 同一逻辑照片包含 RAW+JPEG，策略为 both | 未采集 | B4 计数单位 |
| storage-devices.json | GET /api/v1/storage/devices | 未采集 | B3 角色过滤、B5 名称 |
| job-running.json / job-paused.json | GET /api/v1/copy-jobs/{id} | 未采集 | B1 真机请求与 B5 统计字段 |
| job-completed.json / job-report.json | GET /api/v1/copy-jobs/{id} 与 /report | 未采集 | B5 名称/阶段/timing |
| connection-trace.json | 一次冷启动或配网流程的脱敏连接诊断 | 未采集 | B2 定位失败阶段 |

采集文件需附上来源说明：采集时间、App commit/包指纹、盒子连接 API 版本、复制 revision、接口、HTTP 状态、请求关联 ID、分页关系。使用可关联的占位 ID 替换真实标识，移除授权凭据、口令、私有 URL 参数与非必要文件路径；保留诊断所需的状态、码、统计与字段结构。

已知端点超时（当前源码配置）：受保护 REST connect=8s、receive=15s、send=15s；没有在 B1 全局调大。诊断以 `copy_request_result` 写入已有有容量上限的 connection journal，source 为 `app_copy`，包含 endpoint 类别、job/device ID、耗时、HTTP 状态、平台错误、错误码、可获得的 request_id 与触发源。通过连接诊断导出的 retained history 可包含这些记录。成功请求目前没有响应头元数据回传，request_id 可缺失，不由 App 生成假关联 ID。

本轮自动化入口：

- `test/bird_companion/features/copy/copy_job_read_recovery_test.dart`：读请求局部失败、独立互斥、旧响应、补报告。
- `test/bird_companion/features/copy/active_copy_job_recovery_test.dart`：进程对象重建、设备/mock 隔离、共享 GET、恢复入口。
- `test/bird_companion/features/copy/copy_request_diagnostics_test.dart`：诊断脱敏、导出接线与容量约束。
- `test/bird_companion/features/copy/copy_job_detail_first_load_retry_test.dart`：慢失败退避、前后台、明确 404。

独立 Python HTTP 契约服务未启动时测试会跳过；不能据此填写真实 HTTP 或真机验收通过。

2026-10-23 双机补充：已使用 vivo / 华为交替运行独立手机模拟盒子和正常 App，覆盖连接、完整计划、运行中进度、部分完成计数、暂停/继续及冷启动原任务恢复。仍未采集真实盒子 fixture，手机模拟日志不移入真实样本目录。最终源码测试 1270 通过 / 3 Python 外部用例跳过，31 项原有格式债已清理。最终 APK 及双机安装差异、证据边界见 `doc/汇报/拍鸟伴侣_B6双机模拟盒子验收记录_2026-10-23.md`；尤其华为仍保留前一候选，最后的 404 文案修复版受锁屏密码安装验证阻塞。

2026-10-23 B3 更新：新增 `b3_copy_preflight_invalidation_test.dart`、`b3_copy_targets_and_errors_test.dart` 和 `fakes/fake_copy_environment.dart`，使用合成环境验证失效/恢复、源角色过滤及现有平铺/嵌套错误结构。真实 source-offline、target-offline、storage-devices 样本仍未采集；没有根据未知 409 新增拔盘别名。源 token 字符串轮转不作为换卡证据，实际签发/撤销语义也列入 B3 真机复核。

2026-10-23 B4 更新：新增 `b4_copy_plan_integrity_test.dart`、`b4_copy_preview_api_test.dart` 和 `fakes/synthetic_copy_plan.dart`；既有 Dart/HTTP mock 补显式 plan_state 和一致的计划复制数/字节，均仍为合成数据。App 已按完整分页核对，明细不可验证时禁止创建；新 token 独立校验，实质变化重新确认。真实样本仍全部未采集。后续需同时核对 planned_files/actual_file_count、planned_bytes/total_bytes、source_size、has_more/next_cursor、preview_id/token 及 RAW+JPEG/伴随文件计数单位；当前没有自行增加权威 total/hash 字段。详见 `doc/汇报/拍鸟伴侣_复制B4实施记录_2026-10-23.md`。

2026-10-23 B5 更新：新增 `b5_copy_task_presentation_test.dart`（32 项合成测试），覆盖名称补全/历史快照、阶段真实性、盒子 timing 与四类处理计数。未取得真实 running/paused/resumed/completed/report 样本；小数测试不能证明实际固件精度。待核实 elapsed_seconds 是否含暂停/等待、bytes_per_second 统计区间、终态冻结及 0 占位语义；另需确认 total_files 是否包含全部 skip/not_applicable，以及 progress_percent 单位。尚无独立校验/安全同步/审阅整体成功结果，App 不补造阶段成功或有效耗时/平均速度。详见 `doc/汇报/拍鸟伴侣_复制B5实施记录_2026-10-23.md`。

2026-10-23 B6 更新：全量 Flutter 1268 通过/3 外部 Python HTTP 用例跳过；普通 bird Android 原生单测 246 通过。已生成并独立核验普通 Debug 联调候选，未安装、未操作真实盒子。当前仍没有新增真实响应，以上样本全部待采；全仓原有格式债、严格基线缺项、20 条真机状态及后端 R01～R11 见 `doc/汇报/拍鸟伴侣_复制B6集成回归与交付检查_2026-10-23.md`。本轮候选 APK SHA-256：`6104ea805a4e72a15dd5e0ccf886016e0f6ae7d1d4ddf1b539bf9feb5d54db21`；后续采样需关联本轮构建或重新构建后的准确身份，不能复用旧安装记录。

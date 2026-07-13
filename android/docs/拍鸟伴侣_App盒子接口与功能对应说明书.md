# 拍鸟伴侣 App - 盒子接口与功能对应说明书

更新日期：2026-07-11

## 1. 契约结论

《盒子端与 App 端需求汇总说明书》定义了设备、批次、照片、审阅、复制、任务、事件与日志的**能力和核心字段**，但没有锁定 REST URL、HTTP 方法、鉴权和完整 JSON schema。因此本项目使用 `/api/v1` 作为联调约定；真实盒子端交付 OpenAPI 后，应只修改 data/api 与 DTO 映射层，不直接修改页面。

## 2. 已使用接口

| 接口 | 方法 | App 功能 | 调用文件 | PDF 对应能力 | 状态 |
|---|---|---|---|---|---|
| `/api/v1/device/status` | GET | 连接握手、设备状态、电量/温度/存储/卡/版本 | `connection/data/connection_api.dart`、`device/data/device_status_api.dart` | DeviceStatus、CardStatus | 已接入 |
| `/api/v1/events` | WebSocket | 设备与任务状态事件 | `core/network/event_client.dart` | event_type、payload、timestamp | 已接入；真实盒子待提供 WS |
| `/api/v1/projects` | GET | 历史批次分页、筛选 | `batches/data/batch_api.dart` | Project/Batch | 已接入 |
| `/api/v1/projects/current` | GET | 当前批次 | `batches/data/batch_api.dart` | Project/Batch | 已接入 |
| `/api/v1/projects/{id}/resume` | POST | 恢复未完成批次 | `batches/data/batch_api.dart` | 状态恢复 | 已接入 |
| `/api/v1/projects/{id}/files` | GET | 图库分页、排序、组合筛选 | `gallery/data/photo_api.dart` | File、Preview、Recognition、Rating、Tag | 已接入 |
| `/api/v1/projects/{id}/files/actions` | POST | 批量保留/弃用等操作 | `gallery/data/photo_api.dart` | UserDecision、批量操作 | 已接入；真实失败项 schema 待确认 |
| `/api/v1/projects/{id}/groups` | GET | burst/scene 分组审阅、组内缩略图、推荐理由和对比审阅 | `review/data/review_api.dart` | Group、representative、rank、members、recommendation_reasons | 已接入；新增字段需真实盒子确认 |
| `/api/v1/files/{id}` | GET | 单张详情、主体框、Top-N、评分、EXIF | `review/data/review_api.dart` | Subject、Recognition、Rating | 已接入 |
| `/api/v1/files/{id}/history` | GET | 版本历史 | `review/data/review_api.dart` | VersionHistory | 已接入 |
| `/api/v1/files/{id}/decision` | POST | 人工鸟种、评分、标签、保留状态回写 | `review/data/review_api.dart`、`core/sync/bird_sync_service.dart` | UserDecision、version、updated_at | 已接入，使用幂等键 |
| `/api/v1/projects/{id}/copy/estimate` | GET | 复制范围、容量、目标盘预估 | `copy/data/copy_api.dart` | CopyJob、XmpExport | 已接入 |
| `/api/v1/projects/{id}/copy` | POST | 创建复制任务 | `copy/data/copy_api.dart` | CopyJob | 已接入 |
| `/api/v1/jobs` | GET | 任务中心列表 | `jobs/data/job_api.dart` | JobStatus | 已接入 |
| `/api/v1/jobs/{id}` | GET | 任务详情、进度、当前文件、错误 | `jobs/data/job_api.dart` | JobStatus | 已接入 |
| `/api/v1/jobs/{id}/actions` | POST | 暂停、继续、重试、取消 | `jobs/data/job_api.dart`、`device/data/device_status_api.dart` | 任务控制 | 已接入 |
| `/api/v1/logs/export` | POST | 诊断/任务日志导出 | `jobs/data/job_api.dart` | AuditLog、诊断包 | 已接入；下载保存/分享待真实端确认 |

## 3. 预留但尚未完成接入

| 接口 | 用途 | 需要盒子端确认 |
|---|---|---|
| `/api/v1/device/pair` | 配对码/授权 | 是否需要、凭证形式、过期策略 |
| `/api/v1/jobs/{id}/failures` | GET | 任务失败文件列表与重试入口 | `features/jobs/data/job_api.dart`、`features/jobs/presentation/job_detail_page.dart` | 已接入模拟端；真实端需确认分页和重试格式 |

## 4. 页面主跳转

`连接 -> 设备状态 -> 批次列表 -> 图库 -> 分组审阅/照片详情 -> 复制确认 -> 任务详情 -> 任务中心/批次`

关键路由定义在 `lib/bird_companion/app/app_router.dart`；统一返回按钮为 `core/widgets/page_back_button.dart`。

## 5. 真实盒子联调前必须确认

1. 是否采用以上 URL 及 `data` envelope；否则在 Api 层转换。
2. 配对/授权方案、API 版本协商和错误码规范。
3. 分页 cursor、筛选字段、缩略图 URL 是否需要鉴权头。
4. WebSocket 事件名称及 payload schema。
5. CopyJob 成功、失败项、XMP 校验和日志包下载结构。
6. 乐观回写的 `version` 冲突响应（建议 HTTP 409）和幂等键处理。

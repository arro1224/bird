# 拍鸟伴侣 App P0 设备与任务接口交接文档

> 文档用途：提供给盒子端后端进行接口设计、实现和联调。
>
> 当前范围：设备模块、任务模块，以及任务流程所依赖的当前批次和复制能力。
>
> 不包含：图库列表、照片详情、分组审阅、对比审阅、用户账号、BLE 配网、NAS 复杂同步和云端能力。

## 1. 交接范围

P0 必须完成以下闭环：

```text
连接盒子
-> 查看设备状态
-> 检测存储卡
-> 建立批次
-> 导入/索引
-> AI 分析
-> 查看任务进度和异常
-> 选择复制范围
-> 创建复制任务
-> 查看任务结果
```

App 是设备控制台和任务控制入口。盒子端是设备状态、任务状态、原始文件和导出结果的权威数据源。

App 不应：

- 直接访问盒子 Linux 文件系统路径。
- 直接运行 AI 重模型。
- 直接删除相机存储卡原始照片。
- 依赖互联网完成本地核心流程。

## 2. 通用约定

### 2.1 基础约定

- Base URL：`http(s)://<device-host>:<port>/api/v1`
- 成功响应：沿用当前前端实现，直接返回业务 JSON，不强制增加外层 `data` 包装。
- 时间格式：ISO 8601，包含时区，例如 `2026-07-26T14:20:31+08:00`。
- 所有 ID 使用字符串，且在设备端持久化稳定。
- 所有分页接口支持 `page_size` 和 `cursor`。
- 盒子端断电或 App 断线后，任务不能依赖 App 在线状态才能继续。

### 2.2 写操作元信息

所有创建、修改和控制请求建议携带以下字段：

```json
{
  "operator": "app",
  "client_updated_at": "2026-07-26T14:20:31+08:00",
  "version": 12,
  "idempotency_key": "action-20260726-001"
}
```

字段说明：

| 字段 | 必填 | 说明 |
|---|---:|---|
| `operator` | 是 | 操作来源，当前固定为 `app` |
| `client_updated_at` | 是 | App 发起操作的时间 |
| `version` | 条件 | 有并发修改或状态覆盖风险时必填 |
| `idempotency_key` | 创建/控制必填 | 防止断线重试造成重复任务或重复控制 |

同一个 `idempotency_key` 重复提交时，后端应返回第一次操作的结果，不重复创建任务。

### 2.3 错误响应

HTTP 状态码建议使用：

| 状态码 | 使用场景 |
|---:|---|
| `400` | 请求格式或参数错误 |
| `401/403` | 未配对、无权限或访问码失效 |
| `404` | 设备、批次、任务或目标存储不存在 |
| `409` | 状态冲突、版本冲突、重复创建 |
| `422` | 当前状态不允许执行该操作 |
| `503` | 设备服务暂不可用 |

错误响应格式：

```json
{
  "error": {
    "code": "INSUFFICIENT_SPACE",
    "message": "目标存储空间不足",
    "retryable": false,
    "details": {
      "required_bytes": 256302116864,
      "available_bytes": 128000000000
    }
  }
}
```

## 3. 设备接口

### 3.1 获取设备状态和连接握手

```http
GET /api/v1/device/status
```

用途：

- 首次连接后的握手。
- 重连后的完整状态刷新。
- 设备页下拉刷新。
- App 从后台恢复时读取最新状态。

响应示例：

```json
{
  "connection": {
    "device_id": "k7-7b2a",
    "device_name": "拍鸟伴侣 K7",
    "base_uri": "http://192.168.4.1:8080",
    "network_mode": "hotspot",
    "api_version": "1.0",
    "signal_strength": -46,
    "is_paired": true
  },
  "battery_percent": 82,
  "external_power": false,
  "temperature_celsius": 48.5,
  "storage_total": 1000204886016,
  "storage_free": 742183206912,
  "card": {
    "card_id": "sd-001",
    "inserted": true,
    "readable": true,
    "name": "SanDisk 128GB",
    "total_bytes": 128000000000,
    "free_bytes": 42100000000,
    "error_code": null,
    "error_message": null
  },
  "current_job": null,
  "error_code": null,
  "error_message": null,
  "software_version": "1.2.4",
  "model_version": "BirdAI-3.0.2",
  "category_version": "birds-cn-2026.07",
  "schema_version": "1.0",
  "updated_at": "2026-07-26T14:20:31+08:00"
}
```

字段要求：

| 字段 | 类型 | 说明 |
|---|---|---|
| `connection.device_id` | string | 设备唯一标识 |
| `connection.device_name` | string | 用户可见设备名称 |
| `connection.base_uri` | string | 设备本地服务地址 |
| `connection.network_mode` | string | `hotspot`、`lan`、`manual`、`qr` |
| `connection.api_version` | string | 协议版本 |
| `connection.signal_strength` | number/null | Wi-Fi 信号强度，可用 dBm |
| `connection.is_paired` | boolean | 当前是否完成配对/授权 |
| `battery_percent` | integer/null | 电量百分比 |
| `external_power` | boolean | 是否外部供电 |
| `temperature_celsius` | number/null | 当前温度 |
| `storage_total` | integer/null | 盒子可用存储总量，字节 |
| `storage_free` | integer/null | 盒子剩余存储，字节 |
| `card` | object | 当前存储卡状态 |
| `current_job` | object/null | 当前正在运行或需要处理的任务 |
| `error_code` | string/null | 设备错误码 |
| `error_message` | string/null | 面向用户的错误说明 |
| `software_version` | string/null | 盒子软件版本 |
| `model_version` | string/null | AI 模型版本 |
| `category_version` | string/null | 鸟种类别表版本 |
| `schema_version` | string/null | 数据库或导出 schema 版本 |
| `updated_at` | string | 状态更新时间 |

### 3.2 设备事件推送

```text
WebSocket /api/v1/events
```

如果盒子端暂时不支持 WebSocket，可以先使用 SSE，但事件结构保持一致。

事件格式：

```json
{
  "event_id": "evt-10028",
  "sequence": 10028,
  "event_type": "job_progress",
  "timestamp": "2026-07-26T14:02:18+08:00",
  "payload": {
    "job_id": "job-copy-001",
    "progress": 0.65,
    "finished_count": 1308,
    "current_file": "DSC_2384.ARW"
  }
}
```

P0 事件类型：

```text
device_status_changed
card_status_changed
job_created
job_progress
job_state_changed
job_failed
storage_target_changed
```

事件不是唯一数据源。App 重连后必须重新请求设备状态、当前批次和任务列表。

### 3.3 日志导出

```http
POST /api/v1/logs/export
```

请求示例：

```json
{
  "scope": "device_and_jobs",
  "job_id": "job-copy-001",
  "time_from": "2026-07-26T00:00:00+08:00",
  "time_to": "2026-07-26T23:59:59+08:00",
  "operator": "app",
  "idempotency_key": "log-20260726-001"
}
```

响应示例：

```json
{
  "export_id": "export-001",
  "state": "ready",
  "download_url": "/api/v1/logs/exports/export-001/download",
  "expires_at": "2026-07-27T14:20:31+08:00"
}
```

## 4. 当前批次和存储卡接口

这些接口属于任务流程依赖，不扩展图库功能。

### 4.1 查询当前批次

```http
GET /api/v1/projects/current
```

无当前批次时返回 `200` 和 `null`，不要返回 404。

响应字段：

```json
{
  "project_id": "project-001",
  "card_id": "sd-001",
  "name": "崇明东滩 7月16日",
  "created_at": "2026-07-26T13:20:00+08:00",
  "total_files": 3672,
  "imported_count": 3672,
  "analyzed_count": 2384,
  "review_count": 1288,
  "keep_count": 2012,
  "discard_count": 1648,
  "pending_copy_count": 2012,
  "copy_state": "pending",
  "active_job_id": "job-analysis-001"
}
```

### 4.2 查询批次列表

```http
GET /api/v1/projects?page_size=30&state=incomplete&cursor=<cursor>
```

用于设备页查看历史批次和任务恢复入口。

响应格式：

```json
{
  "items": [],
  "has_more": false,
  "next_cursor": null
}
```

### 4.3 扫描当前存储卡

```http
GET /api/v1/storage/cards/current/scan
```

响应示例：

```json
{
  "scan_state": "detected",
  "card_id": "sd-001",
  "card_name": "SanDisk 128GB",
  "photo_count": 3672,
  "raw_count": 2518,
  "jpeg_count": 1154,
  "required_bytes": 92771293594,
  "capture_started_at": "2026-07-16T05:42:12+08:00",
  "capture_ended_at": "2026-07-16T11:18:26+08:00",
  "error_code": null,
  "error_message": null
}
```

`scan_state`：

```text
detected | scanning | missing | unreadable | empty
```

### 4.4 重新扫描存储卡

```http
POST /api/v1/storage/cards/current/rescan
```

请求体：

```json
{
  "operator": "app",
  "idempotency_key": "scan-20260726-001"
}
```

响应返回新建的扫描任务或当前扫描任务：

```json
{
  "job_id": "job-scan-001",
  "job_type": "import",
  "job_state": "queued"
}
```

### 4.5 建立批次

```http
POST /api/v1/projects
```

请求示例：

```json
{
  "name": "崇明东滩 7月16日",
  "card_id": "sd-001",
  "operator": "app",
  "idempotency_key": "project-20260726-001"
}
```

响应：

```json
{
  "project_id": "project-001",
  "state": "ready_to_import",
  "card_id": "sd-001"
}
```

### 4.6 创建导入/索引任务

```http
POST /api/v1/projects/{projectId}/imports
```

请求示例：

```json
{
  "source": "card",
  "read_only": true,
  "generate_thumbnails": true,
  "generate_previews": true,
  "operator": "app",
  "idempotency_key": "import-20260726-001"
}
```

响应返回统一任务对象。

`read_only` 必须由盒子端强制保证为只读挂载，不能只依赖 App 传参。

### 4.7 创建 AI 分析任务

```http
POST /api/v1/projects/{projectId}/analysis-jobs
```

请求示例：

```json
{
  "mode": "standard",
  "include_grouping": true,
  "operator": "app",
  "idempotency_key": "analysis-20260726-001"
}
```

P0 不要求 App 传递模型参数。模型、类别表和分析阶段由盒子端决定，并在任务和设备状态中返回版本信息。

### 4.8 恢复未完成批次

```http
POST /api/v1/projects/{projectId}/resume
```

请求示例：

```json
{
  "operator": "app",
  "idempotency_key": "resume-20260726-001"
}
```

响应返回当前批次和相关任务 ID。

## 5. 任务接口

### 5.1 查询任务列表

```http
GET /api/v1/jobs?state=active&type=all&page_size=30&cursor=<cursor>
```

支持的 `type`：

```text
import | analysis | copy
```

`sync` 接口属于后续阶段，P0 不要求实现。

支持的 `state`：

```text
queued | running | paused | completed | failed | cancelled
```

响应格式：

```json
{
  "items": [],
  "has_more": false,
  "next_cursor": null
}
```

### 5.2 查询任务详情

```http
GET /api/v1/jobs/{jobId}
```

统一任务对象：

```json
{
  "job_id": "job-copy-001",
  "job_type": "copy",
  "job_state": "running",
  "workflow_stage": "copying",
  "source_project_id": "project-001",
  "source_project_name": "崇明东滩 7月16日",
  "progress": 0.65,
  "total_count": 2012,
  "finished_count": 1308,
  "failed_count": 2,
  "skipped_count": 0,
  "current_file": "DSC_2384.ARW",
  "speed_bytes_per_second": 44040192,
  "estimated_remaining_seconds": 1080,
  "started_at": "2026-07-26T13:20:00+08:00",
  "updated_at": "2026-07-26T14:02:18+08:00",
  "finished_at": null,
  "error_code": null,
  "error_message": null,
  "available_actions": ["pause", "cancel"]
}
```

建议使用两层状态：

```text
job_state:
queued | running | paused | completed | failed | cancelled

workflow_stage:
scanning | importing | analyzing | awaiting_review |
reviewing | awaiting_copy | copying | verifying |
exporting_xmp | completed
```

### 5.3 控制任务

```http
POST /api/v1/jobs/{jobId}/actions
```

请求示例：

```json
{
  "action": "pause",
  "operator": "app",
  "client_updated_at": "2026-07-26T14:02:18+08:00",
  "version": 12,
  "idempotency_key": "job-action-20260726-001"
}
```

P0 支持：

```text
pause
resume
cancel
retry_failed
skip_failed
```

后端必须校验任务当前状态。例如已完成任务不能暂停，复制未开始前不能重试复制失败项。

### 5.4 查询失败项

```http
GET /api/v1/jobs/{jobId}/failures?page_size=100&cursor=<cursor>
```

响应：

```json
{
  "items": [
    {
      "file_id": "photo-001",
      "filename": "DSC_0001.ARW",
      "error_code": "COPY_IO_ERROR",
      "reason": "目标存储写入失败",
      "retryable": true
    }
  ],
  "has_more": false,
  "next_cursor": null
}
```

### 5.5 查询任务报告

```http
GET /api/v1/jobs/{jobId}/report
```

响应示例：

```json
{
  "job_id": "job-copy-001",
  "result": "partial_success",
  "total_count": 2012,
  "success_count": 2009,
  "failed_count": 3,
  "skipped_count": 0,
  "copied_bytes": 256302116864,
  "xmp_success_count": 2009,
  "xmp_failed_count": 0,
  "verification_passed_count": 2009,
  "verification_failed_count": 0,
  "manifest_id": "manifest-001",
  "started_at": "2026-07-26T13:20:00+08:00",
  "finished_at": "2026-07-26T13:47:46+08:00"
}
```

### 5.6 复制预估

```http
GET /api/v1/projects/{projectId}/copy/estimate?mode=keep
```

响应：

```json
{
  "mode": "keep",
  "file_count": 2012,
  "required_bytes": 256302116864,
  "pending_count": 12,
  "targets": [
    {
      "id": "disk-t7",
      "name": "Samsung T7 Shield",
      "free_bytes": 1200000000000,
      "total_bytes": 2000000000000,
      "online": true
    }
  ]
}
```

`mode`：

```text
keep | all | dual
```

### 5.7 创建复制任务

```http
POST /api/v1/projects/{projectId}/copy
```

请求示例：

```json
{
  "mode": "keep",
  "target_id": "disk-t7",
  "source_filter": {
    "keep_states": ["keep", "featured"]
  },
  "generate_xmp": true,
  "verify_after_copy": true,
  "operator": "app",
  "client_updated_at": "2026-07-26T14:10:00+08:00",
  "version": 12,
  "idempotency_key": "copy-20260726-001"
}
```

后端创建成功后返回复制任务对象：

```json
{
  "job_id": "job-copy-001",
  "job_type": "copy",
  "job_state": "queued",
  "source_project_id": "project-001"
}
```

创建前必须由后端再次校验：

- 目标盘存在且在线。
- 目标盘剩余空间足够。
- 当前任务状态允许复制。
- 设备温度和电量满足复制条件。
- 不会写入或删除原始相机存储卡。

## 6. 任务状态和保护规则

### 6.1 设备/任务状态

后端至少需要支持：

```text
idle
card_inserted
importing
analyzing
paused
awaiting_review
reviewing
awaiting_copy
copying
completed
failed
cancelled
```

### 6.2 任务保护

以下情况不能直接创建导入、深度分析或复制任务：

| 条件 | 错误码 |
|---|---|
| 未插入存储卡 | `CARD_NOT_INSERTED` |
| 存储卡不可读 | `CARD_UNREADABLE` |
| 没有可处理照片 | `NO_SUPPORTED_PHOTOS` |
| 电量过低 | `LOW_BATTERY` |
| 温度过高 | `OVER_TEMPERATURE` |
| 目标存储不存在 | `TARGET_NOT_FOUND` |
| 目标存储已断开 | `TARGET_OFFLINE` |
| 目标空间不足 | `INSUFFICIENT_SPACE` |
| 当前任务状态不允许操作 | `INVALID_JOB_STATE` |

## 7. P0 错误码

```text
API_VERSION_INCOMPATIBLE
PAIRING_REQUIRED
CARD_NOT_INSERTED
CARD_UNREADABLE
NO_SUPPORTED_PHOTOS
JOB_NOT_FOUND
INVALID_JOB_STATE
LOW_BATTERY
OVER_TEMPERATURE
TARGET_NOT_FOUND
TARGET_OFFLINE
INSUFFICIENT_SPACE
COPY_IO_ERROR
XMP_EXPORT_FAILED
VERIFY_FAILED
VERSION_CONFLICT
INTERNAL_ERROR
```

## 8. 断线与恢复要求

1. App 断线后，盒子端继续执行导入、分析和复制任务。
2. App 重连后重新请求：
   - `/device/status`
   - `/projects/current`
   - `/projects`
   - `/jobs`
   - 当前任务详情
3. 事件连接断开不能直接等同于设备断开，HTTP 状态查询仍可作为兜底。
4. 同一个创建或控制请求重试时必须复用 `idempotency_key`。
5. 后端返回 `409 VERSION_CONFLICT` 时，App 必须提示用户，不能静默覆盖盒子端较新状态。
6. 任务状态以盒子端为准，App 本地演示状态不能写入真实任务缓存。

## 9. P0 验收清单

- [ ] App 可以通过热点、局域网、手动地址或二维码获取 `/device/status`。
- [ ] 设备状态包含电量、供电、温度、总容量、剩余容量、存储卡和当前任务。
- [ ] 存储卡未插入、读取失败和无照片时返回明确状态和错误码。
- [ ] App 可以建立批次并创建导入任务。
- [ ] App 可以创建 AI 分析任务并读取进度。
- [ ] 任务可以暂停、继续、取消、重试失败项和跳过失败项。
- [ ] App 断线后盒子任务仍继续运行。
- [ ] App 重连后可以读取最新设备、批次和任务状态。
- [ ] 复制预估包含文件数量、容量、待确认数量和目标存储列表。
- [ ] 目标空间不足时后端拒绝创建复制任务。
- [ ] 复制任务支持 XMP 和复制后校验参数。
- [ ] 任务完成后可以读取复制报告、失败数量、XMP 结果和校验结果。
- [ ] 日志导出可以返回可下载的诊断包地址。
- [ ] 所有创建和控制操作支持幂等键。
- [ ] 原始存储卡以只读方式处理，App 和盒子端都不能通过此流程删除原片。

## 10. 非 P0 接口

以下内容暂不阻塞当前设备和任务 P0 联调：

```text
POST /api/v1/device/pair       # BLE 配网或完整设备绑定
GET  /api/v1/device/diagnostics # 独立诊断接口，可先合并到 device/status
POST /api/v1/projects/{id}/sync # NAS、电脑、外置设备复杂同步
```

P0 阶段不建议提供删除任务记录的接口。任务记录、复制报告、Manifest 和审计日志应保留，前端如需要整理列表，使用归档语义即可。

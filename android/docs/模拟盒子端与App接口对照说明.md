# 模拟盒子端与 App 接口对照说明

## 模拟盒子端目录

```text
mock_box_server/
├─ server.py   # Python 标准库 HTTP 服务、内存演示批次/照片/任务数据
└─ README.md   # 启动、真机连接和删除说明
```

它不被 Flutter 或 Android 构建引用。真实盒子端接口完成后可直接删除整个 `mock_box_server/`，不会影响前端代码。

## 真机联调步骤

1. 在电脑项目根目录执行 `python mock_box_server/server.py --host 0.0.0.0 --port 8080`。
2. 手机与电脑接入同一局域网。
3. 在 App 的“手动地址”填写 `http://电脑局域网IP:8080`，例如 `http://192.168.1.8:8080`。
4. 成功后可查看模拟设备、批次、图库、分组、详情、复制预估和任务。

## PDF 需求与当前接口映射

PDF 的“盒子端—App 端协同需求”定义的是能力和对象（DeviceStatus、Project/Batch、File、Group、UserDecision、CopyJob、AuditLog），而不是已锁定的 HTTP URL。以下 `/api/v1` 是前端和模拟盒子采用的联调契约；真实盒子应提供同等语义，字段差异由 DTO/Repository 层适配。

| PDF 协同能力 | 联调接口 | App 文件 | 用途 |
|---|---|---|---|
| 设备连接/状态同步 | `GET /api/v1/device/status` | `features/connection/data/connection_api.dart`、`features/device/data/device_status_api.dart` | 握手、DeviceStatus、CardStatus、当前任务、版本信息 |
| 实时事件 | `WS /api/v1/events` | `core/network/event_client.dart` | 状态、分析、复制、错误事件；模拟服务暂不提供 WS |
| 批次查询 | `GET /api/v1/projects`、`GET /api/v1/projects/current` | `features/batches/data/batch_api.dart` | 当前/历史批次 |
| 恢复批次 | `POST /api/v1/projects/{batchId}/resume` | `features/batches/data/batch_api.dart` | 恢复未完成任务 |
| 照片列表 | `GET /api/v1/projects/{batchId}/files` | `features/gallery/data/photo_api.dart` | 分页、筛选、排序、缩略图引用 |
| 批量审阅 | `POST /api/v1/projects/{batchId}/files/actions` | `features/gallery/data/photo_api.dart` | 批量保留、弃用、标签 |
| 分组结果 | `GET /api/v1/projects/{batchId}/groups` | `features/review/data/review_api.dart` | burst/scene 组 |
| 照片详情 | `GET /api/v1/files/{fileId}` | `features/review/data/review_api.dart` | Preview、主体框、识别、评分、EXIF |
| 人工回写 | `POST /api/v1/files/{fileId}/decision` | `features/review/data/review_api.dart` | UserDecision、版本字段 |
| 复制预估/创建 | `GET /copy/estimate`、`POST /copy` | `features/copy/data/copy_api.dart` | 复制模式、目标盘、容量、CopyJob |
| 任务中心/控制 | `GET /api/v1/jobs`、`GET /jobs/{jobId}`、`POST /jobs/{jobId}/actions` | `features/jobs/data/job_api.dart` | JobStatus、暂停、继续、重试 |
| 日志导出 | `POST /api/v1/logs/export` | `features/jobs/data/job_api.dart` | AuditLog/诊断包导出 |

## 当前前端连接检查

前端已预留上述能力的 API 文件和路由；但部分真实协议仍未由 PDF 锁定，尤其是自动发现（mDNS/UDP）、二维码格式、WebSocket 事件补偿、缩略图鉴权、分页游标、错误码表、版本冲突格式。真实盒子端开发时必须以本表为契约基线补充接口文档，再在 `core/network/api_endpoints.dart` 和各 `data/*_api.dart` 完成最终映射。

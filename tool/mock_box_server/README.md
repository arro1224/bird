# BirdBox 业务与 rc4 配网模拟盒子

> 契约基线：`birdbox-v1@1.0.0`
>
> 固定样例入口：`test/contracts/fixture-manifest.json`。mock 后续新增或调整响应时
> 必须复用这些 fixtures，不得维护一套独立字段定义。

该服务用于本地恢复照片、任务和审阅业务链路，并提供 rc4 首次配对所需的
`GET /health` 与 `POST /api/v1/pairing`。BLE 广播、GATT、分片和网络切换仍由
`FakeBirdBoxBleDataSource`、Fake Wi-Fi 与 Fake DPP 覆盖；HTTP Mock 不能替代真实
K7 无线链路证据。服务只依赖 Dart SDK，不需要安装额外服务。

## 启动

快速开发集（60 张）：

```powershell
dart run tool/mock_box_server/server.dart --quick
```

完整分页集（1200 张，默认）：

```powershell
dart run tool/mock_box_server/server.dart
```

可选参数：

```text
--photos=1200
--host=0.0.0.0
--port=8787
--device-id=mock-k7-001
--quiet
--auth
--progressive-media
--no-asset-events
--state-file=.tmp/mock-box-state.json
```

`--auth` 开启全通道鉴权。配对码 `2468` 只供旧
`POST /api/v1/device/pair` 兼容测试使用；rc4 主流程禁止通过 HTTP 发送验证码。
`--progressive-media` 开启 P1 候选协议的照片状态、资源错误、ETag/304 和
`asset_ready`；默认关闭，因此原有 v1 回归响应保持不变。`--no-asset-events`
用于模拟 WebSocket 不推送资源就绪事件。
服务日志只记录请求方法和路径，不记录配对码、Bearer Token 或签名 URL 查询串。

启动后可访问：

- 宿主机：`http://127.0.0.1:8787`
- Android 模拟器：`http://10.0.2.2:8787`
- rc4 身份健康检查：`GET /health`
- 工具兼容健康检查：`GET /healthz`（不得作为 App rc4 正式接口）

## rc4 配网 HTTP 联调

rc4 Schema 要求完整设备身份使用 `bbx-` 加 32 位小写十六进制。启动用于配网契约
测试的 Mock 时，应显式传入符合约束的设备 ID：

```powershell
dart run tool/mock_box_server/server.dart --quick --auth `
  --device-id=bbx-82f41c9e7a3d4b68a1501e21e536c649
```

rc4 HTTP 接口：

- `GET /health`：无鉴权返回完整 `device_id`、`1.0-rc4`、API 版本和当前网络模式。
- `POST /api/v1/pairing`：使用 BLE 临时 `pairing_session_id` 换取 Token；请求中出现
  `pairing_code` 会按非法请求处理。

旧 `GET /healthz` 与 `POST /api/v1/device/pair` 仅保留兼容测试。正式配网流程必须先
比较 GATT `Device Info.device_id` 与 `/health.device_id`，再交换配对会话；不能用
`/healthz`、名称、蓝牙 MAC 或短编号替代身份确认。

让应用自动连接：

```powershell
flutter run --dart-define=BIRD_TEST_BASE_URL=http://10.0.2.2:8787
```

若应用运行在 Windows 桌面端，将地址改为 `http://127.0.0.1:8787`。

## 数据与接口

- 快速集提供 60 张照片、4 个场景和 5 个连拍组。
- 默认集提供 1200 张照片、4 个场景和 86 个连拍组。
- 数据覆盖待确认、已保留、已弃用、精选、模糊、处理中、低置信度和识别失败。
- 照片 ID、状态、评分、时间、场景和分组均由固定算法生成，每次启动结果一致。
- 决定保存和批量操作保存在当前服务进程内，重启服务后恢复初始数据。

实现的 B1 接口：

- `GET /api/v1/device/status`
- `GET /api/v1/projects/current`
- `GET /api/v1/projects`
- `GET /api/v1/projects/{batchId}/files`
- `GET /api/v1/projects/{batchId}/scenes`
- `GET /api/v1/projects/{batchId}/groups`
- `GET /api/v1/files/{fileId}`
- `GET /api/v1/files/{fileId}/history`
- `POST /api/v1/files/{fileId}/decision`
- `POST /api/v1/projects/{batchId}/files/actions`
- `POST /api/v1/projects/{batchId}/resume`
- `GET /api/v1/species`
- `GET /mock/media/{asset}.png`

P1 渐进图片模式额外提供：

- `GET /api/v1/files/{fileId}/thumbnail`
- `GET /api/v1/files/{fileId}/preview`
- `POST /mock/control/assets`
- `POST /mock/control/events`

启动示例：

```powershell
dart run tool/mock_box_server/server.dart --quick --progressive-media
```

切换单个资源会按需发送 `asset_ready`：

```powershell
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8787/mock/control/assets `
  -ContentType application/json `
  -Body '{"file_id":"photo-0003","kind":"thumbnail","status":"ready"}'
```

P4 渐进媒体发布门禁可直接针对已启动的可控 K7 执行：

```powershell
dart run tool/acceptance/progressive_media_p4_acceptance.dart `
  http://127.0.0.1:8787
```

该门禁验证 pending 404、Retry-After、ETag/304、thumbnail/preview 乱序事件、
WebSocket 断线以及无事件时的 HTTP 恢复。它只临时修改两张
`pending/not_requested` 照片，并在退出前恢复原状态和事件开关；恢复失败会使命令
返回失败，不能忽略。

将 `/mock/control/events` 的 `enabled` 设为 `false` 会断开现有事件连接，便于验证
HTTP 有限重试兜底；重新设为 `true` 后 App 可按正常重连策略恢复。

任务、存储卡和复制验收接口：

- `GET /api/v1/storage/cards/current/scan`
- `POST /api/v1/storage/cards/current/rescan`
- `POST /api/v1/projects`
- `POST /api/v1/projects/{batchId}/imports`
- `POST /api/v1/projects/{batchId}/analysis-jobs`
- `GET /api/v1/projects/{batchId}/copy/estimate`
- `POST /api/v1/projects/{batchId}/copy`
- `GET /api/v1/jobs`
- `GET /api/v1/jobs/{jobId}`
- `POST /api/v1/jobs/{jobId}/actions`
- `GET /api/v1/jobs/{jobId}/report`
- `GET /api/v1/jobs/{jobId}/failures`

## B12-A 已启动模拟盒子验收

当 K7 模拟盒子已经启动时，可直接运行生产 API 与本地筛选组合门禁：

```powershell
dart run tool/acceptance/b12a_k7_acceptance.dart --base-url=http://127.0.0.1:8787
```

该命令会读取健康状态、设备、项目、存储卡、场景和照片，验证“白鹭”、
“普通翠鸟”及组合筛选，并在模拟器内创建隔离的 B12-A 项目和任务以检查
暂停、恢复、取消、409、422、复制报告和日志下载。写入仅存在于模拟器进程；
重启未指定 `--state-file` 的模拟盒子即可恢复初始数据。

B3 旧鉴权兼容联调接口：

- `POST /api/v1/device/pair`
- `GET /api/v1/events`（Bearer WebSocket）
- `POST /api/v1/logs/export`
- `GET /mock/media/{asset}.png?...`（短时签名 URL）
- `GET /mock/logs/{file}?...`（短时签名 URL）

开启 `--auth` 后，除健康检查、设备公开状态、配对和短签名资源外，
REST 接口都校验同一 Bearer Token。无 Token 返回 401，错误或吊销 Token 返回 403；
WS 也执行相同校验。媒体和日志不接收 Bearer，只接受未过期的签名 URL。

## B7 持久化与幂等重放

所有 `POST` 都要求至少 8 个字符的 `X-Idempotency-Key`。同一路径使用同一键的
并发请求只执行一次，后续请求重放首次响应。通过 `--state-file` 指定状态文件后，
项目、任务、审阅、照片覆盖值和幂等响应会在进程重启后恢复：

```powershell
dart run tool/mock_box_server/server.dart --quick --auth --state-file=.tmp/mock-box-state.json
```

状态文件只用于本地测试，可能包含业务样例和响应内容，不得提交到 Git 或作为正式
盒子数据库使用；配对响应不会写入状态文件。

## 图片资源

`assets/` 内的 4 张鸟类照片由 OpenAI 图像生成工具为本项目生成，仅用于本地 mock、测试和界面开发：

- `kingfisher.png`：水边翠鸟，横向自然摄影。
- `egret.png`：浅水白鹭，竖向自然摄影。
- `warbler.png`：芦苇间苇莺，横向自然摄影。
- `sandpiper.png`：滩涂鹬鸟，竖向自然摄影。

图片不含文字和水印。1200 张数据会重复分配这 4 个资源；它们不是最终产品内容，也不替换用户照片。

## 验证

```powershell
flutter test test/bird_companion/core/authentication_flow_test.dart test/bird_companion/core/media_uri_resolution_test.dart test/bird_companion/core/mock_box_server_test.dart
flutter test test/contracts/a7_mock_security_audit_test.dart
```

测试覆盖配对、REST/WS Bearer、重启恢复、并发幂等重放、吊销、Token/签名 URL
到期、设备切换、媒体与日志重新申请，以及原有图片、分页、场景、连拍组、详情和
审阅操作。A7 安全审计另行验证请求日志不包含查询串、Authorization、Wi-Fi 密码
或完整 DPP URI，并验证持久化状态不写入验证码、配对会话或 Token。

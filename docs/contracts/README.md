# BirdBox v1 契约

本目录是 birdpart2 与盒子端之间的唯一 v1 协议基线。版本号固定为
`birdbox-v1@1.0.0`，API URL 版本固定为 `v1`。

## 权威文件

- `birdbox-v1.openapi.yaml`：HTTP/WebSocket 端点、请求、响应、鉴权和错误。
- `schemas/*.schema.json`：跨 HTTP、WebSocket、mock 和 fixture 复用的数据对象。
- `birdbox-v1-baseline.json`：App、源分支和真实盒子联调基线。
- `../decisions/ADR-001-birdbox-v1.md`：冲突决议、兼容窗口和责任边界。
- `../../test/contracts/fixture-manifest.json`：可同时用于 mock 与真实盒子的固定样例。

`birdbox-v1.openapi.yaml` 使用 JSON 语法编写。JSON 是 YAML 1.2 的合法子集，
因此该文件既可被标准 OpenAPI/YAML 工具读取，也可在无第三方依赖的 CI 中直接
通过 `jsonDecode` 校验。

## 固定决议

- 成功响应：新接口使用 `{ "data": ... }`；客户端读侧仅在一个兼容周期内接受直接对象。
- 错误响应：顶层 `error_code` / `error_message`。
- 鉴权：`Authorization: Bearer <token>`；配对和连接握手端点除外。
- API 版本：`X-Api-Version: v1`。
- 幂等：所有 POST 仅使用 `X-Idempotency-Key` 请求头。
- 进度：线协议使用 `0..1`；百分比只在 UI 层计算。
- 任务状态：`queued/running/paused/completed/failed/cancelled`。
- 复制 XMP：请求字段为 `xmp_enabled`。
- WebSocket：v1 事件必须携带完整 `DeviceStatus` 或 `BirdJobStatus`。
- 审阅 Patch：字段省略表示保持，`null` 表示清空，空数组表示清空列表。

## 校验

```powershell
dart run tool/contracts/verify_contracts.dart
flutter test test/contracts/contract_validation_test.dart
```

默认校验会检查 OpenAPI、所有 `$ref`、Schema 和正反 fixtures。增加
`--strict-baseline` 后还会要求真实盒子仓库/固件 SHA、部署方式、数据库迁移、
回滚方式、固定联调地址和四类负责人全部填写：

```powershell
dart run tool/contracts/verify_contracts.dart --strict-baseline
```

在这些外部输入补齐前，契约文件可以进入评审，但 B0 不得标记为完成，B3 之后
不得声称真实联调通过。

## 待评审提案

- `proposals/API-PROPOSAL-20260816-01-PROGRESSIVE-MEDIA.md`：盒子后端
  `0.6.2` 渐进图片资源状态、HTTP 错误、ETag 与 `asset_ready` 事件。

提案文件不是已生效契约。提案获批并分配正式契约版本前，运行时代码、mock、
fixtures 和本目录冻结的 v1 文件仍以 `birdbox-v1@1.0.0` 为准。

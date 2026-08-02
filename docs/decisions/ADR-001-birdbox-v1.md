# ADR-001：冻结 BirdBox v1 连接契约

- 状态：已接受（App 侧）；真实盒子基线待补
- 决议版本：`birdbox-v1@1.0.0`
- 生效日期：2026-07-29
- 集成基线：`fb99f208a4e0ccba7bd8f3abd3154a6d970df92a`
- 决策角色：协议 owner、公共 Flutter 核心 owner、盒子 API owner、测试/发布 owner
- 联系人：见 `docs/contracts/birdbox-v1-baseline.json`；未填写联系人属于 B0 阻塞项

## 背景

birdpart2 已把 `codex/bird-companion-project` 与 `yuyuyu` 合并到同一 Git 提交，
但两套实现仍在成功包装、错误格式、幂等键、任务状态、进度、WebSocket、
复制字段和审阅空值语义上并存。继续直接接 UI 会把兼容逻辑扩散到每个页面。

本 ADR 把说明书 B0 的协议决议变成 OpenAPI、JSON Schema 和固定 fixture。
后续实现不得另造同义字段或第三种包装格式。

## 决议

| 议题 | v1 定稿 | 兼容窗口 |
|---|---|---|
| URL/API 版本 | `/api/v1`；`X-Api-Version: v1` | 不兼容版本返回 `API_VERSION_INCOMPATIBLE` |
| 成功包装 | 新接口统一 `{ "data": ... }` | 读侧可兼容直接对象一个版本周期 |
| 错误包装 | 顶层 `error_code`、`error_message`，可带 `retryable/details` | 临时只读兼容 `error.code/error.message` |
| 幂等键 | 所有 POST 使用 `X-Idempotency-Key` | Body 中的 `idempotency_key` 不再发送 |
| 任务状态 | `queued/running/paused/completed/failed/cancelled` | `idle` 仅作为旧数据读兼容 |
| 任务进度 | `0..1` | `0..100` 输入视为契约错误 |
| XMP 字段 | `xmp_enabled` | `generate_xmp` 仅过渡读取 |
| WebSocket | v1 推送完整 `DeviceStatus` 或 `BirdJobStatus` | 增量 payload、必选 `sequence` 留到 v2 |
| 审阅 Patch | 省略=保持，`null`=清空，`[]`=清空列表 | 旧全量请求仅限兼容周期 |
| 任务删除 | 只允许终态任务，运行态返回 409/422 | archive 语义另立版本 |
| 媒体/日志 | 短时签名 URL；过期返回 401/403，可重新申请 | 不允许绕开统一鉴权使用裸下载客户端 |

## 数据与命名

- 线协议只使用 `project_id`；客户端内部 `batchId` 只能作为 UI 别名，禁止序列化为 `batch_id`。
- 所有 ID 为稳定字符串，时间为带时区的 ISO 8601。
- `SubjectBox` 的 `x/y/width/height` 与置信度均使用 `0..1`。
- 写操作的并发控制使用业务对象 `version`；旧版本返回 HTTP 409 和
  `VERSION_CONFLICT`，客户端不得静默覆盖。
- v1 事件的 payload 是权威对象快照；重连后仍必须重新读取 REST 状态。

## 责任边界

- 协议 owner：批准 OpenAPI、Schema、错误码和兼容窗口。
- 公共 Flutter 核心 owner：保证 DTO、客户端解析和缓存不偏离契约。
- 盒子 API owner：提供可部署实现、固件 SHA、数据库迁移和回滚。
- 测试/发布 owner：让相同 fixture 同时运行在 mock 与真实盒子，并保留证据。

## 验收

1. `dart run tool/contracts/verify_contracts.dart` 通过。
2. `flutter test test/contracts/contract_validation_test.dart` 通过。
3. `--strict-baseline` 通过，表示真实盒子输入和四类联系人已补齐。
4. 接口说明、mock README、OpenAPI、Schema 和 fixture 均引用
   `birdbox-v1@1.0.0`。
5. 协议评审中不存在“待双方确认”的字段、错误、鉴权或幂等语义。

## 回滚与废弃

B0 只增加文档、契约、fixtures 和校验工具，不改变运行时行为。回滚时可整体
revert B0 提交。直接对象、嵌套错误、`idle`、`generate_xmp` 和旧全量审阅请求
在一个兼容周期后废弃；确切日期由协议 owner 在真实盒子基线补齐时登记。

## 当前外部阻塞

`docs/contracts/birdbox-v1-baseline.json` 中仍缺少真实盒子仓库、分支、固件 SHA、
部署命令、数据库 schema/迁移/回滚、固定联调地址和四类联系人。校验器的
`--strict-baseline` 会在这些值为空时失败，这是预期的发布门，而不是可以用
假值绕过的错误。

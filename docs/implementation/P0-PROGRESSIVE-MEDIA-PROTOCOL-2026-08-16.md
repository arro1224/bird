# P0｜后端 0.6.2 渐进图片适配协议准备

> 日期：2026-08-16  
> App 执行状态：内部工作已完成，等待后端确认  
> 对应提案：`docs/contracts/proposals/API-PROPOSAL-20260816-01-PROGRESSIVE-MEDIA.md`

## 1. 本批次结论

P0 不修改 Flutter 运行时代码、不修改 K7 mock 行为，也不修改冻结的
`birdbox-v1@1.0.0` 契约。后端 0.6.2 细则包含新增 Photo 字段、新事件和新的 HTTP
错误语义，必须作为版本化提案评审，不能以“可选字段”名义直接写进冻结 v1。

App 后续采用一套集中式媒体资源状态机，页面只订阅单个
`device_id + file_id + kind`，不在每个 Widget 内各自维护 Timer，也不因
`asset_ready` 刷新整个相册页。

## 2. P0 已完成项

- [x] 核对后端 `0.6.2` 细则与 App 冻结契约。
- [x] 确认 Photo v1 Schema 使用 `additionalProperties: false`，不能直接加入状态字段。
- [x] 确认 v1 EventEnvelope 只允许完整 Device/Job 快照，尚无 `asset_ready`。
- [x] 确认当前 App/mock 使用短时签名媒体 URL，媒体下载不带 Bearer Token。
- [x] 给出缺失字段、未知枚举、404、409、Retry-After、ETag 和断开 WebSocket 的
  App 兼容策略。
- [x] 补齐 `asset_ready` 的候选完整 envelope。
- [x] 输出 PM-01 至 PM-10 后端确认清单。
- [x] 保持配对、Token、项目、导入、分析、mDNS 与手动 IP 在本次范围外。

### 当前 K7 模拟盒基线

2026-08-16 对已打开的 `http://127.0.0.1:8787` 做了只读检查：

- `/healthz` 返回 `ok`；
- 设备为 `mock-k7-001`，软件版本为 `mock-box-1.0.0`；
- 当前照片响应不包含 `thumbnail_status` 或 `preview_status`。

因此该实例只用于旧协议回归，不能作为后端 0.6.2 渐进图片验收环境。P1 会给 mock
增加显式、可控且默认关闭的渐进媒体场景。

## 3. P1 的固定实现边界

在后端回复前，可以按以下可逆设计进入 P1：

1. DTO 新增可空的 `thumbnailStatus/previewStatus`，并提供内部
   `legacy/unknown` 兼容状态。
2. 新建独立媒体资源协调器，集中处理计时器、HTTP 错误、ETag 和事件通知。
3. K7 mock 增加可控状态，但默认仍保持旧响应，避免破坏旧回归。
4. 新协议 fixture 放在 proposal/候选版本范围，不改冻结 v1 fixture。
5. 自动重试采用 1/2/4/5 秒、单激活周期最多 5 次；所有计时器可取消。

以下内容在后端确认前不得固化：

- 正式契约版本号和 capability 字段；
- 图片 URL 的 Bearer/签名鉴权实现；
- 资源重新生成动作接口；
- `asset_ready` 中可选字段的最终必填性；
- 对冻结 v1 OpenAPI、Schema、fixtures 和 ADR 的任何修改。

## 4. 发给后端的确认消息

可直接复制以下内容：

```text
App 已完成 0.6.2 渐进图片适配 P0 协议核对。当前 App 冻结契约为
birdbox-v1@1.0.0，而细则写 1.0-rc2；Photo Schema 禁止额外字段，v1 WS 也只允许
完整 Device/Job 快照，因此我们先按新版本提案处理，不覆盖现有 v1。

请逐项回复：
PM-01  1.0-rc2 与 birdbox-v1@1.0.0 的版本映射及最终版本号；
PM-02  是否提供 progressive_media capability，字段名和值是什么；
PM-03  asset_ready 是否包含 event_id、timestamp，job_id 是否可空；
PM-04  not_requested 由导入流水线自动转 pending，还是图片 GET 触发；
PM-05  asset_failed 后是否有重新生成接口；
PM-06  图片 URL 是短时签名还是需要 Bearer Token；
PM-07  WS payload.etag 是否与 HTTP ETag 头逐字一致；
PM-08  kind 是否固定支持 thumbnail 和 preview；
PM-09  status=ready 后偶发未就绪是否仍返回 404 asset_not_ready；
PM-10  真机/后端 mock 是否能控制 pending、ready、failed、WS 断线和乱序完成。

App 暂定：缺字段走旧 URL；完整 WS envelope；GET 不触发生成；图片 URL 保持短时
签名；ETag 作为不透明值；404 asset_not_ready 有限退避；409/file_not_found 不自动
重试。若任一暂定值不符合后端实现，请在对应编号下给出最终语义和响应示例。
```

## 5. 批次门禁

| 门禁 | 进入条件 | 当前状态 |
|---|---|---|
| P1 内部开发 | 本提案和兼容默认值已记录 | 可开始 |
| P1 契约定稿 | PM-01、PM-03、PM-07、PM-08 已确认 | 等待后端 |
| P2 真机联调 | PM-02、PM-04、PM-06、PM-09 已确认 | 等待后端 |
| P3 失败交互 | PM-05 已确认 | 等待后端 |
| P4 后端验收 | PM-10 场景及真实盒子基线可用 | 等待后端 |

P0 的 App 内部任务已经结束；“协议正式生效”仍是外部待办。收到后端回复后，应把
每个 PM 项的答案写回提案，再创建新版本契约、Schema、fixtures 和 ADR。

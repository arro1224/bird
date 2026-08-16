# 新接口提案｜后端 0.6.2 渐进媒体资源

> 状态：待后端确认（App 侧 P0 草案）  
> 提案编号：API-PROPOSAL-20260816-01  
> 来源：`02_发给App_适配细则.md`  
> 候选契约版本：`birdbox-v1@1.1.0`  
> URL/API Header：仍使用 `/api/v1` 与 `X-Api-Version: v1`

候选版本不是最终结论。后端文档写的是 `1.0-rc2`，而 App 已冻结的基线是
`birdbox-v1@1.0.0`。双方确认版本映射前，不修改现有 v1 OpenAPI、Schema、
fixtures、ADR 或运行时代码。

## 1. 业务功能

- 页面/按键：相册列表缩略图、照片详情大图、分组审核、对比审核、审核编辑。
- 用户目标：导入和分析尚未结束时，已生成的单张图片立即可见，不等待整批完成。
- 现有 v1 无法完成的原因：照片对象没有媒体生成状态；WebSocket 只允许完整的
  设备或任务快照；图片 404 无法区分“尚未就绪”和“文件不存在”。

## 2. 接口身份与兼容边界

- 现有路径：照片列表、照片详情以及 `thumb_ref`、`preview_ref` 指向的 GET URL。
- 新路径：本提案暂不新增路径；失败资源的重新生成接口待后端确认。
- HTTP 方法：媒体读取继续使用 GET。
- 新契约版本：候选 `birdbox-v1@1.1.0`，不得写入已冻结的
  `birdbox-v1@1.0.0`。
- 与 v1 的隔离方式：新增照片字段为可选字段；新增事件只在声明支持本提案的盒子
  版本上发送；旧盒子字段缺失时 App 继续使用旧 URL 加载逻辑。
- 不变范围：配对、Token、项目、导入、分析、mDNS 和手动 IP 连接流程。

### 2.1 能力识别（待确认）

后端需要在以下方案中确认一种，App 不通过软件版本字符串猜能力：

1. 推荐：握手或设备状态返回结构化 capability，例如
   `progressive_media: "1"`；
2. 或者：明确规定照片对象出现任一状态字段即表示支持；
3. 不接受：仅根据 `software_version >= 0.6.2` 推断。

在能力字段确认前，App 的兼容默认值是：状态字段缺失或未知时进入 `legacy` 内部
状态，按旧逻辑请求 URL，但仍使用有限重试，不能崩溃或永久缓存临时 404。

## 3. 照片对象

照片列表和详情对象增加两个可选字段：

```json
{
  "file_id": "file-xxx",
  "thumb_ref": "http://box:8080/api/v1/files/file-xxx/thumbnail",
  "preview_ref": "http://box:8080/api/v1/files/file-xxx/preview",
  "thumbnail_status": "pending",
  "preview_status": "not_requested"
}
```

| 字段 | 类型 | 必填 | 值域 | 缺失语义 |
|---|---|---:|---|---|
| `thumbnail_status` | string | 否 | `not_requested/pending/ready/failed` | `legacy`，继续请求旧 URL |
| `preview_status` | string | 否 | `not_requested/pending/ready/failed` | `legacy`，继续请求旧 URL |

未知枚举值必须被 App 安全解析为内部 `unknown`，不能造成整个照片对象解析失败。
`unknown` 的读取策略与 `legacy` 相同，但记录诊断信息。

### 3.1 状态机

```text
not_requested -> pending -> ready
                        \-> failed
ready -> pending -> ready   # 后端重新生成资源时，ETag 必须改变
failed -> pending           # 仅在后端接受重新生成后发生
```

- `not_requested` 只表达“尚未安排生成”，不等价于文件不存在。
- `pending` 表示已经排队或正在生成。
- `ready` 表示对应 URL 此时应返回图片或合法的 304。
- `failed` 是终态；除非后端接受重新生成，否则 App 不自动请求图片。
- REST 照片状态是重连后的权威状态；WebSocket 只负责降低显示延迟。

`not_requested` 如何进入 `pending` 尚未定义。App 的暂定假设是由导入/分析流水线
自动安排，读取图片 URL 不负责触发生成。若实际是按需生成，后端必须补充明确的
触发方式和幂等语义。

## 4. 图片 HTTP 语义

### 4.1 已就绪

```http
HTTP/1.1 200 OK
Content-Type: image/*
ETag: "<opaque-version>"
```

- `ETag` 按 HTTP 标准作为不透明值处理，App 不假设它一定是裸 SHA-256。
- App 有缓存值时发送 `If-None-Match`；匹配时后端可返回 `304 Not Modified`。
- 同一 `file_id + kind` 内容变化后必须返回不同 ETag。

### 4.2 尚未就绪

```http
HTTP/1.1 404 Not Found
Retry-After: 1
Content-Type: application/json
```

```json
{
  "error_code": "asset_not_ready",
  "error_message": "图片仍在生成，请稍后重试",
  "retryable": true,
  "details": {
    "file_id": "file-xxx",
    "kind": "thumbnail",
    "status": "pending"
  }
}
```

- `Retry-After` 支持整数秒；若缺失或非法，App 使用本地退避值。
- App 仅在 `error_code=asset_not_ready` 时把 404 识别为临时状态。
- 该响应和对应的错误 Widget 状态不得进入永久缓存。

### 4.3 生成失败

```http
HTTP/1.1 409 Conflict
Content-Type: application/json
```

```json
{
  "error_code": "asset_failed",
  "error_message": "图片生成失败",
  "retryable": false,
  "details": {
    "file_id": "file-xxx",
    "kind": "thumbnail",
    "status": "failed"
  }
}
```

App 停止自动请求。当前没有资源重新生成接口，因此 P1 的“手动重试”暂定为重新
读取照片状态；只有状态已经离开 `failed` 才重新取图。若产品要求按钮触发重新
生成，后端必须另行定义带幂等键的动作接口。

### 4.4 文件不存在

```http
HTTP/1.1 404 Not Found
Content-Type: application/json
```

```json
{
  "error_code": "file_not_found",
  "error_message": "文件不存在",
  "retryable": false,
  "details": {
    "file_id": "file-xxx"
  }
}
```

`file_not_found` 不得转成 `pending`，App 不自动重试。

### 4.5 鉴权（待确认）

当前 App 和 mock 的 v1 基线使用短时签名 `thumb_ref/preview_ref`，图片下载不携带
Bearer Token。后端 0.6.2 示例 URL 没有签名参数，但路径位于 `/api/v1`。

P0 暂定保持后端声明的“图片 URL 兼容”语义：URL 自带短时签名，图片客户端不附加
Bearer Token。若 0.6.2 改为 Bearer 鉴权，后端必须明确：

- 是否只允许向当前已配对盒子的同源地址发送 Token；
- URL 跳转时是否禁止把 Token 转发到其他 origin；
- 签名 URL 与 Bearer URL 的识别方式及过期错误码。

鉴权方式未确认前，不进入 P2 真机联调。

## 5. WebSocket `asset_ready`

WebSocket 地址和请求头保持不变：

```text
ws://<K7-IP>:8080/api/v1/events
Authorization: Bearer <token>
X-Api-Version: v1
```

事件必须使用完整 envelope，不能只发送来源文档中的 `event_type + payload`：

```json
{
  "event_id": "evt-asset-0001",
  "event_type": "asset_ready",
  "timestamp": "2026-08-16T10:30:00+08:00",
  "payload": {
    "job_id": "job-xxx",
    "project_id": "project-xxx",
    "file_id": "file-xxx",
    "kind": "thumbnail",
    "status": "ready",
    "etag": "\"sha256-opaque-value\"",
    "width": 512,
    "height": 341,
    "generation_mode": "embedded_thumbnail"
  }
}
```

| 字段 | 必填 | 约束 |
|---|---:|---|
| `event_id` | 是 | 稳定非空字符串，用于诊断与去重 |
| `timestamp` | 是 | 带时区 ISO 8601 |
| `job_id` | 否 | 不属于任务时允许为空/省略，待确认 |
| `project_id` | 是 | 非空字符串 |
| `file_id` | 是 | 非空字符串 |
| `kind` | 是 | `thumbnail` 或 `preview` |
| `status` | 是 | 本事件固定为 `ready` |
| `etag` | 是 | 与图片响应头 ETag 完全一致的不透明值 |
| `width/height` | 是 | 正整数 |
| `generation_mode` | 否 | 诊断信息，App 不据此决定业务逻辑 |

App 以“当前设备 ID + `file_id + kind`”定位资源，只使该资源的旧错误/等待状态
失效并立即取图，不刷新整页。断线重连后必须重新读取 REST 状态；不能把遗漏事件
视为资源仍未就绪。

## 6. App 侧重试与缓存约束

以下是 App 实施策略，不要求后端复刻计时器：

- 收到 `asset_not_ready` 后优先使用合法的 `Retry-After`，否则按
  1 秒、2 秒、4 秒、5 秒退避。
- 单个资源每个激活周期最多自动请求 5 次；页面销毁、资源变更或终态会取消计时器。
- `asset_ready` 到达时取消等待，清除旧错误状态并立即重试。
- `asset_failed`、`file_not_found` 和其他非临时错误不自动重试。
- 新 ETag 到达时清除同一资源的旧缓存/错误；缓存键同时包含设备、文件和资源种类。
- 详情页保留已解码的缩略图，预览图完整解码后才替换，避免闪白。
- WebSocket 断线时，有限 HTTP 重试仍能恢复；达到上限后由页面刷新或用户操作开始
  新的激活周期，禁止后台无限轮询。

## 7. 待后端逐项确认

| ID | 问题 | App 暂定值 | 阻塞批次 |
|---|---|---|---|
| PM-01 | `1.0-rc2` 与冻结的 `birdbox-v1@1.0.0` 是什么关系？ | 按新提案 `1.1.0` 管理，不覆盖冻结文件 | P1 契约入库 |
| PM-02 | 是否提供结构化 capability？ | 字段出现即启用，缺失走 legacy | P2 真机联调 |
| PM-03 | `asset_ready` 是否包含 `event_id/timestamp`？`job_id` 是否可空？ | 使用本文完整 envelope | P1 事件 fixture |
| PM-04 | `not_requested` 由什么操作触发生成？ | 导入流水线自动安排，GET 不触发 | P2 行为验收 |
| PM-05 | `failed` 如何人工重新生成？ | 只重新读状态，不触发生成 | P3 失败入口 |
| PM-06 | 图片 URL 是短时签名还是 Bearer 鉴权？ | 保持短时签名且下载不带 Token | P2 安全联调 |
| PM-07 | `etag` 是否与 HTTP ETag 头逐字一致，是否含引号？ | 作为不透明值逐字透传 | P1 缓存测试 |
| PM-08 | `kind` 是否同时支持 `thumbnail/preview`？ | 两者都支持 | P3 大图验收 |
| PM-09 | `ready` 后短暂 404 是否仍返回 `asset_not_ready`？ | 允许并进入有限重试 | P2 异常验收 |
| PM-10 | 盒子能否提供可控 pending/ready/failed/WS 断线场景？ | 先由 App mock 实现 | P4 真机验收 |

## 8. 交付物

- [x] 独立接口提案
- [ ] 后端逐项书面确认 PM-01 至 PM-10
- [ ] 分配正式契约版本
- [ ] 新版本 OpenAPI
- [x] 候选 Photo 扩展与 AssetReadyEvent JSON Schema（尚未并入正式契约）
- [x] 候选正反 fixtures（尚未并入冻结 fixture manifest）
- [ ] ADR
- [ ] 契约测试
- [ ] 迁移与回滚计划

## 9. 功能映射

- 实施批次：P0 协议提案；P1 模型/mock/资源状态机；P2 相册列表；P3 详情与审核；
  P4 联调验收。
- 页面：相册列表、照片详情、分组审核、对比审核、审核编辑。
- 入口：照片缩略图、详情大图、失败资源手动操作。
- Owner：单人 App 开发；协议批准人与盒子 API Owner 待后端填写。

## 10. 迁移与回滚

- 旧盒子：状态字段缺失，App 使用 `legacy` 路径。
- 新盒子：状态字段和事件按能力启用，单资源更新。
- 回滚：关闭渐进媒体能力后，App 退回旧 URL 加载；不改变配对、项目、导入和分析。
- 安全边界：不根据版本号猜能力，不向非当前盒子 origin 泄露 Bearer Token，不永久
  缓存临时 404。

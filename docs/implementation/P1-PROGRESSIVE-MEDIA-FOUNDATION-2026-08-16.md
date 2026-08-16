# P1｜渐进媒体底层能力

> 日期：2026-08-16  
> 状态：App 内部实施完成，正式契约仍等待后端确认  
> 上游：`P0-PROGRESSIVE-MEDIA-PROTOCOL-2026-08-16.md`

## 1. 本批次交付

- `PreviewRef` 支持 `thumbnail_status` 与 `preview_status`。
- 状态缺失映射为 App 内部 `legacy`，未知枚举映射为 `unknown`；两者继续使用旧 URL
  逻辑，不会导致照片对象解析失败。
- `DeviceEvent` 保留可选 `event_id`，新增容错的 `AssetReadyEvent` 解析。
- 新增全局 `MediaAssetCoordinator`，按
  `device_id + file_id + thumbnail/preview` 定向管理状态、ETag、错误和 Timer。
- 新增不携带 REST Bearer Token 的签名媒体下载器，支持 ETag、If-None-Match、304、
  Retry-After 和错误正文分类。
- 新增媒体磁盘缓存适配与加载服务；新 ETag 事件会删除目标资源缓存，不清空整页或
  其他照片缓存。
- 自动重试为 1/2/4/5/5 秒，单激活周期最多 5 次；资源就绪、终态或销毁时取消
  Timer。
- 依赖图中只创建一套长生命周期协调器和下载服务，供 P2/P3 页面复用。

## 2. HTTP 分类

| HTTP/错误码 | App 分类 | 自动重试 |
|---|---|---:|
| `404 asset_not_ready` | `notReady` | 是，遵循 Retry-After 和次数上限 |
| `409 asset_failed` | `assetFailed` | 否，状态进入 failed |
| `404 file_not_found` | `fileNotFound` | 否 |
| `401/403` | `unauthorized` | 否 |
| `408/429/5xx/网络超时` | `transient` | 是，但仍受次数上限 |
| 其他响应 | `other` | 否 |

下载异常对象不输出签名 URL，避免把查询串中的短时凭据写入日志。

## 3. K7 Mock 模式

旧模式保持默认：

```powershell
dart run tool/mock_box_server/server.dart --quick
```

P1 渐进模式：

```powershell
dart run tool/mock_box_server/server.dart --quick --progressive-media
```

渐进模式提供：

- 照片状态字段；
- `/api/v1/files/{fileId}/thumbnail|preview` 签名资源 URL；
- pending/not_requested 的 404 + Retry-After；
- failed 的 409；
- ready 的 ETag/304；
- 完整 `asset_ready` WebSocket envelope；
- `/mock/control/assets` 单资源状态控制；
- `/mock/control/events` 事件开关和断线模拟。

状态初始分布是确定的：`photo-0001` 为 ready、`photo-0002` 为 failed，其余多数为
pending；每 8 张重复一组，便于稳定自动化测试。

## 4. 候选契约产物

所有新 Schema 与 fixture 位于
`docs/contracts/proposals/progressive-media/`，未加入冻结 v1 manifest：

- Photo 媒体状态扩展 Schema；
- AssetReadyEvent Schema；
- 渐进 Photo 与 asset_ready 正向 fixture；
- asset_not_ready、asset_failed、file_not_found 错误 fixture。

正式版本号确定后，才能把这些候选产物迁移到正式契约目录。

## 5. P2 接入边界

P2 的 `PhotoTile` 只需要：

1. 用当前设备 ID、`photo.id`、thumbnail 构造 `MediaAssetDescriptor`；
2. 调用共享 `MediaAssetService.load`；
3. 只订阅该 key 的 `MediaAssetCoordinator.watch`；
4. 在 `retryDue/assetReadyEvent` 时重新加载当前资源；
5. pending/not_requested 显示占位，terminalFailure 显示失败入口。

P2 不得再创建自己的指数退避 Timer，也不得在 `asset_ready` 时调用整个
`GalleryCubit.refresh()`。

## 6. 仍待后端确认

P1 使用 P0 的可逆默认值实现。PM-01 至 PM-10 尚未获得后端书面回复，尤其是正式
版本号、capability、图片鉴权和 failed 重新生成接口。因此本批次可以进入 P2 的
相册列表开发，但不能宣称后端 0.6.2 真机协议已经定稿。

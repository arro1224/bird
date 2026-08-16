# P2｜相册列表渐进式缩略图

> 日期：2026-08-16  
> 状态：App 实施与 K7 联调完成，正式契约仍等待后端确认  
> 上游：`P1-PROGRESSIVE-MEDIA-FOUNDATION-2026-08-16.md`

## 1. 本批次交付

- 新增可复用的 `ProgressiveMediaImage`，统一处理等待、加载、展示、终态失败和
  手动重试。
- 相册 `PhotoTile` 已按
  `device_id + file_id + thumbnail` 绑定共享 `MediaAssetCoordinator`。
- `pending`、`not_requested` 显示稳定占位，不把 404 当作破图。
- `ready` 和旧协议未返回状态的照片继续加载 URL，兼容当前后端。
- `asset_ready` 只唤醒事件命中的缩略图，不刷新相册列表，也不影响其他卡片。
- WebSocket 不可用时才启用共享协调器的有限 HTTP 轮询；设备离线时不发起轮询。
- `404 asset_not_ready` 按 P1 策略有限重试；`409 asset_failed` 进入终态，只有用户
  点击后才重新检查。
- 新资源加载、组件销毁或资源身份变化时会取消旧请求，避免列表复用导致串图。

## 2. 页面接入边界

本批次只接入相册列表缩略图：

- 已修改：相册页、瀑布流中的 `PhotoTile`。
- 未修改：照片详情、审核页预览图和全屏预览；这些属于 P3。
- 未新增资源生成请求；失败态按钮只重新检查已有 URL，不假定后端已提供重新生成
  接口。

## 3. 自动化验收

覆盖以下行为：

1. 两张 pending 照片中，`asset_ready` 只加载目标照片；
2. WebSocket 不可用时，404 后由协调器触发有限重试并显示成功图片；
3. 409 后不会自动重试，点击失败入口后才再次检查；
4. 原 `PhotoTile` 与 1200 张照片瀑布流回归通过；
5. P1 协调器、模型、Mock、缓存身份和渐进协议候选契约回归通过；
6. Flutter 全量静态分析无问题，正式 v1 契约校验通过。

## 4. K7 实机联调记录

在当前已启动的 `127.0.0.1:8787 --progressive-media` 模拟盒子上，以
`photo-0060/thumbnail` 验证：

| 阶段 | 结果 |
|---|---|
| pending 请求 | `404 asset_not_ready`，`Retry-After: 1` |
| 控制为 ready | 返回资源状态与 `mock-photo-0060-thumbnail-v2` ETag |
| ready 请求 | `200 image/png`，携带相同 ETag |
| If-None-Match | `304 Not Modified` |
| 联调结束 | 已把该资源恢复为 pending |

## 5. 后续批次

P3 可复用同一个 `ProgressiveMediaImage` 接入详情页和审核页 preview，但应继续遵守
定向更新、共享重试和设备隔离规则。后端正式版本号、capability、鉴权以及 failed
重新生成接口未确认前，候选协议仍不能迁入冻结 v1 契约。

# P3｜详情与审核渐进式预览图

> 日期：2026-08-16  
> 状态：App 实施与 K7 联调完成，正式契约仍等待后端确认  
> 上游：`P2-PROGRESSIVE-GALLERY-2026-08-16.md`

## 1. 本批次交付

- 新增 `ProgressivePhotoImage`，统一把 `PhotoSummary` 的 URL、状态与
  `device_id + file_id + thumbnail/preview` 资源身份接入 P1 协调器。
- 单张照片详情大图接入渐进 preview。
- 分组审核主图和横向缩略图接入渐进媒体。
- 双图对比的左右 preview 独立订阅和定向更新。
- 审核编辑页的当前结果图接入同一 preview 状态机。
- preview 尚未完整解码时持续保留 thumbnail；第一帧可显示后才替换，避免闪白。
- 缺少 URL、生成等待和终态失败分别展示，不再把缺少 URL 当作持续加载。
- 失败资源只提供“重新检查”，不假定 GET 会触发生成，也不伪造后端尚未确认的
  重新生成接口。
- 小尺寸分组缩略图使用自适应图标失败入口，避免 76px 卡片内容溢出。

## 2. 页面接入范围

| 页面/区域 | 资源 | 渐进策略 |
|---|---|---|
| 照片详情 | preview + thumbnail | thumbnail 保底，preview 解码后替换 |
| 分组审核主图 | preview + thumbnail | thumbnail 保底，事件定向更新 |
| 分组审核照片条 | thumbnail | 独立资源状态和紧凑失败入口 |
| 双图对比 | 两个 preview | 两侧按 file_id 独立更新，不重载整页 |
| 审核编辑当前结果 | preview + thumbnail | 复用详情资源和缓存身份 |

审核保存、评分、缩放、翻页、分组选择和编辑逻辑均未改变。

## 3. 自动化验收

P3 专项覆盖：

1. preview pending 时 thumbnail 已加载并持续显示；
2. `asset_ready(kind=preview)` 只启动目标 preview；
3. preview 首帧完成后替换 thumbnail；
4. 对比页 409 不自动重试，用户点击后才重新检查；
5. 审核编辑卡片复用相同渐进路径；
6. 76px 分组缩略图失败入口无布局溢出；
7. 最小依赖测试替身和无媒体 URL 的旧页面保持兼容。

审核模块、P2 相册和 P1 协调器联合回归共 64 项通过。

## 4. K7 联调记录

在当前 `127.0.0.1:8787 --progressive-media` 模拟盒子上，以
`photo-0060/preview` 验证：

| 阶段 | 结果 |
|---|---|
| not_requested 请求 | `404 asset_not_ready`，`Retry-After: 1` |
| 控制为 ready | 返回 `mock-photo-0060-preview-v2` ETag |
| ready 请求 | `200 image/png`，携带相同 ETag |
| If-None-Match | `304 Not Modified` |
| 联调结束 | 已恢复为原始 `not_requested` |

## 5. 后续批次

P4 只做跨版本、断线、乱序、压力和真实后端联调验收，不应再新增页面能力。后端尚未
确认 PM-05 的重新生成接口，因此 P3 失败入口仍只重新读取现有资源。

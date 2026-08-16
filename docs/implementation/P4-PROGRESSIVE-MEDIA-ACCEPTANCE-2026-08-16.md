# P4｜渐进媒体联调与发布门禁

> 日期：2026-08-16  
> 状态：App 与可控 K7 验收完成；真实后端协议签字仍待后端成员  
> 上游：`P3-PROGRESSIVE-REVIEW-2026-08-16.md`

## 1. 本批次交付

- 新增可命令行运行的 `progressive_media_p4_acceptance.dart`，可直接对已启动的
  `--progressive-media` K7 执行发布门禁。
- 新增 P4 自动化验收测试，覆盖可控 K7、旧版 K7、默认重试上限和千资源压力。
- 验收过程只临时修改两张 `pending/not_requested` 照片，退出前恢复两个资源状态和
  WebSocket 事件开关；恢复失败会使命令失败。
- P4 不新增页面、接口假设或后台轮询逻辑。

## 2. 验收矩阵

| 场景 | 验收结果 |
|---|---|
| 旧 K7 不返回状态字段 | 映射为 legacy，旧 URL 图片可读 |
| pending/not_requested | `404 asset_not_ready`，Retry-After 为 1 秒 |
| ready | 图片非空，事件 ETag 与 HTTP ETag 完全一致 |
| If-None-Match | 返回 304 |
| thumbnail/preview 乱序完成 | 严格按 WebSocket 到达顺序定向处理 |
| WebSocket 被关闭 | 观察到断线/重连状态 |
| 事件关闭后资源 ready | 未收到 asset_ready，但 HTTP 可恢复图片 |
| 默认自动重试 | 第 5 次后严格停止 |
| 1000 资源逆序 ready | 目标订阅只收到一次，另一设备同名资源不受影响 |
| 紧凑失败入口 | 76px 缩略图无溢出 |
| 验收结束 | 临时资源和事件开关恢复 |

## 3. 当前 K7 实跑结果

执行：

```powershell
dart run tool/acceptance/progressive_media_p4_acceptance.dart `
  http://127.0.0.1:8787
```

结果：

- 设备：`mock-k7-001`；API：`v1`；
- 测试资源：`photo-0060` 与 `photo-0059`；
- ready thumbnail：1,796,852 bytes；
- WS 无事件时 HTTP fallback preview：1,857,846 bytes；
- 乱序事件：`photo-0059:thumbnail` 后 `photo-0060:preview`；
- WebSocket 断线已观察，HTTP fallback 已验证；
- 本次验收约 0.5 秒；
- 两张照片最终恢复为 thumbnail=pending、preview=not_requested，事件开关恢复开启。

## 4. 发布命令

每次后端版本或 App 网络层发生变化后执行：

```powershell
flutter test --no-pub `
  test/bird_companion/acceptance/progressive_media_p4_acceptance_test.dart

dart run tool/acceptance/progressive_media_p4_acceptance.dart `
  http://<K7-IP>:<PORT>

flutter analyze --no-pub
dart run tool/contracts/verify_contracts.dart
```

## 5. 尚不能关闭的外部项

当前运行实例是 App 仓库内的可控 K7 模拟盒子，不等价于后端成员交付的正式设备
版本。以下内容仍需后端书面确认后才能将候选契约迁入正式目录：

- 新协议正式版本号与 capability；
- `asset_ready` 完整 envelope 与 ETag 逐字一致性；
- 图片鉴权方式；
- `not_requested` 的生成触发方式；
- failed 资源的正式重新生成接口；
- 正式 K7 对 pending、failed、断线和乱序场景的可控方式。

因此 P0-P4 的 App 实施与模拟验收已经闭环，但“真实后端协议正式验收通过”仍是外部
待办，不能由 App 侧单方面标记完成。

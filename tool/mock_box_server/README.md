# 照片模块模拟盒子

该服务用于本地恢复照片首页、详情、场景、连拍组和审阅操作的数据链路。它只依赖 Dart SDK，不需要安装额外服务。

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
--quiet
```

启动后可访问：

- 宿主机：`http://127.0.0.1:8787`
- Android 模拟器：`http://10.0.2.2:8787`
- 健康检查：`GET /healthz`

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

WebSocket 事件、复制任务和日志导出不属于 B1 范围，当前服务未实现。

## 图片资源

`assets/` 内的 4 张鸟类照片由 OpenAI 图像生成工具为本项目生成，仅用于本地 mock、测试和界面开发：

- `kingfisher.png`：水边翠鸟，横向自然摄影。
- `egret.png`：浅水白鹭，竖向自然摄影。
- `warbler.png`：芦苇间苇莺，横向自然摄影。
- `sandpiper.png`：滩涂鹬鸟，竖向自然摄影。

图片不含文字和水印。1200 张数据会重复分配这 4 个资源；它们不是最终产品内容，也不替换用户照片。

## 验证

```powershell
flutter test test/bird_companion/core/media_uri_resolution_test.dart test/bird_companion/core/mock_box_server_test.dart
```

测试覆盖媒体相对地址解析、图片可访问性、批次解析、1200 张游标分页、场景与连拍组、详情与历史、决定保存及批量操作。

# RC4-SIM vivo 真机 Debug 模拟测试操作手册

**日期：** 2026-09-03  
**项目：** `D:\Androidstudio2\project\4`  
**设备：** vivo X20，ADB serial `b502aabb`  
**性质：** Debug 模拟预验收，不是真实 K7 证据，不可用于 Release 放行

## 1. 启动前清理

如果窗口中已有 Mock Server，先按 `Ctrl+C` 停止。未指定 `--state-file` 时，重启会清除之前验收创建的模拟项目和任务，避免 B12-A 从被修改的 current project 开始。

确认手机已开启 USB 调试并连接：

```powershell
& "D:\Androidstudio2\platform-tools\adb.exe" devices -l
```

应看到 `b502aabb device`。

## 2. 窗口 1：HTTP Mock Server

完整复制以下命令并保持窗口运行：

```powershell
Set-Location -LiteralPath "D:\Androidstudio2\project\4"

dart run .\tool\mock_box_server\server.dart --quick `
  --auth `
  --progressive-media `
  --host=0.0.0.0 `
  --port=8787 `
  --device-id=bbx-82f41c9e7a3d4b68a1501e21e536c649
```

预期出现：

```text
K7 mock box is running.
Photos: 60
Authentication: enabled
Progressive media: enabled
Press Ctrl+C to stop.
```

此启动方式会覆盖 RC4 临时配对会话、Bearer REST、WebSocket 事件和渐进图片。每个 Mock 进程的 RC4 `pairing_session_id` 只能消费一次；重新安装或重新完整运行 App 前，应先 `Ctrl+C` 并重新启动窗口 1。

## 3. 窗口 2：ADB 映射并运行 Debug 模拟入口

完整复制：

```powershell
Set-Location -LiteralPath "D:\Androidstudio2\project\4"

& "D:\Androidstudio2\platform-tools\adb.exe" `
  -s b502aabb reverse tcp:8787 tcp:8787

& "D:\Androidstudio2\platform-tools\adb.exe" `
  -s b502aabb reverse --list

Invoke-RestMethod http://127.0.0.1:8787/health

& "D:\flutter344\flutter\bin\flutter.bat" run `
  -d b502aabb `
  --debug `
  --flavor birdV1 `
  -t .\lib\main_bird_simulated.dart `
  --dart-define=BIRD_TEST_BASE_URL=http://127.0.0.1:8787 `
  --dart-define=BIRD_SIMULATED_DEVICE_ID=bbx-82f41c9e7a3d4b68a1501e21e536c649
```

`adb reverse --list` 应显示：

```text
(reverse) tcp:8787 tcp:8787
```

也可只执行窗口 2 的 ADB 命令，然后在 Android Studio 选择共享运行配置：

```text
Bird V1 - Simulated Box (Debug)
```

不要选择 `Bird V1 - New Device UI`，后者是生产入口，会扫描真实 BLE 广播。

## 4. vivo 页面操作

1. 确认标题为“模拟 · 查找盒子”；右上角不再显示 `SIMULATED` 角标；
2. 等待 `BirdBox-B7B7B7B7` 出现，点击“连接此盒子”；
3. 点击“开始配对”，输入任意 6 位数字，例如 `123456`；
4. 点击“安全配对并连接”；
5. 选择“直连盒子”，等待“盒子直连已就绪”；
6. 点击“完成”；
7. App 会真实访问窗口 1 的 `/health`，核对 HTTP `device_id` 与模拟 BLE 身份；随后用 BLE 模拟产生的临时会话向 `/api/v1/pairing` 换取 Bearer，并连接 REST/WebSocket；
8. 成功后直接进入正式三标签首页，不再进入“模拟验收结果”页，也不显示 `SIMULATED` 角标；
9. 首页应显示 Mock 中的相册数据。继续检查相册分页/筛选、照片详情与保留/弃用、任务中心、存储与复制、设备状态、系统日志和设置页；这些页面使用正式 Repository，只是服务端地址指向本机 Mock。

还可返回重跑“加入现有 Wi-Fi”，验证 Wi-Fi 扫描/手动输入和 DPP 模拟事件；Direct AP、STA 与 DPP 的终态地址都固定映射到 `http://127.0.0.1:8787`。

## 5. 命令行验收

`b12a_k7_acceptance.dart` 不负责获取 Bearer，因此不能直接复用上面开启 `--auth` 的进程。先停止 App 与窗口 1，再以无鉴权模式重新启动一个全新 Mock：

```powershell
dart run .\tool\mock_box_server\server.dart --quick `
  --host=0.0.0.0 `
  --port=8787 `
  --device-id=bbx-82f41c9e7a3d4b68a1501e21e536c649
```

然后在窗口 2 执行：

```powershell
Set-Location -LiteralPath "D:\Androidstudio2\project\4"

dart run .\tool\acceptance\b12a_k7_acceptance.dart `
  --base-url=http://127.0.0.1:8787

dart run .\tool\acceptance\ble_provisioning_rc4_acceptance.dart `
  --base-url=http://127.0.0.1:8787
```

B12-A 应返回 `"result": "pass"`。RC4 模拟报告应返回：

```text
result=pass
environment=simulated
releasable=false
real_k7_status=pending
```

如果中途中断 B12-A，再次运行前先到窗口 1 按 `Ctrl+C` 并重新启动 Mock，确保进程内模拟状态恢复初始值。

## 6. 本入口的安全边界

- `lib/main_bird_simulated.dart` 在非 Debug 模式直接拒绝启动；
- Fake BLE/Wi-Fi/DPP 只由 `lib/main_bird_simulated.dart` 引用，没有接入 `lib/main.dart`；生产入口仍创建真实平台 BLE/GATT、Wi-Fi 与 DPP 实现；
- 模拟入口不恢复真实盒子的已保存会话，模拟 Token 使用 `persist=false`，不会写入或覆盖 Android Keystore 中的真实盒子凭据；
- 配网完成后复用正式 `BirdAppRouter`、三标签首页、业务 Repository、REST 和 WebSocket 客户端，因此可以测试首页后的业务闭环；
- 地址只允许 `127.0.0.1`、`localhost` 或模拟器专用 `10.0.2.2`，必须显式提供端口；
- 设备 ID 必须满足 `bbx-` 加 32 位小写十六进制；
- 模拟通过不能替代真实 GATT 加密、真实 AP/STA/DPP、厂商兼容性或 K7 发布证据。

## 7. 实施验证结果

- Debug 模拟入口已从“结果页”升级为“建立正式业务会话并进入三标签首页”；
- 完整配网 acceptance、Mock Server 安全与 Fake 隔离回归：38 项通过；
- 独立鉴权 Mock 已验证 `/health` → RC4 `/api/v1/pairing` → Bearer 设备状态与项目接口；
- B12-A 对全新 Mock 进程执行通过，包括 409/422、任务控制、报告和日志；
- RC4 SIM-01～SIM-10 模拟报告全部通过，并保持不可发布标记；
- `birdV1` Debug 模拟 APK 编译成功：`build/app/outputs/flutter-apk/app-birdv1-debug.apk`；
- 静态分析无问题，生产完整性门禁通过。

本轮自动验证时 `adb devices -l` 未发现 `b502aabb`，因此 vivo 上的最终点击与首页截图仍需按第 2～4 节执行。该项只影响本次实机操作证据，不影响已完成的代码、协议与 Android APK 构建验证。

联调过程中修复了一个模拟验收暴露的真实客户端问题：原 `X-Idempotency-Key` 只含系统微秒时间，在 Windows 时钟分辨率下连续请求可能碰撞。现已增加进程内单调序号，重新启动全新 Mock 后 B12-A 的过期版本 409 校验通过。

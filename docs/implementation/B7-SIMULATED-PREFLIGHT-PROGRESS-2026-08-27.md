# B7 模拟预检进度记录

日期：2026-08-28
工作分支：`part2`
同步基线：`thirdtime@463b25d9bd60b3bce4183d637dfd69114d4e22f0`

## 当前结论

B7 simulated preflight 已完成。当前可以展示 App 页面跳转、蓝牙发现/配对入口、Wi-Fi 配网方式选择、DPP 安全失败回退和 Fake BLE/Wi-Fi/DPP 边界行为。

当前结论只能写作：

```text
B7 simulated preflight passed; real K7 acceptance pending.
```

不得写成 B7 Release 通过、真实 K7 已验收或 S4 已关闭。

## 已完成

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| RC4 模拟验收报告契约 | 已完成 | `21a22b643`、`9b92f8ead` |
| 模拟报告失败关闭 | 已完成 | 任一 SIM case 失败时顶层 `result=fail`，CLI 返回非零 |
| SIM-01 至 SIM-10 案例清单 | 已完成 | `tool/acceptance/ble_provisioning_rc4_acceptance.dart` |
| Fake BLE 发现、命令、断连边界 | 已完成 | `ble_provisioning_simulated_flow_test.dart` |
| Fake Wi-Fi 加入、绑定、释放边界 | 已完成 | `ble_provisioning_simulated_flow_test.dart` |
| Fake DPP 能力、启动、临时 URI 清理 | 已完成 | `ble_provisioning_simulated_flow_test.dart` |
| 配网页面入口和安全文案 | 已完成 | `network_provisioning_page_test.dart` |
| B7 页面接入真实模拟状态流 | 已完成 | `880509566`、`b7_simulated_demo_page_test.dart` |
| B7 页面新版 SDK widget 回归 | 已完成 | `b7_simulated_demo_page_test.dart` 2/2 |
| B7 Preflight 全量门禁 | 已完成 | `build/b7/b7-gate-evidence.json` |
| 模拟 runner stderr 兼容 | 已完成 | `run_b7_gate.ps1`、`b7_preflight_gate_test.dart` |

## 当前未完成

- 真实 K7、真实 Android、Release 签名和 S4 关闭。

## 已完成（本批次）

- 真实设备证据空模板（`docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json`）；

## 最新验证

以下命令在本工作树使用 Flutter 3.44.5 / Dart 3.12.2 执行通过：

```powershell
flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart
flutter test --no-pub test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart
flutter test --no-pub test/bird_companion/features/connection/network_provisioning_page_test.dart
flutter analyze --no-pub tool/acceptance/ble_provisioning_rc4_acceptance.dart test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart
flutter test --no-pub test/bird_companion/acceptance test/bird_companion/features/connection test/contracts
powershell -ExecutionPolicy Bypass -File tool/release/run_b7_gate.ps1 -Mode Preflight -FlutterCommand D:\flutter_3.44.5\bin\flutter.bat -DartCommand D:\flutter_3.44.5\bin\cache\dart-sdk\bin\dart.exe
```

结果：RC4 模拟报告 10/10、B7 页面 2/2、B7 acceptance/connection/contracts 129/129、Preflight 全量门禁通过；`flutter analyze`、契约验证和生产完整性均为通过，debug APK 已构建。

## 安全和边界

- 模拟报告固定 `environment=simulated`、`releasable=false`、`real_k7_status=pending`；
- `base-url` 拒绝 userinfo、query 和 fragment，避免敏感值进入证据；
- 不在生产入口、正式 flavor 或依赖装配中增加 Fake/Mock 开关；
- 不修改冻结 RC4 UUID、Schema、错误码、超时、幂等和 operation 语义；
- Release 仍必须提供真实 K7 证据，不接受模拟报告。

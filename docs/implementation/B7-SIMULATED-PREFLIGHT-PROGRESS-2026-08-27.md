# B7 模拟预检进度记录

日期：2026-08-27
工作分支：`part2`
同步基线：`thirdtime@463b25d9bd60b3bce4183d637dfd69114d4e22f0`

## 当前结论

B7 已进入 simulated preflight 阶段。当前可以展示 App 页面跳转、蓝牙发现/配对入口、Wi-Fi 配网方式选择、DPP 安全失败回退和 Fake BLE/Wi-Fi/DPP 边界行为。

当前结论只能写作：

```text
B7 simulated preflight in progress; real K7 acceptance pending.
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

## 当前未完成

- B7 Preflight 脚本的最终全量回归；
- B7 acceptance/flow/page 的 Flutter widget 回归（当前机器 Flutter 3.38.1 / Dart 3.10.0，不满足项目 Dart `>=3.12.0`，编译器无法启动）；
- 真实 K7、真实 Android、Release 签名和 S4 关闭。

## 已完成（本批次）

- 真实设备证据空模板（`docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json`）；

## 最新验证

以下命令在本工作树执行通过：

```powershell
flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart
flutter test --no-pub test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart
flutter test --no-pub test/bird_companion/features/connection/network_provisioning_page_test.dart
flutter analyze --no-pub tool/acceptance/ble_provisioning_rc4_acceptance.dart test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart
```

结果：此前验收报告 3/3、模拟边界 3/3、配网页面 10/10；本批次 B7 页面相关 Dart 静态分析 `No issues found`。Flutter widget 测试需在满足项目 SDK 要求的环境重新执行。

## 安全和边界

- 模拟报告固定 `environment=simulated`、`releasable=false`、`real_k7_status=pending`；
- `base-url` 拒绝 userinfo、query 和 fragment，避免敏感值进入证据；
- 不在生产入口、正式 flavor 或依赖装配中增加 Fake/Mock 开关；
- 不修改冻结 RC4 UUID、Schema、错误码、超时、幂等和 operation 语义；
- Release 仍必须提供真实 K7 证据，不接受模拟报告。

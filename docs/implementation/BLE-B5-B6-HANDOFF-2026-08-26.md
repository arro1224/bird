# BLE B5/B6 新对话交接文档（2026-08-26）

## 1. 当前目标

在不修改成员 A 负责范围的前提下完成成员 B 的 BLE B5/B6 开发、测试、审查、最终验证，并在全部无问题后将本地 `part2` 快进推送到远端 `thirdtime`。

用户已明确授权：**如果全部验证无问题，直接推送到远端 `thirdtime`。**

禁止直接合并 `origin/part1`。

## 2. 工作区和 Git 状态

- 工作目录：`D:\birdphoto\bird_part2_ble`
- linked worktree：是
- 当前分支：`part2`
- 当前代码 HEAD（文档提交前）：`637d6a4568500e4752299f2d48df267d3629a6b1`
- 当前远端基线：`origin/thirdtime@6b6a81ee0261d55ce86aa51fd5cfe3e62ccb08e0`
- 分叉状态：`part2` 比 `origin/thirdtime` 领先 13 个提交、落后 0 个提交
- 当前尚未推送
- 文档提交前的未跟踪文件（本次将一并提交）：
  - `docs/implementation/B6-A-WEBSOCKET-CLOSE-BLOCKER-2026-08-26.md`
  - 本交接文档 `docs/implementation/BLE-B5-B6-HANDOFF-2026-08-26.md`
- 当前 stash：
  - `stash@{0}: backup B6 contract and A blocker before thirdtime sync 2026-08-26`
  - 该 stash 是同步 A hotfix 前的保险备份。**不要再次 pop/apply**，其中 B6 测试已用更新版本提交到当前分支。

Git 安全目录写法：

```powershell
git -c safe.directory=D:/birdphoto/bird_part2_ble <command>
```

固定 Flutter/Dart SDK：

```text
D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat
D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat
```

沙箱执行 Flutter 时使用当前进程级 Git safe-directory：

```powershell
$env:CI='true'
$env:GIT_CONFIG_COUNT='1'
$env:GIT_CONFIG_KEY_0='safe.directory'
$env:GIT_CONFIG_VALUE_0='D:/birdphoto/.tooling/flutter-3.44.5'
```

## 3. A/B 所有权边界

以下成员 A 路径保持只读，不得由 B 修改：

- `android/app/src/main/java/**`
- `lib/bird_companion/features/connection/data/ble/**`
- `lib/bird_companion/features/connection/data/platform/**`
- `lib/bird_companion/features/connection/domain/**`
- `lib/bird_companion/features/connection/data/provisioning_repository_impl.dart`
- `lib/bird_companion/features/connection/data/connection_repository_impl.dart`
- `lib/bird_companion/core/network/**`
- `lib/bird_companion/core/session/**`
- `lib/bird_companion/app/app_dependencies.dart`

B 侧允许范围：

- connection presentation
- B 侧测试和 Fake
- release integrity gate
- B5/B6 设计、计划和交接文档

## 4. `thirdtime` A hotfix 同步情况

A 修复已经拉取并合入 `part2`：

- 远端提交：`5c952c8e8 fix(connection): close replaced event sockets gracefully`
- 远端合并：`6b6a81ee0 merge(hotfix-A6): close replaced event sockets gracefully`
- 本地合并提交：`d6f66046a merge(hotfix-A6): sync WebSocket close fix into part2`

A hotfix 只修改：

- `lib/bird_companion/core/network/event_client.dart`
- `test/bird_companion/core/event_client_close_test.dart`

没有直接合并 `origin/part1`。

## 5. 已完成提交

按时间顺序：

```text
244ce661f docs(connection): design BLE B5 B6 integration
c3ed2a8d6 docs(connection): plan BLE B5 B6 integration
9856cdf8e feat(connection): classify B5 DPP outcomes
50f8ad771 test(connection): harden B5 DPP terminal states
99297d7df feat(connection): complete B5 DPP presentation
6acbe6014 test(connection): cover unknown B5 failures
d26654559 fix(connection): serialize B5 DPP actions
157c86cd7 test(connection): lock B6 recovery presentation
d6f66046a merge(hotfix-A6): sync WebSocket close fix into part2
a5d9c7a75 test(connection): verify B6 session recovery
12cb2567a test(connection): order B6 recovery refresh
6cf59ca2e test(connection): enforce production BLE isolation
```

## 6. 已完成工作

### 6.1 B5 Cubit DPP 结果分类

完成内容：

- 新增 `NetworkProvisioningPhase.dppUnavailable`
- 用户取消映射为 `cancelled`
- 手机/系统 DPP 不可用映射为 `dppUnavailable`
- 普通 DPP 失败映射为脱敏 `failure`
- 诊断信息不进入 presentation state
- DPP bootstrap/handoff 必须等待匹配盒端状态确认后才能成功
- `dppUnavailable` 是稳定终态，晚到错误不会覆盖
- DPP 启动增加 synchronous single-flight 防护

评审中发现的 Important 已全部修复。

### 6.2 B5 安全界面和重试

完成内容：

- DPP 不可用固定安全页面
- 返回 Wi-Fi 方法选择并清理旧状态
- 仅 `systemDppFailed` / `dppTimeout` 显示 DPP retry
- 非 DPP和未知错误不显示 DPP retry
- 快速双击只发一个 repository DPP 命令
- 返回方法页后忽略旧 DPP stream error
- UI 不展示 diagnostic、DPP URI 或其他私密内容

验证：最终 Cubit + page 测试 34/34 通过；加入 Task 3 后为 35/35。

### 6.3 B6 NetworkRecovered presentation contract

提交：`157c86cd7`

验证：

- recovery 显示“已恢复可用网络”
- 不显示 DPP 成功文案
- 不显示“完成”按钮
- 不调用 `onCompleted`
- 不显示 passphrase 或地址

### 6.4 B6 startup 和 dynamic-address session contract

提交：

- `a5d9c7a75 test(connection): verify B6 session recovery`
- `12cb2567a test(connection): order B6 recovery refresh`

验证：

- offline startup 保留 saved device，不 reconnect
- online startup reconnect 一次
- retained-write recovery 一次
- callback 时 refresh generation 为 1，最终为 2
- 动态地址切换关闭旧服务端 WebSocket
- device/REST/media/new WebSocket 迁移到新地址
- Bearer token 保持一致
- foreign-device 地址事件不改变当前 session 或 refresh generation

测试结果：

- B6 contract：3/3 通过
- A close + B6：6/6 通过
- 既有 `dynamic_base_uri_test.dart`：1/1 通过

Task 4 的规格审查和质量复审均通过，无 Critical/Important。

### 6.5 Task 5 production Fake isolation gate

提交：

- `6cf59ca2e test(connection): enforce production BLE isolation`
- `637d6a456 test(connection): lock production gate wiring`

Gate 已实现：

- `_requireContains`：
  - `PlatformBirdBoxBleDataSource()`
  - `MethodChannelBirdBoxWifiPlatform()`
  - `MethodChannelBirdBoxDppPlatform()`
  - `rememberDynamicAddress:`
  - `restoreSavedSession()`
- `_forbid`：
  - `FakeBirdBox`
  - `FakeProvisioningRepository`
- 检查目标严格为：
  - `lib/bird_companion/app/app_dependencies.dart`

已有验证：

- RED：新增测试最初因缺少 Real BLE needle 失败
- GREEN：目标测试 1/1 通过
- gate 输出：`PASS production integrity: entrypoints, dependencies and fallbacks are valid.`
- 两个目标文件 analyze：No issues found
- `diff --check`：通过
- A/app_dependencies 零修改
- 精确锁定 `dependencyPath`
- 5 个 Real needle 分别绑定 `_requireContains`
- 2 个 Fake needle 分别绑定 `_forbid`
- Flutter test 内使用同一 Flutter SDK 自带 Dart 真实执行 gate
- Task 5 规格复审：通过
- Task 5 质量复审：Critical/Important/Minor 均为 0，Ready Yes

## 7. 当前未关闭问题

Task 5 的唯一 Important 已由 `637d6a456` 关闭。目前没有已知 Critical 或 Important；只剩 Task 6 全量验证、最终整体审查和推送。

## 8. 新对话接手后的第一项工作

直接执行第 10 节 Task 6 最终验证。不要重复实现 Task 1-5，不要再次 apply `stash@{0}`。

## 9. A blocker 文档状态

`docs/implementation/B6-A-WEBSOCKET-CLOSE-BLOCKER-2026-08-26.md` 已更新为“已解决”，记录 A 修复提交、公共合并和 B6 通过证据。本交接文档与该复盘文档应一起提交：

```text
docs(connection): record B6 handoff and A6 resolution
```

## 10. Task 6 最终验证

Task 5 双重审查通过、文档状态处理完后执行。

### 10.1 格式

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format --output=none --set-exit-if-changed lib\bird_companion\features\connection\presentation test\bird_companion\features\connection test\bird_companion\release_fake_ble_isolation_test.dart tool\release\verify_production_integrity.dart
```

### 10.2 核心测试

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection test\bird_companion\app\disconnected_device_startup_test.dart test\bird_companion\core\offline_sync_test.dart test\bird_companion\core\event_client_close_test.dart test\bird_companion\release_fake_ble_isolation_test.dart
```

### 10.3 静态分析和 gate

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' analyze --no-pub
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' run tool\release\verify_production_integrity.dart
```

### 10.4 敏感文本审计

```powershell
rg -n "diagnosticMessage|dppUri|DPP:|passphrase|pairingCode|accessToken|print\(|debugPrint\(" lib\bird_companion\features\connection\presentation test\bird_companion\features\connection\network_provisioning_cubit_test.dart test\bird_companion\features\connection\network_provisioning_page_test.dart test\bird_companion\features\connection\b5_b6_session_recovery_test.dart
```

只允许 synthetic test input 和明确的负向脱敏断言，不得有真实 secret 或生产日志输出。

### 10.5 Ownership 和 whitespace

由于 A hotfix 已成为新的 `thirdtime` 基线，B 侧 ownership 应优先比较：

```powershell
git diff --name-only 6b6a81ee0261d55ce86aa51fd5cfe3e62ccb08e0..HEAD
git diff --check 6b6a81ee0261d55ce86aa51fd5cfe3e62ccb08e0..HEAD
```

不要再仅用旧 `290f801fb` 白名单判断，因为 `290f801fb..HEAD` 会合法包含从 `thirdtime` 合入的 A hotfix 文件。

### 10.6 Debug APK

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' build apk --debug --flavor birdV1 -t lib\main.dart --no-pub
```

成功只证明构建集成，不证明真实 K7 或真实 Android Easy Connect 硬件行为。

## 11. 最终审查

Task 6 全部通过后：

1. 使用 `superpowers:verification-before-completion`。
2. 对 `6b6a81ee0..HEAD` 做一次最终整体规格/代码质量审查。
3. Critical/Important 必须为 0。
4. 确认 production presentation 无敏感信息。
5. 确认 A production diff 为 0（相对新 `thirdtime` 基线）。

## 12. 推送步骤

用户已授权“如果已经没问题，就直接推送”。全部验证和最终审查通过后执行：

```powershell
git -c safe.directory=D:/birdphoto/bird_part2_ble fetch origin thirdtime
git -c safe.directory=D:/birdphoto/bird_part2_ble merge-base --is-ancestor origin/thirdtime part2
git -c safe.directory=D:/birdphoto/bird_part2_ble rev-list --left-right --count origin/thirdtime...part2
git -c safe.directory=D:/birdphoto/bird_part2_ble push origin part2:thirdtime
git -c safe.directory=D:/birdphoto/bird_part2_ble fetch origin thirdtime
git -c safe.directory=D:/birdphoto/bird_part2_ble rev-parse HEAD
git -c safe.directory=D:/birdphoto/bird_part2_ble rev-parse origin/thirdtime
```

要求：

- push 必须是 fast-forward。
- 如果远端 `thirdtime` 在验证期间又更新，先停止推送，保护本地改动，重新合入并复跑受影响测试。
- 推送后必须确认 `HEAD == origin/thirdtime`。
- 不推 `part2` 到 `origin/part2`，除非用户另行要求。

## 13. 当前提交相对远端的 B 侧文件

当前 `origin/thirdtime@6b6a81ee0..HEAD` 包含：

```text
docs/superpowers/plans/2026-08-25-ble-b5-b6-dpp-recovery.md
docs/superpowers/specs/2026-08-25-ble-b5-b6-dpp-recovery-design.md
docs/implementation/B6-A-WEBSOCKET-CLOSE-BLOCKER-2026-08-26.md
docs/implementation/BLE-B5-B6-HANDOFF-2026-08-26.md
lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart
lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart
test/bird_companion/features/connection/b5_b6_session_recovery_test.dart
test/bird_companion/features/connection/network_provisioning_cubit_test.dart
test/bird_companion/features/connection/network_provisioning_page_test.dart
test/bird_companion/release_fake_ble_isolation_test.dart
tool/release/verify_production_integrity.dart
```

本交接文档和 A6 复盘文档将在最终验证前提交。

## 14. 新对话建议开场提示词

```text
请读取 D:\birdphoto\bird_part2_ble\docs\implementation\BLE-B5-B6-HANDOFF-2026-08-26.md，严格按其中的当前状态继续。Task 1-5 和双重复审已完成，直接执行 Task 6 全量验证与最终整体审查。全部无问题后，按用户已授权的 fast-forward 方式推送 part2 到远端 thirdtime。不要修改 A 生产路径，不要直接合并 origin/part1，不要再次 apply stash@{0}。
```

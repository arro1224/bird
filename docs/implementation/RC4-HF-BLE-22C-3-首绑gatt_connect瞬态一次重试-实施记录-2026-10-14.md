# BLE-22C-3 首绑 gatt_connect 瞬态一次重试——实施记录（2026-10-14）

接续 [BLE-22C-2 实施记录](RC4-HF-BLE-22C-2-首绑复测与测试工具修正-2026-10-13.md)（M01 首绑 133）。本批是**可回退的最小改动**，只针对 `gatt_connect` 阶段两类已观测的瞬态失败形态；**真机未验收，BLE-22C 仍未通过**，不改写任何既有失败结论。

## 1. 证据分析结论

三场对照（同一 vivo X20、同一 r6 候选 APK）：

| 时点 | c18f4b（133） | ef5b43（无回调） | 9492c8（成功） |
|---|---|---|---|
| createBond 返回 true | ✓ | ✓ | ✓ |
| bonding→bonded | 15.6s | 7.4s | 8.1s |
| bonded→rebuild（settle） | 1.04s | 1.06s | 1.08s |
| 旧 GATT close | deferred | deferred | deferred |
| rebuild 后 | **48ms 即 133** | **~15s 无回调** | 11.3s connected |

关键事实：

1. **第 18 轮七项定点矩阵（含 already_bonded、auth_once 等全部走 GATT 重建的场景）在 vivo 上 14 项全过**——「持有未 close 旧注册 + 1s settle + connectGatt」机制本身在该机可靠。
2. 133 与无回调**只出现在全新绑定后 1 秒内的首次 rebuild**。成功场 9492c8 在连接等待期观测到 `bonded→bonding→bonded` 抖动（SMP 重新协商痕迹）；bond 广播先于 SMP 完全收尾是该机已知行为。
3. 矩阵场景的 bond 在上一会话早已完成，不存在这个窗口。故判定为**首绑后栈瞬态**，与重建逻辑本身无关。

## 2. 改动内容

`BirdBoxBleChannel.java`（+81 行）：

- 新增 `securityConnectRetryCount`（上限常量 `SECURITY_CONNECT_RETRY_MAX = 1`），在 `beginSecurityWrite`（新请求）与 `closeGatt`（会话拆除）归零。
- `handleConnectionState`：`preparing()` 且 `preparationStep == "gatt_connect"` 且 SDK≤28 且未用尽重试时，连接失败回调改走 `retrySecurityConnect(status)` 而非立即 `failNativePreparation`。
- `setPreparationStep` 超时分支：`gatt_connect` 静默 15s（20261013-140734 形态）同样进入一次重试，guard 在 `retrySecurityConnect` 内部保证单发。
- 新增 `retrySecurityConnect(int gattStatus)`：
  1. 发 `gatt_connect_retry_started` 诊断（gattStatus 保留、resultCode=first_post_bond_rebuild）；
  2. 失败客户端 `disconnect()` 后按既有纪律加入 `heldLegacyRegistrations`（不 close、不注销——与「注销会干扰厂商地址映射」的既有结论一致），上限沿袭 `MAX_HELD_LEGACY_REGISTRATIONS`；
  3. 复核 bond 仍为 BONDED，否则按 `bond_lost` 终止；
  4. `gattGeneration++`、置 1s `securityReconnectNotBefore` settle，经代次/owner/token 四重归属守卫后在 settle 期满调 `reconnectGattAfterSecurity()` 重拨。
- 第二次仍失败走原 `failNativePreparation` 路径，两次状态均留证。**未触碰**一次加密恢复上限、代次归属、取消语义、各阶段时限；SDK≥31 行为完全不变。

`ble_critical_event_policy.dart`：`gatt_connect_retry_started` 登记为关键事件（按「新诊断事件必须同步核查保留策略」纪律）。

`BirdBoxBleBridgeTest.java`：新增 4 例（133 后重试成功 / 二次失败有界终止且无第三次拨号 / SDK31 不重试 / 重试期 bond 丢失按 bond_lost 终止）；`connectionCallbackFailureTerminates` 显式标 `@Config(sdk = 31)`（其语义在现代栈不变；SDK 27 行为由新测试覆盖）；SDK27 静默超时测试改为「重试一次 → 二次静默终止」。

## 3. 本地验证

- Android 原生单测（app + virtualBirdBox）**全部通过**（app 模块 169 项）。
- Flutter connection 模块 233 项全过；`flutter analyze` 无问题。
- 本机环境注意：`gradlew --offline` 因缺 `androidx.test:runner:1.6.2` 缓存必败，需联网一次；`tool/ble22/test_tools.ps1` 需 PowerShell 7.4。

## 4. 下一步（不因本批自动完成）

1. 冻结新候选（源码指纹已变，不得沿用 r9 结论），在 vivo X20 复测 P2 未绑定首绑；若 133 复现，诊断中应有 `gatt_connect_retry_started` → 重拨成功（修复生效）或重拨仍 133/静默（H1 对端绑定残留/固件，需板端 btmon 联查）——**重试一致失败本身就是鉴别证据**。
2. 回归 P1/P2 受影响矩阵。
3. 133 关闭并冻结后进入 BLE-22D 数量验收。

## 依据

[BLE-22C-2 实施记录](RC4-HF-BLE-22C-2-首绑复测与测试工具修正-2026-10-13.md)、[BLE-22C 双手机定点复测](RC4-HF-BLE-22C-双手机定点复测与修复记录-2026-10-12.md)、[M01 清单](RC4-HF-华为vivo双机-App待测与BLE改进清单-2026-10-13.md)、[handoff-samples 三场原始事件](ble22-evidence/handoff-samples/)。

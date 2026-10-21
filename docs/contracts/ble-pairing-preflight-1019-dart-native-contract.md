# BLE 1019：Dart / Android 当前接入契约

更新：2026-10-21；原生基线为 `thirdtime` 分支 2026-10-21 R1/R2 修订后的工作区源码。
**离线回归通过不表示模拟盒子、真机或联合签字通过。**
本文件仅涉及 BLE 配对准备，不改变 HTTP、Wi-Fi、热点和复制协议。附件作为需求和协作依据，
当前字段与行为以本仓库代码核对结果为准。实施记录与交接报告在本地保留，不纳入源码提交。

## 1. 生效的 MethodChannel 形状

Channel：`bird_companion/birdbox_ble/methods`。

| 方法 | 线上参数与返回 | 乙侧处理 |
|---|---|---|
| getNativeBondState | `{deviceId: String}` → `not_bonded / bonding / bonded` | deviceId 为 connect 使用的平台句柄；调用前后读取 ownership 快照，核对 connectionGeneration 与 gattInstanceId；不采用 Dart 缓存代替真实 bond 状态 |
| writePairingPreflight | `{value: Uint8List, expectedConnectionGeneration?: int, expectedGattInstanceId?: int}` → `null` | 两个期望参数成对可选；传入后由原生在主线程写前串行校验，失配返回 `gatt_owner_mismatch`。Dart 唯一负责 rc4/分片；null 仅表示 ATT 分片写完成。原生写前复查真实 BOND_NONE，BONDING/BONDED/未知拒绝为 `bond_state_not_none` / `bond_state_unknown`，不会触发 createBond |
| getGattOwnershipState | 无参数 → 下述 Map | 区分缺失特征清单与确实缺0007；缺少清单不推断特征存在或不存在 |
| prepareControlledReconnect | `{expectedConnectionGeneration?: int, expectedGattInstanceId?: int}` → `null` | 期望参数成对可选，失配返回 `gatt_owner_mismatch`。释放 Future 在真实 STATE_DISCONNECTED 回调且 close 完成后才 success(null)；3 秒无回调返回 `gatt_release_unconfirmed`（强制 close）。同代际已释放（传匹配的期望参数）幂等 success；无 GATT 且参数不匹配为 `invalid_state`；不等待本接口不发送的 disconnect 事件 |

ownership Map 的必需字段：

```text
connected: bool                 // 当前 Java 实际为 gatt != null
linkReady: bool
connectionGeneration: int
gattInstanceId: int              // Java 内部的 gattGeneration，非对象 hashCode
discoveryState: absent | connected | discovering | discovered | ready
inflightRequest: String?         // activeSecurityRequestId，不涵盖所有 ATT 操作
preparing: bool
retiring: bool                   // 2026-10-21 新增附加字段：释放屏障进行中
```

`retiring=true` 表示旧客户端停在释放屏障（park）等待真实断开回调；此时快照为
connected=false、gattInstanceId=0、discoveryState=absent。该字段为附加字段，旧读取方可忽略。
discoveryState 生命周期：`absent`（无 GATT）→ `connected`（对象存在，未开始发现）→
`discovering`（discoverServices 已被栈接受、回调未到，ATT 意义上的 pending）→
`discovered`（服务清单已知，通知/MTU 等收尾可能未完成）→ `ready`（linkReady=true，唯一可写的放行态）。
"正在 retire" 的窗口由 `retiring=true` 表达，而非 discoveryState 的取值。

生产 adapter 声明由原生 connect 负责旧连接 reset。Dart 不在普通 connect 前额外调用 disconnect，
也不在替换已知存活连接时抢先清掉 Java 的旧实例，让甲的 park/真实断开/settle 屏障可实际运行。
其他不声明该能力的测试或平台实现保留原有显式清理行为。

当前 Java 不返回 characteristicUuids、gattPresent、设备身份或 gattClosed。
适配器允许未来附加 `characteristicUuids: List<String>`，但不要求甲为此次签名兼容专门添加。
connected=false 时仅接受 linkReady=false、gattInstanceId=0、discoveryState=absent；
connected=true 时 generation 与 instance 必须为正数。

App 内部 `NativeBondSnapshot`、`PublicGattSnapshot` 和带代际的控制方法是 Dart 安全封装，
不是再次要求 Java 返回旧 Map/接收旧参数。内部逻辑事务 requestId 不传作 native security attempt。

## 2. 释放屏障与原子归属（2026-10-21 R1/R2 修订，已实现）

`prepareControlledReconnect`、页面 `disconnect` 与 connect 前的陈旧重置（pre_connect_reset）
共享同一 retire 屏障：closeGatt 先 park 旧客户端（只 disconnect 不 close），等该客户端的
**真实 STATE_DISCONNECTED 回调**到达后才 close 并完成挂起的释放 Future；3 秒（PARKED_RETIRE_DISCONNECT_GUARD_MS）
无回调则发 `controlled_release_disconnect_timeout` 诊断、强制 close、挂起 Future 以
`gatt_release_unconfirmed` 失败。错误驱动型 teardown（link_lost/bond_lost/security_failure 等）
仍立即 close，不需要屏障。链路已知已断（lastKnownConnectionState==DISCONNECTED）时走快速路径：
立即 close、立即 success、诊断 `controlled_release_immediate`。

- disconnect stream 事件时序不变：仍在 closeGatt 内、屏障**起点**发出，字段
  reason/gattStatus/unexpected/connectionGeneration/gattInstanceId。物理确认以上述
  `pre_connect_reset_disconnect_confirmed`（resultCode stale_gatt_disconnected）或
  `controlled_release_disconnect_confirmed`（resultCode retired_gatt_disconnected）诊断为准。
- 受控释放期间（屏障未确认）普通 connect 被 connect 门禁拒绝为 `gatt_busy`；确认后
  1 秒 settle 窗口内的 connect 会延迟到 settle 结束才拨号（防 155233 同型 ACL 未排空）。
- 同代际幂等：释放完成后携带匹配的 expectedConnectionGeneration/expectedGattInstanceId
  再次调用 prepareControlledReconnect 返回 success（诊断 controlled_reconnect_already_released）。
- 原生串行校验即原子性：所有 MethodChannel 调用在主线程串行执行，期望参数校验发生在
  主线程、写/释放动作之前，因此 Dart 前后快照之外的跨调用竞态已被原生消除。

错误映射保留稳定业务码，丢弃原生自由文本与 details，避免 token 等值进入日志：

- pairing_preflight_unsupported → PAIRING_PREFLIGHT_COMMAND_UNSUPPORTED，并仅添加固定的“原生缺特征”标记。
- gatt_busy、PAIRING_PREFLIGHT_BUSY/EXPIRED 沿用既有有限重试策略。
- gatt_owner_mismatch → 过期归属，终态不重试（同代际换 instance 视为换代失效）；
  需重新读 ownership 快照后以新参数重试。
- bond_state_not_none → 绑定已存在，本轮放弃公开预检（BOND_BONDED 走已绑定路径）；
  BONDING 等待状态变化，不自动重试。
- gatt_release_unconfirmed → 本轮终态；Dart 可显式发起新一轮释放。
- bluetooth_permission_denied / bluetooth_unavailable / bond_state_unknown / ble_gatt_not_ready /
  ble_gatt_operation_failed / invalid_request / invalid_state / ble_session_ended 分别映射已有 App 类型。
- MissingPlugin 明确返回 BLE_PAIRING_PREFLIGHT_UNAVAILABLE，不猜测 BOND_NONE。

## 3. 公开预检协议与执行顺序

只有 `capabilities.pairing_preflight_v1 == true` 才使用
`6f7d0007-7a66-4c45-a1b9-5f4d2e3c1000`；能力缺失按 false，字段类型严格校验。
旧盒子不把0007当作必需特征。BOND_NONE 期间仅订阅公开0003，读取公开设备信息/网络状态，
不提前订阅0006或写0004/0005，不提前调用 preparePairing/createBond。

| 请求 | payload |
|---|---|
| prepare_system_pairing | phone_bond_state=not_bonded |
| confirm_pairing_reset | prepare_request_id、reset_token |

请求为 rc4 信封与 UUID v4 request/client ID。confirm 使用新 request ID、同 client ID 和未解析 token；
不得附加 MAC、BlueZ 路径、品牌或网络凭据。reset token 只留内存，终态清理引用；分片字节发送后清零。
字符串不能保证安全擦除。

响应走0003，匹配 requestId、当前逻辑 owner、connectionGeneration、gattGeneration；
可接收增量文档的最小信封；如带 protocol_version/device_id 则严格核对。
缺少代际元数据的通知不能完成公开请求。

prepare 得到 none 才准备就绪；reset_required 不能直接启用“预期断链”。只有匹配 confirm 的
remove_scheduled + disconnect_expected=true 才同步启用窗口，随后等待真实板端断链。
再确认旧 GATT 本地退役、重新扫描广告、新 connection generation 重连、核对完整 device_id、
fresh prepare 得到 none，才允许用户明确点击后的唯一一次系统配对。
扫描名称仅用于候选选择，不作为可信身份。普通 status19、提前断线及旧回调不能被全局吞掉。

BOND_BONDED 跳过公开预检，沿用安全写准备；BOND_BONDING 等待当前状态变化，不启动第二次配对。
原生 bond 成功可直接复用活 GATT，Dart 接受当前 readiness，不要求先断后连。

## 4. 有限重试与兼容

- 准备总期限45秒；全部分片写完后响应3秒；预期断链与新广告各12秒。
- BUSY/EXPIRED 释放后最多重试1次，retry_after_ms 大于2秒即终止本轮。
- INVALID_PEER / CONFIRMATION_REJECTED / REQUEST_ID_CONFLICT / 板端 COMMAND_UNSUPPORTED 终止，不自动 bonding 兜底。
- 有能力却没有0007时最多释放/重连发现1次。Java未给清单时，以原生 write 的
  pairing_preflight_unsupported 错误触发；板端返回 COMMAND_UNSUPPORTED 不触发缓存刷新。
- 无能力的未绑定旧盒子给升级/目标设备手动处理指引，不写0007；已绑定旧盒子继续已绑定路径。

## 5. 页面与前后台

返回“查找盒子”先等待拥有的释放 Future，再允许扫描/连接。断开中禁用新连接，失败保留门禁，
显式重试断开。页面逻辑 owner 与底层 owner 分开，页面重建不抢夺旧释放。

回前台时，已知且空闲的连接查询原生 ownership；同 generation/instance、ready 且无 native attempt
则保留连接及预检许可；不存在、归属变化或快照失败则清除可信状态，显示错误，不自动配对或重连。
公开准备、安全写准备和释放期间的 resume 不干扰当前 attempt。
原生未提供 peer 身份，因此未知 owner 的存量 GATT 不能凭对象存在而直接收养；该场景仍需联合确认。
前台快照异常由 Cubit 捕获进入错误状态。

## 6. 诊断与验证边界

Dart 首错只写一次，后续收尾错误进入有界 secondary_errors；UI、摘要和完整导出保持一致。
关键事件保护包含甲新增的 park/断开确认/超时、重放、cleanup noop、GATT复用判断、公开写回调，
以及乙新增的前台同步。容量不足仍明确记录缺失，不声称无限保留。
禁止持久化 reset_token（包括哈希）、密码、完整地址和原始预检报文。

回归日志与验证结果在本地单独保留，不纳入源码提交。
工具入口 `tool/ble22/ble1019/` 仅准备验收与交付登记；Fake/MethodChannel mock/单元测试
不证明系统框次数、ACL释放、真实板端协议或三机型成功率。APK及正式验收仍待后续集成。

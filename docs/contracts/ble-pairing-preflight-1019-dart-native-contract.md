# BLE 1019：Dart / Android 当前接入契约

更新：2026-10-21；原生基线为 `thirdtime` 的 `d0eb144` 叠加乙第一至三批及本轮原生补充工作区改动。
**离线回归通过不表示模拟盒子、真机或联合签字通过。**

2026-10-21 乙第一批已接入：公开写和受控释放的生产调用总是成对传入两个expected字段，
解析retiring，新增三个稳定App错误码，并保护失配后的跨层cleanup。第二批接入可靠完成等待、
释放失败后的显式恢复和诊断保护。第一、二批未改变Java行为；本轮由乙代补原生释放契约：
终态冻结旧实例和trace，补普通disconnect快速路径终态及可查询lastRelease，超时不再幂等成功。
pre_connect_reset超时或close异常终止本次connect，不继续拨号。
**甲复核结论（2026-10-21，b80dee0c3/5586b6248）：通过。** lastRelease 终态冻结、close 异常
不再假成功、快速路径带退役实例终态、幂等仅限 confirmed、lint 等价改写均确认；
pre_connect_reset 超时从“强制 close 后继续拨号”改为 fail-fast（gatt_release_unconfirmed，
本次 connect 终止不拨号）系甲确认接受的语义修订，取代此前 A6 评审结论，双方以本文件为准。
甲侧原生验证：246/246（Robolectric），Flutter 516 通过/2 跳过，analyze 0 问题。
本文件仅涉及 BLE 配对准备，不改变 HTTP、Wi-Fi、热点和复制协议。附件作为需求和协作依据，
当前字段与行为以本仓库代码核对结果为准。实施记录与交接报告在本地保留，不纳入源码提交。

## 1. 生效的 MethodChannel 形状

Channel：`bird_companion/birdbox_ble/methods`。

| 方法 | 线上参数与返回 | 乙侧处理 |
|---|---|---|
| getNativeBondState | `{deviceId: String}` → `not_bonded / bonding / bonded` | deviceId 为 connect 使用的平台句柄；调用前后读取 ownership 快照，核对 connectionGeneration 与 gattInstanceId；不采用 Dart 缓存代替真实 bond 状态 |
| writePairingPreflight | `{value: Uint8List, expectedConnectionGeneration?: int, expectedGattInstanceId?: int}` → `null` | 两个期望参数成对可选；传入后由原生在主线程写前串行校验，失配返回 `gatt_owner_mismatch`。Dart 唯一负责 rc4/分片；null 仅表示 ATT 分片写完成。原生写前复查真实 BOND_NONE，BONDING/BONDED/未知拒绝为 `bond_state_not_none` / `bond_state_unknown`，不会触发 createBond |
| getGattOwnershipState | 无参数 → 下述 Map | 区分缺失特征清单与确实缺0007；缺少清单不推断特征存在或不存在 |
| prepareControlledReconnect | `{expectedConnectionGeneration?: int, expectedGattInstanceId?: int}` → `null` | 期望参数成对可选，失配返回 `gatt_owner_mismatch`。真实断开且close完成才成功；已知断链快速路径仍需close完成。3秒无回调或close异常返回 `gatt_release_unconfirmed`。仅匹配已确认实例可幂等成功；匹配超时或进行中实例仍未确认；无记录或参数不匹配为 `invalid_state` |

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
lastRelease: Map?                // 本轮新增；本Engine最近一次屏障释放，初始null
```

lastRelease字段为正整数connectionGeneration/gattInstanceId（附gattGeneration别名）、
可选traceId、reason、state（disconnecting/confirmed/unconfirmed）、resultCode、
disconnectObserved和closeCompleted。confirmed必须为retired_gatt_disconnected且两个证据bool均为true；
进行中为awaiting_disconnect；未确认为disconnect_callback_missing、close_failed或release_superseded。
它绑定退役时的实例与trace，跨页面/诊断重订阅仍可查询，但不跨Engine/进程持久化；仅保存最近一条，
丢失或归属不匹配时继续失败。Dart兼容旧ABI缺少lastRelease，存在但字段不合法则拒绝快照。

`retiring=true` 表示旧客户端停在释放屏障（park）等待真实断开回调；此时快照为
connected=false、gattInstanceId=0、discoveryState=absent。Dart兼容旧快照缺少该字段时为false；
存在时必须是bool，retiring=true与connected=true的矛盾快照被拒绝。
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
无回调则强制close后发 `controlled_release_disconnect_timeout` 诊断，挂起 Future 以
`gatt_release_unconfirmed` 失败。pre_connect_reset对应事件带pre_connect_reset前缀；其guard不再继续dial。
close抛异常同样为未确认并终止等待，不将捕获异常视作关闭成功。错误驱动型 teardown（link_lost/bond_lost/security_failure 等）
仍立即 close，不需要屏障。链路已知已断（lastKnownConnectionState==DISCONNECTED）时走快速路径：
close成功后立即完成，并发带退役实例的确认终态；受控接口另保留 `controlled_release_immediate`。

- disconnect stream 事件时序不变：仍在 closeGatt 内、屏障**起点**发出，字段
  reason/gattStatus/unexpected/connectionGeneration/gattInstanceId。物理确认以上述
  `pre_connect_reset_disconnect_confirmed`（resultCode stale_gatt_disconnected）或
  `controlled_release_disconnect_confirmed`（resultCode retired_gatt_disconnected）诊断为准。
  终态在close调用返回后发布，generation/instance/trace取退役时冻结值；晚到的外来trace或旧回调不改写它。
- 受控释放期间（屏障未确认）普通 connect 被 connect 门禁拒绝为 `gatt_busy`；确认后
  1 秒 settle 窗口内的 connect 会延迟到 settle 结束才拨号（防 155233 同型 ACL 未排空）。
- 同代际幂等：释放完成后携带匹配的 expectedConnectionGeneration/expectedGattInstanceId
  再次调用 prepareControlledReconnect 返回 success（诊断 controlled_reconnect_already_released）。
  此处“释放完成”仅含confirmed，超时/close异常/取消的unconfirmed记录不会变成幂等成功。
- 原生串行校验即原子性：所有 MethodChannel 调用在主线程串行执行，期望参数校验发生在
  主线程、写/释放动作之前，因此 Dart 前后快照之外的跨调用竞态已被原生消除。

错误映射保留稳定业务码，丢弃原生自由文本与 details，避免 token 等值进入日志：

- pairing_preflight_unsupported → PAIRING_PREFLIGHT_COMMAND_UNSUPPORTED，并仅添加固定的“原生缺特征”标记。
- gatt_busy、PAIRING_PREFLIGHT_BUSY/EXPIRED 沿用既有有限重试策略。
- gatt_owner_mismatch → BLE_GATT_OWNER_MISMATCH，旧事务终止（同代际换instance同样失效）；
  不为旧事务换一组参数继续执行。后续cleanup不调用仅校验generation的普通disconnect；
  新用户意图可以重新准备，新连接继续由原生connect管理陈旧客户端屏障。
- bond_state_not_none → BLE_BOND_STATE_NOT_NONE，重读真实状态，本轮放弃公开预检（BOND_BONDED走已绑定路径）；
  BONDING 等待状态变化，不自动重试。
- gatt_release_unconfirmed → BLE_GATT_RELEASE_UNCONFIRMED，本轮终态，保持失败及连接门禁。
  Java将超时记录为unconfirmed，后续同实例请求仍失败；迟到回调不会升级旧结果。
  adapter保留有界的已确认和未确认实例：已观察到真实完成或查询到严格匹配lastRelease确认的实例可在absence时成功，
  未知absence不调用原生幂等分支来补出成功。数据源保留失败门禁，不自动重发释放或扫描重连。
  显式重试先核对原始generation/instance；仍是同一活GATT时可重新执行原子释放。
  已无GATT时，显式重试可查询严格匹配且已确认的lastRelease；没有确认记录则必须观察到手机蓝牙关闭并再次确认同generation、非retiring且无活跃attempt，
  才记录adapter_disabled_and_native_absent恢复。retiring=false、迟到事件或幂等成功均不自动清除失败。
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

已知且空闲的连接，包括已绑定GATT，收尾携带原始generation和instance执行受控释放并等待Future。
活动安全attempt使用其request/attempt归属发普通disconnect，区分请求受理与物理释放确认，
接受同trace、generation、instance的controlled_release_disconnect_confirmed终态，
或在等待中查询到同trace及实例的lastRelease确认，再复核ownership；受控Future及终态等待均设4秒保护。
普通disconnect仍只同步返回受理；终态和查询都不能省略归属及本地close复核。
旧ABI缺少实例的事件继续记录gatt_release_completion_unattributed并保持有界失败。
归属失配后只清除本地可信状态，Repository、页面和dispose的后续收尾不触碰替换实例。
匹配confirm后的真实板端断链加上同generation、非retiring的原生absence可走reset快速路径；
只有absence、起点事件或retiring中的快照均不足以放行。已观察到retiring时，清除就绪许可，
阻止新扫描、连接及重复释放，页面显示释放未确认并保留显式重试入口。
若是Dart自己持有的释放Future仍在进行，则继续沿用single-flight等待，resume不另发释放。
Repository看到数据源释放阻塞时不自动触发恢复；页面重建继续等待原释放或显示失败门禁。

返回“查找盒子”先等待拥有的释放 Future，再允许扫描/连接。断开中禁用新连接，失败保留门禁，
显式重试断开。页面逻辑 owner 与底层 owner 分开，页面重建不抢夺旧释放。

回前台时，已知且空闲的连接查询原生 ownership；同 generation/instance、ready 且无 native attempt
则保留连接及预检许可；不存在、归属变化或快照失败则清除可信状态，显示错误，不自动配对或重连。
公开准备、安全写准备和释放期间的 resume 不干扰当前 attempt。
原生未提供 peer 身份，因此未知 owner 的存量 GATT 不能凭对象存在而直接收养；该场景仍需联合确认。
前台快照异常由 Cubit 捕获进入错误状态。

## 6. 诊断与验证边界

第三批行为回归包括终态到达但close未完成、外来trace、只有幂等事件、迟到Future、同代际替换实例、
未知实例的前台快照及外部BONDING最终失败。期望是完成条件明确、失败门禁保留、不追加createBond。
原生回归须实际运行并核对XML结果；工具报告记录命令、退出码、跳过原因与运行前后源码指纹。
设置页、App启动/恢复、STA与直连HTTP接管均参与合流回归。真实Python后端未配置的用例明确跳过。
本轮原生补充的源码及单测不替代甲复核、0007外设预联调、冻结APK及三机型正式验收。

Dart 首错只写一次，后续收尾错误进入有界 secondary_errors；UI、摘要和完整导出保持一致。
关键事件保护包含甲新增的 park/断开确认/超时、重放、cleanup noop、GATT复用判断、公开写回调，
以及乙新增的前台同步。容量不足仍明确记录缺失，不声称无限保留。
新增保护controlled_release_disconnect_confirmed/timeout、controlled_release_immediate、
controlled_reconnect_already_released、pairing_preflight_bond_rejected及Dart释放/显式恢复事件。
短摘要的release_timeline保留请求范围内最近4条释放事实，完整导出仍保留全部实际留存事件。
旧原生teardown_completed仍可能在屏障起点出现，不能把该名称当物理释放证明；
Dart的gatt_release_confirmed才表示本层获得终态并复核close，失败不写Dart teardown_completed。
禁止持久化 reset_token（包括哈希）、密码、完整地址和原始预检报文。

回归日志与验证结果在本地单独保留，不纳入源码提交。
工具入口 `tool/ble22/ble1019/` 仅准备验收与交付登记；Fake/MethodChannel mock/单元测试
不证明系统框次数、ACL释放、真实板端协议或三机型成功率。APK及正式验收仍待后续集成。

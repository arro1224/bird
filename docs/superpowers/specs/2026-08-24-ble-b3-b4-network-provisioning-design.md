# BLE B3/B4 网络配网展示层设计

## 背景

BLE B1/B2 已完成附近 BirdBox 发现、Device Info 信任门、配对授权以及连接方式选择，并已合入 `thirdtime`。现有 rc4 domain 已冻结九条配网命令、网络状态和事件模型；成员 A 已提供 BLE GATT bridge、分片/消息编解码以及 Wi-Fi/DPP 平台抽象，但当前分支尚无生产级 `ProvisioningRepository` 实现或依赖装配。

本批次只完成成员 B 的 B3/B4 presentation、测试 fake 和自动化测试。成员 A 的 Android、BLE data、domain、生产 repository 和真实入口接线全部保持只读。

## 目标

1. 配对授权成功后，用户可以根据 Device Info 能力选择直连盒子或让盒子加入现有 Wi-Fi。
2. B3 完成 Direct AP 命令、进度、停止、恢复和安全结果展示。
3. B4 完成 Wi-Fi 扫描、手动配置、DPP 入口、进度、取消、恢复和安全结果展示。
4. 所有长操作只接受可信 device ID 和当前 operation ID 对应的事件。
5. AP/STA 成功必须再次读取 `getNetworkStatus()` 并确认目标模式、终态、operation ID 和安全 `baseUri`。
6. 配对授权、Wi-Fi 密码、AP passphrase、完整 DPP URI 和 `diagnosticMessage` 不进入 Cubit state、UI 文本、日志、截图、fake 记录或测试断言。
7. 在没有生产 repository 的情况下，保留可选依赖注入和安全完成页，不越权补写成员 A 的实现。

## 非目标与所有权边界

本批次不修改：

- `android/app/src/main/java/**`
- `lib/bird_companion/features/connection/data/ble/**`
- `lib/bird_companion/features/connection/data/platform/**`
- `lib/bird_companion/features/connection/domain/**`
- `BirdCompanionDependencies` 中的生产装配
- 真实 Android Wi-Fi/DPP 系统交互、健康检查或盒子协议行为

本批次不声称完成真机、真实盒子、生产入口或 release 验收。未来成员 A 提供生产 `ProvisioningRepository` 后，才能执行 Android 权限、系统 Wi-Fi/DPP、网络路由、`/health.device_id` 与断线恢复验收。

## 方案选择

采用独立 `NetworkProvisioningCubit`，不扩展 B1/B2 的 `ProvisioningCubit`。

- `ProvisioningCubit` 继续只负责发现、连接、配对和进入连接方式选择。
- `NetworkProvisioningCubit` 负责 B3/B4 能力门控、命令、事件、扫描批次、取消、恢复和终态确认。
- 两个 Cubit 共享同一个注入的 `ProvisioningRepository`，但只有 `ProvisioningCubit` 保持现有断开生命周期；网络 Cubit 关闭时只取消自己的事件订阅。
- `ConnectionPage` 一次性创建两个 Cubit，避免进入网络页面时重复订阅或重建状态机。

未采用的方案：

- 直接扩展 `ProvisioningCubit`：会把发现、配对、AP、STA 和 DPP 合并成过大的状态机，增加重试混淆和秘密泄漏风险。
- B3/B4 各自一个 Cubit：会重复事件过滤、取消、恢复和终态确认逻辑，容易产生不一致行为。

## 状态模型

`NetworkProvisioningState` 只包含安全、展示所需的数据：

- 当前阶段和所选连接方式；
- 可信 device ID 与 Device Info 能力；
- 当前 operation ID 和 `NetworkOperationState`；
- Wi-Fi 扫描批次元数据及临时扫描结果；
- 安全的成功 `baseUri`；
- 恢复模式和安全错误对象；
- 当前操作是否可取消。

状态不得包含：

- 配对码或配对 session；
- Wi-Fi 密码或完整 `StaNetworkConfiguration`；
- AP passphrase；
- 完整 DPP URI；
- `ProvisioningException.diagnosticMessage` 的派生文本；
- production token、client ID 或 platform network handle。

扫描 SSID/BSSID 是用户选择网络所必需的临时页面数据，可以存在于内存状态，但不得持久化、打印或用于分析埋点。Direct AP 的 SSID 不进入状态，完成页只展示已建立安全本地连接和安全 `baseUri`。

每个异步命令使用递增操作代次。Future 完成前若用户返回、重置或启动新动作，旧代次结果必须被忽略，避免晚到的 `CommandAccepted` 覆盖新状态。

## 事件过滤

所有事件必须先满足：

1. `event.deviceId == trustedDeviceId`；
2. 当前阶段允许该事件类型；
3. 对包含 operation ID 的事件，`event.operationId == activeOperationId`。

终态后到达的旧进度、错误设备事件、错误 operation ID 事件和旧 Future 结果全部忽略。

rc4 的 `WifiScanBatch` payload 当前没有 operation ID，presentation 无法自行验证该字段。B 侧只在当前阶段为 scanning、已存在 active operation ID 且批次结构一致时接收；生产 `ProvisioningRepository` 必须依照冻结接口的所有权说明过滤陈旧扫描事件。此限制作为成员 A 接线前置条件保留，不修改 domain 补字段。

## B3：直连盒子

### 能力门控

连接方式页读取 `DeviceCapabilities.directAp`。不支持时卡片禁用并显示原因，不调用 `startDirectAp()`。

### 启动和完成

1. 用户选择直连盒子。
2. Cubit 调用一次 `startDirectAp()`。
3. 保存返回的 operation ID，进入 `startingAp`。
4. 只处理当前设备和 operation 的 `NetworkProgress`、`DirectApReady`、`NetworkRecovered`、`CancelledOperation` 与安全错误。
5. 收到 `DirectApReady` 时不读取到状态或展示 passphrase，立即调用 `getNetworkStatus()`。
6. 只有状态满足以下条件才进入完成页：
   - `activeMode == directAp`
   - `operationState == apReady`
   - `operationId == activeOperationId`
   - `baseUri != null`
7. 条件不满足时进入可重试的状态确认失败，不显示成功。

生产 repository 将来还必须负责 Android 加入网络、路由绑定和 `/health.device_id` 比对；B 侧不会绕过 repository 调用平台 API。

### 停止、取消和返回

- AP ready 后可调用一次 `stopDirectAp()`，以返回的新 operation ID 跟踪停止流程。
- 只有 `NetworkOperationState.cancellable` 或事件明确标记可取消时才显示取消按钮。
- starting AP 等不可取消阶段不伪造取消能力。用户返回时提示盒子操作可能继续，可在重新连接后读取网络状态恢复。
- `NetworkRecovered` 显示恢复到可用网络的结果，不把恢复误报成本次直连成功。

## B4：加入现有 Wi-Fi

### 能力门控

总入口先检查 `infrastructureSta`。进入后分别门控：

- 扫描：`wifiScan`
- 手动输入：`wifiManual`
- DPP：`dppUsableByBox`

不支持项禁用并显示原因，不产生 repository 调用。

### Wi-Fi 扫描

1. 调用一次 `scanWifi()` 并保存 operation ID。
2. 按 `batchIndex` 收集批次；批次数不一致、越界或终态后的批次忽略。
3. 只在所有索引均已收到且完成标记成立时显示列表。
4. 以 BSSID 去重；重复 BSSID 保留 RSSI 更强的记录。
5. 支持的网络优先，再按 RSSI 从强到弱排序，最后用 SSID/BSSID 提供稳定顺序。
6. `unsupported` 网络展示但不可选择。

### 扫描选择与手动配置

扫描选择构造：

- `ProvisioningMethod.bleScanSelection`
- `WifiSelectionMethod.scanResult`
- 扫描结果的 SSID、BSSID、安全类型
- `hidden = false`

手动输入构造：

- `ProvisioningMethod.bleManual`
- `WifiSelectionMethod.manual`
- `bssid = null`
- 用户输入的 SSID、安全类型、隐藏网络和网络类型

冻结契约只要求 SSID 非空、受保护网络密码非空，并禁止 DPP 走 `setStaConfig()`。本批次不加入未冻结的密码长度或字符规则，避免与真实盒子产生协议分歧。

密码由表单自己的 `TextEditingController` 持有，默认遮挡；提交时构造一次 `StaNetworkConfiguration` 传给 Cubit，Cubit 不保存 configuration。提交后和 widget dispose 时清空 controller。失败重试需要用户重新输入密码。

### STA 完成确认

1. `setStaConfig()` 返回新的 operation ID。
2. 只处理该 operation 和可信 device ID 对应的进度、`StaConnected`、恢复、取消和错误。
3. 收到 `StaConnected` 后调用 `getNetworkStatus()`。
4. 只有状态满足以下条件才成功：
   - `activeMode == infrastructureSta`
   - `operationState == staConnected`
   - `operationId == activeOperationId`
   - `baseUri != null`
5. 成功状态只保存安全 `baseUri`，并可调用 `onProvisioningCompleted(Uri)` 交给未来生产入口。

### DPP

- 只有盒子 DPP 能力可用时显示入口。
- B 侧只调用 `startDppProvisioning()` 并跟踪 operation ID。
- 收到 `DppBootstrapReady` 时只更新安全进度，不读取、保存或展示完整 URI。
- Android Easy Connect capability、Activity、URI 生命周期和系统结果属于 production repository/成员 A。
- Android 系统操作成功也不是最终成功，仍必须等待 `StaConnected` 并完成网络状态确认。

## 页面结构

新增或调整以下 B 侧展示组件：

- `ConnectionMethodPage`：能力门控后的直连/现有 Wi-Fi 选择。
- `NetworkProvisioningPage`：按 Cubit phase 调度具体页面。
- `DirectApProvisioningView`：直连进度、确认、成功、停止与恢复。
- `WifiProvisioningMethodView`：扫描、手动和 DPP 入口。
- `WifiScanView`：扫描进度、结果列表、重扫与错误。
- `StaNetworkForm`：扫描选择/手动输入共用的安全配置表单。
- `NetworkOperationView`：统一展示 operation state、取消和安全错误。
- `NetworkProvisioningSuccessView`：展示脱敏结果和完成动作。

页面沿用现有 `AppTheme`、`BirdCard`、`BirdButton`、`ErrorNotice` 和连接背景，不修改全局视觉系统。

## 错误与恢复

- 所有 `ProvisioningException` 使用 `UserMessageMapper` 映射，永不显示 `diagnosticMessage`。
- 能力不支持是普通禁用状态，不进入 failure。
- 扫描失败可重新扫描；重新扫描清空旧批次和旧结果。
- 配置失败可保留所选 SSID/安全类型，但不保留密码。
- 取消后返回 Wi-Fi 方式页或连接方式页，并清空当前 operation。
- AP/STA 终态确认失败提供重新读取状态或返回上一步，不展示伪成功。
- 返回连接方式会递增操作代次，清空扫描结果、成功 URI、恢复信息和错误。
- 网络 Cubit 关闭只取消事件订阅，不调用共享 repository 的 disconnect/dispose。

## 测试设计

### 测试 fake

扩展 `FakeProvisioningRepository`：

- 可配置每条 B3/B4 命令的返回值或异常；
- 提供安全的事件发送入口；
- 只记录命令名、operation ID 和“是否提供密码”等布尔元数据；
- 不保存 configuration、密码、AP passphrase、DPP URI 或配对码；
- 现有 authorize 调用记录改为不含配对码的安全名称。

### Cubit 测试

覆盖：

- Direct AP 能力门控、单次启动、错误设备/operation 过滤；
- `DirectApReady` 后二次状态确认、确认失败、停止、恢复；
- scan capability、乱序多批次、BSSID 去重、稳定排序、扫描失败和重扫；
- 手动与扫描配置元数据、密码不进入状态、配置失败后不保留密码；
- DPP capability、启动、安全处理 bootstrap event、取消；
- STA terminal event 后二次状态确认；
- late Future、旧进度、旧终态和关闭后的事件不覆盖状态；
- Cubit close 只取消订阅。

### Widget 测试

覆盖：

- capability 不支持时入口禁用且没有 repository 调用；
- Direct AP 进度、不可取消/可取消、成功与恢复页面；
- Wi-Fi 扫描列表、unsupported 项、重新扫描；
- 手动 SSID、安全类型、隐藏网络、网络类型和密码必填；
- 密码默认遮挡，提交后输入框清空；
- DPP 入口门控；
- 错误文案不包含 raw diagnostic；
- 成功回调只在二次确认后触发。

## 验证命令

实现完成后至少执行：

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format --output=none --set-exit-if-changed `
  lib\bird_companion\features\connection\presentation `
  test\bird_companion\features\connection

& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub `
  test\bird_companion\features\connection

& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' analyze `
  lib\bird_companion\features\connection\presentation `
  test\bird_companion\features\connection

git diff --check
git status --short
```

若工具链被环境前置阻塞，报告命令、退出码和首个根因，不把未运行写成通过或失败。

## 成功标准

- B3/B4 presentation 能通过 fake repository 完整演示和自动测试。
- 成员 A 路径与 domain 零修改。
- 错误设备、错误 operation 和旧结果不能覆盖当前状态。
- AP/STA 只有二次网络状态确认后才成功。
- 所有秘密数据均不进入状态、UI、日志、fake 记录或断言。
- 生产 repository、真实入口、Android 系统交互、真实盒子和真机验收明确保留为后续依赖。

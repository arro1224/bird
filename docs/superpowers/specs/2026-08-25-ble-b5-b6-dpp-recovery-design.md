# BLE B5/B6 DPP 与动态恢复设计

## 背景

`part2` 已仅快进到公共基线 `thirdtime@290f801fb38ae1a96b2410bdf75c2d02b8a13e2c`。该基线包含成员 A 最新两项交付：

- Android Easy Connect DPP bridge、手机能力检查、系统 Activity 调用和瞬态 DPP URI 清理；
- 稳定 `device_id` 驱动的动态网络地址迁移、保存地址更新、启动恢复和活动操作恢复。

此前 B3/B4 已实现 Direct AP、Wi-Fi 扫描、手动 STA、DPP 入口、进度、取消、恢复和安全结果展示，但当时真实 Android DPP、生产 repository、动态地址迁移与启动恢复仍属于后续依赖。B5/B6 负责在不修改成员 A 实现的前提下完成展示层接线和集成验收。

本设计中的 B5/B6 是 BLE 协作批次，不是旧项目合并说明书中的相册 B5 与复制/设置 B6。

## 目标

1. B5 完成 Android Easy Connect DPP 的用户可见状态闭环。
2. B6 完成启动恢复、动态地址切换和业务会话延续的 B 侧集成验证。
3. 系统接受 DPP 不等于盒子已联网；只有盒子终态和二次状态确认通过后才能显示成功。
4. 启动恢复失败时保留已知设备和离线缓存，不退回首次设置流程。
5. 动态地址变化时继续使用稳定 `device_id`，迁移 REST、WebSocket 和相对媒体访问，并复用仍有效的 Token。
6. DPP URI、Wi-Fi 密码、配对码、Token、平台诊断文本和内部地址细节不得进入 B 侧状态、UI、日志或测试输出。

## 非目标

- 修改 Android MethodChannel、Easy Connect Activity 或权限声明；
- 修改 BLE transport、分片、编解码、domain 模型或协议 fixture；
- 修改生产 `ProvisioningRepositoryImpl`、`ConnectionRepositoryImpl`、`SessionCoordinator` 或 `DeviceSessionCubit`；
- 补写成员 A 的缺陷；若集成测试发现公共实现问题，只提供最小复现和失败证据；
- 声称真实 K7、真实路由器、真实 DPP 手机或 release 真机验收已经完成；
- 处理旧项目批次中的相册、审阅、复制、日志或设置任务。

## 文件所有权

### B 侧允许修改

- `lib/bird_companion/features/connection/presentation/**`
- `test/bird_companion/features/connection/**` 中 B5/B6 presentation 与集成测试
- 必要的 B 侧安全 fake；fake 只记录脱敏观察值
- `tool/release/verify_production_integrity.dart` 及其测试，仅用于加强正式入口 Fake 隔离
- 本设计与后续实施计划文档

### A 侧保持只读

- `android/app/src/main/java/**`
- `lib/bird_companion/features/connection/data/ble/**`
- `lib/bird_companion/features/connection/data/platform/**`
- `lib/bird_companion/features/connection/domain/**`
- `lib/bird_companion/features/connection/data/provisioning_repository_impl.dart`
- `lib/bird_companion/features/connection/data/connection_repository_impl.dart`
- `lib/bird_companion/core/session/**`
- `lib/bird_companion/app/app_dependencies.dart`

若实际实现必须修改只读范围，立即停止该项并记录阻塞，不以“接线需要”为理由越权修改。

## 总体方案

采用增量接线：保留现有 `NetworkProvisioningCubit` 和 `NetworkProvisioningPage`，在现有 generation、可信设备、operation ID 和终态确认机制上补齐 DPP 系统结果映射与恢复展示测试。

不新建第二套连接协调器，也不把发现、配对和网络配网合并成单一巨型状态机。生产 repository 继续独占 Android、BLE、秘密生命周期、网络绑定、`/health.device_id` 校验和会话迁移；B 侧只消费安全结果。

## B5：DPP 系统流程

### 启动门控

1. 盒子必须同时支持 infrastructure STA 和 DPP。
2. 用户选择 DPP 后，Cubit 只调用一次 `ProvisioningRepository.startDppProvisioning()`。
3. 手机 Easy Connect 能力和系统 Activity 可用性由 repository 检查；B 侧不直接调用平台通道。
4. 手机不支持或 Activity 不可用时，页面明确说明该方式不可用，并允许返回选择 Wi-Fi 扫描或手动配置。

### 状态语义

- `preparingDpp`：已向盒子申请 DPP bootstrap，尚未取得系统流程所需信息。
- `waitingDppConfigurator`：Android 系统界面正在接管配置；UI 只显示固定安全提示。
- `dppAuthenticating` / `dppConfigurationReceived`：盒子正在验证或接收配置；仍不是成功。
- 系统返回 accepted：只表示系统流程被接受，Cubit 继续等待盒子事件，不显示成功。
- 匹配的 `StaConnected`：进入网络确认阶段。
- `getNetworkStatus()` 返回相同 operation ID、`infrastructureSta`、`staConnected` 和非空安全 `baseUri`：才进入成功页。

错误设备、错误 operation ID、旧 generation、终态后的旧进度和 Cubit 关闭后的结果全部忽略。

### 结果映射

- `userCancelledDppDialog`：进入取消结果，允许返回其他连接方式。
- `phoneDppNotSupported`、`systemDppActivityUnavailable`：进入 DPP 不可用结果，不把整个盒子标记为不可用。
- `systemDppInvalidUri`：显示安全的系统配网不可用提示，不暴露 URI。
- `dppTimeout`：显示超时和重试入口。
- `systemDppFailed`、盒子 DPP 错误或终态确认失败：进入安全失败页。
- `NetworkRecovered`：转入恢复结果，不误报 DPP 成功。

### 取消

在协议状态允许取消且已有活动 operation ID 时显示取消操作。取消命令只发送一次。系统对话框取消由 repository 负责请求盒子取消和清理瞬态 URI；B 侧只消费脱敏错误或取消结果。

## B6：启动恢复和动态地址

### 启动恢复

生产依赖创建期间继续调用现有 `restoreSavedSession()`：

1. 没有保存设备时进入首次连接流程。
2. 有保存设备且快速恢复成功时进入统一 Shell，并刷新业务数据。
3. 有保存设备但无网络、超时或地址失效时仍进入统一 Shell，保留离线相册和设备上下文，并显示可重试连接状态。
4. 恢复请求必须有超时和取消边界，不允许启动无限加载。

B 侧通过测试验证这些既有公共行为和页面表现，不修改 A 的恢复实现。

### 动态地址切换

当同一稳定 `device_id` 获得新 `baseUri` 时，B6 验证以下集成合同：

1. 保存设备和最近设备条目更新为新地址，不产生同一设备的重复条目。
2. REST client 切换到新地址。
3. 旧 WebSocket 关闭，新 WebSocket 使用新地址和同一仍有效 Token 建立。
4. 相对媒体 URL 随活动会话解析到新地址。
5. `DeviceSessionCubit` 中同一设备的显示地址更新，并请求精确刷新。
6. 地址事件若属于其他 `device_id`，不得覆盖当前设备。

这些行为由 A6 公共实现执行；B6 只增加跨层测试和用户可见状态验证。

### 网络恢复结果

`NetworkRecovered` 表示目标网络失败后盒子恢复到可用网络：

- 显示恢复到 Direct AP 或之前 STA 的安全说明；
- 不显示 IP、passphrase、Token 或内部诊断；
- 不把恢复状态转换为本次配网成功；
- 返回后可重新选择连接方式；
- 若公共会话已经迁移，业务页面继续使用该会话，不要求重新输入配对码。

### 离线写入

启动或动态地址恢复成功后，现有 `onConnectionRecovered` 继续触发 pending operations 同步。B6 验证恢复失败不会删除旧队列，恢复成功后使用原幂等键重放，并在同步完成后请求最终刷新。

## 展示结构

复用现有连接视觉组件，不新增另一套页面框架：

- DPP 等待：固定图标、阶段标题、安全提示和条件式取消按钮；
- DPP 不可用：说明手机或系统不支持，主操作返回其他配网方式；
- DPP 取消：明确未完成且可以重新选择；
- DPP 超时/失败：通过 `UserMessageMapper` 显示固定用户消息和重试/返回操作；
- 网络恢复：区分 Direct AP 与 STA 的安全描述，不包含地址；
- 离线已知设备：继续使用统一 Shell 的现有离线状态和重连入口。

不展示“系统已接受，因此配网成功”一类误导文案。

## 安全约束

以下值不得成为 Cubit state 字段、Widget 文本、fake ledger、日志或测试快照的一部分：

- 完整 DPP URI；
- Wi-Fi SSID 对应的密码、Direct AP passphrase；
- 配对码、pairing authorization；
- access/refresh Token；
- `ProvisioningException.diagnosticMessage`；
- Android system result 原文；
- 用于调试的真实局域网地址。

测试可构造合成 URI 或 Token 作为输入，但断言只能验证没有泄漏以及安全状态变化，不打印秘密值。错误展示统一经 `UserMessageMapper` 或 B 侧固定安全文案。

## 测试设计

### B5 Cubit 测试

- 盒子不支持 DPP 时不调用 repository；
- 手机不支持、Activity 不可用和 URI 无效映射为安全且可返回的状态；
- 用户取消进入取消结果；
- DPP 超时和系统失败进入安全失败；
- 系统 accepted 后仍等待盒子终态；
- 匹配 `StaConnected` 后必须二次确认才能成功；
- 错误设备、错误 operation、旧 Future 和终态后事件被忽略；
- state 和错误对象不包含 DPP URI 或诊断文本。

### B5 Widget 测试

- DPP 等待、不可用、取消、失败、恢复和最终成功文案准确；
- 可取消与不可取消阶段按钮状态准确；
- 页面不显示 DPP URI、系统结果原文和真实地址；
- 只有确认后的成功页调用 completion callback。

### B6 集成测试

- 无保存设备、在线保存设备和离线保存设备三类启动路径；
- 旧地址失败后同一 `device_id` 使用新地址恢复；
- 地址变化关闭旧 WebSocket、复用有效 Token 并迁移 REST/媒体；
- 其他设备地址事件不污染当前 session；
- 恢复失败保留设备与 pending operations；
- 恢复成功触发同步和最终刷新；
- `NetworkRecovered` 只显示恢复结果，不调用成功 completion。

### 门禁

- 正式入口构造 Real BLE/Wi-Fi/DPP 实现；
- 测试 Fake 只能通过显式注入使用；
- release 完整性检查拒绝生产路径中的 Fake 自动发现、自动连接和配对绕过；
- 对 B5/B6 改动执行敏感关键词检查。

## 验证层级

1. B5/B6 新增定向测试。
2. 全部 `test/bird_companion/features/connection` 测试。
3. 启动、会话、缓存迁移和生产入口相关测试。
4. `flutter analyze --no-pub`。
5. 生产完整性/Fake 隔离门禁。
6. 条件允许时构建 birdV1 debug APK；构建通过不等同于真机 DPP 验收。

## 完成标准

- DPP 支持、不支持、系统接管、取消、超时、失败、恢复和最终成功均有明确安全状态与测试；
- 系统接受不被误报为配网成功；
- 启动在线恢复、离线保留和动态地址迁移均有跨层测试；
- 旧 WebSocket 关闭、Token 复用和新地址恢复有自动化证据；
- 正式入口 Fake 隔离门禁通过；
- B 侧改动不包含 A 侧文件；
- 无硬件限制被明确记录，不声称真实 K7 或真实 Android DPP 已验收。

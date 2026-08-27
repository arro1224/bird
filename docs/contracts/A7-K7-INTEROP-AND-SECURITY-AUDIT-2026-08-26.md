# A7 K7 底层联调与安全审计记录

日期：2026-08-26
分支：`part1`
协议：`1.0-rc4`

本文只记录成员 A 负责的 Android、协议、数据、会话、Mock 和契约证据。页面、文案、
settings presentation 与发布门禁属于成员 B。没有真实 K7 或真实 Android 证据时，
对应项目必须保持“外部阻断”，不能用 Fake/Mock 结果替代。

## 一、当前可完成的自动证据

| 能力 | 自动证据 | 状态边界 |
|---|---|---|
| compact/full/异常 Manufacturer Data 候选发现 | `ble_protocol_constants_test.dart`、`ble_discovery_test.dart` | 仅模拟广播 |
| 六个 UUID、Device Info、Network Status | `ble_protocol_constants_test.dart`、`ble_discovery_test.dart`、rc4 fixtures | 仅 App 解析/平台 Fake |
| MTU 23 分片、4096 字节、256 片、5 秒重组 | `ble_fragment_codec_test.dart` | 不代表真实射频/GATT |
| 加密写、通知先订阅、断线不取消盒子操作 | `ble_discovery_test.dart`、Repository 测试 | 不代表真实 Android bonding |
| `/health` 完整身份比较与 pairing session 换 Token | `health_pairing_api_test.dart`、Mock rc4 接口 | 不代表盒子端已部署 |
| request/operation 关联、迟到事件过滤、重连恢复 | `ble_request_idempotency_test.dart`、`network_operation_resume_test.dart` | Fake BLE 证据 |
| AP/STA 回滚与动态 `base_uri` | `network_operation_resume_test.dart`、`dynamic_base_uri_test.dart` | Fake Wi-Fi/HTTP 证据 |
| DPP 能力、取消、超时、临时 URI 清理 | `birdbox_dpp_platform_test.dart`、`dpp_provisioning_repository_test.dart` | Fake DPP/MethodChannel 证据 |
| 请求日志与持久化状态无敏感凭据 | `a7_mock_security_audit_test.dart` | Mock 安全断言 |
| rc4 Schema、fixture 与 App 严格模型一致 | `test/contracts/contract_validation_test.dart` | App/Mock 契约证据 |

建议执行：

```powershell
flutter test test/contracts/contract_validation_test.dart
flutter test test/bird_companion/features/connection
flutter test test/bird_companion/core/authentication_flow_test.dart `
  test/bird_companion/core/cache_schema_migration_test.dart `
  test/bird_companion/core/event_client_close_test.dart
flutter analyze
```

本轮自动验证结果（`part1@b95dc7304` 加当前 A7 工作树）：

- A7 契约、rc4 HTTP、Mock 安全与现有 Mock 回归：17/17 通过。
- `test/contracts`、整个 `features/connection` 及 A 负责的身份、缓存迁移、会话和
  WebSocket 回归：126/126 通过。
- Mock CLI `--device-id` 参数解析：通过。
- `flutter analyze`：通过，0 issues。
- Android `bird`、`birdV1` 两个 flavor 的 AndroidTest 源码编译：通过；当前平台侧
  自动证据仍是 DPP MethodChannel 测试，不能替代 K7 真机联调。
- 仓库全量测试仍存在 B 所属 `settings_phone_layout_test.dart` 首屏布局阻断；该项
  不属于本次 A7 文件改动，不能记录为 A7 底层失败，也不能在 S4 最终门禁中忽略。

## 二、必须使用真实 K7 与 Android 手机的证据

| 编号 | 场景 | 当前状态 | 所需脱敏证据 |
|---:|---|---|---|
| K7-01 | 盒子固件版本、rc4 版本、六个 UUID、字段与错误码一致 | 外部阻断 | 固件 SHA、App SHA、读取结果摘要 |
| K7-02 | 无 Manufacturer Data 的 compact 广播可发现、入列和连接 | 外部阻断 | 扫描/GATT 时间线，不记录 MAC |
| K7-03 | full 广播失败自动降级 compact，异常扩展不阻断 GATT | 外部阻断 | 盒子脱敏档位与原因日志 |
| K7-04 | GATT 完整 `device_id` 与 `/health.device_id` 一致 | 外部阻断 | 仅记录一致/不一致及脱敏 ID 摘要 |
| K7-05 | 加密链路、MTU 23、分片、订阅和断线恢复 | 外部阻断 | Android/K7 操作时间线 |
| K7-06 | BirdBox AP、DHCP、无互联网网络、Network 绑定与释放 | 外部阻断 | 系统结果和 `/health` 结果 |
| K7-07 | AP→STA、STA→AP、STA A→STA B、失败回滚 | 外部阻断 | operation 状态与最终模式 |
| K7-08 | 动态 `base_uri` 后 REST、WS、媒体会话恢复 | 外部阻断 | 三类客户端恢复结果 |
| K7-09 | DPP 成功、失败、取消、超时和不可用 | 外部阻断 | 系统结果、盒子终态、health 结果 |
| K7-10 | 前台扫描、后台恢复、反复开关蓝牙、盒子重启 | 外部阻断 | 场景矩阵和结果 |

## 三、安全取证规则

- 禁止保存或提交验证码、`pairing_session_id`、Wi-Fi/AP 密码、Bearer Token、完整
  DPP URI、完整蓝牙 MAC。
- Mock 请求日志只允许记录 HTTP method 与 path，不记录 query、header 或 body。
- 状态文件不得持久化配对响应、Token 或配对会话。
- 真机截图和日志必须先脱敏；无法脱敏的证据只现场核验，不进入仓库。
- `client_id`、`request_id`、`operation_id` 只记录是否匹配及必要的短摘要。

## 四、当前结论

A7 的 Mock、契约和安全审计可以在没有 K7 时推进；K7-01～K7-10 在真实设备证据
补齐前保持外部阻断。成员 B 的 settings 页面测试阻断与本表底层证据独立处理，不能
由成员 A 修改 B 所属页面或通过弱化测试绕过。

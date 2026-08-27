# A7 模拟基线至 B7 交接方案

日期：2026-08-27

## 一、交接结论

A7 当前交付“模拟环境预检基线”，不交付真实 K7 通过结论。成员 B 可以基于该基线
完成 B7 的页面/状态机回归、验收工具、证据模板和 Preflight 门禁；真实用户流程、
Release 门禁以及 S4 关闭仍等待真实 K7 与真实 Android 手机。

已验证的 App 代码基线：

- `part1@9c46006f4421c7e26b7df911e4b80eac2b5fe83a`
- `flutter analyze`：0 issues
- 全量 `flutter test`：533/533 通过
- B5/B6 settings 阻断修复：`thirdtime@23489978d`

## 二、不可改变的真实链路基线

1. 不修改 `1.0-rc4` 的 UUID、Schema、字段、错误码、超时、幂等和 operation 语义。
2. 生产装配继续构造真实 BLE、Wi-Fi、DPP 和安全存储实现；禁止回退到 Fake/Mock。
3. `MockBoxServer` 只模拟 HTTP；BLE、Wi-Fi、DPP 只允许在测试进程内使用 Fake。
4. 不在 `lib/main.dart`、正式 flavor 或生产依赖注入中加入“模拟盒子”开关。
5. 模拟证据必须标记 `environment=simulated`、`releasable=false`，不得写入真实设备证据。
6. Release 门禁必须要求真实盒子证据，且拒绝 simulated/preflight 证据。
7. Mock 必须适配冻结契约；禁止修改契约去迁就 Mock。

## 三、B7 可以立即实施的文件

以下文件属于成员 B，成员 A 不直接修改：

| 文件 | B7 修改要求 |
|---|---|
| `tool/acceptance/ble_provisioning_rc4_acceptance.dart` | 新增；执行 rc4 模拟验收并生成明确的 simulated 结果 |
| `tool/release/run_b7_gate.ps1` | 保持 `Preflight/Release` 双模式；Preflight 可无盒子，Release 强制真实证据 |
| `tool/release/verify_production_integrity.dart` | 保持生产入口只能构造真实 BLE/Wi-Fi/DPP，检测到 Fake/Mock 即失败 |
| `docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json` | 新增真实证据空模板；不得预填模拟通过结果 |
| `docs/implementation/BLE-RC4-APP-ACCEPTANCE-2026-08-18.md` | 分开记录模拟通过项和真实待验证项 |
| B 所属 `flow/page/acceptance` 测试 | 使用 Fake Repository 覆盖用户流程，不导入生产 Mock 开关 |

## 四、模拟环境组成

| 能力 | 使用实现 | 能证明 | 不能证明 |
|---|---|---|---|
| HTTP 身份与配对 | `tool/mock_box_server/**` | `/health`、`/api/v1/pairing`、Token/日志/持久化规则 | 真实 K7 HTTP 部署和无线可达性 |
| BLE | `FakeBirdBoxBleDataSource` | compact/full/异常广播、九类命令、事件、断连和迟到事件逻辑 | 真实广播、bonding、MTU 和 GATT 通知 |
| Wi-Fi | `FakeBirdBoxWifiPlatform` | 加入、绑定、释放及错误映射 | DHCP、无互联网 Network 和厂商系统行为 |
| DPP | `FakeBirdBoxDppPlatform` | 支持/不支持、成功、失败、取消、超时映射 | 系统 Easy Connect 页面和 K7 最终状态 |

启动 rc4 HTTP Mock 时使用符合冻结格式的测试设备 ID：

```powershell
dart run tool/mock_box_server/server.dart --quick --auth `
  --device-id=bbx-82f41c9e7a3d4b68a1501e21e536c649
```

测试数据必须是明显的合成数据，不得复制真实验证码、密码、Token、完整 DPP URI 或
蓝牙 MAC。

## 五、B7 模拟验收矩阵

| 编号 | 模拟验收场景 | 预期结果 | 真实 K7 状态 |
|---:|---|---|---|
| SIM-01 | compact 广播无 Manufacturer Data | 可入列、可选择，并以 GATT Device Info 完成身份逻辑 | `real_pending` |
| SIM-02 | full、缺失和异常扩展 | 异常扩展被忽略，不阻断基础发现 | `real_pending` |
| SIM-03 | BLE 配对会话换 Token | 验证码不进入 HTTP，临时会话不落盘 | `real_pending` |
| SIM-04 | Direct AP 加入/退出 | 页面状态与 Fake Network 绑定/释放结果一致 | `real_pending` |
| SIM-05 | STA 扫描、手输和 QR | 三种入口统一进入 `set_sta_config` 语义 | `real_pending` |
| SIM-06 | AP→STA、STA→AP、失败回滚 | operation 与最终网络模式一致 | `real_pending` |
| SIM-07 | 动态 `base_uri` | REST、WebSocket、媒体会话刷新逻辑通过 | `real_pending` |
| SIM-08 | DPP 成功/失败/取消/超时/不可用 | 页面状态、重试和安全文案符合约定 | `real_pending` |
| SIM-09 | 断连、迟到事件和恢复 | 不错误取消盒子操作，不接受旧 operation 事件 | `real_pending` |
| SIM-10 | 日志和状态安全 | UI、日志和模拟持久化不暴露敏感信息 | `real_pending` |

所有模拟用例通过后，只能记录：

```text
B7 simulated preflight passed; real K7 acceptance pending.
```

## 六、Preflight 与 Release 隔离

当前可以执行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/run_b7_gate.ps1 `
  -Mode Preflight
```

Preflight 输出必须包含：

- `mode=Preflight`
- `environment=simulated`
- `releasable=false`
- App Git SHA、通过/失败步骤
- `real_k7_status=pending`

Release 模式必须继续要求：

- `-RealBoxEvidencePath`
- 真实 K7 firmware SHA 与冻结 baseline 一致
- 至少一台真实 Android 的设备型号和系统版本
- 所有必需真实用例为 passed 且带脱敏证据引用
- `environment=real_k7`
- `e2e_passed=true`

禁止增加 `SkipRealBoxEvidence`、把 simulated evidence 改名为 real evidence，或降低
上述校验。

## 七、Git 交接流程

本次只同步 A7 模拟预检能力，不代表正式 A7 完成。A/B 不直接相互合并分支；若 B7
需要这批 Mock 能力，由集成人以非最终标记把 `origin/part1` 合入 `thirdtime`：

```text
merge(batch-4-A-preflight): sync simulated A7 baseline
```

禁止使用正式关闭标记：

```text
merge(batch-4-A): sync part1 into thirdtime
```

成员 B 收到预检同步通知后，从本地 `thirdtime` 拉取并合入 `part2`；禁止直接合并
`origin/part1`。B 的建议提交：

```text
test(batch-4/B-preflight): add simulated rc4 acceptance without weakening real gate
```

## 八、完成定义

当前可以完成 A7/B7 simulated preflight、B7 flow/page/acceptance 测试、Preflight
门禁、验收工具和真实证据空模板。

当前不能完成 A7 真实底层联调、B7 真实用户流程验收、B7 Release 门禁和 S4 最终
候选关闭。真实 K7 到位后，沿用同一 rc4 契约和生产链路补充真实证据，不得回滚或
替换当前真实实现。

## 九、可直接发送给成员 B 的通知

```text
【正式批次 4 / A7 模拟预检交接】

A7 模拟环境基线已完成，已验证代码基线：
part1@9c46006f4421c7e26b7df911e4b80eac2b5fe83a
flutter analyze：通过；全量 flutter test：533/533 通过。

当前无真实 K7，本次交接只用于 B7 的 Mock/Fake 页面回归、验收工具、证据模板和
Preflight 门禁，不代表 A7/B7/S4 完成。

B 请保持生产 BLE/Wi-Fi/DPP 装配、rc4 契约和 Release 真实证据门槛不变；模拟结果
必须标记 environment=simulated、releasable=false、real_k7_status=pending。

B 可以完成 B7 simulated preflight；真实用户流程、Release 门禁和 S4 关闭继续等待
真实 K7。请等待集成人以 merge(batch-4-A-preflight) 非最终标记合入 thirdtime 后
再从 thirdtime 回拉；不要直接合并 origin/part1。
```

# BLE 20 虚拟外设与先绑定验证

本工具使用生产 App BLE 通道和独立 Android GATT Server。虚拟外设仅提供 debug 构建，默认 testOnly=true，release variant 禁用；它不进入生产 App。所有证据保持 hardware_status=pending，不能替代真实 BirdBox、华为或 vivo 的无线联调。

## 准备与运行

复用已安装的 API 36.1 镜像及 Android Emulator 36.5 以上版本：

```powershell
.\tool\ble11\setup_ble11_avds.ps1
.\tool\ble11\run_ble11_dual_avd.ps1 -Scenario bond_first -WipeData
.\tool\ble11\run_ble11_dual_avd.ps1 -Scenario auth_once -WipeData
```

运行器检查 5554/5556 端口空闲并验证自建 AVD 身份。它启用 netsim PCAP，使用当前版本默认 RSSI，不宣称固定信号值。测试用 AVD 的系统 Pair 按钮由实际 UI 节点定位并确认；仍依赖真实 SMP、bond 广播及 GATT 回调。除 already_bonded 外，可用 -WipeData 隔离绑定状态；already_bonded 应在成功配对后不清数据运行。-KeepRunning 只用于界面排查，活跃 PCAP 尚未关闭时不作为验收产物。

## 场景

| 场景 | 预期 |
| --- | --- |
| bond_first | createBond 一次，绑定后重建 GATT、恢复通知，命令一次，无恢复 |
| already_bonded | createBond 零次，重建和订阅后写入一次 |
| auth_once | 已绑定状态在首个异常 GATT 轮次返回 5，重建后单次恢复成功 |
| auth_persistent | 两个 GATT 轮次均返回 5，最多一次恢复后终止 |
| att_timeout_first / middle / last | 对真实首、中、末分片省略 ATT 响应，重建后恢复一次 |
| notification_failure | 第二路 CCCD 失败，阻止受保护写入 |
| disconnect_once | 指定分片触发真实断链，当前命令失败 |
| response_delay | ATT 正常确认，业务通知延迟 1000 毫秒 |
| response_wrong | ATT 成功但业务 request_id 错误，等待业务超时 |
| response_duplicate | 两次业务通知，副作用仅执行一次 |
| business_timeout | ATT 全部成功，省略业务通知，业务超时 |

ATT 超时集成场景仅将发送分片上限设为 20 字节，以便大 MTU 下也能分别测试首、中、末片；实际 MTU 和原生写入路径保持真实。其他场景上限为 512 字节，同时不得超过实际 MTU 减 3。

虚拟外设可通过界面选择场景，也接受以下 Intent extras：fault_characteristic（6f7d0005 命令或 6f7d0004 Wi-Fi），fault_position（first/middle/last/index），fault_fragment_index（从 1 开始），fault_status（5/15），att_response_delay_ms、business_response_delay_ms（0 至 60000）。auth_once 的“一次”指一个异常 GATT/订阅轮次，覆盖 Android 栈内部安全重发；实际断开或两路 CCCD 重新恢复后释放。客户端重建可以保留底层连接，不能只等物理断开。auth_persistent 在每个轮次持续失败。省略 ATT 响应在分片重组前注入。

## 华为与 vivo 双手机运行

BLE-21 已补充原生虚拟协议的验证码窗口与独立配网操作状态。应用验证码为 246810；Intent 可额外设置 `business_outcome=success|failure|hold` 和 `business_base_uri`（默认测试保留地址 `http://192.0.2.1:8080`）。`command_accepted` 后约 1.2 秒才生成模拟终态；断开不会取消盒子内存中的操作，重新读取或 `get_network_status` 可获取当前结果。重复 request_id 的完整命令仍由账本去重。原生段不提供真实 AP/STA 或 HTTP 服务，未实现的扫描/DPP/Bearer 授权返回冻结错误码；HTTP 业务闭环请使用 `tool/ble21/run_local_business_checks.ps1` 和 `tool/mock_box_server/README.md` 的 Debug 分段。安全层 13 场景入口与证据规则继续保留。

先用 adb devices 确认两部不同设备在线，核对角色并保持解锁。对端手机保持虚拟外设前台；操作者确认系统配对弹窗。权限/API 能力不支持时登记实际失败，不伪造广播或绑定成功。

脚本预装 App 并按实际 SDK 授予测试权限，Flutter 覆盖安装保留权限。旧版 Android App 端还需开启系统定位总开关；两部手机都需开启蓝牙。ROM 阻止 test-only ADB 安装时，可使用已有独立 debug 手动安装配置（android 目录执行 gradlew :virtualBirdBox:assembleDebug -PvirtualBirdBoxManualInstall=true）；这仍没有 release variant，手动安装后不能宣称正常 test-only 候选已冻结。

```powershell
.\tool\ble11\run_ble20_two_phones.ps1 -AppSerial <App手机序列号> -BoxSerial <虚拟外设手机序列号> -Scenario bond_first
.\tool\ble11\run_ble20_two_phones.ps1 -AppSerial <App手机序列号> -BoxSerial <虚拟外设手机序列号> -Scenario auth_once
```

非 already_bonded 场景先在两部手机的系统设置中清除测试绑定；already_bonded 复用已成功绑定状态。手机证据记录实际型号、SDK 和设备别名，不要求 netsim/PCAP。调换 App/对端角色后重新运行。单台在线手机不构成双手机证据。

## 证据与校验

输出位于 outputs/ble11/，已排除源代码管理。schema_version=2 分别使用 virtual_birdbox_avd 和 virtual_birdbox_phone；旧 schema 1 只作历史读取，不能充当新的先绑定证据。

```powershell
dart tool/ble11/validate_ble11_evidence.dart <场景.evidence.json>
```

新规则交叉检查真实 createBond 次数、父请求与完整消息哈希、命令次数与 ATT 次数、代次、通知恢复、分片长度、单次恢复及业务去重。AVD 命令行校验会重读本地蓝牙 PCAP 并核对 SHA-256，拒绝缺失、篡改或越界路径。单元测试 fixture 仅用于校验规则，不代表无线通过。

PCAP 可能含链路标识，仅留本地；对外提供脱敏 JSON 和捕获哈希，真实板端验收另行执行。完整 13 场景候选冻结在 BLE 23 进行，主成功和一次恢复通过不等于整个矩阵通过。

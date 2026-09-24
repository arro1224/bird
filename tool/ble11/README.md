# BLE-11 双 AVD 运行器

该目录只服务于模拟验证，不进入 BirdBox 发布 APK。虚拟盒子 APK 的
`android:testOnly=true`，Gradle 同时禁用了它的 release variant。

## 一次性准备

```powershell
powershell -ExecutionPolicy Bypass -File tool\ble11\setup_ble11_avds.ps1 -UpdateEmulator
```

要求 Android Emulator 36.5+。脚本复用已安装的 API 36.1 Play Store x86_64
镜像，创建 `ble11_app_api36` 和 `ble11_box_api36` 两台不同 AVD。

## 场景运行

每个场景建议使用 `-WipeData` 单独运行，以隔离 Android Bond 数据：

```powershell
powershell -ExecutionPolicy Bypass -File tool\ble11\run_ble11_dual_avd.ps1 -Scenario success -WipeData
powershell -ExecutionPolicy Bypass -File tool\ble11\run_ble11_dual_avd.ps1 -Scenario auto_bond -WipeData
powershell -ExecutionPolicy Bypass -File tool\ble11\run_ble11_dual_avd.ps1 -Scenario fallback_once -WipeData
powershell -ExecutionPolicy Bypass -File tool\ble11\run_ble11_dual_avd.ps1 -Scenario disconnect_once -WipeData
```

运行前须关闭占用 `emulator-5554` 或 `emulator-5556` 的模拟器。运行器必须亲自
启动两台 AVD，才能保证两边进入同一个 netsim 实例并把 PCAP 写入本次证据目录。

运行器会：

- 隐藏启动两台 AVD，并用 netsim 固定 BLE RSSI 为 -55 dBm；
- 启用 PCAP、安装 debug/test-only 虚拟盒子和 BirdBox App；
- 使用生产 `PlatformBirdBoxBleDataSource` 和原生 `BirdBoxBleChannel`；
- 校验发现、五特征、两路订阅、匹配 `request_id`、Bond 后 GATT 恢复、
  原字节单次重试、主动断链与连接代次；
- 在 `outputs/ble11/<时间>-<场景>/` 生成脱敏日志、PCAP 和 JSON 证据；
- 强制证据保持 `evidence_kind=simulated`、`hardware_status=pending`。

任何场景缺少 PCAP、JSON/文本证据包含完整 MAC 或凭据、尝试宣称硬件通过，
或没有满足对应断言，证据校验都会失败。PCAP 是未脱敏的受限调试产物，可能
含链路层标识；只在本地保管，外发时仅提供证据 JSON 中的路径和 SHA-256，不能
直接粘贴或上传。双 AVD 结果只代表 AOSP 模拟栈，不能替代 OPPO、Huawei 和
真实 BirdBox/K7 联调。

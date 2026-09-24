# BLE-12 诊断复制与回传说明

## 可以回传

- 候选 `candidate_id`、Git SHA、源码指纹和 APK SHA-256；
- App“复制诊断 JSON”产生的脱敏 JSON；
- 虚拟 BirdBox 的脱敏事件 JSONL；
- 场景名称、时间、手机型号、Android/ColorOS/HarmonyOS 版本；
- PCAP 的文件名、相对路径、字节数和 SHA-256。

## 不能直接回传

- 原始 PCAP；
- 完整蓝牙 MAC、BSSID、SSID；
- 配对码、配对会话标识；
- Wi-Fi 密码、DPP URI；
- Access Token、Refresh Token 或任何 Cookie；
- 未脱敏的 logcat 全量日志。

回传前运行包内 `verify_package.ps1`，并确认所有 JSON 都保持：

```text
evidence_kind=simulated
hardware_status=pending
releasable=false
```

真实硬件证据必须单独使用 BLE-03 模板和校验器，不得覆盖模拟证据文件。

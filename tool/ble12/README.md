# BLE 12 候选冻结与模拟证据包

BLE 20 已把新候选规则更新为先绑定流程。当前 App 为 1.14.11+176，虚拟外设为 ble20/2；旧 schema 1 四场景包保留历史读取，新候选不得复用它们。

生成器运行全量 Flutter 测试、静态分析及 App/虚拟外设原生测试，冻结源码、构建环境和 APK SHA-256。新候选最低要求 App 原生 126 项、虚拟外设 31 项检查，并提供 BLE 20 全部 13 场景 schema 2 证据，场景见 [运行手册](../ble11/README.md)。

```powershell
.\tool\ble12\build_ble12_candidate.ps1 -Ble11Evidence <13个场景证据路径> -CreateZip
dart tool/ble12/validate_ble12_candidate.dart --manifest=<候选目录>/candidate-manifest.json --repository=.
```

双 AVD 场景包含实际 PCAP 与哈希；双手机虚拟外设场景可使用 virtual_birdbox_phone，不要求 netsim。无可用环境时只允许登记实际环境缺口；提供主成功和一次恢复不能替代完整矩阵。包内 verify_package.ps1 用于离线文件校验。

本次 BLE 20 仅更新兼容规则和工具，本轮未生成完整候选包。BLE 23 再统一冻结版本、全部必要批次、设备结果与交接材料。所有模拟候选保持 hardware_status=pending、releasable=false。

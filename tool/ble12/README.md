# BLE-12 候选冻结与模拟证据包

生成器会运行全量 Flutter 测试、静态分析、20 个 App 原生 BLE 测试、8 个虚拟
盒子测试，并重新构建 App 与虚拟盒子 APK。随后冻结：

- 当前基线 Git SHA、分支和工作区状态；
- BLE 生产/测试/工具文件逐文件 SHA-256 及稳定汇总指纹；
- 两个 APK 的 SHA-256；
- Flutter、Dart、Java、Gradle、Android Emulator 和 AVD 环境；
- BLE-11 状态、自动测试摘要、外场手册、诊断说明和回传模板。

运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool\ble12\build_ble12_candidate.ps1
```

如果四个 BLE-11 双 AVD 场景已经完成，可传入四个证据文件：

```powershell
powershell -ExecutionPolicy Bypass -File tool\ble12\build_ble12_candidate.ps1 `
  -Ble11Evidence <success.json>,<auto_bond.json>,<fallback_once.json>,<disconnect_once.json> `
  -CreateZip
```

Emulator 低于 36.5 时，生成器只允许输出诚实的
`simulation.status=pending_environment`；若已经具备 36.5+，却没有提供四场景
证据，生成器会拒绝打包。无论模拟场景是否通过，顶层状态始终是
`hardware_status=pending`、`releasable=false`。

包内离线校验：

```powershell
powershell -ExecutionPolicy Bypass -File <候选目录>\verify_package.ps1
```

仓库侧语义与当前源码冻结校验：

```powershell
dart tool\ble12\validate_ble12_candidate.dart `
  --manifest=<候选目录>\candidate-manifest.json `
  --repository=.
```

# 拍鸟伴侣

拍鸟伴侣是用于连接拍鸟盒子、浏览与审阅照片、管理复制任务和设备状态的 Flutter Android 客户端。

## 运行

```powershell
flutter pub get
flutter run --flavor bird
```

默认入口 `lib/main.dart` 会启动任务与设备模块。独立入口仍保留在
`lib/main_bird_settings.dart`，项目业务源码位于 `lib/bird_companion`。

## Android 构建

统一使用 `tool/release/build_android_apks.ps1`：

```powershell
# 日常联调，只生成 bird Debug
powershell -ExecutionPolicy Bypass -File tool/release/build_android_apks.ps1

# 华为扫描排查，只生成 Scan A/B Debug
powershell -ExecutionPolicy Bypass -File tool/release/build_android_apks.ps1 -Mode HuaweiAB

# 模拟盒子入口，只生成 birdSim Debug
powershell -ExecutionPolicy Bypass -File tool/release/build_android_apks.ps1 -Mode Simulation
```

只有 `bird` 允许生成 Release；`birdSim`、`birdScanA` 和 `birdScanB` 均为内部 Debug
构建，不得作为正常 App 交付。

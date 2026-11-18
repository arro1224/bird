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

正式 App 仍仅使用 `bird` Release；`birdSim`、`birdScanA` 和 `birdScanB` 仍仅支持内部 Debug。
独立的 `birdDemo` 可生成演示用 Debug / Release，使用独立包名和本机调试证书，不作为正式 App 或真实盒子验收证据。

## 内置盒子演示版（显式启用）

默认 `lib/main.dart` 和 `bird` 不变。需要内置盒子时，在项目根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_demo_apk.ps1
```

脚本先运行模拟业务和正常入口隔离检查，再生成独立演示 APK，并输出完整路径。
也可使用统一构建入口：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/build_android_apks.ps1 -Mode EmbeddedDemo -BuildType Release
```

演示入口为 `lib/main_bird_demo.dart`，应用标识为 `deckers.thibault.aves.bird.demo`，
内置本机盒子服务与离线示例照片，可与正常 App 共存。示例照片只打入 `birdDemo`。
电脑端与 App 内置端共用同一套模拟盒子实现。使用边界、维护位置和验证方式见
[内置盒子复用说明](docs/embedded-box-demo.md)。

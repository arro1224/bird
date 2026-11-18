# 项目4内置模拟盒子复用说明

## 使用

正常 App 仍使用 `lib/main.dart` 和默认 `bird`，连接真实盒子。

在项目根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_demo_apk.ps1
```

默认先测试后构建演示 Release，输出 APK 完整路径。安装包、源码指纹、签名指纹
及构建清单保存在 `build/delivery/embedded-demo-时间戳/`。调试时可加 `-BuildType Debug`。
已有测试通过后再次构建可加 `-SkipTests`。可用 `-OutputDirectory` 指定仓库内的新目录，
已有显式输出目录拒绝覆盖。

完整构建入口也支持：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/build_android_apks.ps1 -Mode EmbeddedDemo -BuildType Release
```

直接运行应用时必须同时选择入口和 flavor：

```powershell
flutter run --flavor birdDemo -t lib/main_bird_demo.dart
```

演示包名为 `deckers.thibault.aves.bird.demo`，显示“拍鸟伴侣演示版”，可与正常 App 共存。
启动后自动连接本机模拟服务，无需盒子、电脑服务、USB或互联网。
顶部“演示工具”可重新连接和演示配网；应用验证码123456。
四张已有鸟类图片组成60条示例照片记录。硬件状态、识别、文件复制和网络切换为模拟效果。

## 复用结构

| 位置 | 用途 |
| --- | --- |
| `lib/bird_companion/simulation/mock_box_server.dart` | 唯一的 Dart HTTP/WebSocket 模拟盒子实现 |
| `tool/mock_box_server/mock_box_server.dart` | 兼容原工具和测试的导出入口 |
| `tool/mock_box_server/server.dart` | 原电脑服务入口，可用 `--embedded-demo` 开启增强演示 |
| `lib/bird_companion/simulation/embedded_demo/demo_runtime.dart` | 打包照片释放、只监听127.0.0.1、内存授权、离线网络适配和自动连接 |
| `lib/bird_companion/simulation/embedded_demo/embedded_demo_app.dart` | 复用原 App 路由和三个标签页的演示宿主 |
| `lib/main_bird_demo.dart` | 明确启用的演示入口 |
| `tool/build_demo_apk.ps1` | 一条命令测试并生成安装包 |
| `tool/release/build_android_apks.ps1` | 与正常构建共用 APK、签名、源码指纹和交付清单逻辑 |

## 从11.18独立演示版迁入的内容

- 选中照片的分块清单与封存接口，单张选择的有效预检，设备别名。
- 普通任务、复制任务、审阅、别名与持续复制会话的保存和恢复。
- 持续复制自动推进、暂停/恢复、分页文件明细、分组历史、信息更新预览和结果。
- 盒子服务与照片资源内置、App 启动自动连接、配网状态与HTTP模式一致。
- 共用原有 Repository、鉴权、WebSocket、相册、任务、设备与设置页面。

增强服务通过 `embeddedDemo: true` 明确启用。传统模拟模式默认保留原有能力声明、
子任务统计和手动跟随推进方式，原有模拟验收不自动变成持续复制演示。

## 与正常 App 的边界

- `lib/main.dart`、`lib/main_bird.dart` 和默认 `bird` 保持原入口。
- 正常依赖工厂的新增参数仅为接口注入点，默认仍构造真实 BLE、Wi-Fi、DPP、网络监测和安全会话存储。
- 正常 App 的导入图不包含 simulation 服务或演示宿主。
- 示例资源通过 Flutter flavor 限定为 `birdDemo`，构建脚本检查实际 APK：演示包必须有四张样图，正常包必须没有。
- Gradle拒绝演示入口与正常 flavor 混用。专用安卓集成测试仅允许 Debug。
- `birdDemo` 使用本机调试证书；正常 Release 原有正式签名与发布门禁保持原流程。
- 演示清单始终为模拟、不可正式发布、不是实际盒子验收证据。

## 后续维护

新的模拟HTTP接口、任务状态、持久化修复只修改共享模拟服务；不要在电脑端和内置端再复制一份实现。
演示特有的能力变化使用 `embeddedDemo` 开关，真实 App 接口和默认行为独立验证。
更换样图优先复用 `tool/mock_box_server/assets/`；同步更新 `DemoRuntime.sampleNames` 与构建脚本的资源核对清单。
不要用 `-NoPub` 构建演示 Release：当前Flutter版本需要重新生成Release插件注册，避免误带集成测试组件。

## 验证

```powershell
flutter test --concurrency 4 --timeout 2m test
dart run tool/release/verify_production_integrity.dart
flutter test integration_test/embedded_demo_app_test.dart --flavor birdDemo -d <验证设备>
```

安卓集成测试只应用到专用模拟器或测试设备，可在断网状态验证页面。
普通构建使用原统一入口 `-Mode Normal`，会额外核对模拟样图未打入正常 APK。
本次验证结果和安装包路径记录在 `build/embedded-demo-verification/` 与各构建交付清单中。

任务进度与断线恢复回归包含40秒观察窗口，全量测试使用 `--timeout 2m`，避免默认30秒测试时限提前中断真实计时验证。

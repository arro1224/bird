# 拍鸟伴侣

拍鸟伴侣是用于连接拍鸟盒子、浏览与审阅照片、管理复制任务和设备状态的 Flutter Android 客户端。

## 运行

```powershell
flutter pub get
flutter run --flavor bird
```

默认入口 `lib/main.dart` 会启动任务与设备模块。独立入口仍保留在
`lib/main_bird_settings.dart`，项目业务源码位于 `lib/bird_companion`。

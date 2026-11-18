import 'dart:async';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_widgets.dart';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'demo_runtime.dart';
import 'package:flutter/material.dart';

class BirdDemoBootstrap extends StatefulWidget {
  const BirdDemoBootstrap({super.key});
  @override
  State<BirdDemoBootstrap> createState() => _BirdDemoBootstrapState();
}

class _BirdDemoBootstrapState extends State<BirdDemoBootstrap> {
  late Future<DemoRuntime> _future = DemoRuntime.start();
  DemoRuntime? _runtime;

  @override
  void dispose() {
    final runtime = _runtime;
    if (runtime != null) unawaited(runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DemoRuntime>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        _runtime = snapshot.data;
        return BirdEmbeddedDemoApp(runtime: snapshot.data!);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flutter_dash_rounded, size: 72),
                  const SizedBox(height: 18),
                  const Text('拍鸟伴侣 · 演示版', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (snapshot.hasError) ...[
                    const Text('演示盒子启动失败，请点击重试。'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => setState(() => _future = DemoRuntime.start()), child: const Text('重新启动')),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('正在准备内置盒子和示例照片…'),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class BirdEmbeddedDemoApp extends StatefulWidget {
  const BirdEmbeddedDemoApp({super.key, required this.runtime});
  final DemoRuntime runtime;
  @override
  State<BirdEmbeddedDemoApp> createState() => _BirdEmbeddedDemoAppState();
}

class _BirdEmbeddedDemoAppState extends State<BirdEmbeddedDemoApp> {
  final _navigator = GlobalKey<NavigatorState>();

  Route<dynamic>? _route(RouteSettings settings) => BirdAppRouter.onGenerateRoute(
    settings,
    provisioningRepository: widget.runtime.provisioning,
    onProvisioningCompleted: widget.runtime.connect,
  );

  void _showTools() {
    showModalBottomSheet<void>(
      context: _navigator.currentContext!,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('内置盒子演示', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('已内置 ${widget.runtime.server.photoCount} 张${widget.runtime.server.acceptanceProfile == null ? '示例' : '返修验收'}照片、相机存储卡和 USB 目标盘。照片审阅、导入、分析、复制、设备及设置沿用现有 App 页面，任务会自动推进。'),
              const SizedBox(height: 8),
              const Text('盒子状态、识别结果、文件复制和网络切换为模拟效果。无需真实盒子、电脑或联网；审阅记录和任务历史保存在本机。'),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新连接内置盒子'),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.runtime.connect();
                  if (mounted) BirdFeedback.success(_navigator.currentContext!, '内置盒子已重新连接。');
                },
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth_searching),
                title: const Text('演示连接与配网'),
                subtitle: const Text('应用验证码：123456'),
                onTap: () {
                  Navigator.pop(context);
                  _navigator.currentState!.pushNamed(BirdRoutes.connection, arguments: const ConnectionArgs(entryMode: ConnectionEntryMode.addOrSwitch));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BirdCompanionScope(
    dependencies: widget.runtime.dependencies,
    child: PhoneDiagnosticLifecycle(
      recorder: widget.runtime.dependencies.phoneDiagnostics,
      child: MaterialApp(
        navigatorKey: _navigator,
        scaffoldMessengerKey: BirdFeedback.messengerKey,
        navigatorObservers: [BirdFeedbackNavigatorObserver(), PhoneDiagnosticNavigationObserver(widget.runtime.dependencies.phoneDiagnostics)],
        title: '拍鸟伴侣 · 演示版',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: BirdAppShell(initialIndex: 0, onGenerateRoute: _route),
        onGenerateRoute: _route,
        builder: (context, child) => Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.science_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(widget.runtime.server.acceptanceProfile == null ? '演示版 · 内置模拟盒子' : '模拟验收 · ${widget.runtime.server.photoCount} 张', style: const TextStyle(fontSize: 12))),
                        TextButton(
                          onPressed: _showTools,
                          child: const Text('演示工具', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child ?? const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    ),
  );
}

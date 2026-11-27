import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_demo_shell.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/simulation/embedded_demo/demo_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  const demoMode = bool.fromEnvironment('BIRD_DEMO_MODE');
  if (!demoMode) {
    throw StateError(
      'main_bird_settings.dart is demo-only. '
      'Run with --dart-define=BIRD_DEMO_MODE=true.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  BirdErrorBoundary.install();
  runApp(const BirdSettingsBootstrap());
}

class BirdSettingsBootstrap extends StatefulWidget {
  const BirdSettingsBootstrap({super.key});

  @override
  State<BirdSettingsBootstrap> createState() => _BirdSettingsBootstrapState();
}

class _BirdSettingsBootstrapState extends State<BirdSettingsBootstrap> {
  late final Future<DemoRuntime> _runtime = DemoRuntime.start(autoConnect: false);
  DemoRuntime? _createdRuntime;

  @override
  void dispose() {
    final runtime = _createdRuntime;
    if (runtime != null) unawaited(runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DemoRuntime>(
    future: _runtime,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        _createdRuntime ??= snapshot.data;
        return BirdSettingsApp(runtime: snapshot.data!);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: snapshot.hasError ? const Text('拍鸟伴侣启动失败，请完全停止应用后重试。') : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class BirdSettingsApp extends StatefulWidget {
  const BirdSettingsApp({super.key, required this.runtime});

  final DemoRuntime runtime;

  @override
  State<BirdSettingsApp> createState() => _BirdSettingsAppState();
}

class _BirdSettingsAppState extends State<BirdSettingsApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final TaskExperienceController _taskController = TaskExperienceController(
    const DemoTaskExperienceDataSource(),
  );
  BirdCompanionDependencies get _dependencies => widget.runtime.dependencies;
  late final DeviceStatusCubit _deviceStatus = DeviceStatusCubit(
    _dependencies.deviceRepository,
    _dependencies.deviceSessionCubit,
    _dependencies.refreshCoordinator,
    _dependencies.dataChangeBus,
  );
  late final StreamSubscription<DeviceSessionState> _deviceSessionSubscription;
  Future<void>? _reconnectInFlight;

  @override
  void initState() {
    super.initState();
    _syncTaskConnection(_dependencies.deviceSessionCubit.state);
    _deviceSessionSubscription = _dependencies.deviceSessionCubit.stream.listen(_syncTaskConnection);
  }

  @override
  void dispose() {
    unawaited(_deviceSessionSubscription.cancel());
    _taskController.dispose();
    unawaited(_deviceStatus.close());
    super.dispose();
  }

  void _reconnectDemo() {
    if (_reconnectInFlight != null) return;
    final future = _connectAndRefresh();
    _reconnectInFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_reconnectInFlight, future)) _reconnectInFlight = null;
      }),
    );
  }

  Future<void> _connectAndRefresh() async {
    final session = _dependencies.deviceSessionCubit;
    session.connecting();
    try {
      await widget.runtime.connect();
      await _deviceStatus.load();
      if (mounted) {
        _messenger.currentState?.showSnackBar(const SnackBar(content: Text('内置模拟盒子已连接，网络状态已刷新。')));
      }
    } catch (error) {
      if (mounted) {
        await session.connected(const DeviceSessionState());
        _messenger.currentState?.showSnackBar(SnackBar(content: Text('模拟盒子连接失败：$error')));
      }
    }
  }

  void _syncTaskConnection(DeviceSessionState state) {
    final connectionState = switch (state.phase) {
      DeviceSessionPhase.connected => TaskConnectionState.connected,
      DeviceSessionPhase.connecting || DeviceSessionPhase.reconnecting => TaskConnectionState.reconnecting,
      DeviceSessionPhase.disconnected || DeviceSessionPhase.incompatible => TaskConnectionState.disconnected,
    };
    _taskController.setConnectionState(connectionState);
  }

  @override
  Widget build(BuildContext context) => BirdCompanionScope(
    dependencies: _dependencies,
    child: MaterialApp(
      scaffoldMessengerKey: _messenger,
      title: '拍鸟伴侣 K7 设置',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: BlocProvider.value(
        value: _deviceStatus,
        child: BirdDemoShell(
          taskController: _taskController,
          settingsPageBuilder: (context) {
            return Stack(
              children: [
                SettingsShowcasePage(
                  embedded: true,
                  deviceSession: _dependencies.deviceSessionCubit,
                  deviceStatus: _deviceStatus,
                  onReconnect: _reconnectDemo,
                ),
              ],
            );
          },
        ),
      ),
      onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
        settings,
        provisioningRepository: _dependencies.provisioningRepository,
        onProvisioningCompleted: widget.runtime.connect,
      ),
    ),
  );
}

import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_demo_shell.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/b7_simulated_demo_page.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
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
  late final Future<BirdCompanionDependencies> _dependencies = BirdCompanionDependencies.create();
  BirdCompanionDependencies? _createdDependencies;

  @override
  void dispose() {
    _createdDependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BirdCompanionDependencies>(
    future: _dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        _createdDependencies ??= snapshot.data;
        return BirdSettingsApp(dependencies: snapshot.data!);
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
  const BirdSettingsApp({super.key, required this.dependencies});

  final BirdCompanionDependencies dependencies;

  @override
  State<BirdSettingsApp> createState() => _BirdSettingsAppState();
}

class _BirdSettingsAppState extends State<BirdSettingsApp> {
  final TaskExperienceController _taskController = TaskExperienceController(
    const DemoTaskExperienceDataSource(),
  );
  late final DeviceStatusCubit _deviceStatus = DeviceStatusCubit(
    widget.dependencies.deviceRepository,
    widget.dependencies.deviceSessionCubit,
    widget.dependencies.refreshCoordinator,
    widget.dependencies.dataChangeBus,
  )..load();
  late final StreamSubscription<DeviceSessionState> _deviceSessionSubscription;

  @override
  void initState() {
    super.initState();
    _syncTaskConnection(widget.dependencies.deviceSessionCubit.state);
    _deviceSessionSubscription = widget.dependencies.deviceSessionCubit.stream.listen(_syncTaskConnection);
  }

  @override
  void dispose() {
    unawaited(_deviceSessionSubscription.cancel());
    _taskController.dispose();
    unawaited(_deviceStatus.close());
    super.dispose();
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
    dependencies: widget.dependencies,
    child: MaterialApp(
      title: '拍鸟伴侣 K7 设置',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: BlocProvider.value(
        value: _deviceStatus,
        child: BirdDemoShell(
          taskController: _taskController,
          settingsPageBuilder: (context, onOpenTask, onOpenAlbum) {
            final task = _taskController.currentTask;
            return Stack(
              children: [
                SettingsShowcasePage(
                  embedded: true,
                  deviceSession: widget.dependencies.deviceSessionCubit,
                  deviceStatus: _deviceStatus,
                  currentBatchTitle: task.sourceBatch ?? '当前批次',
                  currentBatchSummary: '${task.total} 张照片 · ${task.pendingReviewCount ?? 0} 张待审',
                  currentTaskTitle: task.type.label,
                  currentTaskSummary: '${task.processed} / ${task.total} · ${task.progressPercent}%',
                  onOpenCurrentBatch: onOpenAlbum,
                  onOpenCurrentTask: onOpenTask,
                ),
                Positioned(
                  right: 16,
                  bottom: 96,
                  child: FloatingActionButton.extended(
                    heroTag: 'b7-simulated-demo',
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const B7SimulatedDemoPage(),
                      ),
                    ),
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    label: const Text('蓝牙配网'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      onGenerateRoute: BirdAppRouter.onGenerateRoute,
    ),
  );
}

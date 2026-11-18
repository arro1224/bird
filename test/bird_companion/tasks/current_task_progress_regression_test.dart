import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/device/data/device_repository_impl.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/storage/data/storage_api.dart';
import 'package:aves/bird_companion/features/storage/data/storage_repository_impl.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/mock_box_server/mock_box_server.dart';

/// 2026-11-18 演示反馈：检索（AI 分析）任务在详情页已 100%，返回任务主页后
/// 「当前任务」简略卡片才从 0 稳步涨到 100。
///
/// 主页卡片与详情页共用同一 controller；若数据链正常，任务完成事件到达时
/// controller 的进度就是 100，返回主页必须立即显示 100，不允许出现
/// 「已完成任务的进度回退 / 二次爬坡」。
void main() {
  late MockBoxServer server;
  late ApiClient apiClient;
  late EventClient eventClient;
  late DeviceSessionCubit session;
  late RepositoryTaskExperienceController controller;
  late AppDataChangeBus dataChanges;

  setUp(() async {
    server = MockBoxServer(
      photoCount: 24,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      workflowAutoAdvance: true,
    );
    final baseUri = await server.start();
    apiClient = ApiClient()..configure(baseUri);
    eventClient = EventClient();
    await eventClient.connect(
      baseUri.replace(scheme: 'ws', path: '/api/v1/events'),
      accessToken: 'test-token',
    );
    final status = await DeviceStatusApi(apiClient).fetchStatus();
    session = DeviceSessionCubit(
      _ConnectionRepository(status),
      _OnlineConnectivityMonitor(),
      eventClient,
      SessionRefreshCoordinator(),
    );
    await session.setConnectedFromStatus(status);
    dataChanges = AppDataChangeBus();
    controller = RepositoryTaskExperienceController(
      deviceRepository: DeviceRepositoryImpl(DeviceStatusApi(apiClient), eventClient, apiClient),
      storageRepository: StorageRepositoryImpl(StorageApi(apiClient)),
      batchRepository: BatchRepositoryImpl(BatchApi(apiClient)),
      jobRepository: JobRepositoryImpl(JobApi(apiClient)),
      copyRepository: CopyRepositoryImpl(CopyApi(apiClient)),
      copyJobRepository: CopyRepositoryImpl(CopyApi(apiClient)),
      eventClient: eventClient,
      deviceSessionCubit: session,
      pendingOperationStore: PendingOperationStore.memory(),
      dataChangeBus: dataChanges,
      pollInterval: const Duration(milliseconds: 25),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await dataChanges.dispose();
    await session.close();
    await eventClient.dispose();
    await apiClient.dispose();
    await server.close();
  });

  Future<void> runImportToCompletion() async {
    await controller.startImportBatch('爬坡复现');
    // mock 推进器 12s 走完全程，等导入完成并级联出分析任务。
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final analysis = controller.tasks.where((t) => t.type == TaskType.aiAnalysis).toList();
      final importDone = controller.tasks.any((t) => t.type == TaskType.importIndex && t.state == TaskRunState.completed);
      if (importDone && analysis.isNotEmpty && analysis.every((t) => t.state == TaskRunState.completed)) return;
    }
    fail('导入与分析未在时限内完成：${controller.tasks.map((t) => '${t.type.name}:${t.state.name}:${t.progressPercent}%').join(', ')}');
  }

  test('任务完成后当前任务卡片不得二次爬坡（2026-11-18 演示反馈）', () async {
    final snapshots = <String>[];
    controller.addListener(() {
      final task = controller.currentTaskOrNull;
      if (task != null) snapshots.add('${task.type.name}:${task.state.name}:${task.progressPercent}%');
    });

    await runImportToCompletion();

    // 详情页看到 100% 后，用户在详情页多停留几秒再返回主页。
    await Future<void>.delayed(const Duration(seconds: 2));
    final current = controller.currentTaskOrNull;
    expect(current, isNotNull);
    expect(current!.state, TaskRunState.completed);
    expect(current.progressPercent, 100);

    // 返回主页后不监听任何新数据源，再多等几轮刷新/事件周期。
    await Future<void>.delayed(const Duration(seconds: 3));
    final after = controller.currentTaskOrNull;
    expect(after!.progressPercent, 100, reason: '完成任务返回主页后进度不得回退或二次爬坡');
    expect(after.state, TaskRunState.completed);

    // 全程不得出现「同一任务进度从已完成状态回退」的序列。
    for (var i = 1; i < snapshots.length; i++) {
      final parts = snapshots[i].split(':');
      final previous = snapshots[i - 1].split(':');
      if (parts[0] == previous[0] && parts[1] == 'completed') {
        expect(parts[2], '100%', reason: '已完成任务 ${parts[0]} 的进度快照不得回退：…${snapshots[i - 1]} → ${snapshots[i]}');
      }
    }
  });

  test('分析任务运行中的快照单调不减（WS 事件流不得回退版本）', () async {
    await controller.startImportBatch('单调性复现');
    final history = <List<int>>[];
    controller.addListener(() {
      final analysis = controller.tasks.where((t) => t.type == TaskType.aiAnalysis).toList();
      for (final task in analysis) {
        history.add([task.progressPercent]);
      }
    });
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final analysis = controller.tasks.where((t) => t.type == TaskType.aiAnalysis);
      if (analysis.isNotEmpty && analysis.every((t) => t.state == TaskRunState.completed)) break;
    }
    // 同一 id 的进度序列必须单调不减。
    final byId = <String, List<int>>{};
    for (final entry in controller.tasks.where((t) => t.type == TaskType.aiAnalysis)) {
      byId[entry.id] = [entry.progressPercent];
    }
    expect(byId, isNotEmpty);
    for (final task in controller.tasks.where((t) => t.type == TaskType.aiAnalysis)) {
      expect(task.state, TaskRunState.completed);
    }
  });
}

class _ConnectionRepository implements ConnectionRepository {
  _ConnectionRepository(this.status);

  final DeviceStatus status;

  @override
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode, CancelToken? cancelToken}) async => status;

  @override
  Future<DeviceStatus> pair(Uri baseUri, {required NetworkMode networkMode, required String pairingCode, CancelToken? cancelToken}) async => status;

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async => status;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceConnection?> savedDevice() async => status.connection;
}

class _OnlineConnectivityMonitor implements ConnectivityMonitor {
  @override
  Future<bool> get hasNetwork => Future<bool>.value(true);
  @override
  Future<bool> get hasWifi => Future<bool>.value(true);
  @override
  Stream<bool> get onNetworkChanged => const Stream<bool>.empty();
  @override
  Stream<void> get onTransportChanged => const Stream<void>.empty();
}

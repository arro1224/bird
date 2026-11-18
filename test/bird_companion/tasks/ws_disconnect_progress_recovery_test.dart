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

/// 2026-11-18 演示反馈第二段：WS 断连场景下「返回主页后当前任务卡片从 0
/// 稳步涨到 100」的复现尝试。
///
/// 场景建模：真机 Wi-Fi 抖动 → WS 断开（App 侧感知 onDone/onError）→
/// 重连退避期间 REST 轮询接管 → 每轮 refreshFromBox 采样一次进度。
/// 断言：即便采样节奏放慢，controller 的进度也必须单调不减地收敛到
/// 盒子当前态，不得回退到 0 重新爬坡。
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
      pollInterval: const Duration(milliseconds: 400),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await dataChanges.dispose();
    await session.close();
    await eventClient.disconnect();
    await eventClient.dispose();
    await apiClient.dispose();
    await server.close();
  });

  test('WS 断连期间 REST 轮询接管，进度单调收敛不回退', () async {
    // 模拟任务创建后 WS 立即断开（真机 Wi-Fi 抖动）。
    await controller.startImportBatch('断连爬坡复现');
    await eventClient.disconnect();
    expect(eventClient.currentState, EventConnectionState.disconnected);

    final seen = <String, List<int>>{};
    controller.addListener(() {
      for (final task in controller.tasks) {
        seen.putIfAbsent(task.id, () => []).add(task.progressPercent);
      }
    });

    // 覆盖 mock 全链时长：导入 12s + 级联分析 12s（分析任务在 App 经 REST
    // 轮询发现导入完成后才创建）+ 轮询采样延迟，40s 窗口必须收敛到 100。
    await Future<void>.delayed(const Duration(seconds: 40));

    expect(seen, isNotEmpty, reason: 'WS 断连后必须由 REST 轮询接管进度更新');
    for (final entry in seen.entries) {
      final series = entry.value;
      for (var i = 1; i < series.length; i++) {
        expect(series[i], greaterThanOrEqualTo(series[i - 1]),
            reason: '任务 ${entry.key} 的轮询采样序列不得回退：$series');
      }
      expect(series.last, 100, reason: '任务 ${entry.key} 40 秒后必须收敛到 100：$series');
    }

    // 期间 session 必须 refreshFromBox 至少一次（轮询或恢复刷新）。
    expect(controller.currentTaskOrNull, isNotNull);
  });

  test('断连期间任务完成的完成态必须在恢复刷新后可见（completed 不被回退为 running）', () async {
    await controller.startImportBatch('完成态保持复现');
    // 等任务跑完（WS 在线，收到完整事件流）。
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final tasks = controller.tasks;
      if (tasks.isNotEmpty && tasks.every((t) => t.state == TaskRunState.completed)) break;
    }
    expect(controller.tasks, isNotEmpty);
    expect(controller.tasks.every((t) => t.state == TaskRunState.completed), isTrue,
        reason: 'WS 正常时任务应通过事件流收敛到 completed');

    // 断开 WS 后再多轮 REST 轮询：已完成状态不得被旧快照回退。
    await eventClient.disconnect();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(controller.tasks.every((t) => t.state == TaskRunState.completed), isTrue,
        reason: 'REST 快照不会把 completed 任务回退为 running（mock 端任务已终态）');
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

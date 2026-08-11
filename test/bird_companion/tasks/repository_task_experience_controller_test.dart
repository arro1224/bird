import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
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

void main() {
  late MockBoxServer server;
  late ApiClient apiClient;
  late EventClient eventClient;
  late DeviceSessionCubit session;
  late RepositoryTaskExperienceController controller;
  late JobRepositoryImpl jobs;
  late DeviceStatus status;
  late PendingOperationStore pendingOperations;
  late BatchRepositoryImpl batches;
  late AppDataChangeBus dataChanges;

  setUp(() async {
    server = MockBoxServer(
      photoCount: 24,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final baseUri = await server.start();
    apiClient = ApiClient()..configure(baseUri);
    eventClient = EventClient();
    await eventClient.connect(
      baseUri.replace(scheme: 'ws', path: '/api/v1/events'),
      accessToken: 'test-token',
    );
    status = await DeviceStatusApi(apiClient).fetchStatus();
    session = DeviceSessionCubit(
      _ConnectionRepository(status),
      _OnlineConnectivityMonitor(),
      eventClient,
      SessionRefreshCoordinator(),
    );
    await session.setConnectedFromStatus(status);
    jobs = JobRepositoryImpl(JobApi(apiClient));
    batches = BatchRepositoryImpl(BatchApi(apiClient));
    dataChanges = AppDataChangeBus();
    pendingOperations = PendingOperationStore.memory();
    controller = RepositoryTaskExperienceController(
      deviceRepository: DeviceRepositoryImpl(
        DeviceStatusApi(apiClient),
        eventClient,
        apiClient,
      ),
      storageRepository: StorageRepositoryImpl(StorageApi(apiClient)),
      batchRepository: batches,
      jobRepository: jobs,
      copyRepository: CopyRepositoryImpl(CopyApi(apiClient)),
      eventClient: eventClient,
      deviceSessionCubit: session,
      pendingOperationStore: pendingOperations,
      dataChangeBus: dataChanges,
      pollInterval: const Duration(milliseconds: 25),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await dataChanges.dispose();
    await pendingOperations.dispose();
    await session.close();
    await eventClient.dispose();
    await apiClient.dispose();
    await server.close();
  });

  test('B1 computes home entries from frozen reads and device pending writes', () async {
    expect(controller.homeInputsReady, isTrue);
    expect(
      controller.executableTaskTypes,
      containsAll([
        TaskType.importIndex,
        TaskType.aiAnalysis,
        TaskType.copy,
      ]),
    );
    expect(controller.executableTaskTypes, isNot(contains(TaskType.sync)));

    await pendingOperations.save(
      PendingOperation(
        id: 'other-device-write',
        type: PendingOperationType.updateReview,
        payload: const {'file_id': 'photo-1', 'version': 1},
        createdAt: DateTime.utc(2026, 8, 10),
        deviceId: 'box-other',
        projectId: controller.activeBatchId,
        fileId: 'photo-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.executableTaskTypes, isNot(contains(TaskType.sync)));

    await pendingOperations.save(
      PendingOperation(
        id: 'active-device-write',
        type: PendingOperationType.updateReview,
        payload: const {'file_id': 'photo-2', 'version': 1},
        createdAt: DateTime.utc(2026, 8, 10, 0, 1),
        deviceId: status.connection.id,
        projectId: controller.activeBatchId,
        fileId: 'photo-2',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.executableTaskTypes, contains(TaskType.sync));

    session.disconnected('B1 disconnect');
    await Future<void>.delayed(Duration.zero);
    expect(controller.executableTaskTypes, isEmpty);
  });

  test('creating an import project refreshes a retained album current batch', () async {
    final album = BatchListCubit(batches, null, dataChanges);
    addTearDown(album.close);
    await album.load();
    final previousId = album.state.current?.id;

    final projectId = await controller.startImportBatch('cross-tab-refresh');
    await _waitUntil(() => album.state.current?.id == projectId);

    expect(projectId, isNot(previousId));
    expect(album.state.current?.id, projectId);
    expect(album.state.current?.totalFiles, 0);
  });

  test(
    'scan → project → import → reconnect → analysis keeps box job identity',
    () async {
      expect(controller.sdCard.state, SdCardReadState.detected);
      expect(controller.sdCard.photoCount, 24);

      final projectId = await controller.startImportBatch('B4 实施批次');
      final importId = controller.currentJobId!;
      expect(projectId, startsWith('project-'));
      expect(importId, startsWith('job-import-'));
      expect(projectId, isNot(startsWith('demo-')));
      expect(importId, isNot(startsWith('demo-')));
      expect(controller.taskById(importId).sourceBatch, 'B4 实施批次');
      expect(controller.taskById(importId).sourceBatchId, projectId);

      final beforeDisconnect = controller.taskById(importId);
      session.disconnected('test disconnect');
      await eventClient.disconnect();
      await server.completeJob(importId, emitEvent: false);
      expect(controller.taskById(importId), same(beforeDisconnect));

      await session.setConnectedFromStatus(status);
      await _waitUntil(
        () => controller.jobs.any(
          (job) => job.type == BirdJobType.analysis && job.sourceProjectId == projectId,
        ),
      );
      final recoveredImport = controller.jobs.singleWhere(
        (job) => job.id == importId,
      );
      expect(recoveredImport.id, importId);
      expect(recoveredImport.state, BirdJobState.completed);

      await eventClient.connect(
        status.connection.baseUri.replace(
          scheme: 'ws',
          path: '/api/v1/events',
        ),
        accessToken: 'test-token',
      );
      final analysis = controller.jobs.singleWhere(
        (job) => job.type == BirdJobType.analysis,
      );
      final navigation = controller.analysisCompletedProjects.first;
      await server.completeJob(analysis.id, emitEvent: false);
      await controller.refreshFromBox();
      expect(await navigation.timeout(const Duration(seconds: 2)), projectId);

      final report = await controller.report(analysis.id);
      expect(report.jobId, analysis.id);
      expect(report.totalCount, 24);
      expect(report.successCount, 24);
    },
  );

  test('control uses version and maps 409/422 to task messages', () async {
    await controller.startImportBatch('控制接口批次');
    final job = controller.jobs.singleWhere(
      (candidate) => candidate.type == BirdJobType.import,
    );

    await expectLater(
      jobs.control(job.id, 'pause', version: job.version! + 1),
      throwsA(
        isA<ApiException>().having(
          (error) => UserMessageMapper.fromError(error).title,
          'message title',
          '任务状态已更新',
        ),
      ),
    );

    final paused = await jobs.control(
      job.id,
      'pause',
      version: job.version!,
    );
    expect(paused.state, BirdJobState.paused);
    await expectLater(
      jobs.control(paused.id, 'pause', version: paused.version!),
      throwsA(
        isA<ApiException>().having(
          (error) => UserMessageMapper.fromError(error).title,
          'message title',
          '当前操作不可用',
        ),
      ),
    );
  });

  test('409 refreshes the task snapshot without retrying the write', () async {
    await controller.startImportBatch('conflict-refresh');
    final stale = controller.jobs.singleWhere(
      (candidate) => candidate.type == BirdJobType.import,
    );

    final authoritative = await jobs.control(
      stale.id,
      'pause',
      version: stale.version!,
    );
    expect(authoritative.state, BirdJobState.paused);

    await expectLater(
      controller.controlJob(stale.id, TaskAction.pause),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );

    final refreshed = controller.jobs.singleWhere(
      (candidate) => candidate.id == stale.id,
    );
    expect(refreshed.state, BirdJobState.paused);
    expect(refreshed.version, authoritative.version);
  });

  test('disconnect blocks task controls before a box write is sent', () async {
    await controller.startImportBatch('disconnect-control-guard');
    final job = controller.jobs.singleWhere(
      (candidate) => candidate.type == BirdJobType.import,
    );
    session.disconnected('test disconnect');

    await expectLater(
      controller.controlJob(job.id, TaskAction.pause),
      throwsA(isA<StateError>()),
    );

    final authoritative = await jobs.detail(job.id);
    expect(authoritative.state, BirdJobState.running);
    expect(authoritative.version, job.version);
  });

  test('WS recovery converges missed task events through a full REST snapshot', () async {
    await controller.startImportBatch('b6-event-recovery');
    final importJob = controller.jobs.singleWhere(
      (candidate) => candidate.type == BirdJobType.import,
    );

    // Keep the REST device session healthy while the event channel is down.
    await eventClient.disconnect();
    await server.completeJob(importJob.id, emitEvent: false);
    expect(
      controller.jobs.singleWhere((candidate) => candidate.id == importJob.id).state,
      BirdJobState.running,
    );

    await eventClient.connect(
      status.connection.baseUri.replace(
        scheme: 'ws',
        path: '/api/v1/events',
      ),
      accessToken: 'test-token',
    );

    await _waitUntil(
      () => controller.jobs.any((candidate) => candidate.id == importJob.id && candidate.state == BirdJobState.completed),
    );
    expect(controller.homeInputsReady, isTrue);
  });

  test('concurrent controls submit only the first task write', () async {
    await controller.startImportBatch('duplicate-control-guard');
    final job = controller.jobs.singleWhere(
      (candidate) => candidate.type == BirdJobType.import,
    );

    final first = controller.controlJob(job.id, TaskAction.pause);
    final duplicate = controller.controlJob(job.id, TaskAction.cancel);
    await Future.wait([first, duplicate]);

    final authoritative = await jobs.detail(job.id);
    expect(authoritative.state, BirdJobState.paused);
    expect(authoritative.availableActions, containsAll(['resume', 'cancel']));
  });

  test('concurrent manual AI analysis reuses one real job identity', () async {
    final projectId = await controller.startImportBatch('manual-analysis');

    final firstRequest = controller.startAnalysisForActiveProject();
    final duplicateRequest = controller.startAnalysisForActiveProject();
    final results = await Future.wait(<Future<String>>[
      firstRequest,
      duplicateRequest,
    ]);
    final firstJobId = results.first;
    final secondJobId = await controller.startAnalysisForActiveProject();

    expect(firstJobId, startsWith('job-analysis-'));
    expect(results.last, firstJobId);
    expect(secondJobId, firstJobId);
    expect(firstJobId, isNot(startsWith('demo-')));
    expect(
      controller.jobs.where((job) => job.type == BirdJobType.analysis && job.sourceProjectId == projectId),
      hasLength(1),
    );
  });

  test('clears the active project when the box reports no current project', () async {
    final projectId = await controller.startImportBatch('cleared-project');
    expect(controller.activeBatchId, projectId);

    server.setCurrentProjectAvailable(false);
    await controller.refreshFromBox();

    expect(controller.activeBatchId, isNull);
    await expectLater(
      controller.startAnalysisForActiveProject(),
      throwsA(isA<StateError>()),
    );
  });

  test('copy completion emits the real job id for report navigation', () async {
    final projectId = await controller.startImportBatch('report-navigation');
    final importId = controller.currentJobId!;
    await server.completeJob(importId, emitEvent: false);
    await controller.refreshFromBox();
    await _waitUntil(
      () => controller.jobs.any(
        (job) => job.type == BirdJobType.analysis,
      ),
    );
    final analysis = controller.jobs.singleWhere(
      (job) => job.type == BirdJobType.analysis,
    );
    await server.completeJob(analysis.id, emitEvent: false);
    await controller.refreshFromBox();

    final estimate = await controller.copyRepository.estimate(
      projectId,
      'all',
    );
    final target = estimate.targets.firstWhere((item) => item.online);
    final copy = await controller.copyRepository.create(
      projectId,
      'all',
      target.id,
      xmpEnabled: true,
      verifyAfterCopy: true,
      version: estimate.version,
    );
    await controller.refreshFromBox();

    final navigation = controller.copyCompletedJobs.first;
    await server.completeJob(copy.id, emitEvent: false);
    await controller.refreshFromBox();

    expect(
      await navigation.timeout(const Duration(seconds: 2)),
      copy.id,
    );
  });

  test('polls running jobs while events are unavailable and stops after WS', () async {
    await controller.startImportBatch('轮询恢复批次');
    final jobId = controller.currentJobId!;
    await eventClient.disconnect();
    final before = server.jobListRequestCount;
    await server.completeJob(jobId, emitEvent: false);
    await _waitUntil(
      () => controller.jobs.singleWhere((job) => job.id == jobId).state == BirdJobState.completed,
    );
    expect(server.jobListRequestCount, greaterThan(before));

    await eventClient.connect(
      status.connection.baseUri.replace(
        scheme: 'ws',
        path: '/api/v1/events',
      ),
      accessToken: 'test-token',
    );
    final afterReconnect = server.jobListRequestCount;
    await _waitUntil(
      () => server.jobListRequestCount > afterReconnect,
    );
    final afterRecoverySnapshot = server.jobListRequestCount;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.jobListRequestCount, afterRecoverySnapshot);
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not reached before $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _OnlineConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => true;
}

class _ConnectionRepository implements ConnectionRepository {
  _ConnectionRepository(this.status);

  final DeviceStatus status;

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async => status;

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) async => status;

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

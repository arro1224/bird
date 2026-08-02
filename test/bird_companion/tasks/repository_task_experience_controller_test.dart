import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
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
    status = DeviceStatus(
      connection: DeviceConnection(
        id: 'box-b4',
        name: 'B4 mock box',
        baseUri: baseUri,
        networkMode: NetworkMode.manual,
        apiVersion: 'v1',
        isPaired: true,
      ),
      card: const CardStatus(
        inserted: true,
        readable: true,
        name: 'MOCK-SD',
      ),
    );
    session = DeviceSessionCubit(
      _ConnectionRepository(status),
      _OnlineConnectivityMonitor(),
      eventClient,
      SessionRefreshCoordinator(),
    );
    await session.setConnectedFromStatus(status);
    jobs = JobRepositoryImpl(JobApi(apiClient));
    controller = RepositoryTaskExperienceController(
      storageRepository: StorageRepositoryImpl(StorageApi(apiClient)),
      batchRepository: BatchRepositoryImpl(BatchApi(apiClient)),
      jobRepository: jobs,
      copyRepository: CopyRepositoryImpl(CopyApi(apiClient)),
      eventClient: eventClient,
      deviceSessionCubit: session,
      pollInterval: const Duration(milliseconds: 25),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await session.close();
    await eventClient.dispose();
    await apiClient.dispose();
    await server.close();
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
      jobs.control(job.id, 'pause', version: job.version + 1),
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
      version: job.version,
    );
    expect(paused.state, BirdJobState.paused);
    await expectLater(
      jobs.control(paused.id, 'pause', version: paused.version),
      throwsA(
        isA<ApiException>().having(
          (error) => UserMessageMapper.fromError(error).title,
          'message title',
          '当前操作不可用',
        ),
      ),
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
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.jobListRequestCount, afterReconnect);
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

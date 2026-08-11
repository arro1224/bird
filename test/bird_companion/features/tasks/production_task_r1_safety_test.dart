import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R1 task detail write guards', () {
    testWidgets('disconnect keeps task actions visible but disabled', (
      tester,
    ) async {
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      )..setConnectionState(TaskConnectionState.disconnected);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            controller: controller,
            taskId: 'demo-copy-failed',
          ),
        ),
      );

      expect(find.textContaining('盒子任务可能仍在运行'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '重试失败项'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '跳过失败项'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '导出日志'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('an in-flight task write disables duplicate actions', (
      tester,
    ) async {
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      )..setBusyState(acting: true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailPage(
            controller: controller,
            taskId: 'demo-import-running',
          ),
        ),
      );

      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '暂停任务'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '取消任务'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('R1 legacy job detail guards', () {
    late EventClient events;
    late _FakeJobRepository repository;

    setUp(() {
      events = EventClient();
      repository = _FakeJobRepository(_runningJob());
    });

    tearDown(() async {
      await events.dispose();
    });

    test('connection phase is part of the write eligibility state', () {
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.connected,
        ).canSubmitWrites,
        isTrue,
      );
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.reconnecting,
        ).canSubmitWrites,
        isFalse,
      );
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.disconnected,
        ).canSubmitWrites,
        isFalse,
      );
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.connected,
          controlling: true,
        ).canSubmitWrites,
        isFalse,
      );
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.connected,
          loading: true,
        ).canSubmitWrites,
        isFalse,
      );
      expect(
        const JobDetailState(
          connectionPhase: DeviceSessionPhase.connected,
          authorityReady: false,
        ).canSubmitWrites,
        isFalse,
      );
    });

    test('disconnected job detail rejects control before repository write', () async {
      final sessionEvents = EventClient();
      final session = DeviceSessionCubit(
        _DisconnectedConnectionRepository(),
        _OfflineConnectivityMonitor(),
        sessionEvents,
        SessionRefreshCoordinator(),
      );
      final cubit = JobDetailCubit(
        repository,
        events,
        repository.job.id,
        null,
        null,
        session,
      );
      addTearDown(cubit.close);
      addTearDown(session.close);
      addTearDown(sessionEvents.dispose);

      await cubit.load();
      await cubit.control('pause');

      expect(repository.controlActions, isEmpty);
      expect(cubit.state.error, isA<StateError>());
      expect(cubit.state.connectionPhase, DeviceSessionPhase.disconnected);
    });

    test('job detail rejects actions omitted from available_actions', () async {
      repository.job = _runningJob(availableActions: const []);
      final cubit = JobDetailCubit(repository, events, repository.job.id);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.control('pause');

      expect(repository.controlActions, isEmpty);
      expect(cubit.state.error, isA<StateError>());
    });

    test('job detail submits only the first concurrent control', () async {
      final gate = Completer<BirdJobStatus>();
      repository.controlGate = gate;
      final cubit = JobDetailCubit(repository, events, repository.job.id);
      addTearDown(cubit.close);
      await cubit.load();

      final first = cubit.control('pause');
      final duplicate = cubit.control('cancel');
      await duplicate;

      expect(repository.controlActions, ['pause']);
      expect(cubit.state.controlling, isTrue);

      gate.complete(
        _runningJob(
          state: BirdJobState.paused,
          availableActions: const ['resume', 'cancel'],
          version: 2,
        ),
      );
      await first;

      expect(repository.controlActions, ['pause']);
      expect(cubit.state.job?.state, BirdJobState.paused);
      expect(cubit.state.controlling, isFalse);
    });
  });
}

BirdJobStatus _runningJob({
  BirdJobState state = BirdJobState.running,
  List<String> availableActions = const ['pause', 'cancel'],
  int version = 1,
}) => BirdJobStatus(
  id: 'job-copy-r1',
  type: BirdJobType.copy,
  state: state,
  totalCount: 24,
  finishedCount: 8,
  availableActions: availableActions,
  version: version,
);

class _FakeJobRepository implements JobRepository {
  _FakeJobRepository(this.job);

  BirdJobStatus job;
  final List<String> controlActions = [];
  Completer<BirdJobStatus>? controlGate;

  @override
  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  }) async {
    controlActions.add(action);
    final gate = controlGate;
    if (gate != null) return gate.future;
    return job;
  }

  @override
  Future<BirdJobStatus> detail(String id) async => job;

  @override
  Future<List<JobFailure>> failures(String jobId) async => const [];

  @override
  Future<List<BirdJobStatus>> list() async => [job];

  @override
  Future<JobPage> page({
    String? cursor,
    int pageSize = 50,
    String? state,
    String? type,
  }) async => JobPage(items: [job], hasMore: false);

  @override
  Future<JobFailurePage> failurePage(
    String jobId, {
    String? cursor,
    int pageSize = 50,
  }) async => const JobFailurePage.empty();

  @override
  Future<void> delete(String id) async {}

  @override
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  }) async => null;

  @override
  Future<JobReport> report(String id) => throw UnsupportedError('A running task has no report');

  @override
  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  ) => throw UnsupportedError('not used');

  @override
  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  ) => throw UnsupportedError('not used');
}

class _OfflineConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => false;
}

class _DisconnectedConnectionRepository implements ConnectionRepository {
  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) => throw UnsupportedError('not used');

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) => throw UnsupportedError('not used');

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) => throw UnsupportedError('not used');

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceConnection?> savedDevice() async => null;
}

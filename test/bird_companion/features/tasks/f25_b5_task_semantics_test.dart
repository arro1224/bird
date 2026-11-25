import 'dart:async';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_job_summary_sheet.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in <(String, String)>[
    ('insufficient_space', '目标盘空间不足'),
    ('target_missing', '原目标盘未连接'),
    ('target_changed', '目标盘已变化'),
    ('target_read_only', '目标盘只读'),
    ('role_conflict', '存储角色冲突'),
    ('source_unavailable', '源卡暂不可用'),
    ('future_reason', '存储受阻，等待处理'),
  ]) {
    test('blocked_kind ${entry.$1} has its own explanation', () {
      final session = _follow(kind: entry.$1);
      final stage = resolveSmartFollowStage(session: session);
      expect(stage.label, entry.$2);
      expect(stage.isWaiting, isTrue);
      expect(stage.hint, isNot(contains('请插回原来的目标盘')));
      expect(session.state, SmartFollowState.waitingForTarget);
    });
  }

  test('legacy insufficient-space reason and unknown newer kind use known evidence; explicit newer kind wins', () {
    expect(resolveSmartFollowStage(session: _follow(reason: 'COPY_INSUFFICIENT_SPACE')).label, '目标盘空间不足');
    expect(
      resolveSmartFollowStage(
        session: _follow(kind: 'future_reason', reason: 'COPY_INSUFFICIENT_SPACE'),
      ).label,
      '目标盘空间不足',
    );
    expect(
      resolveSmartFollowStage(
        session: _follow(kind: 'target_read_only', reason: 'COPY_INSUFFICIENT_SPACE'),
      ).label,
      '目标盘只读',
    );
    expect(resolveSmartFollowStage(session: _follow()).label, '存储受阻，等待处理');
  });

  test('byte snapshot preserves large exact counts; missing and malformed values stay unknown', () {
    final session = _follow(kind: 'insufficient_space', details: {'free_bytes': 4294967296, 'required_bytes': 5000000000, 'reserved_bytes': 1073741824});
    expect(session.blockage!.bytes('free_bytes'), 4294967296);
    expect(session.blockage!.bytes('missing_bytes'), isNull);
    expect(session.blockage!.observedAt, DateTime.utc(2026, 11, 25, 1, 2, 3));
    for (final invalid in [-1, 1.2, '1024', true]) {
      expect(_follow(details: {'missing_bytes': invalid}).blockage!.bytes('missing_bytes'), isNull);
    }
  });

  testWidgets('storage snapshot shows only known bytes and retries original session with current version and stable key', (tester) async {
    _large(tester);
    final gateway = _FollowGateway();
    final repository = SmartFollowRepository(gateway);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SmartFollowRunPage(repository: repository, sessionId: 'sf-b5'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('目标盘空间不足'), findsOneWidget);
    expect(find.text('可用空间：1024 字节'), findsOneWidget);
    expect(find.text('预留空间：512 字节'), findsOneWidget);
    expect(find.byKey(const ValueKey('blocked-missing_bytes')), findsNothing);
    expect(find.textContaining('受阻快照时间：2026-11-25'), findsOneWidget);
    expect(find.textContaining('受阻时的快照'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('smart-follow-action-retry')));
    await tester.tap(find.byKey(const Key('smart-follow-action-retry')));
    await tester.pumpAndSettle();
    expect(gateway.actions, [('sf-b5', 'retry', 9, 'sf-b5-retry-9')]);
    expect(repository.snapshot('sf-b5')!.stateVersion, 10);
    expect(repository.snapshot('sf-b5')!.summary!.fileCounts['copied'], 3);
    expect(gateway.startCalls, 0);
  });

  testWidgets('blocked session without allowed retry has no retry button or fabricated space', (tester) async {
    _large(tester);
    final gateway = _FollowGateway()..value = _follow(kind: 'target_changed', details: {}, actions: []);
    final repository = SmartFollowRepository(gateway);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SmartFollowRunPage(repository: repository, sessionId: 'sf-b5'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('目标盘已变化'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-retry')), findsNothing);
    expect(find.byKey(const ValueKey('blocked-free_bytes')), findsNothing);
    await expectLater(repository.act('sf-b5', SmartFollowAction.retry), throwsA(isA<ApiException>()));
    expect(gateway.actions, isEmpty);
  });

  testWidgets('image preparation is read-only even if an older box returns stale control actions', (tester) async {
    _large(tester);
    final job = _job(type: BirdJobType.sync, progress: 1, actions: const ['pause', 'resume', 'cancel', 'retry_failed', 'skip_failed']);
    final task = JobStatusViewAdapter.toTaskSummary(job)!;
    expect(job.canPause || job.canResume || job.canRetry || job.canCancel || job.canSkipFailed, isFalse);
    expect(task.availableActions, {TaskAction.exportLog});
    final controller = TaskExperienceController(const ProductionTaskExperienceDataSource())..replaceRepositoryTasks([task]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: controller, taskId: job.id),
      ),
    );
    expect(find.text('准备浏览图片'), findsOneWidget);
    expect(find.text('正在收尾'), findsNWidgets(2));
    for (final action in ['暂停任务', '继续任务', '取消任务', '重试失败项', '跳过失败项']) {
      expect(find.text(action), findsNothing);
    }
    expect(find.text('生成预览'), findsOneWidget);
    expect(find.textContaining('不支持暂停'), findsOneWidget);
  });

  testWidgets('legacy job card uses the same preparation title and no controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobCard(
            job: _job(type: BirdJobType.sync, actions: ['pause', 'cancel']),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('准备浏览图片'), findsOneWidget);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('取消'), findsNothing);
  });

  test('AI actions remain its own available actions and progress is independent of preparation', () {
    final ai = JobStatusViewAdapter.toTaskSummary(_job(progress: .6, actions: ['cancel']))!;
    final preparation = JobStatusViewAdapter.toTaskSummary(_job(type: BirdJobType.sync, progress: 1))!;
    expect(ai.progressPercent, 60);
    expect(ai.availableActions, {TaskAction.cancel, TaskAction.exportLog});
    expect(preparation.progressPercent, 100);
    expect(preparation.state, TaskRunState.running);
    expect(preparation.photoPreparation, isTrue);
  });

  testWidgets('offline progress keeps exact update time and missing ETA without saying zero minutes', (tester) async {
    _large(tester);
    final task = JobStatusViewAdapter.toTaskSummary(_job(progress: .4))!;
    expect(task.remainingMinutes, isNull);
    final controller = TaskExperienceController(const ProductionTaskExperienceDataSource())
      ..replaceRepositoryTasks([task])
      ..setConnectionState(TaskConnectionState.disconnected);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: controller, taskId: task.id),
      ),
    );
    expect(find.text('剩余时间暂不可用'), findsOneWidget);
    expect(find.textContaining('上次进度快照'), findsOneWidget);
    final local = task.updatedAt!.toLocal();
    expect(find.textContaining('${local.hour.toString().padLeft(2, '0')}:02:03'), findsOneWidget);
    expect(find.text('预计剩余 0 分钟'), findsNothing);
    expect(controller.taskById(task.id).progressPercent, 40);
    expect(task.copyWith(state: TaskRunState.paused).updatedAt, task.updatedAt);
  });

  test('missing update time stays unknown; explicit zero ETA is distinct from absent ETA', () {
    final unknown = JobStatusViewAdapter.toTaskSummary(const BirdJobStatus(id: 'unknown-time', type: BirdJobType.analysis, state: BirdJobState.running))!;
    expect(unknown.freshnessLabel, '盒子未提供更新时间');
    expect(unknown.etaLabel, '剩余时间暂不可用');
    expect(JobStatusViewAdapter.toTaskSummary(const BirdJobStatus(id: 'zero-eta', type: BirdJobType.analysis, state: BirdJobState.running, estimatedRemainingSeconds: 0))!.remainingMinutes, 0);
  });

  testWidgets('completed preparation summary stays separate from offline review writeback', (tester) async {
    final task = JobStatusViewAdapter.toTaskSummary(_job(type: BirdJobType.sync, state: BirdJobState.completed, progress: 1))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TaskSyncJobSummarySheet(task: task)),
      ),
    );
    expect(find.text('图片准备摘要'), findsOneWidget);
    expect(find.textContaining('与离线审阅修改回写分别记录'), findsOneWidget);
    expect(find.text('同步任务摘要'), findsNothing);
  });

  test('old-client action rejection has a clear explanation', () {
    final message = UserMessageMapper.fromError(const ApiException(message: 'action unavailable', code: 'action_not_available', statusCode: 409));
    expect(message.title, '当前任务不支持此操作');
    expect(message.message, contains('图片准备由盒子自动执行'));
  });

  for (final incoming in [
    _job(version: 8, state: BirdJobState.running),
    _job(version: 9, state: BirdJobState.running),
    _job(version: null, state: BirdJobState.running),
  ]) {
    test('late version ${incoming.version} cannot undo terminal version 9', () {
      expect(incoming.canReplace(_job(version: 9, state: BirdJobState.completed, progress: 1)), isFalse);
    });
  }

  test('higher-version retry is accepted, while wrong project and same-version regressing progress are rejected', () {
    expect(_job(version: 10).canReplace(_job(version: 9, state: BirdJobState.failed)), isTrue);
    expect(_job(version: 10, project: 'another-project').canReplace(_job()), isFalse);
    expect(_job(version: 9, progress: .3).canReplace(_job(version: 9, progress: .8)), isFalse);
  });

  test('detail merges newer terminal event before an older in-flight REST response without regression', () async {
    final jobs = _Jobs()..value = _job(version: 1);
    final events = _Events();
    final cubit = JobDetailCubit(jobs, events, 'job-b5');
    addTearDown(() async {
      await cubit.close();
      await events.dispose();
    });
    await cubit.load();
    jobs.pending = Completer<BirdJobStatus>();
    final load = cubit.load();
    events.send(_job(version: 3, state: BirdJobState.completed, progress: 1));
    await Future<void>.delayed(Duration.zero);
    jobs.pending!.complete(_job(version: 2, progress: .5));
    await load;
    expect(cubit.state.job!.state, BirdJobState.completed);
    expect(cubit.state.job!.version, 3);
  });

  test('list REST refresh preserves newer terminal event; failed read retains snapshot and disables writes', () async {
    final jobs = _Jobs()..value = _job(version: 1);
    final events = _Events();
    final cubit = JobCenterCubit(jobs, null, events);
    addTearDown(() async {
      await cubit.close();
      await events.dispose();
    });
    await cubit.load();
    events.send(_job(version: 3, state: BirdJobState.completed, progress: 1));
    await Future<void>.delayed(Duration.zero);
    jobs.value = _job(version: 2, progress: .5);
    await cubit.load();
    expect(cubit.state.jobs.single.state, BirdJobState.completed);
    jobs.fail = true;
    await cubit.load();
    expect(cubit.state.jobs.single.version, 3);
    await cubit.control('job-b5', 'cancel');
    expect(jobs.controls, 0);
  });

  test('both legacy controllers reject all preparation controls before HTTP', () async {
    final jobs = _Jobs()..value = _job(type: BirdJobType.sync, actions: ['pause', 'resume', 'cancel', 'retry_failed', 'skip_failed']);
    final events = _Events();
    final detail = JobDetailCubit(jobs, events, 'job-b5');
    final center = JobCenterCubit(jobs);
    addTearDown(() async {
      await detail.close();
      await center.close();
      await events.dispose();
    });
    await detail.load();
    await center.load();
    for (final action in ['pause', 'resume', 'cancel', 'retry', 'skip_failed']) {
      await detail.control(action);
      await center.control('job-b5', action);
    }
    expect(jobs.controls, 0);
  });

  test('late control ACK cannot undo a newer terminal event', () async {
    final jobs = _Jobs()
      ..value = _job(version: 1, actions: ['pause'])
      ..pendingControl = Completer<BirdJobStatus>();
    final events = _Events();
    final cubit = JobDetailCubit(jobs, events, 'job-b5');
    addTearDown(() async {
      await cubit.close();
      await events.dispose();
    });
    await cubit.load();
    final control = cubit.control('pause');
    events.send(_job(version: 3, state: BirdJobState.completed, progress: 1));
    await Future<void>.delayed(Duration.zero);
    jobs.pendingControl!.complete(_job(version: 2, state: BirdJobState.paused));
    await control;
    expect(cubit.state.job!.state, BirdJobState.completed);
    expect(cubit.state.job!.version, 3);
    expect(cubit.state.controlling, isFalse);
  });
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SmartFollowSession _follow({String? kind, String? reason, Map<String, dynamic>? details, List<String> actions = const ['retry'], int version = 9, String state = 'waiting_for_target'}) => SmartFollowSession.fromJson({
  'session': {'id': 'sf-b5', 'job_id': 'rec-b5', 'state': state, 'state_version': version, 'allowed_actions': actions, 'updated_at': '2026-11-25T01:02:03Z'},
  'summary': {
    'execution_mode': 'continuous_queue',
    'phase': state == 'following' ? 'copying' : 'waiting_for_storage',
    'blocked_kind': kind,
    'blocked_reason': reason,
    'blocked_details': details ?? {'free_bytes': 1024, 'required_bytes': 2048, 'reserved_bytes': 512},
    'file_counts': {'copied': 3, 'blocked': state == 'following' ? 0 : 1},
  },
});

class _FollowGateway extends FakeSmartFollowBackend {
  SmartFollowSession value = _follow(kind: 'insufficient_space');
  final List<(String, String, int, String?)> actions = [];
  @override
  Future<SmartFollowSession> session(String id) async => value;
  @override
  Future<SmartFollowSession?> act(String id, SmartFollowAction action, {required int expectedStateVersion, String? idempotencyKey}) async {
    actions.add((id, action.wire, expectedStateVersion, idempotencyKey));
    return value = _follow(version: expectedStateVersion + 1, state: 'following');
  }
}

BirdJobStatus _job({int? version = 9, BirdJobType type = BirdJobType.analysis, BirdJobState state = BirdJobState.running, double progress = .2, List<String> actions = const [], String project = 'project-b5'}) => BirdJobStatus(
  id: 'job-b5',
  type: type,
  state: state,
  version: version,
  sourceProjectId: project,
  progress: progress,
  finishedCount: (progress * 10).round(),
  totalCount: 10,
  updatedAt: DateTime.utc(2026, 11, 25, 1, 2, 3),
  availableActions: actions,
);

class _Jobs implements JobRepository {
  BirdJobStatus value = _job();
  Completer<BirdJobStatus>? pending;
  Completer<BirdJobStatus>? pendingControl;
  var controls = 0;
  var fail = false;
  @override
  Future<BirdJobStatus> detail(String id) async => pending?.future ?? value;
  @override
  Future<JobPage> page({String? cursor, int pageSize = 50, String? state, String? type}) async {
    if (fail) throw StateError('synthetic unavailable');
    return JobPage(items: [value], hasMore: false);
  }

  @override
  Future<BirdJobStatus> control(String id, String action, {required int version}) async {
    controls++;
    return pendingControl?.future ?? value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('unexpected optional operation');
}

class _Events extends EventClient {
  final _updates = StreamController<DeviceEvent>.broadcast();
  final _states = StreamController<EventConnectionState>.broadcast();
  @override
  Stream<DeviceEvent> get events => _updates.stream;
  @override
  Stream<EventConnectionState> get connectionStates => _states.stream;
  @override
  EventConnectionState get currentState => EventConnectionState.connected;
  void send(BirdJobStatus job) => _updates.add(DeviceEvent(type: 'job_updated', payload: job.toJson(), timestamp: DateTime.now()));
  @override
  Future<void> dispose() async {
    await _updates.close();
    await _states.close();
    await super.dispose();
  }
}

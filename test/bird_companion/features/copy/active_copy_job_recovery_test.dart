import 'dart:async';

import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_recovery.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/active_copy_jobs_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('存储重建保留设备隔离和多活动任务，终态仅作为最近结果', () async {
    final disk = _Disk();
    final store = ActiveCopyJobStore(disk);
    await store.remember('box-a', 'job-1', CopyJobState.running);
    await store.remember('box-a', 'job-2', CopyJobState.paused);
    await store.remember('box-b', 'job-1', CopyJobState.queued);
    store.dispose();
    final restored = ActiveCopyJobStore(disk);
    addTearDown(restored.dispose);
    expect(restored.activeForDevice('box-a').map((job) => job.jobId), unorderedEquals(['job-1', 'job-2']));
    expect(restored.activeForDevice('box-b').single.state, CopyJobState.queued);
    await restored.remember('box-a', 'job-1', CopyJobState.completed);
    expect(restored.activeForDevice('box-a').single.jobId, 'job-2');
    expect(restored.forDevice('box-a').length, 2);
    await restored.remember('box-a', 'job-1', CopyJobState.completed, stateVersion: 4);
    await restored.remember('box-a', 'job-1', CopyJobState.running, stateVersion: 3);
    expect(restored.activeForDevice('box-a').map((job) => job.jobId), isNot(contains('job-1')), reason: '晚到的旧快照不能把终态重新标为活动');
  });

  test('失败的持久化保留内存 ID，后续保存仍可成功；mock 不读写真实记录', () async {
    final disk = _Disk()..fail = true;
    final store = ActiveCopyJobStore(disk);
    addTearDown(store.dispose);
    await expectLater(store.remember('box-a', 'job-1', CopyJobState.running), throwsStateError);
    expect(store.activeForDevice('box-a').single.jobId, 'job-1');
    disk.fail = false;
    await store.remember('box-a', 'job-2', CopyJobState.running);
    final restored = ActiveCopyJobStore(disk);
    final mock = ActiveCopyJobStore.memory();
    addTearDown(restored.dispose);
    addTearDown(mock.dispose);
    expect(restored.activeForDevice('box-a').length, 2);
    expect(mock.forDevice('box-a'), isEmpty);
    await mock.remember('box-a', 'mock-1', CopyJobState.queued);
    expect(ActiveCopyJobStore(disk).forDevice('box-a').any((job) => job.jobId == 'mock-1'), isFalse);
  });

  test('损坏行被忽略，存储容量有边界，恢复写入顺序不倒退', () async {
    final disk = _Disk()
      ..value = {
        'schema_version': 1,
        'jobs': [
          null,
          {'job_id': 3},
        ],
      };
    final store = ActiveCopyJobStore(disk);
    addTearDown(store.dispose);
    expect(store.forDevice('box-a'), isEmpty);
    await Future.wait([
      store.remember('box-a', 'job-1', CopyJobState.queued),
      store.remember('box-a', 'job-1', CopyJobState.completed),
    ]);
    final restored = ActiveCopyJobStore(disk);
    addTearDown(restored.dispose);
    expect(restored.forDevice('box-a').single.state, CopyJobState.completed);
    for (var i = 0; i < 20; i++) {
      await store.remember('box-a', 'job-$i', CopyJobState.running);
    }
    expect(store.forDevice('box-a').length, ActiveCopyJobStore.maximumJobsPerDevice);
  });

  test('会话恢复只 GET 当前设备原 ID，网络失败保留，404 清理', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.close);
    fixture.connected = false;
    await fixture.recovery.recover();
    expect(fixture.repository.reads, isEmpty);
    fixture.connected = true;
    fixture.repository.error = TimeoutException('network');
    await fixture.recovery.recover();
    expect(fixture.store.activeForDevice('box-a').single.jobId, 'job-a');
    expect(fixture.repository.reads, ['job-a']);
    fixture.repository.error = null;
    await fixture.recovery.recover();
    expect(fixture.store.activeForDevice('box-a'), isEmpty);
    expect(fixture.store.forDevice('box-a').single.state, CopyJobState.completed);
    fixture.device = 'box-b';
    fixture.repository.error = const ApiException(message: '', statusCode: 404);
    await fixture.recovery.recover();
    expect(fixture.repository.reads.last, 'job-b');
    expect(fixture.store.forDevice('box-b'), isEmpty);
  });

  test('恢复请求期间切换设备，旧结果不会写回；会话信号可再次恢复', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.close);
    final pending = Completer<CopyJobDetail>();
    fixture.repository.pending = pending;
    final readA = fixture.recovery.recover();
    fixture.device = 'box-b';
    fixture.repository.pending = null;
    fixture.sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    pending.complete(_detail('job-a'));
    await readA;
    expect(fixture.store.activeForDevice('box-a').single.state, CopyJobState.running);
    expect(fixture.store.activeForDevice('box-b'), isEmpty);
    fixture.device = 'box-a';
    fixture.sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.store.activeForDevice('box-a'), isEmpty);
  });

  test('详情页与会话恢复同时读取同一任务，只发一个 GET', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.close);
    final pending = Completer<CopyJobDetail>();
    fixture.repository.pending = pending;
    final cubit = CopyJobDetailCubit(
      fixture.repository,
      copyJobId: 'job-a',
      deviceId: 'box-a',
      canRead: () => fixture.recovery.canRead('box-a'),
      detailReader: (trigger) => fixture.recovery.readJob('box-a', 'job-a', trigger: trigger),
    );
    addTearDown(cubit.close);
    final page = cubit.load();
    final recovery = fixture.recovery.recover();
    expect(fixture.repository.reads, ['job-a']);
    pending.complete(_detail('job-a'));
    await Future.wait([page, recovery]);
    expect(cubit.state.detail?.copyJobId, 'job-a');
    expect(fixture.repository.reads, ['job-a']);
  });

  testWidgets('应用对象重建后任务入口可用，导航带原 deviceId/jobId，不自动跳转', (tester) async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.close);
    fixture.connected = false;
    Object? arguments;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ActiveCopyJobsBanner(recovery: fixture.recovery)),
        onGenerateRoute: (settings) {
          arguments = settings.arguments;
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('原任务详情')));
        },
      ),
    );
    expect(find.text('继续查看复制任务'), findsOneWidget);
    expect(find.textContaining('等待盒子连接'), findsOneWidget);
    expect(arguments, isNull);
    await tester.tap(find.text('继续查看复制任务'));
    await tester.pumpAndSettle();
    expect((arguments as CopyJobDetailArgs).copyJobId, 'job-a');
    expect((arguments as CopyJobDetailArgs).deviceId, 'box-a');
    expect(fixture.repository.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

CopyJobDetail _detail(String id) => CopyJobDetail(copyJobId: id, state: CopyJobState.completed, stateVersion: 2, eventSeq: 0, allowedActions: const []);

class _Disk implements DiagnosticStorage {
  Object? value;
  bool fail = false;
  @override
  T? read<T>(String key) => value as T?;
  @override
  Future<void> write(String key, Object? value) async {
    if (fail) throw StateError('disk');
    this.value = value;
  }

  @override
  Future<void> remove(String key) async => value = null;
}

class _RecoveryRepository implements CopyJobRepository {
  final reads = <String>[];
  Object? error;
  Completer<CopyJobDetail>? pending;
  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    reads.add(copyJobId);
    if (error != null) throw error!;
    return pending == null ? _detail(copyJobId) : await pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecoveryFixture {
  final sessions = StreamController<void>.broadcast(sync: true);
  final refreshes = StreamController<void>.broadcast(sync: true);
  final repository = _RecoveryRepository();
  late final ActiveCopyJobStore store;
  late final CopyJobRecovery recovery;
  String device = 'box-a';
  bool connected = true;

  static Future<_RecoveryFixture> create() async {
    final fixture = _RecoveryFixture();
    final disk = _Disk();
    final beforeRestart = ActiveCopyJobStore(disk);
    await beforeRestart.remember('box-a', 'job-a', CopyJobState.running);
    await beforeRestart.remember('box-b', 'job-b', CopyJobState.running);
    beforeRestart.dispose();
    fixture.store = ActiveCopyJobStore(disk);
    fixture.recovery = CopyJobRecovery(
      repository: fixture.repository,
      store: fixture.store,
      currentDeviceId: () => fixture.device,
      isConnected: () => fixture.connected,
      sessionChanges: fixture.sessions.stream,
      refreshes: fixture.refreshes.stream,
    );
    return fixture;
  }

  Future<void> close() async {
    recovery.dispose();
    await sessions.close();
    await refreshes.close();
    store.dispose();
  }
}

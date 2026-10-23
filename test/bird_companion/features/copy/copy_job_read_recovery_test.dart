import 'dart:async';

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('事件失败不能阻止新进度及 allowed_actions 发布', () async {
    final repository = _ReadRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    await cubit.load();
    repository.detail = _detail(CopyJobState.paused, 2, [CopyAllowedAction.resume]);
    repository.eventsError = TimeoutException('events');

    await cubit.pollTick();

    expect(cubit.state.detail?.state, CopyJobState.paused);
    expect(cubit.state.detail?.stateVersion, 2);
    expect(cubit.state.detail?.allowedActions, [CopyAllowedAction.resume]);
  });

  test('慢轮询期间 tick 和手动刷新合并，不重复请求', () async {
    final repository = _ReadRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    await cubit.load();
    final pending = Completer<CopyJobDetail>();
    repository.pendingDetail = pending;

    final first = cubit.pollTick();
    final second = cubit.pollTick();
    final refresh = cubit.load();
    expect(repository.getCalls, 2);
    pending.complete(_detail(CopyJobState.running, 2));
    await Future.wait([first, second, refresh]);
    expect(cubit.state.detail?.stateVersion, 2);
  });

  test('事件失败不阻断终态报告，报告失败后可以独立补读', () async {
    final repository = _ReadRepository()
      ..detail = _detail(CopyJobState.completed, 3)
      ..eventsError = TimeoutException('events')
      ..reportError = TimeoutException('report');
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);

    await cubit.load();
    expect(repository.reportCalls, 1);
    expect(repository.itemsCalls, 1);
    expect(cubit.state.detail?.state, CopyJobState.completed);

    repository.reportError = null;
    await cubit.pollTick();
    expect(cubit.state.report?.copyJobId, 'job-1');
    expect(repository.getCalls, 1, reason: '终态补读不重拉已确认详情');
    expect(repository.itemsCalls, 1, reason: '成功的失败项清单不重复加载');
  });

  test('动作前在途旧详情不能覆盖操作后 paused 状态', () async {
    final repository = _ReadRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    await cubit.load();
    final oldRead = Completer<CopyJobDetail>();
    repository.pendingDetail = oldRead;
    final poll = cubit.pollTick();
    repository.pendingDetail = null;
    repository.detail = _detail(CopyJobState.paused, 2, [CopyAllowedAction.resume]);

    await cubit.act(CopyAllowedAction.pause);
    oldRead.complete(_detail(CopyJobState.running, 1, [CopyAllowedAction.pause]));
    await poll;

    expect(repository.actionCalls, 1);
    expect(cubit.state.detail?.state, CopyJobState.paused);
    expect(cubit.state.detail?.stateVersion, 2);
  });

  test('事件挂起时后续详情仍能更新，且不并发重拉事件', () async {
    final repository = _ReadRepository();
    final events = Completer<CopyJobEventPage>();
    repository.pendingEvents = events;
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    final first = cubit.load();
    await Future<void>.delayed(Duration.zero);
    repository.detail = _detail(CopyJobState.paused, 2);
    final next = cubit.pollTick();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.detail?.stateVersion, 2);
    expect(repository.getCalls, 2);
    expect(repository.eventsCalls, 1);
    events.complete(const CopyJobEventPage(events: [], hasMore: false));
    await Future.wait([first, next]);
  });

  test('终态附属请求最多自动尝试五次，手动补读不重新 GET 详情', () async {
    final repository = _ReadRepository()
      ..detail = _detail(CopyJobState.completed, 3)
      ..reportError = TimeoutException('report');
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    await cubit.load();
    for (var i = 0; i < 10; i++) {
      await cubit.pollTick();
    }
    expect(repository.reportCalls, 5);
    expect(repository.itemsCalls, 1);
    expect(repository.getCalls, 1);
    expect(cubit.needsTerminalRefresh, isFalse);
    repository.reportError = null;
    await cubit.retrySupplemental();
    expect(repository.reportCalls, 6);
    expect(repository.getCalls, 1);
    expect(cubit.state.reportError, isNull);
    expect(cubit.state.report, isNotNull);
  });

  test('慢报告不阻止失败项单独恢复，也不会并发重拉报告', () async {
    final pendingReport = Completer<CopyReport>();
    final repository = _ReadRepository()
      ..detail = _detail(CopyJobState.completed, 3)
      ..pendingReport = pendingReport
      ..itemsError = TimeoutException('items');
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');
    addTearDown(cubit.close);
    final first = cubit.load();
    await Future<void>.delayed(Duration.zero);
    repository.itemsError = null;
    final second = cubit.pollTick();
    await Future<void>.delayed(Duration.zero);
    expect(repository.itemsCalls, 2);
    expect(repository.reportCalls, 1);
    expect(cubit.state.failedItemsError, isNull);
    pendingReport.complete(const CopyReport(copyJobId: 'job-1'));
    await Future.wait([first, second]);
  });

  test('断开或切换设备时不读原 ID，旧响应无效；原设备恢复后可读', () async {
    final repository = _ReadRepository();
    var available = true;
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1', canRead: () => available);
    addTearDown(cubit.close);
    await cubit.load();
    final pending = Completer<CopyJobDetail>();
    repository.pendingDetail = pending;
    final read = cubit.pollTick();
    available = false;
    cubit.sessionChanged();
    await cubit.pollTick();
    expect(repository.getCalls, 2);
    pending.complete(_detail(CopyJobState.completed, 5));
    await read;
    expect(cubit.state.detail?.state, CopyJobState.running);
    repository.pendingDetail = null;
    repository.detail = _detail(CopyJobState.paused, 2);
    available = true;
    await cubit.load();
    expect(cubit.state.detail?.state, CopyJobState.paused);
  });
}

CopyJobDetail _detail(CopyJobState state, int version, [List<CopyAllowedAction> actions = const []]) => CopyJobDetail(
  copyJobId: 'job-1',
  state: state,
  stateVersion: version,
  eventSeq: 0,
  allowedActions: actions,
);

class _ReadRepository implements CopyJobRepository {
  CopyJobDetail detail = _detail(CopyJobState.running, 1, [CopyAllowedAction.pause]);
  Completer<CopyJobDetail>? pendingDetail;
  Completer<CopyJobEventPage>? pendingEvents;
  Completer<CopyReport>? pendingReport;
  Object? eventsError;
  Object? reportError;
  Object? itemsError;
  int getCalls = 0, reportCalls = 0, itemsCalls = 0, actionCalls = 0, eventsCalls = 0;

  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    getCalls++;
    return pendingDetail == null ? detail : await pendingDetail!.future;
  }

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) async {
    eventsCalls++;
    if (pendingEvents != null) return pendingEvents!.future;
    if (eventsError != null) throw eventsError!;
    return const CopyJobEventPage(events: [], hasMore: false);
  }

  @override
  Future<CopyReport> jobReport(String copyJobId) async {
    reportCalls++;
    if (pendingReport != null) return pendingReport!.future;
    if (reportError != null) throw reportError!;
    return const CopyReport(copyJobId: 'job-1');
  }

  @override
  Future<CopyJobItemPage> jobItems(String copyJobId, {String? cursor, String? state}) async {
    itemsCalls++;
    if (itemsError != null) throw itemsError!;
    return const CopyJobItemPage(items: [], hasMore: false);
  }

  @override
  Future<CopyJobDetail?> jobAction(String copyJobId, String actionWire, {required int expectedStateVersion}) async {
    actionCalls++;
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

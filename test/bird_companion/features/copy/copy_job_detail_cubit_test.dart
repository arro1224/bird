import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// 事件流缺口恢复测试（bug 修复回归：首次缺口必须从 0 重拉，
/// 二次缺口才报错防死循环）。
///
/// _GapRepository 模拟后端事件分页：由测试注入是否返回缺口页。
class _GapRepository implements CopyJobRepository {
  _GapRepository();

  /// 每次增量（afterSeq != null）请求返回的页；null 表示走正常空页。
  List<CopyJobEvent> Function(int? afterSeq)? incrementalOverride;

  /// from-0 全量请求返回的页。
  List<CopyJobEvent> fullEvents = [];

  int incrementalCalls = 0;
  int fullCalls = 0;

  CopyJobDetail get detail => const CopyJobDetail(
    copyJobId: 'job-1',
    state: CopyJobState.running,
    stateVersion: 1,
    eventSeq: 10,
    allowedActions: [],
  );

  @override
  Future<CopyJobDetail> getJob(String copyJobId) async => detail;

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) async {
    if (afterSeq == null) {
      fullCalls++;
      return CopyJobEventPage(events: List.unmodifiable(fullEvents), hasMore: false);
    }
    incrementalCalls++;
    final events = incrementalOverride?.call(afterSeq) ?? const [];
    return CopyJobEventPage(events: List.unmodifiable(events), hasMore: false);
  }

  @override
  Future<CopyReport> jobReport(String copyJobId) async => const CopyReport();

  @override
  Future<CopyJobItemPage> jobItems(String copyJobId, {String? cursor, String? state}) async =>
      const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async =>
      const CopyJobPage(items: [], hasMore: false);

  @override
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) async => null;

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async =>
      const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) async => const SafeRemoveResult(safeToRemove: true);

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );
}

CopyJobEvent _event(int seq) => CopyJobEvent(
  seq: seq,
  type: 'state_changed',
  message: 'event $seq',
  createdAt: DateTime(2026, 10, 9, 10, 0, seq),
);

void main() {
  test('首次缺口：增量页跳号时从 0 重拉一次并补齐事件', () async {
    final repository = _GapRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');

    // 正常加载：全量事件 1..3。
    repository.fullEvents = [_event(1), _event(2), _event(3)];
    await cubit.load();
    expect(cubit.state.lastEventSeq, 3);
    expect(repository.fullCalls, 1);

    // 轮询增量返回 6..7（跳过 4、5）→ 触发缺口重拉。
    repository.incrementalOverride = (_) => [_event(6), _event(7)];
    // 重拉全量时后端已补齐 1..7。
    repository.fullEvents = [
      _event(1),
      _event(2),
      _event(3),
      _event(4),
      _event(5),
      _event(6),
      _event(7),
    ];
    await cubit.pollTick();

    expect(repository.incrementalCalls, 1);
    expect(repository.fullCalls, 2, reason: '缺口必须触发一次从 0 重拉');
    expect(cubit.state.events.map((event) => event.seq), [1, 2, 3, 4, 5, 6, 7]);
    expect(cubit.state.lastEventSeq, 7);
    expect(cubit.state.error, isNull, reason: '首次缺口恢复成功后不应报错');
  });

  test('二次缺口：报错防死循环，不再无限重拉', () async {
    final repository = _GapRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');

    repository.fullEvents = [_event(1), _event(2), _event(3)];
    await cubit.load();

    // 第一次缺口（3 → 6）→ 重拉全量补齐为连续 1..6，恢复成功不报错。
    final incrementalResponses = [
      [_event(6)],
      [_event(9)], // 第二次缺口：恢复后又跳号。
    ];
    var incrementalIndex = 0;
    repository.incrementalOverride = (_) {
      final page = incrementalResponses[
        incrementalIndex < incrementalResponses.length ? incrementalIndex : incrementalResponses.length - 1
      ];
      incrementalIndex++;
      return page;
    };
    repository.fullEvents = [
      _event(1),
      _event(2),
      _event(3),
      _event(4),
      _event(5),
      _event(6),
    ];
    await cubit.pollTick();
    expect(repository.fullCalls, 2);
    expect(cubit.state.error, isNull);
    expect(cubit.state.lastEventSeq, 6);

    // 第二次缺口（6 → 9）→ 已用过恢复机会，报错且不再重拉。
    await cubit.pollTick();
    expect(repository.fullCalls, 2, reason: '二次缺口不得再次触发重拉');
    expect(cubit.state.error, isA<StateError>());
  });

  test('无缺口时增量正常合并，lastEventSeq 推进', () async {
    final repository = _GapRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job-1');

    repository.fullEvents = [_event(1), _event(2), _event(3)];
    await cubit.load();

    repository.incrementalOverride = (afterSeq) => [_event(4)];
    await cubit.pollTick();

    expect(repository.fullCalls, 1, reason: '无缺口不重拉');
    expect(cubit.state.lastEventSeq, 4);
    expect(cubit.state.error, isNull);
  });
}

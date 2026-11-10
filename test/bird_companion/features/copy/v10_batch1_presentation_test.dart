import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_job_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CopyJobDetail task({CopyJobState state = CopyJobState.completed, Map<String, dynamic> stats = const {}, DateTime? start, DateTime? finish}) => CopyJobDetail(
  copyJobId: 'job',
  state: state,
  stateVersion: 1,
  eventSeq: 3,
  allowedActions: const [],
  stats: CopyJobStats.fromJson(stats),
  startedAt: start,
  finishedAt: finish,
);

void main() {
  test('terminal average uses copied bytes and elapsed time, including waits', () {
    final timing = CopyTaskTiming.forTask(task(stats: {'copied_bytes': 20480}), const CopyReport(copyJobId: 'job', elapsedSeconds: 10, totalBytes: 999999));
    expect(timing.bytesPerSecond, 2048);
    expect(timing.speedTitle, '平均速度（含暂停/等待）');
    expect(timing.averageCalculated, isTrue);
    expect(timing.source, contains('终态报告'));
  });
  test('reliable terminal start/finish may supply wall-clock elapsed', () {
    final start = DateTime.utc(2026, 11, 10, 1);
    final timing = CopyTaskTiming.forTask(task(stats: {'copied_bytes': 1000}, start: start, finish: start.add(const Duration(milliseconds: 2500))), null);
    expect(timing.elapsedSeconds, 2.5);
    expect(timing.bytesPerSecond, 400);
    expect(timing.elapsedTitle, '耗时（起止时间计算）');
  });
  test('invalid elapsed and unknown copied bytes never produce a fake rate', () {
    final start = DateTime.utc(2026, 11, 10);
    for (final end in [start, start.subtract(const Duration(seconds: 1))]) {
      expect(CopyTaskTiming.forTask(task(stats: {'copied_bytes': 1000}, start: start, finish: end), null).bytesPerSecond, isNull);
    }
    for (final stats in [
      <String, dynamic>{},
      {'copied_bytes': -1},
      {'copied_bytes': 2.5},
    ]) {
      final timing = CopyTaskTiming.forTask(task(stats: stats), const CopyReport(elapsedSeconds: 10, totalBytes: 10000));
      expect(timing.bytesPerSecond, isNull);
    }
  });
  test('zero server metrics are valid and take precedence; foreign reports ignored', () {
    final current = task(stats: {'elapsed_seconds': 10, 'bytes_per_second': 4096, 'copied_bytes': 9999});
    final zero = CopyTaskTiming.forTask(current, const CopyReport(copyJobId: 'job', elapsedSeconds: 0, bytesPerSecond: 0));
    expect(zero.elapsedSeconds, 0);
    expect(zero.bytesPerSecond, 0);
    expect(zero.averageCalculated, isFalse);
    expect(CopyTaskTiming.forTask(current, const CopyReport(copyJobId: 'other', elapsedSeconds: 999)).elapsedSeconds, 10);
  });
  test('running and paused snapshots do not calculate or consume terminal report rates', () {
    for (final state in [CopyJobState.running, CopyJobState.paused]) {
      final timing = CopyTaskTiming.forTask(task(state: state, stats: {'copied_bytes': 20480, 'elapsed_seconds': 10}), const CopyReport(bytesPerSecond: 1234));
      expect(timing.bytesPerSecond, isNull);
      expect(timing.averageCalculated, isFalse);
    }
  });
  test('structured persisted events retain payload and restore observed stages', () {
    final event = CopyJobEvent.fromJson({
      'seq': 2,
      'type': 'state_changed',
      'payload': {'state': 'running'},
      'created_at': '2026-11-10T01:02:03Z',
    });
    final timeline = CopyTimeline.compute(state: CopyJobState.completedWithErrors, events: [event]);
    final copying = timeline.stages[CopyTimelineStageId.copyingFiles.index];
    expect(event.payload['state'], 'running');
    expect(copying.status, CopyStageStatus.observed);
    expect(copying.recordedAt, DateTime.utc(2026, 11, 10, 1, 2, 3));
    expect(timeline.stages[CopyTimelineStageId.verifyingFiles.index].status, CopyStageStatus.unknown);
    expect(timeline.stages[CopyTimelineStageId.done.index].status, CopyStageStatus.partial);
  });
  test('legacy state messages add facts without certifying stage completion', () {
    final timeline = CopyTimeline.compute(
      state: CopyJobState.completed,
      events: const [
        CopyJobEvent(seq: 2, type: 'state_changed', message: '开始复制文件'),
        CopyJobEvent(seq: 1, type: 'state_changed', message: '正在获取目标盘'),
        CopyJobEvent(seq: 3, type: 'item_completed', message: '文件已复制并通过校验'),
      ],
    );
    expect(timeline.stages[CopyTimelineStageId.acquiringTarget.index].status, CopyStageStatus.observed);
    expect(timeline.stages[CopyTimelineStageId.copyingFiles.index].status, CopyStageStatus.observed);
    expect(timeline.stages[CopyTimelineStageId.verifyingFiles.index].status, CopyStageStatus.unknown);
    expect(timeline.stages[CopyTimelineStageId.safeSync.index].status, CopyStageStatus.unknown);
  });
  test('incomplete history and malformed events do not manufacture missing phases', () {
    final timeline = CopyTimeline.compute(
      state: CopyJobState.failed,
      events: const [
        CopyJobEvent(seq: null, type: 'state_changed', payload: {'state': 'running'}),
        CopyJobEvent(seq: 0, type: 'state_changed', message: '开始复制文件'),
        CopyJobEvent(seq: 1, type: 'item_completed', payload: {'state': 'running'}),
        CopyJobEvent(seq: 2, type: 'state_changed', payload: {'state': 'future_state'}, message: '开始复制文件'),
      ],
    );
    expect(timeline.stages[CopyTimelineStageId.copyingFiles.index].status, CopyStageStatus.unknown);
    expect(timeline.stages[CopyTimelineStageId.done.index].status, CopyStageStatus.failed);
    expect(CopyJobEvent.fromJson({'seq': 1, 'payload': 'broken'}).payload, isEmpty);
  });
  test('current wait/pause state wins over history and earliest sequence supplies record time', () {
    final first = DateTime.utc(2026, 11, 10, 1);
    final events = [
      CopyJobEvent(seq: 5, type: 'state_changed', payload: const {'state': 'running'}, createdAt: first.add(const Duration(minutes: 5))),
      CopyJobEvent(seq: 2, type: 'state_changed', payload: const {'state': 'running'}, createdAt: first),
    ];
    final waiting = CopyTimeline.compute(state: CopyJobState.waitingForTarget, events: events);
    expect(waiting.stages[CopyTimelineStageId.acquiringTarget.index].status, CopyStageStatus.active);
    final paused = CopyTimeline.compute(state: CopyJobState.paused, events: events).stages[CopyTimelineStageId.copyingFiles.index];
    expect(paused.status, CopyStageStatus.observed);
    expect(paused.note, contains('任务已暂停'));
    expect(paused.recordedAt, first);
  });
  testWidgets('recorded phases show evidence and local time instead of a success mark', (tester) async {
    final time = DateTime(2026, 11, 10, 12, 34, 56);
    final timeline = CopyTimeline.compute(
      state: CopyJobState.completed,
      events: [CopyJobEvent(seq: 1, type: 'state_changed', message: '开始复制文件', createdAt: time)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CopyJobTimeline(timeline: timeline)),
        ),
      ),
    );
    expect(find.text('已有记录'), findsOneWidget);
    expect(find.textContaining('记录时间：2026-11-10 12:34:56'), findsOneWidget);
    expect(find.textContaining('未提供独立结束状态'), findsOneWidget);
  });
}

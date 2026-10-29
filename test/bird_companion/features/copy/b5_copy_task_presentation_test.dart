import 'dart:async';

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_list_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobStats stats({int copied = 4, int skipped = 1, int failed = 0, int notApplicable = 0, double? percent, num? elapsed = 12, num? speed = 2048}) => CopyJobStats(
  totalFiles: 5,
  copiedFiles: copied,
  skippedFiles: skipped,
  failedFiles: failed,
  notApplicableFiles: notApplicable,
  totalBytes: 5000,
  copiedBytes: copied * 1000,
  progressPercent: percent,
  elapsedSeconds: elapsed,
  bytesPerSecond: speed,
);
CopyJobDetail detail({CopyJobState state = CopyJobState.running, CopyJobStats? progress, CopyJobDeviceSnapshot? source, CopyJobDeviceSnapshot? target, bool? export}) =>
    CopyJobDetail(copyJobId: 'job', state: state, stateVersion: 1, eventSeq: 0, allowedActions: state.isTerminal ? [] : [CopyAllowedAction.pause], stats: progress, sourceDevice: source, targetDevice: target, reviewExportEnabled: export);

class TaskRepository implements CopyJobRepository {
  CopyJobDetail current = detail(progress: stats());
  CopyReport report = const CopyReport(copyJobId: 'job');
  int actions = 0, detailCalls = 0;
  @override
  Future<CopyJobDetail> getJob(String id) async {
    detailCalls++;
    return current;
  }

  @override
  Future<CopyJobDetail?> jobAction(String id, String action, {required int expectedStateVersion}) async {
    actions++;
    return current;
  }

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);
  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);
  @override
  Future<CopyReport> jobReport(String id) async => report;
  @override
  Future<CopyJobPage> listJobs({String? cursor}) async => CopyJobPage(
    items: [CopyJobListItem(copyJobId: 'job', state: current.state, stats: current.stats)],
    hasMore: false,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CopyStageStatus stage(CopyTimeline timeline, CopyTimelineStageId id) => timeline.stages[id.index].status;

void main() {
  test('frozen alias/name precedes current online name; unplugged snapshots remain readable', () {
    const frozen = CopyJobDeviceSnapshot(mediaId: 'disk', userAlias: '拍摄时备份盘', displayName: '旧名称');
    expect(copyTaskDeviceName(source: false, snapshot: frozen, devices: [b3Device('disk')]), '拍摄时备份盘');
    expect(copyTaskDeviceName(source: false, snapshot: frozen), '拍摄时备份盘');
    expect(copyTaskDeviceName(source: true, snapshot: const CopyJobDeviceSnapshot(displayName: '相机卡')), '相机卡');
  });
  test('same-ID online device supplements missing snapshot name; wrong ID/offline cannot', () {
    const snapshot = CopyJobDeviceSnapshot(mediaId: 'disk');
    final online = b3Device('disk', name: '在线备份盘');
    expect(copyTaskDeviceName(source: false, snapshot: snapshot, devices: [online]), '在线备份盘');
    expect(copyTaskDeviceName(source: false, snapshot: snapshot, devices: [b3Device('other')]), '目标存储设备（名称暂不可用）');
    expect(copyTaskDeviceName(source: false, snapshot: snapshot, devices: [b3Device('disk', online: false)]), contains('名称暂不可用'));
  });
  test('missing ID, raw media ID, UUID and paths never become fallback names', () {
    for (final value in ['media_secret', '/dev/sda', '/mnt/usb', '550e8400-e29b-41d4-a716-446655440000']) {
      expect(CopyJobDeviceSnapshot(mediaId: value, displayName: value).presentationLabel, isNull);
      expect(copyTaskDeviceName(source: true, snapshot: CopyJobDeviceSnapshot(mediaId: value)), '源存储设备（名称暂不可用）');
    }
    expect(copyTaskDeviceName(source: true, devices: [b3Device('disk')]), contains('名称暂不可用'));
  });
  test('report frozen name fills missing detail but not a different media ID', () {
    const report = CopyJobDeviceSnapshot(mediaId: 'disk', displayName: '报告冻结名');
    expect(
      copyTaskDeviceName(
        source: false,
        snapshot: const CopyJobDeviceSnapshot(mediaId: 'disk'),
        reportSnapshot: report,
      ),
      '报告冻结名',
    );
    expect(
      copyTaskDeviceName(
        source: false,
        snapshot: const CopyJobDeviceSnapshot(mediaId: 'other'),
        reportSnapshot: report,
      ),
      contains('名称暂不可用'),
    );
  });
  test('root media IDs and actual optional review configuration parse without defaults', () {
    final json = <String, dynamic>{'copy_job_id': 'job', 'state': 'completed', 'source_media_id': 'source', 'target_media_id': 'target'};
    final parsed = CopyJobDetail.fromJson(json);
    expect(parsed.sourceDevice!.mediaId, 'source');
    expect(parsed.targetDevice!.mediaId, 'target');
    expect(parsed.reviewExportEnabled, isNull);
    expect(
      CopyJobDetail.fromJson({
        ...json,
        'review_export': {'enabled': false},
      }).reviewExportEnabled,
      false,
    );
    expect(
      CopyJobDetail.fromJson({
        ...json,
        'review_export': {'enabled': 'false'},
      }).reviewExportEnabled,
      isNull,
    );
  });

  for (final state in [CopyJobState.completed, CopyJobState.completedWithErrors, CopyJobState.cancelled, CopyJobState.failed, CopyJobState.paused, CopyJobState.unknown]) {
    test('${state.wire} never certifies verifying or safe sync without evidence', () {
      final timeline = CopyTimeline.compute(state: state, stats: stats(copied: 5, skipped: 0));
      expect(stage(timeline, CopyTimelineStageId.verifyingFiles), CopyStageStatus.unknown);
      expect(stage(timeline, CopyTimelineStageId.safeSync), CopyStageStatus.unknown);
      expect(stage(timeline, CopyTimelineStageId.writingReview), CopyStageStatus.unknown);
    });
  }
  test('running copied==total does not infer verifying', () {
    final timeline = CopyTimeline.compute(state: CopyJobState.running, stats: stats(copied: 5, skipped: 0));
    expect(stage(timeline, CopyTimelineStageId.copyingFiles), CopyStageStatus.active);
    expect(stage(timeline, CopyTimelineStageId.verifyingFiles), CopyStageStatus.unknown);
  });
  test('queued stage is pending, unknown stays unknown; only whole task completion turns green', () {
    expect(stage(CopyTimeline.compute(state: CopyJobState.queued), CopyTimelineStageId.copyingFiles), CopyStageStatus.pending);
    final terminal = CopyTimeline.compute(state: CopyJobState.completed);
    expect(terminal.stages.where((s) => s.status == CopyStageStatus.done).map((s) => s.id), [CopyTimelineStageId.done]);
  });
  test('explicit disabled export is not applicable, missing config remains unknown', () {
    expect(stage(CopyTimeline.compute(state: CopyJobState.completed, reviewExportEnabled: false), CopyTimelineStageId.writingReview), CopyStageStatus.skipped);
    expect(stage(CopyTimeline.compute(state: CopyJobState.completed), CopyTimelineStageId.writingReview), CopyStageStatus.unknown);
  });
  test('CSV success/not_requested does not certify the whole XMP/embedded stage', () {
    for (final csv in ['success', 'not_requested']) {
      final timeline = CopyTimeline.compute(
        state: CopyJobState.completed,
        reviewExportEnabled: true,
        report: CopyReport(csvStatus: csv, xmpCount: 5),
      );
      expect(stage(timeline, CopyTimelineStageId.writingReview), CopyStageStatus.unknown);
    }
  });
  for (final report in [const CopyReport(csvStatus: 'failed'), const CopyReport(csvStatus: 'success', exportFailedCount: 1), const CopyReport(embedDegradedCount: 1)]) {
    test('review failure/degradation remains visible despite completed', () {
      final timeline = CopyTimeline.compute(state: CopyJobState.completed, reviewExportEnabled: true, report: report);
      expect(stage(timeline, CopyTimelineStageId.writingReview), report.embedDegradedCount == 1 ? CopyStageStatus.partial : CopyStageStatus.failed);
      expect(stage(timeline, CopyTimelineStageId.done), CopyStageStatus.partial);
    });
  }

  test('four outcomes counted consistently; no copied-only 80% fallback', () {
    final data = CopyTaskProgress.fromStats(stats(), CopyJobState.completed);
    expect(data.processed, 5);
    expect(data.percent, isNull);
    expect(data.summary(CopyJobState.completed), '处理完成 5 项（复制 4，跳过 1，失败 0，不适用 0）');
    final mixed = CopyTaskProgress.fromStats(stats(copied: 2, failed: 1, skipped: 1, notApplicable: 1), CopyJobState.running);
    expect(mixed.processed, 5);
    expect(mixed.summary(CopyJobState.running), startsWith('已处理'));
    expect(mixed.copiedBytes, 2000);
  });
  test('missing/invalid counters do not silently become zero or a false denominator', () {
    final missing = CopyTaskProgress.fromStats(CopyJobStats.fromJson({'total_files': 5, 'copied_files': 2}), CopyJobState.running);
    expect(missing.skipped, isNull);
    expect(missing.processed, isNull);
    expect(missing.copiedBytes, isNull);
    expect(missing.percent, isNull);
    final invalid = CopyTaskProgress.fromStats(CopyJobStats.fromJson({'total_files': -1, 'copied_files': 2.5}), CopyJobState.running);
    expect(invalid.total, isNull);
    expect(invalid.copied, isNull);
  });
  test('server progress takes precedence; zero placeholders, NaN, >100 and stale terminal fraction hidden', () {
    expect(CopyTaskProgress.fromStats(stats(percent: .4), CopyJobState.running).percent, .4);
    for (final value in [0, -1, 101, double.nan, double.infinity]) {
      expect(CopyJobStats.fromJson({'progress_percent': value}).effectiveProgressPercent, isNull);
    }
    expect(CopyJobStats.fromJson({'progress_percent': 45}).effectiveProgressPercent, .45);
    expect(CopyTaskProgress.fromStats(stats(percent: .8), CopyJobState.completed).percent, isNull);
    expect(CopyTaskProgress.fromStats(stats(percent: 1), CopyJobState.completed).percent, 1);
  });
  test('report and detail share outcome accounting, including all skips/not applicable', () {
    const report = CopyReport(actualFileCount: 5, copiedFiles: 0, failedFiles: 0, skippedFiles: 4, notApplicableFiles: 1);
    final data = CopyTaskProgress.fromStats(stats(copied: 0, skipped: 4, notApplicable: 1), CopyJobState.completed);
    expect(CopyTaskProgress.fromReport(report).summary(CopyJobState.completed), data.summary(CopyJobState.completed));
  });

  test('timing parses numeric precision without deriving speed; invalid values unavailable, zero retained', () {
    final parsed = CopyJobStats.fromJson({'elapsed_seconds': 47.74, 'bytes_per_second': 1024.5});
    expect(parsed.elapsedSeconds, 47.74);
    expect(parsed.bytesPerSecond, 1024.5);
    final report = CopyReport.fromJson({'elapsed_seconds': 47.74, 'bytes_per_second': 1024.5});
    expect(CopyTaskTiming.fromReport(report).elapsedLabel, '47.74 秒');
    for (final bad in [-1, double.nan, double.infinity, 'invalid']) {
      expect(CopyReport.fromJson({'elapsed_seconds': bad, 'bytes_per_second': bad}).elapsedSeconds, isNull);
      expect(CopyJobStats.fromJson({'bytes_per_second': bad}).bytesPerSecond, isNull);
    }
    expect(CopyTaskTiming.fromReport(const CopyReport(elapsedSeconds: 0, bytesPerSecond: 0)).elapsedLabel, '0 秒');
    expect(CopyTaskTiming.fromReport(const CopyReport(elapsedSeconds: 0, bytesPerSecond: 0)).speedLabel, '0 B/s');
  });
  test('terminal timing is atomic by source: missing report metric does not borrow runtime value', () {
    final task = detail(state: CopyJobState.completed, progress: stats(elapsed: 12, speed: 4096));
    final timing = CopyTaskTiming.forTask(task, const CopyReport(elapsedSeconds: 47.74));
    expect(timing.elapsedLabel, '47.74 秒');
    expect(timing.speedLabel, '暂不可用');
    expect(timing.source, '终态报告');
    expect(CopyTaskTiming.forTask(task, null).source, '任务详情');
  });
  test('paused/resumed timing uses only each received box sample', () {
    final paused = CopyTaskTiming.forTask(detail(state: CopyJobState.paused, progress: stats(elapsed: 10, speed: null)), null);
    final resumed = CopyTaskTiming.forTask(detail(progress: stats(elapsed: 11, speed: 2048)), null);
    expect(paused.elapsedLabel, '10 秒');
    expect(paused.speedLabel, '暂不可用');
    expect(resumed.elapsedLabel, '11 秒');
    expect(resumed.speedLabel, '2.0 KB/s');
  });

  test('slow names do not delay detail/events/actions; cancellation releases pending read', () async {
    final repository = TaskRepository();
    final names = Completer<CopyDeviceList>();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job', deviceReader: () => names.future);
    await cubit.load();
    expect(cubit.state.detail, isNotNull);
    await cubit.act(CopyAllowedAction.pause);
    expect(repository.actions, 1);
    await cubit.close();
    names.complete(CopyDeviceList(devices: [b3Device('disk')]));
  });
  test('names failure never becomes a detail failure; frozen historical name survives next sparse response', () async {
    final repository = TaskRepository()
      ..current = detail(
        source: const CopyJobDeviceSnapshot(mediaId: 'source', displayName: '创建时名称'),
      );
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job', deviceReader: () async => throw StateError('storage offline'));
    await cubit.load();
    repository.current = detail(source: const CopyJobDeviceSnapshot(mediaId: 'source'));
    await cubit.load();
    expect(cubit.state.error, isNull);
    expect(cubit.state.sourceNameSnapshot!.presentationLabel, '创建时名称');
    expect(cubit.state.devices, isEmpty);
    await cubit.close();
  });
  test('old name response cannot leak across session generation and in-flight requests coalesce', () async {
    var readable = true, calls = 0;
    final old = Completer<CopyDeviceList>(), fresh = Completer<CopyDeviceList>();
    final cubit = CopyJobDetailCubit(TaskRepository(), copyJobId: 'job', canRead: () => readable, deviceReader: () => ++calls == 1 ? old.future : fresh.future);
    await cubit.load();
    final same = cubit.refreshDeviceNames();
    expect(calls, 1);
    readable = false;
    cubit.sessionChanged();
    readable = true;
    final latest = cubit.refreshDeviceNames();
    fresh.complete(CopyDeviceList(devices: [b3Device('new')]));
    await latest;
    old.complete(CopyDeviceList(devices: [b3Device('old')]));
    await same;
    expect(cubit.state.devices.single.mediaId, 'new');
    await cubit.close();
  });
  test('wrong task report never overrides timing or historical names', () async {
    final repository = TaskRepository()
      ..current = detail(state: CopyJobState.completed)
      ..report = const CopyReport(copyJobId: 'other', elapsedSeconds: 999);
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job');
    await cubit.load();
    expect(cubit.state.report, isNull);
    expect(cubit.state.reportError, isNotNull);
    await cubit.close();
  });

  testWidgets('detail shows frozen name and runtime box timing without inferred percentage', (tester) async {
    final repository = TaskRepository()
      ..current = detail(
        progress: stats(elapsed: 47.74, speed: 2048),
        source: const CopyJobDeviceSnapshot(mediaId: 'media_secret', displayName: '现场相机卡'),
        target: const CopyJobDeviceSnapshot(mediaId: 'unknown_target'),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => throw StateError('offline')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('耗时（盒子统计）：47.74 秒'), findsOneWidget);
    expect(find.text('速度（盒子统计）：2.0 KB/s'), findsOneWidget);
    expect(find.byKey(const Key('copy-job-progress-bar')), findsNothing);
    await tester.scrollUntilVisible(find.text('现场相机卡'), 300);
    expect(find.text('现场相机卡'), findsOneWidget);
    expect(find.text('目标存储设备（名称暂不可用）'), findsOneWidget);
    expect(find.text('media_secret'), findsNothing);
    expect(find.text('unknown_target'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('terminal report and header retain export failure, missing report speed and report outcomes', (tester) async {
    final repository = TaskRepository()
      ..current = detail(state: CopyJobState.completed, progress: stats(copied: 1, skipped: 0, elapsed: 10, speed: 4096), export: true)
      ..report = const CopyReport(copyJobId: 'job', copiedFiles: 4, failedFiles: 0, skippedFiles: 1, notApplicableFiles: 0, actualFileCount: 5, elapsedSeconds: 47.74, csvStatus: 'failed');
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(copyJobId: 'job', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('部分完成'), findsWidgets);
    expect(find.text('耗时（盒子统计）：47.74 秒'), findsOneWidget);
    expect(find.text('速度（盒子统计）：暂不可用'), findsOneWidget);
    expect(find.text('处理完成 5 项（复制 4，跳过 1，失败 0，不适用 0）'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('copy-report-outcomes')), 400);
    expect(find.text('部分完成（有失败或降级）'), findsOneWidget);
    expect(find.text('复制完成'), findsNothing);
    expect(find.text('处理完成 5 项（复制 4，跳过 1，失败 0，不适用 0）'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('running list says processed and includes not applicable; never says processing complete', (tester) async {
    final repository = TaskRepository()..current = detail(progress: stats(copied: 1, skipped: 1, failed: 1, notApplicable: 1));
    await tester.pumpWidget(MaterialApp(home: CopyJobListPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('已处理 4 项（复制 1，跳过 1，失败 1，不适用 1）'), findsOneWidget);
    expect(find.textContaining('处理完成'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

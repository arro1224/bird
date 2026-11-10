import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CopyJobStats stats({int copied = 4, int failed = 0, int skipped = 1, int notApplicable = 0, int total = 5, double? percent, num? elapsed = 47.74, num? speed = 2048}) => CopyJobStats(
  totalFiles: total,
  copiedFiles: copied,
  failedFiles: failed,
  skippedFiles: skipped,
  notApplicableFiles: notApplicable,
  totalBytes: 5000,
  copiedBytes: 4000,
  progressPercent: percent,
  elapsedSeconds: elapsed,
  bytesPerSecond: speed,
);

class _Repository implements CopyJobRepository {
  _Repository(this.current, this.report);

  final CopyJobDetail current;
  final CopyReport report;

  @override
  Future<CopyJobDetail> getJob(String id) async => current;

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => report;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CopyJobDetail completed({CopyJobStats? progress}) => CopyJobDetail(copyJobId: 'job', state: CopyJobState.completed, stateVersion: 1, eventSeq: 0, allowedActions: const [], stats: progress ?? stats());

void main() {
  test('v10-11 终态处理数达到文件总数时显示 100%，计数全部来自后端', () {
    expect(CopyTaskProgress.fromStats(stats(percent: .8), CopyJobState.completed).percent, 1);
    expect(CopyTaskProgress.fromStats(stats(copied: 2, failed: 1, skipped: 1, notApplicable: 1), CopyJobState.completedWithErrors).percent, 1);
    // 没有总数（无法证明达到）时不造 100%。
    expect(CopyTaskProgress.fromStats(stats(total: 0), CopyJobState.completed).percent, isNull);
    expect(CopyTaskProgress.fromReport(const CopyReport(actualFileCount: 5, copiedFiles: 4, failedFiles: 1, skippedFiles: 0, notApplicableFiles: 0)).percent, 1);
    expect(CopyTaskProgress.fromReport(const CopyReport(copiedFiles: 4)).percent, isNull);
  });

  testWidgets('v10-11 完成详情：100% 进度、耗时/速度与统计来源', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(
      completed(),
      const CopyReport(copyJobId: 'job', actualFileCount: 5, copiedFiles: 4, failedFiles: 0, skippedFiles: 1, notApplicableFiles: 0, elapsedSeconds: 47.74, bytesPerSecond: 2048),
    );
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('copy-job-progress-bar')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('耗时（盒子统计）：47.74 秒'), findsOneWidget);
    expect(find.text('速度（盒子统计）：2.0 KB/s'), findsOneWidget);
    expect(find.text('统计来源：终态报告'), findsOneWidget);
    expect(find.text('处理完成 5 项（复制 4，跳过 1，失败 0，不适用 0）'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-11 缺失的耗时/速度显示暂不可用，不本地估算', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(completed(), const CopyReport(copyJobId: 'job', actualFileCount: 5, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0));
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();
    expect(find.text('耗时（盒子统计）：暂不可用'), findsOneWidget);
    expect(find.text('速度（盒子统计）：暂不可用'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

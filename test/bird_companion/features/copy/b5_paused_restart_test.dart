import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobStats pausedStats() => const CopyJobStats(totalFiles: 20, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 20000, copiedBytes: 5000);

CopyJobDetail pausedDetail({String? errorCode}) => CopyJobDetail(
  copyJobId: 'job',
  state: CopyJobState.paused,
  stateVersion: 7,
  eventSeq: 3,
  allowedActions: const [CopyAllowedAction.resume, CopyAllowedAction.cancel],
  stats: pausedStats(),
  sourceDevice: const CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'),
  targetDevice: const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
  errorCode: errorCode,
);

class _Repository implements CopyJobRepository {
  _Repository(this.current);

  CopyJobDetail current;

  @override
  Future<CopyJobDetail> getJob(String id) async => current;

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => const CopyReport(copyJobId: 'job');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('v10-2 重启后仍显示已暂停 5/20、快照设备名与继续入口', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(pausedDetail());
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => CopyDeviceList(devices: [b3Device('card', source: true, target: false), b3Device('disk')]))));
    await tester.pumpAndSettle();

    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('已处理 5 项（复制 5，跳过 0，失败 0，不适用 0）'), findsOneWidget);
    expect(find.text('相机卡'), findsOneWidget);
    expect(find.text('U 盘 Ee'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('copy-job-action-resume'))).onPressed, isNotNull);
    // 不是终结态：不出现完成/失败报告。
    expect(find.text('复制完成'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-2 刷新/重新进入后暂停状态与统计不从本地漂移', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(pausedDetail());
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();
    // 模拟重启后再次读取同一 paused 任务（状态、进度、版本仍来自后端）。
    repository.current = pausedDetail();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('已处理 5 项（复制 5，跳过 0，失败 0，不适用 0）'), findsOneWidget);
    expect(find.byKey(const Key('copy-job-action-resume')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-2 不可恢复任务显示明确错误码，未归类项如实暴露', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final detail = CopyJobDetail(
      copyJobId: 'job',
      state: CopyJobState.failed,
      stateVersion: 1,
      eventSeq: 0,
      allowedActions: const [],
      stats: pausedStats(),
      errorCode: 'COPY_TASK_UNRECOVERABLE',
      errorMessage: '原任务无法恢复，请重新创建复制任务。',
    );
    final repository = _Repository(detail);
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();

    expect(find.text('任务失败原因（COPY_TASK_UNRECOVERABLE）'), findsOneWidget);
    expect(find.text('原任务无法恢复，请重新创建复制任务。'), findsOneWidget);
    expect(find.byKey(const Key('copy-job-unclassified')), findsOneWidget);
    expect(find.textContaining('15 项未归类'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

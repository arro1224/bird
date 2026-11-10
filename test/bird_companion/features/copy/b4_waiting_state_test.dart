import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_list_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CopyJobDetail job({
  required CopyJobState state,
  List<CopyAllowedAction> actions = const [],
  CopyJobDeviceSnapshot? target,
  List<CopyJobItem> failed = const [],
}) => CopyJobDetail(
  copyJobId: 'job',
  state: state,
  stateVersion: 3,
  eventSeq: 0,
  allowedActions: actions,
  stats: const CopyJobStats(totalFiles: 10, copiedFiles: 3, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 1000, copiedBytes: 300),
  targetDevice: target ?? const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
);

class _Repository implements CopyJobRepository {
  _Repository({required this.current, this.failed = const []});

  CopyJobDetail current;
  List<CopyJobItem> failed;

  @override
  Future<CopyJobDetail> getJob(String id) async => current;

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => CopyJobItemPage(items: state == 'failed' ? failed : const [], hasMore: false);

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => const CopyReport(copyJobId: 'job', actualFileCount: 10, copiedFiles: 3, failedFiles: 7, skippedFiles: 0, notApplicableFiles: 0);

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async => CopyJobPage(items: [CopyJobListItem(copyJobId: 'job', state: current.state, stats: current.stats)], hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('v10-1 内部英文异常不外泄，中文用户文案保留', () {
    expect(
      const CopyJobItem(copyItemId: 'i1', errorCode: 'COPY_STORAGE_UNAVAILABLE', errorMessage: 'expected exactly one present device, found 0').failureText,
      '正在恢复存储设备，原任务已保留。',
    );
    expect(
      const CopyJobItem(copyItemId: 'i2', errorCode: 'COPY_TARGET_NOT_PRESENT', errorMessage: 'target device is not present').failureText,
      '目标 U 盘已断开，请插回原目标盘。',
    );
    expect(
      const CopyJobItem(copyItemId: 'i3', errorCode: 'COPY_IO_ERROR', errorMessage: '目标 U 盘写入失败，请检查设备。').failureText,
      '目标 U 盘写入失败，请检查设备。',
    );
  });

  testWidgets('v10-1 waiting_for_target 在详情显示等待而非终结，并提示插回原目标盘', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(current: job(state: CopyJobState.waitingForTarget));
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();

    expect(find.text('等待目标设备'), findsOneWidget);
    expect(find.textContaining('等待原目标 U 盘'), findsOneWidget);
    expect(find.textContaining('不会自动更换其他设备'), findsOneWidget);
    // 不是终结态：不出现终态报告/完成文案。
    expect(find.text('复制完成'), findsNothing);
    expect(find.text('任务失败报告'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-1 waiting 任务在列表显示等待状态与未终结文案', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(current: job(state: CopyJobState.waitingForTarget));
    await tester.pumpWidget(MaterialApp(home: CopyJobListPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('等待目标设备'), findsOneWidget);
    expect(find.text('目标 U 盘已断开，请插回原目标盘。'), findsOneWidget);
    expect(find.text('已处理 3 项（复制 3，跳过 0，失败 0，不适用 0）'), findsOneWidget);
    expect(find.textContaining('处理完成'), findsNothing);
  });

  testWidgets('v10-1 失败项不渲染内部英文异常', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(
      current: job(state: CopyJobState.completedWithErrors),
      failed: const [
        CopyJobItem(copyItemId: 'i1', sourceRelativePath: 'A.RAW', errorCode: 'COPY_STORAGE_UNAVAILABLE', errorMessage: 'expected exactly one present device, found 0'),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: CopyJobDetailPage(copyJobId: 'job', repository: repository, deviceReader: () async => const CopyDeviceList(devices: []))));
    await tester.pumpAndSettle();

    expect(find.textContaining('expected exactly one'), findsNothing);
    expect(find.text('正在恢复存储设备，原任务已保留。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CopyJobDetail detail() => const CopyJobDetail(
  copyJobId: 'job',
  state: CopyJobState.running,
  stateVersion: 4,
  eventSeq: 2,
  allowedActions: [CopyAllowedAction.pause],
  stats: CopyJobStats(totalFiles: 20, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 20000, copiedBytes: 5000),
  sourceDevice: CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'),
  targetDevice: CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
);

class _Repository implements CopyJobRepository {
  _Repository({this.fail = false});

  bool fail;

  @override
  Future<CopyJobDetail> getJob(String id) async {
    if (fail) throw StateError('network down');
    return detail();
  }

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
  test('v10-4 会话重连中读取不可用时不报错，重试会真正恢复并继续读取', () async {
    final repository = _Repository(fail: true);
    var readable = false, recovering = true, reconnects = 0;
    final cubit = CopyJobDetailCubit(
      repository,
      copyJobId: 'job',
      canRead: () => readable,
      sessionRecovering: () => recovering,
      onReconnect: () async {
        reconnects++;
        readable = true;
        recovering = false;
        repository.fail = false;
        return true;
      },
    );
    cubit.sessionChanged();
    expect(cubit.state.error, isNull);
    expect(cubit.recovering, isTrue);

    await cubit.retryConnection();
    expect(reconnects, 1);
    expect(cubit.state.detail, isNotNull);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('v10-4 重连失败保留加载结果为空并给出错误，不静默', () async {
    final cubit = CopyJobDetailCubit(_Repository(fail: true), copyJobId: 'job', canRead: () => false, sessionRecovering: () => false, onReconnect: () async => false);
    cubit.sessionChanged();
    expect(cubit.state.error, isNotNull);
    await cubit.retryConnection();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });

  test('v10-4 会话短暂不可读时保留任务快照设备名', () async {
    var readable = true, recovering = false;
    final cubit = CopyJobDetailCubit(_Repository(), copyJobId: 'job', canRead: () => readable, sessionRecovering: () => recovering);
    await cubit.load();
    expect(cubit.state.detail, isNotNull);
    readable = false;
    recovering = true;
    cubit.sessionChanged();
    expect(cubit.state.detail?.targetDevice?.presentationLabel, 'U 盘 Ee');
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  testWidgets('v10-4 回前台先显示正在恢复而不是红条，重试后加载出任务', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(fail: true);
    var readable = false, recovering = true, reconnects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(
          copyJobId: 'job',
          repository: repository,
          canRead: () => readable,
          sessionRecovering: () => recovering,
          onReconnect: () async {
            reconnects++;
            readable = true;
            recovering = false;
            repository.fail = false;
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('正在恢复连接/同步任务状态'), findsOneWidget);
    expect(find.text('请连接原盒子'), findsNothing);
    expect(find.byKey(const Key('copy-job-recovering')), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-job-recovering-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(reconnects, 1);
    expect(find.text('任务处理情况'), findsOneWidget);
    expect(find.text('U 盘 Ee'), findsOneWidget);
    expect(find.byKey(const Key('copy-job-recovering')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-4 恢复失败后给出明确错误和可重试入口', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(
          copyJobId: 'job',
          repository: _Repository(fail: true),
          canRead: () => false,
          sessionRecovering: () => false,
          onReconnect: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请连接原盒子'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

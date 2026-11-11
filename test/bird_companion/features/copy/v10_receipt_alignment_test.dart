import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobDetail waitingDetail() => const CopyJobDetail(
  copyJobId: 'job',
  state: CopyJobState.waitingForTarget,
  stateVersion: 12,
  eventSeq: 4,
  allowedActions: [CopyAllowedAction.resume, CopyAllowedAction.cancel],
  stats: CopyJobStats(totalFiles: 20, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 20000, copiedBytes: 5000),
  sourceDevice: CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'),
  targetDevice: CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
  errorCode: 'COPY_TARGET_NOT_PRESENT',
  errorMessage: '目标 U 盘已断开，请插回原目标盘。',
);

class _WaitingRepository implements CopyJobRepository {
  int actions = 0;

  @override
  Future<CopyJobDetail> getJob(String id) async => waitingDetail();

  @override
  Future<CopyJobDetail?> jobAction(String id, String action, {required int expectedStateVersion}) async {
    actions++;
    return waitingDetail();
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

class _EventCursorRepository implements CopyJobRepository {
  final calls = <int?>[];

  @override
  Future<CopyJobDetail> getJob(String id) async => const CopyJobDetail(
    copyJobId: 'job',
    state: CopyJobState.running,
    stateVersion: 3,
    eventSeq: 0,
    allowedActions: [CopyAllowedAction.pause],
    stats: CopyJobStats(totalFiles: 5, copiedFiles: 1, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 500, copiedBytes: 100),
  );

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async {
    calls.add(afterSeq);
    if (afterSeq == null) {
      return const CopyJobEventPage(
        events: [CopyJobEvent(seq: 1, type: 'state_changed')],
        hasMore: true,
        nextCursor: '5',
      );
    }
    return const CopyJobEventPage(
      events: [CopyJobEvent(seq: 5, type: 'state_changed')],
      hasMore: false,
    );
  }

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => const CopyReport(copyJobId: 'job');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('P0-1 waiting 的资源错误码不渲染成任务失败，优先展示后端中文消息且 resume 可用', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _WaitingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(
          copyJobId: 'job',
          repository: repository,
          deviceReader: () async => CopyDeviceList(devices: [b3Device('card', source: true, target: false), b3Device('disk')]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('目标 U 盘已断开，请插回原目标盘。'), findsOneWidget);
    expect(find.byKey(const Key('copy-job-failure-reason')), findsNothing);
    expect(find.textContaining('任务失败原因'), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('copy-job-action-resume'))).onPressed, isNotNull);
    expect(find.byKey(const Key('copy-job-action-cancel')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('P1-6 事件补取优先使用服务端 next_cursor，而不是最后一条 seq', () async {
    final repository = _EventCursorRepository();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job');
    await cubit.load();
    expect(repository.calls, [null, 5]);
    expect(cubit.state.events.map((event) => event.seq), [1, 5]);
    await cubit.close();
  });
}
